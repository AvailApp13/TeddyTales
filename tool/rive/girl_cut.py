"""Девочка (JOY) из студийного фото — без фона, с мягким краем меха.

    python3 tool/rive/girl_cut.py          # → assets_src/rive/girl/joy_cut.png

Заказчик 14.10, вариант «Б»: слои девочки делаем сами из присланного фото
(`assets_src/rive/girl/joy_photo.jpg`, 1718 × 2576, та же студийная серия,
что у мальчика). Это первый шаг — вырезка целиком; дальше она делится на
слои по образцу мальчика.

Как вырезается:
1. Контур — `joy_alpha.png`: маска Higgsfield `remove_background` (14.10,
   job b12d9ce3-b809-42e6-97ef-6c1f6138bf8a; 1365 × 2047 → размер фото),
   срезана по мишке, левый верхний угол — `ALPHA_AT`. Своя разметка
   (GrabCut) теряла кружево юбки на почти белом полу и цепляла пол у стоп,
   маска Higgsfield чистая.
2. Фон — гладкий градиент. Он восстанавливается полиномом 3-й степени по
   пикселям вне мишки (ошибка ~1,5 единицы яркости).
3. Цвет края очищается от примеси фона: F = (I − (1 − a)·B) / a.
4. Кромка меха по силуэту (5–8 px) на фото отсвечивает голубовато-серым
   фоном студии — на тёплых стенах комнат это кайма. Тон кромки
   подтягивается к меху на 14 px глубже (фактура остаётся), а цвет
   полупрозрачных ворсинок берётся от ближайшего плотного меха.

Зависимости: numpy, scipy, Pillow.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, 'assets_src/rive/girl')
SRC = os.path.join(DIR, 'joy_photo.jpg')
ALPHA = os.path.join(DIR, 'joy_alpha.png')
OUT = os.path.join(DIR, 'joy_cut.png')

ALPHA_AT = (412, 918)                     # где лежит маска на фото
BOX = (400, 900, 1320, 2200)              # рамка мишки с запасом — для фона


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
    im = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float64)
    h, w, _ = im.shape
    bg = background(im)
    crop = np.asarray(Image.open(ALPHA).convert('L')).astype(np.float64) / 255
    alpha = np.zeros((h, w))
    x0, y0 = ALPHA_AT
    alpha[y0:y0 + crop.shape[0], x0:x0 + crop.shape[1]] = crop
    a3 = np.clip(alpha, 1e-3, 1)[..., None]
    color = np.clip((im - (1 - a3) * bg) / a3, 0, 255)
    # кромка меха: тон — как у меха глубже от края
    inside = alpha > 0.5
    dist = ndimage.distance_transform_edt(inside)
    solid = alpha >= 0.9
    norm = np.maximum(ndimage.gaussian_filter(solid.astype(float), 3), 1e-6)
    lf = np.stack([ndimage.gaussian_filter(color[..., c] * solid, 3) for c in range(3)], -1) / norm[..., None]
    _, (dy, dx) = ndimage.distance_transform_edt(dist < 14, return_indices=True)
    deep = lf[dy, dx]
    fur_deep = (deep.mean(2) > 200) & (deep.max(2) - deep.min(2) < 30)
    w = np.clip(1 - dist / 12, 0, 1) * fur_deep * (alpha > 0.03)
    color = np.clip(color + (deep - lf) * w[..., None], 0, 255)
    # край меха — цветом соседнего плотного меха
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    near = np.stack([ndimage.gaussian_filter(color[..., c] * solid, 2) /
                     np.maximum(ndimage.gaussian_filter(solid.astype(float), 2), 1e-6)
                     for c in range(3)], -1)[iy, ix]
    furish = (near.mean(2) > 190) & (near.max(2) - near.min(2) < 30)
    t = np.clip((0.85 - alpha) / 0.35, 0, 1) * furish * (alpha < 0.9)
    color = color * (1 - t[..., None]) + near * t[..., None]
    color[alpha < 0.03] = 0
    rgba = np.dstack([color, alpha * 255]).round().astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(OUT, optimize=True)
    ys, xs = np.where(alpha > 0.5)
    print(f'{OUT}: мишка {xs.min()}…{xs.max()} × {ys.min()}…{ys.max()}')


if __name__ == '__main__':
    main()
