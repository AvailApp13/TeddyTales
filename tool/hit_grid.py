"""Сетка нажатия: где на картинке вещь (lib/game/hit_mask.dart).

Заказчик 09.10: нажатие должно ловить только саму вещь — не тень и не
прозрачные углы картинки. Сетка 32 × 32 по прямоугольнику картинки; клетка
«вещь», если вещь закрывает хотя бы 15 % клетки, и ещё одна клетка запаса
вокруг — чтобы палец у самого края вещи не промахивался.

Только numpy: модуль подключают и tool/item_shapes.py, и
tool/nursery3d/items.py (Python Blender'а, без scipy).
"""

import numpy as np

SIDE = 32


def grid(alpha, share=0.15, grow=1):
    """alpha — доля непрозрачности 0…1 (высота × ширина) → сетка SIDE × SIDE."""
    h, w = alpha.shape
    ys = np.linspace(0, h, SIDE + 1).astype(int)
    xs = np.linspace(0, w, SIDE + 1).astype(int)
    g = np.zeros((SIDE, SIDE), bool)
    for r in range(SIDE):
        for c in range(SIDE):
            cell = alpha[ys[r]:max(ys[r + 1], ys[r] + 1), xs[c]:max(xs[c + 1], xs[c] + 1)]
            g[r, c] = cell.mean() >= share
    for _ in range(grow):
        p = np.pad(g, 1)
        g = np.zeros_like(g)
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                g |= p[dy:dy + SIDE, dx:dx + SIDE]
    return g


def to_hex(g):
    """Построчно сверху вниз, старший бит байта — левая клетка."""
    return np.packbits(g.reshape(-1)).tobytes().hex()
