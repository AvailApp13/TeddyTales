#!/usr/bin/env python3
"""
Схема расстановки костей поверх снимка артборда: порядок, первый и второй клик,
координаты. Координаты берутся из `teddy mcp:bones` (сетка rig/bear_proportions.json).

    python3 tools/scripts/draw_bones_guide.py   # -> handoff/reference/bones_guide.png
"""
import math, re, subprocess
from PIL import Image, ImageDraw, ImageFont

R = '/home/user/TeddyTales'
out = subprocess.run(['node', 'bin/teddy.mjs', 'mcp:bones'], cwd=f'{R}/tools', capture_output=True, text=True).stdout
pts = {m[0]: ((int(m[1]), int(m[2])), (int(m[3]), int(m[4]))) for m in re.findall(r'(\w+)\s+from \((\d+), (\d+)\)\s+to \((\d+), (\d+)\)', out)}
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'; FB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
f = ImageFont.truetype(F, 20); fs = ImageFont.truetype(F, 17); fb = ImageFont.truetype(FB, 24); fn = ImageFont.truetype(FB, 22); ft = ImageFont.truetype(FB, 30)

B = [(1, 'root', (255, 90, 90), 'таз → грудь', (0, 40)),
     (2, 'root_body', (255, 170, 40), 'грудь → центр головы', (28, -20)),
     (3, 'root_arm_left', (90, 200, 255), 'плечо → лапа', (-30, -44)),
     (4, 'root_arm_right', (60, 140, 255), 'плечо → лапа', (10, -44)),
     (5, 'root_leg_left', (120, 230, 120), 'бедро → стопа', (-50, 8)),
     (6, 'root_leg_right', (40, 180, 90), 'бедро → стопа', (20, 8))]

bear = Image.open(f'{R}/handoff/reference/editor_bear_v2.png').convert('RGBA').resize((1024, 1024))
bear.alpha_composite(Image.new('RGBA', bear.size, (0, 0, 0, 90)))
img = Image.new('RGBA', (1724, 1024), (30, 30, 34, 255)); img.alpha_composite(bear, (0, 0))
ov = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)

def bone(a, b, col):
    ax, ay = a; bx, by = b; L = math.hypot(bx - ax, by - ay); ux, uy = (bx - ax) / L, (by - ay) / L; nx, ny = -uy, ux
    w = max(10, L * 0.09); m = (ax + ux * L * 0.18, ay + uy * L * 0.18)
    poly = [a, (m[0] + nx * w, m[1] + ny * w), b, (m[0] - nx * w, m[1] - ny * w)]
    d.polygon(poly, fill=col + (150,)); d.line(poly + [poly[0]], fill=(255, 255, 255, 255), width=2)
    h = 16; d.polygon([b, (bx - ux * h + nx * h * .6, by - uy * h + ny * h * .6), (bx - ux * h - nx * h * .6, by - uy * h - ny * h * .6)], fill=(255, 255, 255, 255))

for n, name, col, _, _ in B: bone(*pts[name], col)
for n, name, col, _, off in B:
    a, b = pts[name]
    d.ellipse((a[0] - 8, a[1] - 8, a[0] + 8, a[1] + 8), fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=2)
    cx, cy = a[0] + off[0], a[1] + off[1]
    if off == (0, 40): d.line([(a[0], a[1] + 9), (cx, cy - 16)], fill=(255, 255, 255, 255), width=2)
    d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=col + (255,), outline=(255, 255, 255, 255), width=2)
    d.text((cx, cy), str(n), font=fn, fill=(0, 0, 0, 255), anchor='mm')
    right = b[0] >= a[0]
    d.text((b[0] + (12 if right else -12), b[1] + 10), name, font=fs, fill=(255, 255, 255, 255), anchor='la' if right else 'ra', stroke_width=3, stroke_fill=(0, 0, 0, 255))
img.alpha_composite(ov)

d = ImageDraw.Draw(img); x, y = 1050, 24
d.text((x, y), 'Кости мишки: порядок', font=ft, fill=(255, 255, 255)); y += 52
d.text((x, y), 'Белая точка — первый клик, стрелка — второй.', font=f, fill=(210, 210, 210)); y += 28
d.text((x, y), 'Координаты — артборд Bear_Boy, как в редакторе.', font=f, fill=(210, 210, 210)); y += 44
for n, name, col, what, _ in B:
    a, b = pts[name]
    clicks = f'сразу клик ({b[0]}, {b[1]})' if n == 2 else f'клик ({a[0]}, {a[1]}) → клик ({b[0]}, {b[1]})'
    tail = {1: 'не выходи из инструмента', 2: 'продолжение root; потом Esc'}.get(n, 'Esc')
    d.ellipse((x, y + 2, x + 30, y + 32), fill=col, outline=(255, 255, 255)); d.text((x + 15, y + 17), str(n), font=fn, fill=(0, 0, 0), anchor='mm')
    d.text((x + 44, y), name, font=fb, fill=(255, 255, 255)); d.text((x + 54 + d.textlength(name, font=fb), y + 4), f'— {what}', font=f, fill=(200, 200, 200))
    d.text((x + 44, y + 32), clicks, font=f, fill=(255, 230, 150)); d.text((x + 44, y + 58), tail, font=fs, fill=(170, 170, 170)); y += 96
y += 6
for line in ['Перед началом: клик по пустому месту холста,', 'чтобы ничего не было выделено.', 'Инструмент Bone — клавиша B.', '',
             'После всех шести: в Hierarchy перетащи', '3, 4, 5, 6 внутрь root. Переименуй каждую', '(двойной клик по имени) — имена как на схеме.', '',
             'Точно попадать не нужно: пришли скрин,', 'координаты поправлю сам.']:
    d.text((x, y), line, font=f, fill=(230, 230, 230)); y += 27
img.convert('RGB').save(f'{R}/handoff/reference/bones_guide.png'); print('ok', sorted(pts))
