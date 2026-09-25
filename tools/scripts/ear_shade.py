#!/usr/bin/env python3
"""
Тень сгиба уха (D22): ухо загибается на зрителя по линии сгиба поперёк кости уха;
без светотени это читается как «ухо сузилось». Слой ear_<сторона>_shade — то же ухо с
той же прозрачностью: на складке светлый блик, загнутый край слегка темнее.
Лежит сразу над своим ухом, на той же сетке и весах (tools/lib/bear_weights.mjs), в
анимации проявляется вместе со сгибом (прозрачность 0 в покое).

Прозрачность слоя — ровно как у уха: генератор сетки Rive обводит контур только по
плотным пикселям, и полупрозрачная маска тени обрезалась жёстким краем (сетка из 81
вершины, плоская заливка без меха). С альфой уха контур и сетка совпадают с ухом.

    python3 tools/scripts/ear_shade.py handoff/layers_v2     # вызывается и из split_full_bear.py

Пишет ear_left_shade.png / ear_right_shade.png (кадр 1333×2000, как остальные слои) и
вставляет их в layers.json (order_back_to_front — сразу над ухом, layers).
"""
import json, sys
import numpy as np
from PIL import Image

D = sys.argv[1]
meta = json.load(open(f'{D}/layers.json'))
FOLD_W = (-10, 22)      # ширина сгиба, px кадра — как EAR_FOLD в bear_weights.mjs
# край уха загибается НА зрителя: складка ближе к свету — на ней светлый блик, дальше
# загнутый край слегка темнее (смотрит вниз). Тёмная складка читалась как сгиб назад.
RIDGE = (6, 11)         # блик: центр и полуширина от линии сгиба, px кадра
LIGHT = 0.16            # блик — мех светлее на 16 %
DARK = 0.22             # загнутый край темнее на 22 % (у самого края уха)
OUTER = (25, 110)       # затемнение растёт от складки к краю


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


order = [n for n in meta['order_back_to_front'] if not n.endswith('_shade')]
for en, E in meta['ear_pivots'].items():
    L = np.asarray(Image.open(f'{D}/{en}.png').convert('RGBA')).astype(np.float32)
    H, W = L.shape[:2]
    u = np.subtract(E['tip'], E['pivot']); u /= np.linalg.norm(u)
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    s = (X - E['fold'][0]) * u[0] + (Y - E['fold'][1]) * u[1]     # от линии сгиба наружу
    k = 1 + LIGHT * np.exp(-((s - RIDGE[0]) / RIDGE[1]) ** 2) - DARK * smooth(*OUTER, s)
    out = np.dstack([L[..., :3] * k[..., None], L[..., 3]]).round().clip(0, 255).astype(np.uint8)
    name = f'{en}_shade'
    Image.fromarray(out, 'RGBA').save(f'{D}/{name}.png', optimize=True)
    ys, xs = np.nonzero(out[..., 3])
    meta['layers'][name] = {'bbox': [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
                            'px': int(len(xs)), 'hidden': True}
    order.insert(order.index(en) + 1, name)
    print(name, meta['layers'][name]['bbox'])
meta['order_back_to_front'] = order
json.dump(meta, open(f'{D}/layers.json', 'w'), indent=1, ensure_ascii=False)
