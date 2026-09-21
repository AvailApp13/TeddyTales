"""Готовит картинки товаров магазина к упаковке в приложение.

Заказчик присылает вещи кадрами по 1200–1500 пикселей и весом под мегабайт
каждая. В карточке магазина такая картинка показывается стороной меньше
двухсот точек, то есть девять десятых веса уходит впустую — а вес здесь
чувствительный: полсотни товаров лежат в самом приложении, их тянет с собой
каждая установка.

Поэтому: обрезаем прозрачные поля и сохраняем WebP с альфой.

**Картинка обрезана впритык к вещи, без полей.** До 21.09 каждая вещь
вписывалась в квадрат 512 с полем в 4% — и доля пустоты внутри квадрата у
всех получалась разная: у ромашек в банке вещь занимала 234 точки из 512, у
кресла — 480. В комнате вещь показывается по своему настоящему размеру в
метрах, и считается он по краям картинки: с разными полями один и тот же
метр давал бы разный размер на экране. Поэтому край картинки — это край
вещи, и ничего больше.

    python3 tool/pack_shop.py assets/shop/mapping.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from clean_cut import cleaned_image

SIDE = 512
QUALITY = 86


def pack(source: Path, target: Path) -> tuple[int, int]:
    # Сначала чистим: нарезка листа режет прямоугольниками, и в угол куска
    # попадает лист соседнего растения или полоска фона. В карточке этого
    # не видно, а в полноэкранном просмотре бросается в глаза — заказчик
    # 20.09: «вырезано не аккуратно». Заодно обрезаются прозрачные поля —
    # а с 21.09 это ещё и размер вещи: по краям картинки комната считает,
    # каким она встанет в кадр.
    image, _, _ = cleaned_image(Image.open(source))
    image.thumbnail((SIDE, SIDE), Image.LANCZOS)

    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, 'WEBP', quality=QUALITY, method=6)
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
