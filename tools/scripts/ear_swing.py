#!/usr/bin/env python3
"""
Ось поворота уха (D26): ухо почти круглое (с продолжением под капюшоном — круг R≈100 px),
и ось D20 стояла в 27 px от центра этого круга — при повороте контур уха почти не менялся
(центр уха сдвигался на 3–5 px даже при 30°). Ось уносится вглубь головы: от центра круга
уха на SWING px к центру лица. Поворот вокруг неё сдвигает ухо вдоль края капюшона
(«внимание» — вверх к острию, «повисли» — вниз-наружу), край капюшона у уха идёт следом
(веса капюшона — tools/lib/bear_weights.mjs, HOOD_EAR).

Пишет в handoff/layers_v2/layers.json → ear_pivots[ухо]: circle [x, y, R] и swing [x, y].
    python3 tools/scripts/ear_swing.py
"""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

SWING = 90   # px кадра от центра круга уха к центру лица
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'handoff', 'layers_v2')
meta = json.load(open(f'{D}/layers.json'))
face = np.asarray(Image.open(f'{D}/face.png'))[..., 3] > 128
fy, fx = np.where(face); F = np.array([fx.mean(), fy.mean()])
for e in ('ear_left', 'ear_right'):
    a = np.asarray(Image.open(f'{D}/{e}.png'))[..., 3] > 128
    ey, ex = np.where(a & ~ndimage.binary_erosion(a, iterations=2))       # контур уха с продолжением
    A = np.c_[2 * ex, 2 * ey, np.ones(len(ex))]; c = np.linalg.lstsq(A, ex ** 2 + ey ** 2, rcond=None)[0]
    C = c[:2]; R = float(np.sqrt(c[2] + C @ C))
    u = (F - C) / np.linalg.norm(F - C); S = C + u * SWING
    meta['ear_pivots'][e]['circle'] = [round(float(C[0]), 1), round(float(C[1]), 1), round(R, 1)]
    meta['ear_pivots'][e]['swing'] = [round(float(S[0]), 1), round(float(S[1]), 1)]
    print(e, 'круг', meta['ear_pivots'][e]['circle'], 'ось', meta['ear_pivots'][e]['swing'])
json.dump(meta, open(f'{D}/layers.json', 'w'), indent=1, ensure_ascii=False)
