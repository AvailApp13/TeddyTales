#!/usr/bin/env python3
"""
Офлайн-проверка поз без редактора: слои handoff/layers_v2 поворачиваются
вокруг осей костей (как их повернёт Rive) и складываются в порядке отрисовки.

    python3 tools/scripts/simulate_pose.py out.png head=10 arm_left=35 arm_right=-35 leg_left=12 ...

Оси — в координатах артборда (как в teddy mcp:bones), переводятся в кадр
слоёв через общий трансформ слоёв (bear_proportions.photo + AB).
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

R = '/home/user/TeddyTales'
D = f'{R}/handoff/layers_v2'
P = json.load(open(f'{R}/rig/bear_proportions.json'))['photo']
S = 760 / P['bodyHeightPx']
CX, CY = 512 + (666.5 - P['axisX']) * S, 985 - (P['groundY'] - 1000) * S   # центр кадра в артборде
to_full = lambda xa, ya: (666.5 + (xa - CX) / S, 1000 + (ya - CY) / S)
PIVOT = {  # кость: ось в артборде
    'head': (524.0, 554.0), 'arm_left': (381, 577), 'arm_right': (658, 577),
    'leg_left': (453, 812), 'leg_right': (582, 812),
}
BONE_OF = {'ears': 'head', 'face': 'head', 'hood': 'head',
           'paw_left': 'arm_left', 'sleeve_left': 'arm_left', 'paw_right': 'arm_right', 'sleeve_right': 'arm_right',
           'foot_left': 'leg_left', 'foot_right': 'leg_right'}
out = sys.argv[1]
ang = {k: float(v) for k, v in (a.split('=') for a in sys.argv[2:])}
order = json.load(open(f'{D}/layers.json'))['order_back_to_front']
canvas = Image.new('RGBA', (1333, 2000), (40, 40, 46, 255))
for n in order:
    L = Image.open(f'{D}/{n}.png').convert('RGBA')
    b = BONE_OF.get(n)
    if b and ang.get(b):
        px, py = to_full(*PIVOT[b])
        L = L.rotate(-ang[b], resample=Image.BICUBIC, center=(px, py))   # Rive: +угол по часовой (y вниз)
    canvas.alpha_composite(L)
canvas.convert('RGB').save(out)
