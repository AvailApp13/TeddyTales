"""Сетки нажатия для картинок магазина → lib/game/item_shapes.dart.

Заказчик 09.10 (проверка интерьера): нажатие должно ловить только саму
вещь. Картинка вещи обрезана впритык (tool/pack_shop.py), но углы у неё
прозрачные: у столика между ножками, у растения между листьями. Стоит
столик перед комодом — и нажатие по комоду сквозь пустоту между ножками
открывало столик. По сетке нажимается только то, где на картинке вещь.

    python3 tool/item_shapes.py

Запускается сам в конце tool/pack_shop.py — сетки всегда по нынешним
картинкам.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from hit_grid import grid, to_hex

ROOT = Path(__file__).resolve().parents[1]


def write_shapes(items: Path = ROOT / 'assets/shop/items',
                 target: Path = ROOT / 'lib/game/item_shapes.dart') -> int:
    lines = [
        '// Сгенерировано tool/item_shapes.py — не править руками.',
        '//',
        '// Где на картинке магазина сама вещь: сетка нажатия по прямоугольнику',
        '// картинки (lib/game/hit_mask.dart).',
        '',
        "import 'hit_mask.dart';",
        '',
        'const Map<String, HitMask> itemShapes = {',
    ]
    files = sorted(items.glob('*.webp'))
    for path in files:
        alpha = np.asarray(Image.open(path).convert('RGBA'))[..., 3] / 255.0
        lines.append(f"  '{path.stem}': HitMask(")
        lines.append(f"    '{to_hex(grid(alpha))}',")
        lines.append('  ),')
    lines.append('};')
    target.write_text('\n'.join(lines) + '\n')
    return len(files)


if __name__ == '__main__':
    print(f'{write_shapes()} вещей → lib/game/item_shapes.dart')
