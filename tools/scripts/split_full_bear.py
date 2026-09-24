#!/usr/bin/env python3
"""
Режет целого мишку (PNG с прозрачным фоном, например full_no_tag из Higgsfield)
на слои рига. Все слои — полный кадр исходника, поэтому в Rive они ставятся
ОДНИМ общим трансформом и складываются обратно в исходную картинку пиксель
в пиксель.

    python3 tools/scripts/split_full_bear.py <full.png> <out_dir>

Слои (сзади вперёд, как в редакторе): foot_left, foot_right, shorts, shirt
(корпус толстовки), paw_left, paw_right, sleeve_left, sleeve_right, ears, face, hood. Рукава
отделены по шву реглана и висят на костях рук вместе с лапами. Каждый пиксель принадлежит ровно одному слою; задний
слой дополнительно заходит на 3 px под передних соседей, чтобы при сглаживании
на стыке не просвечивал фон.

Светлый ореол по краю меха (от белого фона генерации) снимается: цвет
полупрозрачных пикселей края заменяется цветом ближайшего непрозрачного
пикселя (decontaminate), прозрачность волосков сохраняется.

Скрытые продолжения (EXTEND): корпус толстовки продолжается под капюшоном и
рукавами, рукава — под капюшоном, лапы — под рукавами, стопы — под шортами.
Заполняются инпейнтингом (OpenCV Telea) только из пикселей самого слоя, зона
ограничена формой части (над краем / в контуре корпуса / в колонках штанины). В покое закрыты
передними слоями; открываются, когда кости поворачивают части.
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
# рукава реглана: отделяются от корпуса по шву (многоугольники в координатах кадра,
# сняты по шву на bear_boy_v2_full.png). Оси костей плеч стоят на верхней точке шва.
from PIL import ImageDraw
def poly_mask(pts):
    im_ = Image.new('L', (W, H), 0); ImageDraw.Draw(im_).polygon(pts, fill=1); return np.asarray(im_).astype(bool)
# подгиб рукава внизу доходит до ~1350: нижняя граница опущена, иначе полоска
# подгиба остаётся в корпусе и торчит «хвостиком», когда рука поднята
SLEEVE_L = [(200, 1040), (472, 1040), (466, 1110), (452, 1180), (440, 1240), (425, 1285), (410, 1318), (404, 1352), (200, 1352)]
SLEEVE_R = [(880, 1040), (1160, 1040), (1160, 1352), (966, 1352), (960, 1320), (940, 1290), (918, 1250), (905, 1190), (893, 1120)]
sleeve_l = shirt & poly_mask(SLEEVE_L)
sleeve_r = shirt & poly_mask(SLEEVE_R)
shirt = shirt & ~sleeve_l & ~sleeve_r

# порядок = порядок отрисовки в редакторе (сзади вперёд): ноги, шорты, корпус
# толстовки (кость root), руки с рукавами (кости рук), голова (кость root_body)
regions = {
    'foot_left': biggest(feet & (X < axis)), 'foot_right': biggest(feet & (X >= axis)),
    'shorts': yellow,
    'shirt': shirt,
    'paw_left': biggest(paws & (X < axis)), 'paw_right': biggest(paws & (X >= axis)),
    'sleeve_left': sleeve_l, 'sleeve_right': sleeve_r,
    'ears': ears, 'face': face,
    'hood': hood,
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

# --- скрытые продолжения: что откроется при движении. Слой продолжается под
# переднего соседа; цвет восстанавливается инпейнтингом (OpenCV Telea) только
# из пикселей самого слоя. Зона ограничена формой части, чтобы при повороте
# продолжение не вылезало за силуэт. В покое продолжение закрыто.
import cv2
def above(mask, depth):
    """Пиксели не выше depth над верхним краем маски в той же колонке."""
    top = np.where(mask.any(0), mask.argmax(0), H + 10)
    return (Y >= top[None, :] - depth) & (Y < top[None, :] + 5)
def hull(mask, grow):
    pts = np.argwhere(mask)[:, ::-1].astype(np.int32)
    h = cv2.convexHull(pts); hm = np.zeros((H, W), np.uint8); cv2.fillConvexPoly(hm, h, 1)
    return ndimage.binary_dilation(hm.astype(bool), iterations=grow)
def cols_of(mask, shrink):
    xs = np.where(mask.any(0))[0]; lo, hi = xs.min() + shrink, xs.max() - shrink
    return (X >= lo) & (X <= hi)
SHIRT_ALL = shirt | sleeve_l | sleeve_r          # толстовка целиком: её контур задаёт линию плеч
ARMPIT = {'side_left': SLEEVE_L[6], 'side_right': SLEEVE_R[4]}   # нижние точки шва реглана (подмышки)
EXTEND = {  # слой: [(кто закрывает, глубина px, ограничение формы)]
    'shirt': [('hood', 50, 'shirt_hull'), ('face', 50, 'shirt_hull'), ('sleeve_left', 120, 'side_left'), ('sleeve_right', 120, 'side_right'),
              ('paw_left', 120, 'side_left'), ('paw_right', 120, 'side_right')],
    'sleeve_left': [('hood', 40, 'shirt_hull')], 'sleeve_right': [('hood', 40, 'shirt_hull')],
    'paw_left': [('sleeve_left', 45, None)], 'paw_right': [('sleeve_right', 45, None)],
    'foot_left': [('shorts', 60, 'cols')], 'foot_right': [('shorts', 60, 'cols')],
}
def extension(own_op, cover, depth, rule):
    dist = ndimage.distance_transform_edt(~own_op)
    ext = cover & (dist <= depth) & ~own_op
    if rule == 'above': ext &= above(own_op, depth)
    elif rule == 'hull': ext &= hull(own_op, 6)
    elif rule == 'shirt_hull': ext &= hull(SHIRT_ALL, 2) & above(own_op, depth)
    elif rule in ('side_left', 'side_right'):
        # бок корпуса под рукавом: от подмышки прямо вверх (у толстовки бок вертикальный),
        # а не диагональ контура — иначе при подъёме руки торчит острый клин
        # линия бока: от подмышки (ax, ay) вниз к внешнему углу подола (hx, hy);
        # выше подмышки — вертикаль. Заполняется всё, что между линией бока и корпусом.
        ax_, ay_ = ARMPIT[rule]
        rows = np.where(own_op.any(1))[0]; hy = int(rows.max() - 25)
        xs_h = np.where(own_op[hy])[0]; hx = xs_h.min() if rule == 'side_left' else xs_h.max()
        t = np.clip((Y - ay_) / max(hy - ay_, 1), 0, 1)
        line_x = ax_ + (hx - ax_) * t
        side = (X >= line_x) if rule == 'side_left' else (X <= line_x)
        ext &= hull(own_op | ext, 2) & side
    elif rule == 'cols': ext &= cols_of(own_op, 12)
    return ext
def texture_detail(own_op, shape, size=72):
    """Высокочастотная фактура слоя (трикотаж, ворс), замощённая на shape."""
    dist = ndimage.distance_transform_edt(own_op)
    cy, cx = np.unravel_index(np.argmax(dist), dist.shape)
    r = int(min(size // 2, max(dist.max() - 2, 4)))
    patch = clean[cy - r:cy + r, cx - r:cx + r].astype(np.float64)
    hp = patch - ndimage.gaussian_filter(patch, (3, 3, 0))
    tile = np.concatenate([hp, hp[::-1]], 0); tile = np.concatenate([tile, tile[:, ::-1]], 1)   # зеркальное замощение без швов
    reps = (shape[0] // tile.shape[0] + 2, shape[1] // tile.shape[1] + 2, 1)
    return np.tile(tile, reps)[:shape[0], :shape[1]]

def inpaint_into(col, own_op, ext):
    ys, xs = np.where(ext | ndimage.binary_dilation(ext, iterations=20) & own_op)
    if len(ys) == 0: return col
    y0, y1, x0, x1 = max(ys.min() - 4, 0), min(ys.max() + 5, H), max(xs.min() - 4, 0), min(xs.max() + 5, W)
    crop = col[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)
    known = own_op[y0:y1, x0:x1]
    fill = cv2.inpaint(np.ascontiguousarray(crop[..., ::-1]), (~known).astype(np.uint8), 9, cv2.INPAINT_TELEA)[..., ::-1]
    fill = fill.astype(np.float64) + texture_detail(own_op, fill.shape[:2])
    e = ext[y0:y1, x0:x1]; out = col.copy(); sub = out[y0:y1, x0:x1]; sub[e] = fill[e]; return out

meta = {'source': src, 'size': [W, H], 'ycut_hood_shirt': int(ycut), 'axisX': float(axis), 'order_back_to_front': order, 'layers': {}}
recon = np.zeros((H, W, 4))
for i, n in enumerate(order, 1):
    own = full == i
    front = np.isin(full, list(range(i + 1, len(order) + 1)))
    m = own | (ndimage.binary_dilation(own, iterations=3) & front & (A >= 250))  # заход только под непрозрачное
    # полоса захода под соседей красится цветом самого слоя (ближайший свой пиксель),
    # иначе при движении по краю мелькнёт чужой цвет (голубая кайма у лап и т.п.)
    own_op = own & (A >= 250)
    _, (oy, ox) = ndimage.distance_transform_edt(~own_op, return_indices=True)
    col = clean.copy(); alpha = A * m; strip = m & ~own
    col[strip] = clean[oy[strip], ox[strip]]
    ext_all = np.zeros((H, W), bool)
    for cover_name, depth, rule in EXTEND.get(n, []):
        cover = (full == order.index(cover_name) + 1) & (A >= 250) & ~m
        ext_all |= extension(own_op, cover, depth, rule)
    if ext_all.any():
        col = inpaint_into(col, own_op, ext_all)
        # внешний край продолжения (там, где за ним фон, а не сам слой) смягчается на ~1.5 px
        soft = ndimage.gaussian_filter((ext_all | own_op).astype(np.float64), 1.2)
        alpha = np.where(ext_all, np.clip(soft * 2 - 0.5, 0, 1) * 255, alpha); m = m | ext_all
        meta.setdefault('extensions', {})[n] = int(ext_all.sum())
    layer = np.dstack([col, alpha]).clip(0, 255).astype(np.uint8)
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
