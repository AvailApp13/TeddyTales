#!/usr/bin/env python3
"""Генератор гайда размерного ряда интерьера для дизайнера.

Единственный источник правды — lib/game/room_layout.dart (габариты в модулях,
1 модуль = рост мишки = 15 см реального героя) и lib/game/shop_items.dart
(русские названия предметов). Скрипт собирает:

  docs/interior-size-guide.md   — таблица габаритов в модулях и сантиметрах
  docs/interior-size-guide.png  — диаграмма размерного ряда в масштабе

Запуск из корня репозитория:  python3 tool/gen_interior_guide.py
После правки room_layout.dart перегенерировать оба файла этим же скриптом.
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MODULE_CM = 15.0  # рост мишки в сантиметрах — база всей сетки

# --- Парсинг room_layout.dart ------------------------------------------------

PLACEMENT_RE = re.compile(
    r"RoomPlacement\(\s*'(?P<id>\w+)',\s*(?P<fx>[\d.]+),\s*"
    r"w:\s*(?P<w>[\d.]+),\s*h:\s*(?P<h>[\d.]+)"
    r"(?:,\s*wallFy:\s*(?P<wallfy>[\d.]+))?"
)

TITLE_RE = re.compile(r"id:\s*'(?P<id>\w+)',\s*emoji:\s*'[^']*',\s*title:\s*'(?P<title>[^']+)'")

# Группы диаграммы в порядке появления в room_layout.dart.
GROUPS = [
    ('Мебель', {'wardrobe', 'shelf', 'bed', 'dresser', 'table', 'chair',
                'armchair', 'lamp', 'basket', 'rug'}),
    ('Декор', {'pic_bear', 'pic_forest', 'pic_moon', 'clock', 'poster',
               'garland', 'plant', 'cactus', 'pillow_heart', 'pillow_star'}),
    ('Игрушки', {'teddy', 'ball', 'cubes', 'duck', 'drum', 'car', 'train',
                 'puzzle', 'rocket', 'kite'}),
]


def parse():
    layout_src = (ROOT / 'lib/game/room_layout.dart').read_text()
    items_src = (ROOT / 'lib/game/shop_items.dart').read_text()
    titles = {m['id']: m['title'] for m in TITLE_RE.finditer(items_src)}

    rows = []
    for m in PLACEMENT_RE.finditer(layout_src):
        rows.append({
            'id': m['id'],
            'title': titles.get(m['id'], m['id']),
            'w': float(m['w']),
            'h': float(m['h']),
            'wall': m['wallfy'] is not None,
        })
    return rows


def cm(v):
    s = f'{v * MODULE_CM:.1f}'.rstrip('0').rstrip('.')
    return s


# --- Markdown ----------------------------------------------------------------

def write_md(rows):
    lines = [
        '# Размерный ряд интерьера — гайд для дизайнера',
        '',
        '> Файл сгенерирован скриптом `tool/gen_interior_guide.py` из',
        '> `lib/game/room_layout.dart`. Не править руками: меняются габариты —',
        '> правится room_layout.dart, гайд и сцена пересобираются сами.',
        '',
        '## Система измерений',
        '',
        f'Базовый модуль — **рост мишки, стоящего в комнате**: 1 модуль = {MODULE_CM:.0f} см',
        'реального героя. Все предметы каталога заданы в долях этого роста, поэтому',
        'таблица ниже читается двумя способами:',
        '',
        '- **в модулях** — насколько предмет больше или меньше мишки (для композиции кадра);',
        f'- **в сантиметрах** — реальный размер при росте героя {MODULE_CM:.0f} см (для отрисовки).',
        '',
        'Диаграмма в масштабе: `interior-size-guide.png` (пунктир — рост мишки).',
        '',
        '## Что важно дизайнеру',
        '',
        '- Рисовать каждый предмет в пропорции Ш×В из таблицы: арт встанет на место',
        '  эмодзи-заглушки в сцене без переразметки.',
        '- Формат — PNG с прозрачным фоном, без вписанных теней от пола: тень кладёт сцена.',
        '- Запас разрешения: высота предмета в пикселях ≥ 2× его высоты в модулях × 450 px',
        '  (мишка рисуется примерно 450 px на экране ×2 ретина).',
        '- Настенные предметы висят по центру отведённой рамки, напольные прижаты к полу.',
        '- Габариты не догма: если предмету нужна другая пропорция — согласовать, мы',
        '  правим одну строчку в `room_layout.dart`, и сцена перестраивается.',
        '',
    ]
    for group, ids in GROUPS:
        lines += [f'## {group}', '',
                  '| Предмет | id | Ш×В, модули | Ш×В, см | Крепление |',
                  '|---|---|---|---|---|']
        for r in rows:
            if r['id'] not in ids:
                continue
            place = 'стена' if r['wall'] else 'пол'
            lines.append(
                f"| {r['title']} | `{r['id']}` | {r['w']:.2f} × {r['h']:.2f} "
                f"| {cm(r['w'])} × {cm(r['h'])} | {place} |"
            )
        lines.append('')
    lines += [
        '## Сменные поверхности',
        '',
        'Обои (`wall_rose`, `wall_sage`, `wall_sky`) и полы (`floor_wood`,',
        '`floor_light`, `floor_carpet`) — не предметы, а заливки всей сцены.',
        'Дизайнеру нужны тайлящиеся текстуры: обои с мягким паттерном, пол с досками',
        'или ковровым ворсом. Базовые цвета — в `roomSurfaces` того же файла.',
        '',
    ]
    (ROOT / 'docs/interior-size-guide.md').write_text('\n'.join(lines))


# --- PNG-диаграмма -----------------------------------------------------------

BG = (250, 243, 230)        # AppColors.background
INK = (74, 59, 42)          # тёмно-коричневый текст
BOX = (240, 183, 170)       # blush — заливка габаритов
BOX_LINE = (231, 156, 148)  # blushStrong
BEAR = (144, 191, 144)      # sage — эталонный модуль
GRID = (235, 220, 196)      # outline

PX_PER_MODULE = 150
PAD = 60
LABEL_H = 74


def write_png(rows):
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 20)
    font_small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 16)
    font_big = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 30)

    by_id = {r['id']: r for r in rows}
    strips = []  # (заголовок, элементы строки)
    for group, ids in GROUPS:
        items = [by_id[i] for r in rows for i in [r['id']] if i in ids]
        items.sort(key=lambda r: -r['h'])
        strips.append((group, items))

    gap = 46

    def slot_w(r):
        """Слот предмета: сам габарит, но не уже своих подписей."""
        return max(
            r['w'] * PX_PER_MODULE,
            0.55 * PX_PER_MODULE,
            font.getlength(r['title']) + 14,
            font_small.getlength(f"{cm(r['w'])}×{cm(r['h'])} см") + 14,
        )

    strip_hs, strip_ws = [], []
    for group, items in strips:
        max_h = max(r['h'] for r in items)
        strip_hs.append(max(max_h, 1.0) * PX_PER_MODULE + LABEL_H + 70)
        w = PAD * 2 + (1.0 * PX_PER_MODULE * 0.66 + gap)  # эталон-мишка
        w += sum(slot_w(r) + gap for r in items)
        strip_ws.append(w)

    W = int(max(strip_ws))
    H = int(120 + sum(strip_hs))
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)

    d.text((PAD, 34), 'TeddyTales — размерный ряд интерьера', font=font_big, fill=INK)
    d.text((PAD, 78), f'1 модуль = рост мишки = {MODULE_CM:.0f} см. '
                      'Пунктир на каждой полке — этот модуль.',
           font=font, fill=INK)

    y = 120
    for (group, items), sh in zip(strips, strip_hs):
        base = y + sh - LABEL_H  # линия «пола» полки
        d.text((PAD, y + 8), group, font=font_big, fill=INK)
        d.line([(PAD, base), (W - PAD, base)], fill=GRID, width=3)
        # Пунктир модуля.
        my = base - PX_PER_MODULE
        for x in range(PAD, W - PAD, 22):
            d.line([(x, my), (x + 11, my)], fill=BEAR, width=3)

        x = PAD
        # Эталон: силуэт мишки в 1 модуль.
        bw = 1.0 * PX_PER_MODULE * 0.66
        _draw_bear(d, x, base, bw, PX_PER_MODULE)
        d.text((x + bw / 2, base + 12), 'мишка', font=font, fill=INK, anchor='ma')
        d.text((x + bw / 2, base + 38), f'{MODULE_CM:.0f} см', font=font_small,
               fill=INK, anchor='ma')
        x += bw + gap

        for r in items:
            w_px = r['w'] * PX_PER_MODULE
            h_px = r['h'] * PX_PER_MODULE
            slot = slot_w(r)
            bx = x + (slot - w_px) / 2
            d.rounded_rectangle([bx, base - h_px, bx + w_px, base], radius=10,
                                fill=BOX, outline=BOX_LINE, width=3)
            cx = x + slot / 2
            d.text((cx, base + 12), r['title'], font=font, fill=INK, anchor='ma')
            d.text((cx, base + 38), f"{cm(r['w'])}×{cm(r['h'])} см",
                   font=font_small, fill=INK, anchor='ma')
            x += slot + gap
        y += sh

    img.save(ROOT / 'docs/interior-size-guide.png')


def _draw_bear(d, x, base, w, h):
    """Узнаваемый силуэт мишки ровно в 1 модуль высоты."""
    cx = x + w / 2
    head_r = h * 0.19
    ear_r = head_r * 0.45
    body_w, body_h = w * 0.9, h * 0.52
    top = base - h
    # Уши, голова, туловище, лапы.
    for sx in (-1, 1):
        d.ellipse([cx + sx * head_r * 0.85 - ear_r, top + head_r * 0.15 - ear_r,
                   cx + sx * head_r * 0.85 + ear_r, top + head_r * 0.15 + ear_r],
                  fill=BEAR)
    d.ellipse([cx - head_r, top, cx + head_r, top + head_r * 2], fill=BEAR)
    d.rounded_rectangle([cx - body_w / 2, top + head_r * 1.7,
                         cx + body_w / 2, base], radius=int(body_w * 0.3),
                        fill=BEAR)


if __name__ == '__main__':
    rows = parse()
    write_md(rows)
    write_png(rows)
    print(f'OK: {len(rows)} предметов → docs/interior-size-guide.md + .png')
