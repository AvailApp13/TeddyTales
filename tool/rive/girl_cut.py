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
   фоном студии — на тёплых стенах комнат это кайма. На 16 px от силуэта
   цвет кромки — ближайшего меха сразу за ней, 16–22 px от края (рисунок
   ворсинок по яркости свой). Полупрозрачная кайма силуэта — цветом
   ближайшего плотного пикселя (мех — мехом, кофта — тканью).

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
    # кромка меха: тон — как у меха глубже от края. Образец — ближайший
    # чистый мех не ближе 10 px к силуэту (над лентой банта на макушке
    # глубже лежит зелёная лента — её брать нельзя); ткань и бант не трогаем
    inside = alpha > 0.5
    dist = ndimage.distance_transform_edt(inside)
    solid = alpha >= 0.9
    sat = color.max(2) - color.min(2)
    lum = color.mean(2)
    fur = solid & (sat < 25) & (lum > 170)
    # образец — ближайший мех сразу за кромкой, 16–22 px от силуэта (у
    # макушки и ушей кромка на фото холоднее и темнее — подсветка
    # студийного фона; дальше вглубь у уха уже тень раковины; где за
    # кромкой лента банта — берётся ближайший мех за ней)
    deep_fur = fur & (dist >= 16) & (dist <= 22)
    norm = np.maximum(ndimage.gaussian_filter(deep_fur.astype(float), 4), 1e-6)
    field = np.stack([ndimage.gaussian_filter(color[..., c] * deep_fur, 4) for c in range(3)], -1) / norm[..., None]
    _, (dy, dx) = ndimage.distance_transform_edt(~deep_fur, return_indices=True)
    deep = field[dy, dx]
    # только кромка меха: ближайший плотный пиксель — мех (у кофты и юбки
    # кромка тоже бледная, но перекрашивать её в белый мех нельзя)
    _, (sy, sx) = ndimage.distance_transform_edt(~solid, return_indices=True)
    by_fur = fur[sy, sx]
    rim = (alpha > 0.03) & (sat < 40) & (dist < 16) & by_fur
    w = np.clip((16 - dist) / 8, 0, 1) * rim          # 1 до 8 px от края, к 16 px — 0
    # яркость ворса — своя (рисунок ворсинок), цвет и уровень — меха; у
    # полупрозрачных ворсинок своя яркость — шум (там почти один фон)
    sl = ndimage.gaussian_filter(lum * solid, 2) / np.maximum(ndimage.gaussian_filter(solid.astype(float), 2), 1e-6)
    keep = np.where(alpha >= 0.6, np.clip(lum / np.maximum(sl, 1), 0.9, 1.1), 1.0)
    # кромка на фото темнее середины меха на 10–15 единиц: на розовой стене
    # это серая обводка. Уровень кромки — как у самого светлого меха рядом
    # (в 20 px), чуть ниже
    fl = ndimage.gaussian_filter(lum * fur, 3) / np.maximum(ndimage.gaussian_filter(fur.astype(float), 3), 1e-6)
    ref = ndimage.maximum_filter(np.where(fur, fl, 0), size=41)
    gain = np.clip(0.98 * ref / np.maximum(deep.mean(2), 1), 1.0, 1.12)
    target = deep * (gain * keep)[..., None]
    color = np.clip(color * (1 - w[..., None]) + target * w[..., None], 0, 255)
    # полупрозрачная кайма силуэта — цветом соседнего плотного: у меха —
    # меха, у кофты — ткани (на фото кайма бледная от фона студии).
    # Полупрозрачная органза банта внутри силуэта — своя.
    near = np.stack([ndimage.gaussian_filter(color[..., c] * solid, 2) /
                     np.maximum(ndimage.gaussian_filter(solid.astype(float), 2), 1e-6)
                     for c in range(3)], -1)[sy, sx]
    t = np.clip((0.6 - alpha) / 0.3, 0, 1) * (dist == 0)
    color = color * (1 - t[..., None]) + near * t[..., None]
    color[alpha < 0.03] = 0
    rgba = np.dstack([color, alpha * 255]).round().astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(OUT, optimize=True)
    ys, xs = np.where(alpha > 0.5)
    print(f'{OUT}: мишка {xs.min()}…{xs.max()} × {ys.min()}…{ys.max()}')


if __name__ == '__main__':
    main()
