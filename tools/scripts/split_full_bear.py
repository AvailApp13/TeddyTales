#!/usr/bin/env python3
"""
Режет целого мишку (PNG с прозрачным фоном, например full_no_tag из Higgsfield)
на слои рига. Все слои — полный кадр исходника, поэтому в Rive они ставятся
ОДНИМ общим трансформом и складываются обратно в исходную картинку пиксель
в пиксель.

    python3 tools/scripts/split_full_bear.py <full.png> <out_dir>

Слои (сзади вперёд, как в редакторе): foot_left, foot_right, shorts, shirt
(корпус толстовки), paw_left, paw_right, sleeve_left, sleeve_right (рука целиком
поверх корпуса — D16), hood_lining, ears, face, hood. Рукава
отделены по шву реглана и висят на костях рук вместе с лапами. Каждый пиксель принадлежит ровно одному слою; задний
слой дополнительно заходит на 3 px под передних соседей, чтобы при сглаживании
на стыке не просвечивал фон.

Светлый ореол по краю меха (от белого фона генерации) снимается: цвет
полупрозрачных пикселей края заменяется цветом ближайшего непрозрачного
пикселя (decontaminate), прозрачность волосков сохраняется.

Скрытые продолжения (EXTEND): корпус толстовки и рукава продолжаются под
капюшоном (зеркально своей тканью, с тенью), лапы — под рукавами, стопы — под шортами.
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
# ниже подмышки граница идёт по складке между рукавом и боком корпуса, от
# внутреннего угла манжеты — наклонно вниз-наружу, между манжетой и боком
# корпуса. Горизонтальный срез здесь отдавал рукаву кусок бока у подола: при
# подъёме руки он уезжал с рукавом, а в корпусе оставалась ступенька.
SLEEVE_L = [(200, 1040), (472, 1040), (466, 1110), (452, 1180), (440, 1240), (426, 1280), (412, 1300), (398, 1320), (389, 1333), (300, 1365), (200, 1365)]
SLEEVE_R = [(880, 1040), (1160, 1040), (1160, 1375), (1060, 1375), (975, 1344), (957, 1320), (937, 1296), (918, 1250), (905, 1190), (893, 1120)]
sleeve_l = shirt & poly_mask(SLEEVE_L)
sleeve_r = shirt & poly_mask(SLEEVE_R)
shirt = shirt & ~sleeve_l & ~sleeve_r
def poly_cov(pts, ss=4):
    """Доля пикселя внутри многоугольника (суперсэмплинг ss×ss)."""
    im_ = Image.new('L', (W * ss, H * ss), 0)
    ImageDraw.Draw(im_).polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    return np.asarray(im_, np.float64).reshape(H, ss, W, ss).mean((1, 3)) / 255
# Срезы, которые открываются в движении, — сглаженные: передний слой по линии
# среза получает дробную прозрачность (доля пикселя на его стороне), иначе
# при подъёме руки / наклоне головы край корпуса и капюшона — «лесенка».
CUT = {  # слой: (доля пикселя на стороне слоя, соседи по срезу)
    'sleeve_left': (poly_cov(SLEEVE_L), ['shirt']),
    'sleeve_right': (poly_cov(SLEEVE_R), ['shirt']),
    'hood': (np.clip(bound[None, :] - Y + 0.5, 0, 1), ['shirt', 'sleeve_left', 'sleeve_right']),
}

# порядок = порядок отрисовки в редакторе (сзади вперёд): ноги, шорты, корпус
# толстовки (кость root), руки — лапа под рукавом (кости рук), голова (root_body).
# Рука целиком ПОВЕРХ корпуса (D16): рукав — сетка, шов реглана и подмышка
# держатся за туловище, поэтому корпус у шва не открывается и запаса под
# корпусом рукаву не нужно.
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

# бок корпуса у подола, где его касается лапа: ворс лапы лежит поверх края
# корпуса, и ближайшее-по-слою разбиение режет его рвано (при подъёме руки на
# боку оставались серые крошки). Здесь край корпуса — ломаная по силуэту бока
# (снята по bear_boy_v2_full.png от угла манжеты вниз): со стороны корпуса всё
# корпусу, снаружи — лапе. Кромка корпуса сглажена по ломаной, цвет — свой.
SIDE = {  # лапа: (точки края корпуса (x, y) сверху вниз, сторона корпуса по x)
    'paw_left': ([(389, 1333), (386, 1346), (380, 1354), (374, 1362), (370, 1370), (368, 1380), (367, 1390)], 1),
    'paw_right': ([(975, 1344), (986, 1354), (989, 1362), (991, 1370), (996, 1378), (1002, 1386), (1005, 1394)], -1),
}
side_cov = np.ones((H, W)); side_zone = np.zeros((H, W), bool); side_band = np.zeros((H, W), bool)
for paw, (pts, sgn) in SIDE.items():
    py_, px_ = [p[1] for p in pts], [p[0] for p in pts]
    edge_x = np.interp(np.arange(H), py_, px_)[:, None]
    d = (X - edge_x) * sgn                                   # >0 — сторона корпуса
    zone = (Y >= py_[0]) & (Y <= py_[-1]) & (np.abs(d) < 14) & (A > 0)
    pid, sid = order.index(paw) + 1, order.index('shirt') + 1
    # полупрозрачная кайма сразу снаружи края — это сглаживание самого корпуса:
    # остаётся корпусу (с исходной прозрачностью), а не уезжает с лапой/рукавом «ниткой»
    band = zone & (d < 0) & (d > -5) & (A < 200) & np.isin(full, [sid, pid, order.index('sleeve_left') + 1, order.index('sleeve_right') + 1])
    full[band] = sid; side_band |= band
    full[zone & (d < 0) & ~band & (full == sid)] = pid
    full[zone & (d >= 0) & (full == pid)] = sid
    side_cov = np.where(zone, np.clip(d + 0.5, 0, 1), side_cov); side_zone |= zone

# край меховых слоёв, прилегающий к ткани спереди, несёт цвет ткани (подкладка,
# тень от подола). Эти 5 px отдаём переднему соседу, а мех под ним продолжится
# собственным цветом (полоса захода ниже) — при движении края остаются чистыми.
# Лапа отдаёт кромку только своему рукаву: у корпуса толстовки лапа лишь
# касается бока, и мех, отданный корпусу, остаётся на нём крошками, когда рука
# поднята.
FUR = {'ears': None, 'face': None, 'foot_left': None, 'foot_right': None,
       'paw_left': ['sleeve_left'], 'paw_right': ['sleeve_right']}
for i, n in enumerate(order, 1):
    if n not in FUR: continue
    front_ids = list(range(i + 1, len(order) + 1)) if FUR[n] is None else [order.index(f) + 1 for f in FUR[n]]
    front = np.isin(full, front_ids)
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
face_x0, face_x1 = xs_face.min(), xs_face.max()
SHIRT_ALL = shirt | sleeve_l | sleeve_r          # толстовка целиком: её контур задаёт линию плеч
EXTEND = {  # слой: [(кто закрывает, глубина px, ограничение формы)]
    # под рукавами корпус не продолжается: рукава — сетки, у шва и подмышки держатся за туловище (D16)
    'shirt': [('hood', 80, 'shirt_hull'), ('face', 80, 'shirt_hull')],
    # рукав под капюшоном — без контура толстовки: угол капюшона на плече при наклоне
    # головы чуть приподнимается, под ним должна быть ткань плеча, а не фон
    'sleeve_left': [('hood', 70, 'above')], 'sleeve_right': [('hood', 70, 'above')],
    'paw_left': [('sleeve_left', 45, None)], 'paw_right': [('sleeve_right', 45, None)],
    'foot_left': [('shorts', 60, 'cols')], 'foot_right': [('shorts', 60, 'cols')],
}
def extension(own_op, cover, depth, rule):
    dist = ndimage.distance_transform_edt(~own_op)
    ext = cover & (dist <= depth) & ~own_op
    if rule == 'above': ext &= above(own_op, depth)
    elif rule == 'hull': ext &= hull(own_op, 6)
    elif rule == 'shirt_hull':
        # по бокам — в контуре толстовки (плечи под капюшоном не «квадратные»);
        # под лицом (колонки подбородка) — на всю глубину вверх: при наклоне
        # головы обод капюшона у подбородка поднимается выше верха оболочки
        chin = (X >= face_x0) & (X <= face_x1)
        ext &= (hull(SHIRT_ALL, 12) | chin) & above(own_op, depth)
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

def inpaint_into(col, own_op, ext, detail=True):
    ys, xs = np.where(ext | ndimage.binary_dilation(ext, iterations=20) & own_op)
    if len(ys) == 0: return col
    y0, y1, x0, x1 = max(ys.min() - 4, 0), min(ys.max() + 5, H), max(xs.min() - 4, 0), min(xs.max() + 5, W)
    crop = col[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)
    known = own_op[y0:y1, x0:x1]
    fill = cv2.inpaint(np.ascontiguousarray(crop[..., ::-1]), (~known).astype(np.uint8), 9, cv2.INPAINT_TELEA)[..., ::-1]
    fill = fill.astype(np.float64) + (texture_detail(own_op, fill.shape[:2]) if detail else 0)
    e = ext[y0:y1, x0:x1]; out = col.copy(); sub = out[y0:y1, x0:x1]; sub[e] = fill[e]; return out

meta = {'source': src, 'size': [W, H], 'ycut_hood_shirt': int(ycut), 'axisX': float(axis), 'order_back_to_front': order, 'layers': {}}
recon = np.zeros((H, W, 4))
for i, n in enumerate(order, 1):
    own = full == i
    front = np.isin(full, list(range(i + 1, len(order) + 1)))
    m = own | (ndimage.binary_dilation(own, iterations=3) & front & (A >= 250))  # заход только под непрозрачное
    if n == 'shirt':
        # под рукой, которая уходит, заход корпуса открылся бы полоской у бока:
        # под лапами его нет, под рукавами — 2 px (под сглаженный край рукава)
        arm = np.isin(full, [order.index(k) + 1 for k in ('paw_left', 'paw_right', 'sleeve_left', 'sleeve_right')])
        m = own | (ndimage.binary_dilation(own, iterations=3) & front & ~arm & (A >= 250)) \
                | (ndimage.binary_dilation(own, iterations=2) & np.isin(full, [order.index(k) + 1 for k in ('sleeve_left', 'sleeve_right')]))
    # полоса захода под соседей красится цветом самого слоя (ближайший свой пиксель),
    # иначе при движении по краю мелькнёт чужой цвет (голубая кайма у лап и т.п.)
    own_op = own & (A >= 250)
    # кромка у соседних слоёв (2 px) несёт смешанный цвет соседа (голубой+бежевый на
    # подгибе рукава над лапой и т.п.). В движении кромка уходит от соседа и светится —
    # красим её цветом своего слоя, взятым в 4 px от шва.
    others = (full > 0) & (full != i) & (A >= 250)
    near = own & ndimage.binary_dilation(others, iterations=2)
    if near.any():
        core = own_op & ~ndimage.binary_dilation(others, iterations=4)
        if core.any():
            _, (cy_, cx_) = ndimage.distance_transform_edt(~core, return_indices=True)
            clean_i = clean.copy(); clean_i[near] = clean[cy_[near], cx_[near]]
        else: clean_i = clean
    else: clean_i = clean
    _, (oy, ox) = ndimage.distance_transform_edt(~own_op, return_indices=True)
    col = clean_i.copy(); alpha = A * m; strip = m & ~own
    col[strip] = clean_i[oy[strip], ox[strip]]
    if n.startswith(('paw_', 'foot_')):
        # полупрозрачный ворс по краю лапы/стопы — цветом своего меха: общий
        # decontaminate красит его в цвет ближайшей ткани (кайма у корпуса),
        # и в движении у лапы тянется голубая «нитка»
        semi = own & (A < 250)
        col[semi] = clean_i[oy[semi], ox[semi]]
    if n == 'shirt':
        sz = side_zone & (full == i)
        col[sz] = clean_i[oy[sz], ox[sz]]; alpha = np.where(sz, np.where(side_band, A, 255 * side_cov), alpha)
    if n in CUT:
        cov, nbrs = CUT[n]
        nb = np.isin(full, [order.index(k) + 1 for k in nbrs])
        extra = nb & (cov > 0.001) & ndimage.binary_dilation(own, iterations=2)
        col[extra] = clean_i[oy[extra], ox[extra]]
        zone = (own | extra) & ndimage.binary_dilation(nb, iterations=2)   # только у самого среза
        alpha = np.where(zone, A * cov, alpha); m = m | extra
    ext_all = np.zeros((H, W), bool); ext_hood = np.zeros((H, W), bool)
    for cover_name, depth, rule in EXTEND.get(n, []):
        cover = (full == order.index(cover_name) + 1) & (A >= 250) & ~m
        e = extension(own_op, cover, depth, rule); ext_all |= e
        if cover_name in ('hood', 'face'): ext_hood |= e
    if ext_all.any():
        # под капюшоном — без замощения фактуры: в узкой полосе, что открывается
        # у ворота, замощение читается сеткой; там гладкая заливка с тенью
        col = inpaint_into(col, own_op, ext_all & ~ext_hood)
        if ext_hood.any():
            col = inpaint_into(col, own_op, ext_hood, detail=False)
            # ткань под капюшоном — зеркальное продолжение своей ткани вверх от края
            # (в каждой колонке отражение относительно верхнего края слоя): живая
            # фактура ворота без швов замощения; где отражение не попадает в свой
            # слой, остаётся гладкая заливка
            top = np.where(own_op.any(0), own_op.argmax(0), H)
            yy, xx = np.where(ext_hood)
            ys_ = 2 * top[xx] - yy + 2
            ok = (ys_ < H) & (ys_ >= 0)
            ok[ok] &= own_op[ys_[ok], xx[ok]]
            mir = np.zeros((H, W), bool); mir[yy[ok], xx[ok]] = True
            col[yy[ok], xx[ok]] = clean_i[ys_[ok], xx[ok]]
            # лёгкое размытие отражения: без ступенек между колонками и без
            # отражённых тёмных точек шва (читались чёрточками у ворота)
            bl = ndimage.gaussian_filter(col, (1.4, 1.4, 0)); col[mir] = bl[mir]
            # ворот под капюшоном в тени: запас темнеет вглубь (до −22 % на 45 px),
            # иначе при наклоне головы из-под обода выглядывает светлый треугольник
            dd = ndimage.distance_transform_edt(~own_op)
            col[ext_hood] *= (1 - 0.22 * np.clip(dd[ext_hood] / 45, 0, 1))[:, None]
        # внешний край продолжения (там, где за ним фон, а не сам слой) смягчается на ~1.5 px
        soft = ndimage.gaussian_filter((ext_all | m).astype(np.float64), 1.2)
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
# --- подкладка капюшона (D16): на голове, за лицом; закрывает место внутри
# капюшона, если кромка капюшона и лицо разойдутся. В покое целиком закрыта.
hood_own = (full == order.index('hood') + 1) & (A >= 250)
hole = biggest(ndimage.binary_fill_holes(hood_own | (full == order.index('face') + 1)) & ~hood_own)   # только проём лица, без пустот в острие
# под подбородком подкладка не нужна (там запас ворота) — выглядывала серым клином из-под обода
chin_line = np.full(W, float(H)); chin_line[cols] = fb[cols] + 6
lining = ndimage.binary_dilation(hole, iterations=18) & (hole | hood_own) & (Y < chin_line[None, :])
# внутренняя сторона капюшона: гладкая заливка из цвета капюшона, затенённая
# (открывается узкой щелью у подбородка — замощение фактуры читалось сеткой)
# Заливается только из голубой ткани капюшона: под ободом лежат ворсинки
# подбородка, их копия в подкладке выглядывала бежевой полоской.
hood_blue = hood_own & blue & ~ndimage.binary_dilation(face, iterations=6)
lin_col = inpaint_into(clean.copy(), hood_blue, lining, detail=False)
lin_col[lining] *= 0.82
lin_a = np.where(lining, 255.0, 0.0)
layer = np.dstack([lin_col, lin_a]).clip(0, 255).astype(np.uint8); layer[~lining, :3] = 0
Image.fromarray(layer, 'RGBA').save(f'{out}/hood_lining.png', optimize=True)
ys, xs = np.where(lining)
meta['layers']['hood_lining'] = {'bbox': [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1], 'px': int(lining.sum()), 'hidden': True}
fi = meta['order_back_to_front'].index('ears')
meta['order_back_to_front'].insert(fi, 'hood_lining')

alpha_err = np.abs(recon[..., 3] - A).max()
meta['check'] = {'alphaMaxError': float(alpha_err)}
json.dump(meta, open(f'{out}/layers.json', 'w'), indent=1, ensure_ascii=False)
print(json.dumps({k: v for k, v in meta.items() if k != 'layers'}, ensure_ascii=False))
for n, v in meta['layers'].items(): print(f'{n:11s} bbox {v["bbox"]}  px {v["px"]}')
