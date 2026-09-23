"""
Вырезает мишку из референсного фото и кладёт результат с прозрачным фоном.
Запуск из корня репозитория:

    ./venv/bin/python tools/cutout_reference.py            # нужны pillow, numpy, scipy
    ./venv/bin/python tools/cutout_reference.py <фото> <out.png> <x0> <x1> <y0> <y1>

По умолчанию — handoff/reference/bear_boy_front_hd.jpg (1334x2000, мишка
ростом ~1050 px) -> handoff/reference/bear_boy_cutout_hd.png.

Как режется: фон в студийных кадрах нейтрально-серый (разброс каналов
RGB < 15), а мех, толстовка и шорты — цветные. Фигура = пиксели внутри
рамки, у которых разброс каналов > 18 или яркость < 0.35 (глаза, нос).
Дальше морфология: opening 1 (шум), closing 6 (швы, блики), заливка
только мелких дыр (< 1500 px — просвет между ног остаётся просветом),
одна связная фигура, край смягчён на ~1 px. Порог по хроме, а не по
HSV-насыщенности: у светло-голубого капюшона насыщенность в бликах
падает ниже 0.10, и старый порог резал в нём дыры.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

args = sys.argv[1:]
src_path = args[0] if args else 'handoff/reference/bear_boy_front_hd.jpg'
out_path = args[1] if len(args) > 1 else 'handoff/reference/bear_boy_cutout_hd.png'
x0, x1, y0, y1 = (int(v) for v in args[2:6]) if len(args) >= 6 else (330, 1010, 570, 1660)

src = Image.open(src_path).convert('RGB')
rgb = np.asarray(src).astype(float)
sm = ndimage.gaussian_filter(rgb, (1, 1, 0))
chroma = sm.max(-1) - sm.min(-1)
V = sm.max(-1) / 255
Yg, Xg = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
box = (Xg > x0) & (Xg < x1) & (Yg > y0) & (Yg < y1)

fig = box & ((chroma > 18) | (V < 0.35))
fig = ndimage.binary_opening(fig, iterations=1)
fig = ndimage.binary_closing(fig, iterations=6)
holes = ndimage.binary_fill_holes(fig) & ~fig
lab, n = ndimage.label(holes)
sizes = ndimage.sum(holes, lab, range(1, n + 1))
fig |= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s < 1500])
lab, n = ndimage.label(fig)
sizes = ndimage.sum(fig, lab, range(1, n + 1))
fig = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 2000])
alpha = np.clip((ndimage.gaussian_filter(fig.astype(float), 1.2) - 0.3) / 0.4, 0, 1)

ys, xs = np.where(fig)
bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
tile = np.dstack([rgb, alpha * 255]).astype('uint8')[by0:by1, bx0:bx1]
Image.fromarray(tile, 'RGBA').save(out_path)
print(f'{out_path}: {bx1-bx0}x{by1-by0}, рамка в фото x {bx0}..{bx1}, y {by0}..{by1}')
