"""Девочка (JOY) из студийного фото — без фона, с мягким краем меха.

    python3 tool/rive/girl_cut.py          # → assets_src/rive/girl/joy_cut.png

Заказчик 14.10, вариант «Б»: слои девочки делаем сами из присланного фото
(`assets_src/rive/girl/joy_photo.jpg`, 1718 × 2576, та же студийная серия,
что у мальчика). Это первый шаг — вырезка целиком; дальше она делится на
слои по образцу мальчика.

Как вырезается:
1. Фон — гладкий градиент. Он восстанавливается полиномом 3-й степени по
   пикселям вне мишки (ошибка ~1,5 единицы яркости).
2. Разметка для GrabCut (OpenCV): почти совпадает с фоном — фон наверняка;
   ткань (насыщенный цвет) и светлый мех выше юбки — мишка наверняка;
   остальное решает GrabCut по цветовым моделям. Внизу фон почти белый, как
   мех, но он холодный, а мех тёплый — на этом и различаются.
3. Мягкий край ±3 px: доля меха — проекция «пиксель − фон» на «мех − фон»,
   цвет очищается от примеси фона: F = (I − (1 − a)·B) / a. На синем и на
   кремовом фоне каймы нет.
4. Кружево по низу юбки — белое на почти белом полу; полоса под розовой
   тканью считается отдельно, с усиленной долей.

Зависимости: numpy, scipy, Pillow, opencv-python-headless.
"""
import os

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, 'assets_src/rive/girl')
SRC = os.path.join(DIR, 'joy_photo.jpg')
OUT = os.path.join(DIR, 'joy_cut.png')

# Рамка мишки с запасом и уровень пола (пиксели исходного фото).
BOX = (400, 900, 1320, 2200)
FLOOR_Y = 2112
FUR = np.array([247.0, 244.0, 238.0])     # тёплый белый мех


def background(im):
    """Гладкий фон по пикселям вне рамки мишки."""
    h, w, _ = im.shape
    yy, xx = np.mgrid[0:h, 0:w]
    known = np.ones((h, w), bool)
    known[BOX[1]:BOX[3], BOX[0]:BOX[2]] = False
    sel = known[::8, ::8]

    def basis(x, y):
        return np.stack([x ** i * y ** j for i in range(4) for j in range(4) if i + j <= 3], -1)

    a = basis(xx[::8, ::8][sel] / w - 0.5, yy[::8, ::8][sel] / h - 0.5)
    full = basis((xx / w - 0.5).ravel(), (yy / h - 0.5).ravel())
    bg = np.zeros_like(im)
    for c in range(3):
        coef, *_ = np.linalg.lstsq(a, im[::8, ::8, c][sel], rcond=None)
        bg[..., c] = (full @ coef).reshape(h, w)
    return bg


def main():
    rgb = np.asarray(Image.open(SRC).convert('RGB'))
    im = rgb.astype(np.float64)
    h, w, _ = im.shape
    bg = background(im)
    d = im - bg
    lum = d.mean(2)
    sat = im.max(2) - im.min(2)
    warm = (im[..., 0] - im[..., 2]) - (bg[..., 0] - bg[..., 2])
    mag = np.sqrt((d ** 2).sum(2))
    yy = np.mgrid[0:h, 0:w][0]

    # разметка
    strong = (sat > 40) | ((lum > 22) & (yy < 1900)) | ((lum < -50) & (yy < 1500))
    strong = ndimage.binary_opening(strong, iterations=2)
    lab, n = ndimage.label(strong)
    size = ndimage.sum(strong, lab, range(1, n + 1))
    strong = np.isin(lab, [i + 1 for i, s in enumerate(size) if s > 2000])
    mark = np.full((h, w), cv2.GC_PR_BGD, np.uint8)
    mark[mag >= 6] = cv2.GC_PR_FGD
    mark[ndimage.binary_erosion(strong, iterations=3)] = cv2.GC_FGD
    near = ndimage.binary_dilation(strong, iterations=25)
    mark[(mag < 5) & ~near] = cv2.GC_BGD
    mark[mag < 3.5] = cv2.GC_BGD
    mark[yy > FLOOR_Y] = cv2.GC_BGD
    box = np.zeros((h, w), bool)
    box[BOX[1]:BOX[3], BOX[0]:BOX[2]] = True
    mark[~box] = cv2.GC_BGD

    # GrabCut в 0,6 размера
    s = 0.6
    small = cv2.resize(rgb, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    ms = cv2.resize(mark, (small.shape[1], small.shape[0]), interpolation=cv2.INTER_NEAREST)
    bgd, fgd = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(small, cv2.COLOR_RGB2BGR), ms, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    fg = ((ms == cv2.GC_FGD) | (ms == cv2.GC_PR_FGD)).astype(np.float32)
    fg = cv2.resize(fg, (w, h), interpolation=cv2.INTER_LINEAR) > 0.5
    fg = ndimage.binary_opening(fg, iterations=2)
    lab, n = ndimage.label(fg)
    fg = lab == 1 + np.argmax(ndimage.sum(fg, lab, range(1, n + 1)))

    # кружево: полоса до 60 px под розовой тканью юбки, светлее фона
    pink = (im[..., 0] - im[..., 1] > 12) & (sat > 18) & (yy > 1700)
    pink = ndimage.binary_opening(pink, iterations=2)
    below = np.zeros_like(pink)
    for k in range(1, 61):
        below[k:] |= pink[:-k]
    lace = below & ~pink & (lum > 3) & (yy < FLOOR_Y)
    fg |= ndimage.binary_closing(lace, iterations=2)
    fg = ndimage.binary_fill_holes(fg)

    # мягкий край и очистка цвета
    fb = FUR - bg
    proj = (d * fb).sum(2) / np.maximum((fb ** 2).sum(2), 25.0)
    inner = ndimage.binary_erosion(fg, iterations=3)
    outer = ndimage.binary_dilation(fg, iterations=3)
    band = outer & ~inner
    edge = np.clip(np.maximum(proj * 1.1, warm / 12.0), 0, 1)
    edge[sat > 38] = 1
    edge[lace] = np.clip(proj[lace] * 1.5, 0, 1)
    alpha = inner.astype(np.float64)
    alpha[band] = edge[band]
    alpha = np.minimum(alpha, ndimage.gaussian_filter(outer.astype(float), 1.0))
    a3 = np.clip(alpha, 1e-3, 1)[..., None]
    color = np.clip((im - (1 - a3) * bg) / a3, 0, 255)
    color[alpha < 0.03] = 0
    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(OUT, optimize=True)
    ys, xs = np.where(alpha > 0.5)
    print(f'{OUT}: мишка {xs.min()}…{xs.max()} × {ys.min()}…{ys.max()}')


if __name__ == '__main__':
    main()
