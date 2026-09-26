#!/usr/bin/env python3
"""
Задняя часть капюшона hood_back (D27): капюшон целиком плюс его контур, продолженный за
ушами. Слой лежит под ушами, капюшон (передний слой) — над ними: уши «продеты» в капюшон.
Когда ухо сдвигается, за ним открывается ткань капюшона, а не пустота; сам капюшон стоит.
Тот же слой — запас ткани для движений капюшона и поворотов головы.

За ухом контур капюшона на кадре не виден: он продолжается гладкой кривой по видимому краю
капюшона выше и ниже уха (полином 3-й степени в осях хорды между концами стыка уха,
layers.json → ear_pivots.contact). Ткань — отражение ткани капюшона через линию стыка
(та же вязка и тон), края мягкие. Продолжение не выходит за непрозрачную часть уха — в покое
его закрывает ухо, кадр прежний.

    python3 tools/scripts/hood_back.py      # пишет handoff/layers_v2/hood_back.png, layers.json
"""
import json, os
import numpy as np
import cv2
from PIL import Image
from scipy import ndimage

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'handoff', 'layers_v2')
REACH = 150     # px контура капюшона по обе стороны от стыка — по ним строится продолжение
INSET = 10      # ткань для отражения берётся на столько глубже края капюшона
meta = json.load(open(f'{D}/layers.json'))
hood = np.asarray(Image.open(f'{D}/hood.png').convert('RGBA')).astype(np.float32)
H, W = hood.shape[:2]
hm = (hood[..., 3] > 128).astype(np.uint8)
cnt = max(cv2.findContours(hm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)[0], key=len)[:, 0, :].astype(np.float64)
# ткань под непрозрачной частью капюшона (в покое её закрывает капюшон) — запас для движений;
# полупрозрачную кромку не повторяем: два слоя на кромке сделали бы край плотнее уже в покое
out = np.where((hood[..., 3] >= 250)[..., None], hood, 0).astype(np.float32)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
added = {}
for e in ('ear_left', 'ear_right'):
    ear = np.asarray(Image.open(f'{D}/{e}.png').convert('RGBA'))[..., 3]
    top, bot = [np.array(p, float) for p in meta['ear_pivots'][e]['contact']]
    # концы стыка на контуре капюшона и дуга между ними, закрытая ухом
    it = int(np.argmin(np.hypot(*(cnt - top).T))); ib = int(np.argmin(np.hypot(*(cnt - bot).T)))
    n = len(cnt)
    fwd = (ib - it) % n; hidden = [(it + k) % n for k in range(fwd + 1)]
    if fwd > n / 2: hidden = [(ib + k) % n for k in range((it - ib) % n + 1)]
    hs = set(hidden)
    covered = ear[cnt[:, 1].astype(int), cnt[:, 0].astype(int)] > 128
    # оси хорды: u — от верхнего конца к нижнему, v — наружу от капюшона
    u = (bot - top) / np.linalg.norm(bot - top); v = np.array([-u[1], u[0]])
    mid = (top + bot) / 2
    if hm[int(mid[1] + 20 * v[1]), int(mid[0] + 20 * v[0])]: v = -v
    loc = lambda P: np.c_[(P - top) @ u, (P - top) @ v]
    L = np.linalg.norm(bot - top)
    # опорные точки: видимый контур капюшона по обе стороны стыка (не под ухом)
    ref = [i for i in range(n) if i not in hs and not covered[i]]
    pl = loc(cnt[ref]); near = (pl[:, 0] > -REACH) & (pl[:, 0] < L + REACH) & (np.abs(pl[:, 1]) < REACH)
    pl = pl[near]
    c = np.polyfit(pl[:, 0], pl[:, 1], 3)
    s = np.linspace(0, L, 200); curve = top + np.outer(s, u) + np.outer(np.polyval(c, s), v)
    # область продолжения: между дугой стыка и новой кривой
    poly = np.vstack([cnt[hidden], curve[::-1]]).astype(np.int32)
    R = np.zeros((H, W), np.uint8); cv2.fillPoly(R, [poly], 1)
    R = R.astype(bool) & ~hm.astype(bool)
    # в покое продолжение целиком под непрозрачной частью уха
    R &= ndimage.binary_erosion(ear >= 250, iterations=2)
    # ткань: отражение через линию хорды, глубже края на INSET
    q = np.c_[xx[R], yy[R]]; ql = loc(q)
    src = top + np.outer(ql[:, 0], u) + np.outer(-ql[:, 1] - INSET, v)
    sx = np.clip(np.round(src[:, 0]), 0, W - 1).astype(int); sy = np.clip(np.round(src[:, 1]), 0, H - 1).astype(int)
    ok = hood[sy, sx, 3] >= 250
    rgb = out[..., :3].copy()
    rgb[yy[R][ok].astype(int), xx[R][ok].astype(int)] = hood[sy[ok], sx[ok], :3]
    miss = np.zeros((H, W), bool); miss[yy[R][~ok].astype(int), xx[R][~ok].astype(int)] = True
    if miss.any():
        known = (hood[..., 3] >= 250) | (R & ~miss)
        mask = (~known & ndimage.binary_dilation(R, iterations=8)).astype(np.uint8) * 255
        rgb = cv2.inpaint(rgb.clip(0, 255).astype(np.uint8), mask, 7, cv2.INPAINT_TELEA).astype(np.float32)
    # мягкий край по новой кривой; под кромкой переднего капюшона — непрозрачно
    soft = ndimage.gaussian_filter(R.astype(np.float32), 1.0)
    a = np.where(R, np.clip(soft * 2, 0, 1) * 255, 0)
    under = ndimage.binary_dilation(R, iterations=4) & (hood[..., 3] < 250) & ~R & (ear >= 250)   # под кромкой у стыка, закрытой ухом
    out[..., :3] = np.where((R | under)[..., None], rgb, out[..., :3])
    rgb_under = rgb
    out[..., 3] = np.maximum(out[..., 3], np.where(under, 255, a))
    added[e] = int(R.sum())
    print(e, 'продолжение контура за ухом:', added[e], 'px, выход кривой наружу до', round(float(np.polyval(c, s).max()), 1), 'px')
out[..., :3] = np.where(out[..., 3:4] > 0, out[..., :3], 0)
Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA').save(f'{D}/hood_back.png', optimize=True)
ys, xs = np.where(out[..., 3] > 0)
meta['layers']['hood_back'] = {'bbox': [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1], 'px': int((out[..., 3] > 0).sum()),
                               'hidden': True, 'behind_ears': added}
order = meta['order_back_to_front']
if 'hood_back' not in order: order.insert(order.index('ear_left'), 'hood_back')
json.dump(meta, open(f'{D}/layers.json', 'w'), indent=1, ensure_ascii=False)
print('порядок:', order)
