"""Готовит картинки товаров магазина к упаковке в приложение.

Заказчик присылает вещи кадрами по 1200–1500 пикселей и весом под мегабайт
каждая. В карточке магазина такая картинка показывается стороной меньше
двухсот точек, то есть девять десятых веса уходит впустую — а вес здесь
чувствительный: полсотни товаров лежат в самом приложении, их тянет с собой
каждая установка.

Поэтому: обрезаем прозрачные поля (иначе вещь болтается в кадре и в сетке
карточек выглядит мельче соседей), вписываем в квадрат с небольшим полем и
сохраняем WebP с альфой.

    python3 tool/pack_shop.py assets/shop/mapping.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

SIDE = 512
PAD = 0.04
QUALITY = 86


def pack(source: Path, target: Path) -> tuple[int, int]:
    image = Image.open(source).convert('RGBA')

    # Обрезаем по самой вещи, а не по кадру: у присланных картинок поля
    # разной ширины, и без обрезки одинаковые по размеру вещи выходят в
    # карточках разного масштаба.
    box = image.split()[-1].point(lambda v: 255 if v > 8 else 0).getbbox()
    if box:
        image = image.crop(box)

    inner = round(SIDE * (1 - 2 * PAD))
    image.thumbnail((inner, inner), Image.LANCZOS)

    canvas = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
    canvas.paste(
        image,
        ((SIDE - image.width) // 2, (SIDE - image.height) // 2),
        image,
    )

    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, 'WEBP', quality=QUALITY, method=6)
    return image.size


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mapping', type=Path)
    parser.add_argument('--root', type=Path, default=Path('assets/shop'))
    parser.add_argument('--out', type=Path, default=Path('assets/shop/items'))
    args = parser.parse_args()

    mapping = json.loads(args.mapping.read_text())
    total = 0
    for item_id, relative in mapping.items():
        target = args.out / f'{item_id}.webp'
        pack(args.root / relative, target)
        total += target.stat().st_size

    print(f'{len(mapping)} шт., всего {total / 1024:.0f} КБ, '
          f'в среднем {total / len(mapping) / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
