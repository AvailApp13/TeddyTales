#!/usr/bin/env python3
"""Режет выровненные кадры мишки на детали для рига.

Работает поверх `tool/align_plush.py`: тот сводит независимые генерации на
общую сетку, этот режет их по одним и тем же рамкам. Рамки не выдуманы —
они сняты с силуэта кадра `0calm` на холсте 2480 × 3307:

* до y≈600 виден только конус капюшона, он узкий;
* на y 700–1000 силуэт резко шире синего — это уши торчат из капюшона;
* на y≈1600 силуэт сужается до 863 пикселей: это шея, самое узкое место
  между головой и плечами, и именно там проходит шов;
* на y 1700–2300 силуэт растёт до 1572 — плечи и рукава;
* после y≈2450 синего нет вовсе: начинаются шорты и ноги.

## Почему детали перекрываются

Голова кончается ниже шва, корпус начинается выше него. Голову рисуем
поверх корпуса, поэтому при дыхании и кивке под ней всегда есть тело и дыра
не появляется. Запас перекрытия — `OVERLAP`, его хватает на смещение
головы в обе стороны на половину этой величины.

Именно этого не хватало прошлому ригу: там голова тянулась сеткой и
утаскивала за собой капюшон.

## Почему не нужна борьба с ореолом

Кадры приходят с готовой альфой (background: transparent у модели), а не
вырезаются из фона. Полупрозрачных пикселей с цветом старого фона здесь
просто нет, так что перекраска юбки, которая нужна была при нарезке фото,
тут не требуется.

    python3 tool/cut_parts.py parts/ aligned/*.png
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

OVERLAP = 220
"""Запас перекрытия между деталями в пикселях холста."""

PARTS: dict[str, tuple[int, int, int, int]] = {
    # Капюшон, уши и морда. Низ уходит ниже шеи (1600) на запас перекрытия,
    # но обязан остаться ВЫШЕ белой пуговицы: она начинается на y≈1660.
    # Пуговица, попав и на голову, и на кофту, при подъёме головы
    # раздваивалась — на экране это выглядело как брак склейки.
    'head': (560, 80, 1930, 1645),
    # Кофта с рукавами и лапами. Верх заходит выше шеи, низ — ниже кофты.
    'torso': (430, 1540, 2050, 2520),
    # Шорты и ноги.
    'legs': (660, 2330, 1860, 3260),
}

BODY_FROM = '0calm'
"""Из какого кадра берём корпус и ноги: они одинаковы во всех, берём спокойный."""

HEAD_FROM = ('0calm', '1happy', '2sad', '3sleep', '4chew', '8gazeL', '9gazeR')
"""Кадры, из которых режем головы.

`5cheer` и `6wave` отличаются только позой лап, голова там та же радостная;
`7surprise` не выполнил задачу — рот «о» не сыграл, вернулась та же улыбка.
Брать их как отдельные головы незачем.
"""

WEBP_QUALITY = 92
"""Детали внутри .riv лежат в WEBP; 92 — предел, за которым растёт только вес."""

FEATHER = 150
"""Высота растушёвки нижнего края головы, пиксели холста.

Голова лежит поверх кофты, и в зоне перекрытия обе детали показывают одно
и то же — плечи и ворот. Пока голова стоит, это незаметно: её непрозрачные
пиксели просто закрывают такие же под ними. Стоит голове подняться на
вдохе, и нижняя кромка съезжает: видно ступеньку между «плечами с головы» и
«плечами с кофты».

Лечится не запретом двигаться, а тем, что у головы нет резкого низа:
последние полтораста пикселей она плавно растворяется в кофте, и
расхождение размазывается вместе с кромкой.
"""


def feather_bottom(part: Image.Image, height: int) -> Image.Image:
    """Гасит альфу к нижнему краю детали по линейному градиенту."""
    ramp = Image.linear_gradient('L').resize((part.width, height))
    fade = Image.new('L', part.size, 255)
    fade.paste(ramp.transpose(Image.FLIP_TOP_BOTTOM),
               (0, part.height - height))
    part.putalpha(ImageChops.multiply(part.getchannel('A'), fade))
    return part


def cut(image: Image.Image, box: tuple[int, int, int, int],
        feather: int = 0) -> Image.Image:
    """Вырезает деталь и обрезает пустые поля, сохраняя смещение."""
    part = image.crop(box)
    if feather:
        part = feather_bottom(part, feather)
    tight = part.getbbox()
    if tight is None:
        raise SystemExit(f'Рамка {box} попала в пустоту — проверь координаты')
    return part.crop(tight), (box[0] + tight[0], box[1] + tight[1])


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2

    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)

    frames = {Path(p).stem: Path(p) for p in argv[2:]}
    missing = [n for n in (BODY_FROM, *HEAD_FROM) if n not in frames]
    if missing:
        raise SystemExit(f'Не хватает кадров: {", ".join(missing)}')

    placements: dict[str, dict] = {}

    def emit(name: str, source: str, box: tuple[int, int, int, int],
             feather: int = 0) -> None:
        image = Image.open(frames[source]).convert('RGBA')
        part, (x, y) = cut(image, box, feather)
        part.save(out_dir / f'{name}.webp', 'WEBP',
                  quality=WEBP_QUALITY, method=6)
        placements[name] = {
            'source': source,
            'x': x, 'y': y,
            'w': part.width, 'h': part.height,
        }
        print(f'{name:14s} <- {source:8s} {part.width}x{part.height} @ {x},{y}')

    emit('torso', BODY_FROM, PARTS['torso'])
    emit('legs', BODY_FROM, PARTS['legs'])
    for source in HEAD_FROM:
        emit(f'head_{source[1:]}', source, PARTS['head'], FEATHER)

    (out_dir / 'placements.json').write_text(
        json.dumps(placements, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )
    print(f'\n{len(placements)} деталей -> {out_dir}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
