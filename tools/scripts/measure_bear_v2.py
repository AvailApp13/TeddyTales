#!/usr/bin/env python3
"""
Снимает размерную сетку рига (rig/bear_proportions.json) с нового мишки:
целый кадр handoff/reference/bear_boy_v2_full.png + его слои handoff/layers_v2
+ отдельная голова (для макушки под капюшоном, совмещается по глазам).

    python3 tools/scripts/measure_bear_v2.py <head.png>

Единица — рост без капюшона (макушка -> земля) = 1.0; x от оси (вправо +),
y — высота над землёй. Точки, которых на кадре не видно (плечи, бёдра),
помечены «оценка».
"""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage

R = '/home/user/TeddyTales'
FULL = f'{R}/handoff/reference/bear_boy_v2_full.png'
L = f'{R}/handoff/layers_v2'
head_png = sys.argv[1]

def rgba(p): return np.asarray(Image.open(p).convert('RGBA')).astype(int)
def mask(n): return rgba(f'{L}/{n}.png')[..., 3] > 128
def bbox(m): ys, xs = np.where(m); return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
def blobs(m, k):
    lab, n = ndimage.label(m); s = ndimage.sum(m, lab, range(1, n + 1)); c = ndimage.center_of_mass(m, lab, range(1, n + 1))
    idx = np.argsort(-s)[:k]; return [(c[i][1], c[i][0], s[i], lab == i + 1) for i in idx]

full = rgba(FULL); A = full[..., 3]
face = mask('face')
dark = (A > 200) & (full[..., :3].max(-1) < 60) & face
eyesF = sorted(blobs(dark, 2), key=lambda b: b[0])
axis = (eyesF[0][0] + eyesF[1][0]) / 2
eyeY = (eyesF[0][1] + eyesF[1][1]) / 2
ground = bbox(A > 20)[3]
hoodTop = bbox(A > 20)[1]

# голова целиком (скрыта капюшоном): совмещаем отдельную голову по глазам
hd = rgba(head_png); hA = hd[..., 3] > 128
eyesH = sorted(blobs(hA & (hd[..., :3].max(-1) < 60), 2), key=lambda b: b[0])
k = (eyesF[1][0] - eyesF[0][0]) / (eyesH[1][0] - eyesH[0][0])
hx0, hy0, hx1, hy1 = bbox(hA)
rows = np.where(hA.sum(1) > 0.7 * hA.sum(1).max())[0]          # шар головы без шеи
ball_top, ball_bot = hy0, rows.max()
mapY = lambda y: eyeY + (y - (eyesH[0][1] + eyesH[1][1]) / 2) * k
mapX = lambda x: axis + (x - (eyesH[0][0] + eyesH[1][0]) / 2) * k
headTop = mapY(ball_top)
U = ground - headTop
gx = lambda x: round((x - axis) / U, 4)
gy = lambda y: round((ground - y) / U, 4)
gw = lambda w: round(w / U, 4)
def part(x0, y0, x1, y1, shape='ellipse', src='измерено'):
    return {'x': gx((x0 + x1) / 2), 'y': gy((y0 + y1) / 2), 'w': gw(x1 - x0), 'h': gw(y1 - y0), 'shape': shape, 'source': src}

P = {}
P['head'] = part(mapX(hx0), mapY(ball_top), mapX(hx1), mapY(ball_bot), src='измерено: отдельная голова, совмещённая по глазам (макушка под капюшоном)')
shirt = mask('shirt'); sx0, sy0, sx1, sy1 = bbox(shirt)
pl, pr = mask('paw_left'), mask('paw_right')
torso_x0, torso_x1 = bbox(pl)[2], bbox(pr)[0]                   # тело между лапами
P['body'] = part(torso_x0, sy0, torso_x1, sy1, src='измерено: торс толстовки между лапами')
sh = mask('shorts'); P['body_base'] = part(*bbox(sh), src='измерено: по шортам')
for side, e in (('left', eyesF[0]), ('right', eyesF[1])):
    d = 2 * np.sqrt(e[2] / np.pi); P[f'eye_{side}'] = {'x': gx(e[0]), 'y': gy(e[1]), 'w': gw(d), 'h': gw(d), 'shape': 'ellipse', 'source': 'измерено'}
hsv = np.asarray(Image.open(FULL).convert('RGB').convert('HSV')).astype(int)
brown = face & (A > 200) & (full[..., :3].max(-1) < 150) & (full[..., :3].max(-1) >= 60) & (hsv[..., 1] > 60)
nose = blobs(ndimage.binary_opening(brown, iterations=2), 1)[0][3]; nx0, ny0, nx1, ny1 = bbox(nose)
P['nose'] = part(nx0, ny0, nx1, ny1, src='измерено')
mouth_zone = face & (Y := np.arange(face.shape[0])[:, None]) > ny1
mdark = mouth_zone & (A > 200) & (full[..., :3].max(-1) < 130) & (np.abs(np.arange(face.shape[1])[None, :] - axis) < (nx1 - nx0))
mx0, my0, mx1, my1 = bbox(mdark) if mdark.any() else (nx0, ny1, nx1, ny1 + 20)
P['mouth'] = part(mx0, my0, mx1, my1, src='измерено')
ew = P['eye_left']['w']
for side in ('left', 'right'):
    e = P[f'eye_{side}']; P[f'eyebrow_{side}'] = {'x': e['x'], 'y': round(e['y'] + 1.9 * ew, 4), 'w': round(1.3 * ew, 4), 'h': round(0.35 * ew, 4), 'shape': 'rect', 'source': 'оценка: бровей у мишки нет, место под анимацию'}
ears = blobs(mask('ears'), 2); ears = sorted(ears, key=lambda b: b[0])
for side, b in zip(('left', 'right'), ears):
    x0, y0, x1, y1 = bbox(b[3]); w = x1 - x0
    P[f'ear_{side}'] = {'x': gx((x0 + x1) / 2), 'y': gy(y0 + w / 2), 'w': gw(w), 'h': gw(w * 1.05), 'shape': 'ellipse', 'source': 'измерено: видимая часть уха, низ под капюшоном — оценка'}
for side, pm in (('left', pl), ('right', pr)):
    x0, y0, x1, y1 = bbox(pm); P[f'hand_{side}'] = part(x0, y0, x1, y1, src='измерено: лапа из рукава')
    inner = x1 if side == 'left' else x0
    sx = inner + (-1 if side == 'left' else 1) * 0.02 * U + (axis - inner) * 0.35
    P[f'shoulder_{side}'] = {'x': gx(sx), 'y': gy(sy0 + 0.07 * U), 'w': 0.0, 'h': 0.0, 'shape': 'point', 'source': 'оценка: под рукавом'}
for side in ('left', 'right'):
    x0, y0, x1, y1 = bbox(mask(f'foot_{side}'))
    P[f'foot_{side}'] = part(x0, y0, x1, y1, src='измерено')
    shx0, shy0, shx1, shy1 = bbox(sh)
    legx = (x0 + x1) / 2
    P[f'leg_{side}'] = part(legx - 0.45 * (x1 - x0), shy0 + 0.45 * (shy1 - shy0), legx + 0.45 * (x1 - x0), y1 - 0.25 * (y1 - y0), src='оценка: под шортами')
    P[f'hip_{side}'] = {'x': gx((legx + axis) / 2 + (legx - axis) * 0.2), 'y': gy(shy0 + 0.35 * (shy1 - shy0)), 'w': 0.0, 'h': 0.0, 'shape': 'point', 'source': 'оценка: под шортами'}
P['outfit_head (капюшон)'] = part(*bbox(mask('hood')), shape='rect', src='измерено: слой hood')
P['outfit_body (толстовка)'] = part(*bbox(shirt), shape='rect', src='измерено: слой shirt')
P['outfit_feet (шорты)'] = part(*bbox(sh), shape='rect', src='измерено: слой shorts')

old = json.load(open(f'{R}/rig/bear_proportions.json'))
parts = {k: P[k] for k in old['parts'] if k in P}
H = ground - headTop
new = {
    '_readme': [
        'Размерная сетка мишки-мальчика v2 по handoff/reference/bear_boy_v2_full.png (Higgsfield, без бирки, прозрачный фон).',
        'Снимается скриптом tools/scripts/measure_bear_v2.py со слоёв handoff/layers_v2.',
        'Единица — рост без капюшона (от макушки под капюшоном до земли) = 1.0.',
        'x — смещение от оси симметрии (вправо +), y — высота над землёй.',
        'Ось симметрии — середина между глазами; глаза — чёрные бусины без белка, eye == pupil.',
        'source: «измерено» — по слоям; «оценка» — точка под одеждой (плечи, бёдра, ноги), уточняется при постановке костей.',
    ],
    'photo': {'file': 'handoff/reference/bear_boy_v2_full.png', 'width': int(full.shape[1]), 'height': int(full.shape[0]),
              'axisX': round(float(axis), 1), 'groundY': float(ground), 'headTopY': round(float(headTop), 1), 'hoodTopY': float(hoodTop),
              'bodyHeightPx': round(float(H), 1), 'totalHeightPx': float(ground - hoodTop)},
    'ratios': {
        'headWidthToHeight': parts['head']['w'], 'headToBodyHeight': parts['head']['h'],
        'eyeSpacingToHeadWidth': round((parts['eye_right']['x'] - parts['eye_left']['x']) / parts['head']['w'], 3),
        'noseBelowEyes': round(parts['eye_left']['y'] - parts['nose']['y'], 3),
        'shouldersWidth': round(parts['shoulder_right']['x'] - parts['shoulder_left']['x'], 3),
        'armLength': round(float(np.hypot(parts['hand_left']['x'] - parts['shoulder_left']['x'], parts['hand_left']['y'] - parts['shoulder_left']['y'])), 3),
        'legLength': round(parts['hip_left']['y'] - parts['foot_left']['y'], 3),
        'hoodOverHead': round((headTop - hoodTop) / H, 3),
    },
    'parts': parts,
}
json.dump(new, open(f'{R}/rig/bear_proportions.json', 'w'), ensure_ascii=False, indent=2)
open(f'{R}/rig/bear_proportions.json', 'a').write('\n')
print(json.dumps(new['photo'], ensure_ascii=False)); print(json.dumps(new['ratios'], ensure_ascii=False))
for k in parts: print(f'{k:24s} old {old["parts"][k]["x"]:+.3f},{old["parts"][k]["y"]:.3f} {old["parts"][k]["w"]:.3f}x{old["parts"][k]["h"]:.3f}   new {parts[k]["x"]:+.3f},{parts[k]["y"]:.3f} {parts[k]["w"]:.3f}x{parts[k]["h"]:.3f}')
