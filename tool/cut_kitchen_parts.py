"""Части мишки для кухни из файлов GPT (холст 864 × 1536) → ассеты и доли кадра.

Запуск: python3 tool/cut_kitchen_parts.py <папка со step2 и step3>
Кладёт обрезанные PNG в assets/rooms/kitchen/ и печатает Rect в долях
кадра 941 × 1672 для lib/widgets/kitchen_scene.dart.
"""
import sys, os, glob
import numpy as np
from PIL import Image

SRC = sys.argv[1]
OUT = 'assets/rooms/kitchen'
W, H = 864, 1536  # холст GPT; сцена в долях кадра, поэтому масштаб не важен

PARTS = {
    'foot_left': 'step2/kitchen_foot_left.png', 'foot_right': 'step2/kitchen_foot_right.png',
    'ear_left': 'step3/kitchen_ear_left.png', 'ear_right': 'step3/kitchen_ear_right.png',
    'paw_left': 'step2/kitchen_paw_left.png', 'paw_right': 'step2/kitchen_paw_right.png',
    'sleeve_left': 'step2/kitchen_sleeve_left.png', 'sleeve_right': 'step2/kitchen_sleeve_right.png',
    'torso': 'step2/kitchen_torso.png', 'head': 'step2/kitchen_head.png',
    'eyes_open': 'step3/kitchen_eyes_open.png', 'eyes_closed': 'step3/kitchen_eyes_closed.png',
    'eyes_happy': 'step3/kitchen_eyes_happy.png', 'eyes_sad': 'step3/kitchen_eyes_sad.png',
    'eyes_wide': 'step3/kitchen_eyes_wide.png',
    'mouth_neutral': 'step3/kitchen_mouth_neutral.png', 'mouth_open': 'step3/kitchen_mouth_open.png',
    'mouth_chew': 'step3/kitchen_mouth_chew.png', 'mouth_smile': 'step3/kitchen_mouth_smile.png',
    'mouth_sad': 'step3/kitchen_mouth_sad.png', 'mouth_o': 'step3/kitchen_mouth_o.png',
}
# Общая рамка для сменных спрайтов: глаза и рты режутся одной рамкой, иначе
# при подмене они встанут по-разному.
GROUPS = {'eyes': (372, 776, 484, 828), 'mouth': (396, 824, 458, 860)}

os.makedirs(OUT, exist_ok=True)
print('// доли кадра: Rect.fromLTWH(left, top, width, height)')
for name, rel in PARTS.items():
    im = Image.open(os.path.join(SRC, rel)).convert('RGBA')
    assert im.size == (W, H), (name, im.size)
    a = np.array(im)[..., 3]
    # лапы: припуск под манжету у GPT синий — обрезаем верх до меха
    group = next((g for g in GROUPS if name.startswith(g)), None)
    if group:
        x0, y0, x1, y1 = GROUPS[group]
    else:
        ys, xs = np.where(a > 8)
        x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    crop = im.crop((x0, y0, x1, y1))
    crop.save(os.path.join(OUT, f'{name}.png'), optimize=True)
    print(f"  {name:14s} Rect.fromLTWH({x0/W:.6f}, {y0/H:.6f}, {(x1-x0)/W:.6f}, {(y1-y0)/H:.6f}),  // {x1-x0}×{y1-y0}")
