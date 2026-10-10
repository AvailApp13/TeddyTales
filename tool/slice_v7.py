#!/usr/bin/env python3
"""Режет листы v7 на части по номенклатуре ТЗ 2.3.

Рамки сняты с листа `a1-body` (2880 × 2880) по координатной сетке, а не
выдуманы: у мишки на этом листе руки отведены от корпуса, ноги разведены, и
каждая конечность отделена от соседей полосой фона. Именно поэтому её можно
вырезать, не оставив дыры под перекрытием.

## Перехлёст

ТЗ 2.5 требует на каждом стыке не меньше 10% длины стыка и не меньше 24
единиц артборда. Артборд 1024 на холсте 2880 — это коэффициент 2,81, то
есть 24 единицы превращаются в 68 пикселей холста. Берём с запасом.

Перехлёст нужен затем, что кость гнёт деталь в суставе: если плечо кончается
ровно там, где начинается предплечье, при сгибе между ними откроется щель.

## Растушёвка

Стыки внутри тела растушёвываются: деталь, лежащая выше, к своей границе
плавно тает. На однородном мехе это делает шов невидимым даже когда кости
разошлись сильнее ожидаемого. Растушёвываются только внутренние срезы, а
внешний контур силуэта — никогда: там честная альфа от `unbackground.py`.

    python3 tool/slice_v7.py out/ sheets/
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SHEET = 2880
"""Сторона листа в пикселях."""

# Части тела с листа a1-body. Рамка — (left, top, right, bottom) в пикселях
# холста; `fade` — с какой стороны срез растушёвывается и на сколько
# пикселей. Стороны: 't' верх, 'b' низ.
BODY = {
    # Корпус: от основания шеи до промежности. Верх уходит под голову,
    # низ ложится поверх бёдер и потому тает.
    'torso': {'box': (1000, 940, 1890, 2020), 'fade': {'b': 90}},

    # Руки. Каждое следующее звено ложится поверх предыдущего и тает к нему
    # верхним краем; нижнее звено остаётся плотным. Гасить обе стороны стыка
    # нельзя: две полупрозрачные детали, наложенные друг на друга, дают в
    # зоне перехлёста видимую полосу.
    'arm_left_upper':  {'box': (590, 1080, 1090, 1440), 'fade': {}},
    'arm_left_lower':  {'box': (590, 1350, 1090, 1680), 'fade': {'t': 90}},
    'paw_left':        {'box': (590, 1600, 1090, 1790), 'fade': {'t': 70}},
    'arm_right_upper': {'box': (1790, 1080, 2290, 1440), 'fade': {}},
    'arm_right_lower': {'box': (1790, 1350, 2290, 1680), 'fade': {'t': 90}},
    'paw_right':       {'box': (1790, 1600, 2290, 1790), 'fade': {'t': 70}},

    # Ноги — та же логика сверху вниз.
    'leg_left_upper':  {'box': (1000, 1860, 1480, 2280), 'fade': {}},
    'leg_left_lower':  {'box': (1000, 2190, 1480, 2540), 'fade': {'t': 90}},
    'foot_left':       {'box': (1000, 2460, 1480, 2780), 'fade': {'t': 70}},
    'leg_right_upper': {'box': (1420, 1860, 1900, 2280), 'fade': {}},
    'leg_right_lower': {'box': (1420, 2190, 1900, 2540), 'fade': {'t': 90}},
    'foot_right':      {'box': (1420, 2460, 1900, 2780), 'fade': {'t': 70}},
}


# Голова и лицо с листа b1-head. Рамки сняты по координатной сетке того же
# листа. Уши лежат ПОД головой: на фронтальном ракурсе они выходят из-за
# черепа, и если положить их сверху, при подрагивании они поедут по лбу.
HEAD = {
    'head':      {'box': (330, 450, 2570, 2640), 'fade': {}},
    'ear_left':  {'box': (80, 260, 860, 1290), 'fade': {}},
    'ear_right': {'box': (1940, 260, 2760, 1290), 'fade': {}},
    'muzzle':    {'box': (1060, 1740, 1860, 2400), 'fade': {}},
    'nose':      {'box': (1300, 1820, 1610, 2080), 'fade': {}},
    'eye_left':  {'box': (975, 1585, 1200, 1820), 'fade': {}},
    'eye_right': {'box': (1730, 1585, 1955, 1820), 'fade': {}},
    'mouth':     {'box': (1320, 2070, 1590, 2260), 'fade': {}},
}

# Спрайты состояний: та же рамка, но с другого листа. Подменяются целиком,
# поэтому обязаны совпадать по рамке до пикселя — иначе при смене выражения
# глаз прыгнет.
SPRITES = {
    'eye_left_half':  ('b3-eyes-half', 'eye_left'),
    'eye_right_half': ('b3-eyes-half', 'eye_right'),
    'eye_left_shut':  ('b4-eyes-shut', 'eye_left'),
    'eye_right_shut': ('b4-eyes-shut', 'eye_right'),
    'eye_left_happy': ('b5-happy', 'eye_left'),
    'eye_right_happy': ('b5-happy', 'eye_right'),
    'eye_left_sad':   ('b6-sad', 'eye_left'),
    'eye_right_sad':  ('b6-sad', 'eye_right'),
    'mouth_smile':    ('b5-happy', 'mouth_wide'),
    'mouth_sad':      ('b6-sad', 'mouth'),
    'mouth_open':     ('b7-chew', 'mouth_wide'),
    'mouth_o':        ('b8-surprise', 'mouth_wide'),
}

MOUTH_WIDE = (1230, 2020, 1690, 2330)
"""Расширенная рамка рта: открытый рот и «о» не влезают в рамку вышивки."""

ERASE = ('eye_left', 'eye_right', 'mouth')
"""Что стирается с детали `head`.

Голова вырезается целиком, вместе с лицом. Но глаза и рот кладутся сверху
отдельными деталями — чтобы зрачки могли ездить, а рот меняться. Если
оставить их ещё и на голове, поверх нарисованных глаз лягут настоящие, и
при первом же движении взгляда мишка станет четырёхглазым.

Нос не стирается: он никуда не двигается, и отдельной деталью он нужен
только как якорь совмещения листов.
"""

ERASE_FEATHER = 45
"""Растушёвка заплатки. Резкий край заплатки виден на мехе даже под
глазом."""


def erase(part: Image.Image, origin: tuple[int, int]) -> Image.Image:
    """Закрашивает лицо мехом, взятым рядом.

    Заплатка берётся строго над стираемым местом: там та же шерсть, то же
    направление ворса и тот же свет. Брать её сбоку нельзя — на скуле ворс
    лежит иначе, и заплатка читается пятном.
    """
    left, top = origin
    for name in ERASE:
        box = MOUTH_WIDE if name == 'mouth' else HEAD[name]['box']
        x0, y0, x1, y1 = (box[0] - left, box[1] - top,
                          box[2] - left, box[3] - top)
        height = y1 - y0
        # Откуда брать заплатку. Для глаз — со лба, он прямо над ними и
        # там та же шерсть. Для рта — с подбородка снизу: сверху у рта
        # нос, и заплатка с него сажает на морду тёмное пятно.
        if name == 'mouth':
            donor = part.crop((x0, y1 + 30, x1, y1 + 30 + height))
        else:
            donor = part.crop((x0, max(0, y0 - height - 60),
                               x1, max(height, y0 - 60)))
        if donor.size != (x1 - x0, height):
            donor = donor.resize((x1 - x0, height))
        mask = Image.new('L', (x1 - x0, height), 255)
        mask = mask.filter(ImageFilter.GaussianBlur(0))
        patch = Image.new('L', (x1 - x0, height), 0)
        draw = ImageDraw.Draw(patch)
        draw.rectangle((ERASE_FEATHER, ERASE_FEATHER,
                        x1 - x0 - ERASE_FEATHER, height - ERASE_FEATHER),
                       fill=255)
        patch = patch.filter(ImageFilter.GaussianBlur(ERASE_FEATHER / 2))
        part.paste(donor, (x0, y0), patch)
    return part


SPLIT = 1455
"""Где проходит вертикальный раздел между ногами.

Ноги соприкасаются бёдрами, поэтому разделить их рамкой нельзя: рамка левой
ноги захватила бы кусок правой. Пиксели правее этой линии вырезаются из
левой ноги, левее — из правой.
"""

SPLIT_FADE = 40
"""Растушёвка вертикального раздела: резкая линия по меху видна."""

DUST = 12.0
"""Ниже этой альфы пиксель считается пылью и гасится начисто."""


def feather(alpha: np.ndarray, fade: dict, split: str | None) -> np.ndarray:
    """Гасит альфу к внутренним срезам детали."""
    height, width = alpha.shape
    out = alpha.astype(np.float32)

    if 't' in fade:
        depth = fade['t']
        ramp = np.linspace(0.0, 1.0, depth, dtype=np.float32)
        out[:depth] *= ramp[:, None]
    if 'b' in fade:
        depth = fade['b']
        ramp = np.linspace(1.0, 0.0, depth, dtype=np.float32)
        out[height - depth:] *= ramp[:, None]

    if split == 'left':
        # Деталь слева от раздела: гасим вправо.
        edge = width - SPLIT_FADE
        out[:, edge:] *= np.linspace(1.0, 0.0, SPLIT_FADE, dtype=np.float32)
    elif split == 'right':
        out[:, :SPLIT_FADE] *= np.linspace(0.0, 1.0, SPLIT_FADE,
                                           dtype=np.float32)
    return out


def cut(sheet: Image.Image, spec: dict, split: str | None):
    """Вырезает деталь, растушёвывает срезы и обрезает пустые поля."""
    left, top, right, bottom = spec['box']
    part = sheet.crop((left, top, right, bottom))
    alpha = np.array(part.getchannel('A'), dtype=np.float32)
    alpha = feather(alpha, spec.get('fade', {}), split)
    # Почти прозрачное — в ноль. Иначе тринадцать деталей, наложенных друг
    # на друга, суммируют свои остатки, и каждая рамка проступает на тёмном
    # фоне светлым прямоугольником.
    alpha[alpha < DUST] = 0.0
    part.putalpha(Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8)))

    tight = part.getbbox()
    if tight is None:
        raise SystemExit(f'Рамка {spec["box"]} попала в пустоту')
    return part.crop(tight), (left + tight[0], top + tight[1])


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2

    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    sheets = Path(argv[2])

    body = Image.open(sheets / 'a1-body.png').convert('RGBA')
    placements: dict[str, dict] = {}

    def emit(name: str, sheet_name: str, image: Image.Image, spec: dict,
             split: str | None = None) -> None:
        part, (x, y) = cut(image, spec, split)
        part.save(out_dir / f'{name}.webp', 'WEBP', quality=92, method=6)
        placements[name] = {'sheet': sheet_name, 'x': x, 'y': y,
                            'w': part.width, 'h': part.height}
        print(f'{name:18s} {part.width:4d}x{part.height:<4d} @ {x},{y}')

    head = Image.open(sheets / 'b1-head.png').convert('RGBA')
    for name, spec in HEAD.items():
        image = head
        if name == 'head':
            image = erase(head.copy(), (0, 0))
        emit(name, 'b1-head', image, spec)

    for name, (sheet_name, frame) in SPRITES.items():
        box = MOUTH_WIDE if frame == 'mouth_wide' else HEAD[frame]['box']
        image = Image.open(sheets / f'{sheet_name}.png').convert('RGBA')
        emit(name, sheet_name, image, {'box': box, 'fade': {}})

    for name, spec in BODY.items():
        split = None
        if name.startswith('leg_left') or name.startswith('foot_left'):
            split = 'left'
        elif name.startswith('leg_right') or name.startswith('foot_right'):
            split = 'right'

        emit(name, 'a1-body', body, spec, split)

    (out_dir / 'placements.json').write_text(
        json.dumps(placements, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8')
    print(f'\n{len(placements)} частей -> {out_dir}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
