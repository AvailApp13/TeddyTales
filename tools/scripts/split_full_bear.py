#!/usr/bin/env python3
"""
Режет целого мишку (PNG с прозрачным фоном, например full_no_tag из Higgsfield)
на слои рига. Все слои — полный кадр исходника, поэтому в Rive они ставятся
ОДНИМ общим трансформом и складываются обратно в исходную картинку пиксель
в пиксель.

    python3 tools/scripts/split_full_bear.py <full.png> <out_dir>

Слои (сзади вперёд): ears, face, feet_left, feet_right, shorts, paw_left,
paw_right, shirt, hood. Каждый пиксель принадлежит ровно одному слою; задний
слой дополнительно заходит на 3 px под передних соседей, чтобы при сглаживании
на стыке не просвечивал фон.

Светлый ореол по краю меха (от белого фона генерации) снимается: цвет
полупрозрачных пикселей края заменяется цветом ближайшего непрозрачного
пикселя (decontaminate), прозрачность волосков сохраняется.
"""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
a = np.asarray(im).astype(np.float64)
rgb, A = a[..., :3], a[..., 3].copy()
# шум прозрачности вне фигуры (A<=8) — в ноль, иначе слои растягиваются на весь кадр
A[A <= 8] = 0
A[~ndimage.binary_dilation(ndimage.binary_fill_holes(A > 20), iterations=12)] = 0
H, W = A.shape
Y = np.arange(H)[:, None]; X = np.arange(W)[None, :]
hsv = np.asarray(im.convert('RGB').convert('HSV')).astype(np.float64)
hue, sat = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255

# --- снять светлый ореол
opaque = A >= 250
_, (iy, ix) = ndimage.distance_transform_edt(~opaque, return_indices=True)
edge = (A > 0) & ~opaque
clean = rgb.copy()
clean[edge] = rgb[iy[edge], ix[edge]] * 0.85 + rgb[edge] * 0.15

# --- классы цвета
al = A > 20
blue = al & (((hue > 185) & (hue < 250) & (sat > 0.07)) | ((rgb[..., 2] - rgb[..., 0] > 10) & (rgb[..., 2] > 170)))
yellow = al & (hue > 35) & (hue < 70) & (sat > 0.2)
def biggest(m):
    lab, n = ndimage.label(m)
    if n == 0: return m
    s = ndimage.sum(m, lab, range(1, n + 1)); return lab == (np.argmax(s) + 1)
blue = biggest(ndimage.binary_opening(blue, iterations=1))
yellow = ndimage.binary_fill_holes(biggest(ndimage.binary_opening(yellow, iterations=1)))
fur = al & ~blue & ~yellow

# --- граница капюшон/толстовка: самая узкая строка синего силуэта в зоне шеи
ys_b = np.where(blue.any(1))[0]
y0, y1 = ys_b.min(), ys_b.max()
lo, hi = int(y0 + (y1 - y0) * 0.55), int(y0 + (y1 - y0) * 0.75)
width = [np.ptp(np.where(blue[y])[0]) if blue[y].any() else 1e9 for y in range(lo, hi)]
ycut = lo + int(np.argmin(width))

face = ndimage.binary_fill_holes(blue) & ~blue & al          # всё, что внутри синего кольца
# под подбородком обод капюшона опускается ниже прямой линии: граница идёт
# по контуру подбородка + толщина обода (RIM px), по бокам — прямая ycut
RIM = 24
fb = np.full(W, -1.0)
cols = np.where(face.any(0))[0]
for x in cols: fb[x] = np.where(face[:, x])[0].max()
bound = np.full(W, float(ycut))
bound[cols] = np.maximum(ycut, fb[cols] + RIM)
bound = ndimage.uniform_filter1d(bound, 25)
hood = blue & (Y < bound[None, :])
shirt = blue & ~hood
ys_y = np.where(yellow.any(1))[0]; ymid_shorts = (ys_y.min() + ys_y.max()) // 2
xs_face = np.where(face.any(0))[0]; axis = (xs_face.min() + xs_face.max()) / 2
ears = fur & ~face & (Y < ycut) & ~ndimage.binary_fill_holes(blue | face)
paws = fur & ~face & (Y >= ycut) & (Y < ymid_shorts)
feet = fur & ~face & (Y >= ymid_shorts)
regions = {
    'ears': ears, 'face': face,
    'foot_left': biggest(feet & (X < axis)), 'foot_right': biggest(feet & (X >= axis)),
    'shorts': yellow,
    'paw_left': biggest(paws & (X < axis)), 'paw_right': biggest(paws & (X >= axis)),
    'shirt': shirt, 'hood': hood,
}
order = list(regions)  # сзади вперёд

# --- полное разбиение: каждый пиксель с A>0 — ближайшему слою
lab = np.zeros((H, W), np.int32)
for i, n in enumerate(order, 1): lab[regions[n]] = i
_, (jy, jx) = ndimage.distance_transform_edt(lab == 0, return_indices=True)
full = lab[jy, jx] * (A > 0)

# край меховых слоёв, прилегающий к ткани спереди, несёт цвет ткани (подкладка,
# тень от подола). Эти 5 px отдаём переднему соседу, а мех под ним продолжится
# собственным цветом (полоса захода ниже) — при движении края остаются чистыми.
FUR = {'ears', 'face', 'foot_left', 'foot_right', 'paw_left', 'paw_right'}
for i, n in enumerate(order, 1):
    if n not in FUR: continue
    front = np.isin(full, list(range(i + 1, len(order) + 1)))
    if not front.any(): continue
    _, (fy, fx) = ndimage.distance_transform_edt(~front, return_indices=True)
    border = (full == i) & ndimage.binary_dilation(front, iterations=5)
    full[border] = full[fy[border], fx[border]]

meta = {'source': src, 'size': [W, H], 'ycut_hood_shirt': int(ycut), 'axisX': float(axis), 'order_back_to_front': order, 'layers': {}}
recon = np.zeros((H, W, 4))
for i, n in enumerate(order, 1):
    own = full == i
    front = np.isin(full, list(range(i + 1, len(order) + 1)))
    m = own | (ndimage.binary_dilation(own, iterations=3) & front & (A >= 250))  # заход только под непрозрачное
    # полоса захода под соседей красится цветом самого слоя (ближайший свой пиксель),
    # иначе при движении по краю мелькнёт чужой цвет (голубая кайма у лап и т.п.)
    _, (oy, ox) = ndimage.distance_transform_edt(~(own & (A >= 250)), return_indices=True)
    col = clean.copy(); strip = m & ~own
    col[strip] = clean[oy[strip], ox[strip]]
    layer = np.dstack([col, A * m]).clip(0, 255).astype(np.uint8)
    layer[~m, :3] = 0
    Image.fromarray(layer, 'RGBA').save(f'{out}/{n}.png', optimize=True)
    ys, xs = np.where(own)
    meta['layers'][n] = {'bbox': [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1], 'px': int(own.sum())}
    # сборка «сзади вперёд» для проверки
    L = layer.astype(np.float64); la = L[..., 3:4] / 255
    recon[..., :3] = L[..., :3] * la + recon[..., :3] * (1 - la)
    recon[..., 3:4] = la * 255 + recon[..., 3:4] * (1 - la)
alpha_err = np.abs(recon[..., 3] - A).max()
meta['check'] = {'alphaMaxError': float(alpha_err)}
json.dump(meta, open(f'{out}/layers.json', 'w'), indent=1, ensure_ascii=False)
print(json.dumps({k: v for k, v in meta.items() if k != 'layers'}, ensure_ascii=False))
for n, v in meta['layers'].items(): print(f'{n:11s} bbox {v["bbox"]}  px {v["px"]}')
