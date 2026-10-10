"""Режет лист с несколькими товарами на отдельные картинки.

Заказчик присылает для магазина не по одной вещи, а листами: на одном PNG
разом десяток горшков с цветами или пяток кресел и ковриков. Карточка в
магазине продаёт одну вещь, поэтому лист надо разобрать.

Режем по альфе, а не рамками: рамка — прямоугольник, а вещь — нет, и на
соседний предмет она заедет. Связная область непрозрачных пикселей и есть
один предмет; всё, что мельче порога, — это мусор от кисти и обрезки
листьев, их отбрасываем.

Тонкость: у растения листья и кашпо могут не соприкасаться вовсе, а у
полки висящая лиана отрывается от доски. Поэтому маска перед разметкой
«раздувается»: соседние куски одного предмета склеиваются, а разные
предметы, между которыми пустое поле, остаются врозь. Радиус подбирается
на глаз по результату — он же и печатается в отчёте.

    python3 tool/cut_shop.py assets/shop/sheets/s2.png --grow 12
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def split_axis(
    solid: np.ndarray,
    box: tuple[int, int, int, int],
    axis: int,
    gap: int,
    valley: float,
) -> list[tuple[int, int, int, int]]:
    """Делит кусок по провалам плотности вдоль одной оси.

    `axis=0` режет по вертикали (соседи стоят рядом), `axis=1` — по
    горизонтали (обрезок ковра, попавший под полку).

    Не «есть ли хоть один пиксель», а «много ли их»: у пальм кроны соседей
    находят друг на друга, и полностью пустого столбца между горшками не
    бывает — зато бывает глубокий провал.
    """
    left, top, right, bottom = box
    window = solid[top:bottom, left:right]
    profile = window.sum(axis=axis)
    span = len(profile)
    floor = max(1.0, valley * profile.max())

    runs: list[tuple[int, int]] = []
    start: int | None = None
    empty = 0
    for i, dense in enumerate(profile > floor):
        if dense:
            if start is None:
                start = i
            empty = 0
        elif start is not None:
            empty += 1
            # Провал засчитываем не сразу: узкая щель бывает и внутри
            # предмета — между ножками кресла, между листьями.
            if empty >= gap:
                runs.append((start, i - empty + 1))
                start = None
    if start is not None:
        runs.append((start, span))

    # Крошку отбрасываем: это обрывки листьев и теней по краям.
    runs = [r for r in runs if r[1] - r[0] > 0.08 * span]
    if len(runs) < 2:
        return [box]

    if axis == 0:
        return [(left + a, top, left + b, bottom) for a, b in runs]
    return [(left, top + a, right, top + b) for a, b in runs]


def split_piece(
    solid: np.ndarray,
    box: tuple[int, int, int, int],
    gap: int = 10,
    valley: float = 0.04,
    depth: int = 0,
) -> list[tuple[int, int, int, int]]:
    """Режет кусок по обеим осям, пока он делится.

    Раздувание маски склеивает не только части одного предмета, но и
    соседей, стоящих вплотную: четыре горшка в ряд приезжают одним куском,
    а под полкой повисает срезанный край ковра с соседнего ряда.
    """
    if depth > 3:
        return [box]

    for axis in (0, 1):
        parts = split_axis(solid, box, axis, gap, valley)
        if len(parts) > 1:
            return [
                p
                for part in parts
                for p in split_piece(solid, part, gap, valley, depth + 1)
            ]

    return [box]


def cut(
    path: Path,
    out_dir: Path,
    grow: int,
    min_area: float,
    alpha_floor: int,
    pad: int,
    valley: float = 0.04,
) -> list[tuple[str, int, int]]:
    image = Image.open(path).convert('RGBA')
    alpha = np.array(image)[..., 3]

    # Полупрозрачный фон у некоторых листов не нулевой: порог выше нуля
    # отсекает его, не трогая кромку ворса.
    solid = alpha > alpha_floor
    grown = ndimage.binary_dilation(solid, iterations=grow) if grow else solid

    labels, count = ndimage.label(grown)
    total = solid.size
    out: list[tuple[str, int, int]] = []

    out_dir.mkdir(parents=True, exist_ok=True)
    boxes: list[tuple[int, int, int, int]] = []
    for slice_y, slice_x in ndimage.find_objects(labels):
        area = (slice_y.stop - slice_y.start) * (slice_x.stop - slice_x.start)
        if area / total < min_area:
            continue
        boxes.append((slice_x.start, slice_y.start, slice_x.stop, slice_y.stop))

    # Делим по нераздутой маске: раздувание как раз и затягивает просветы,
    # по которым предметы различаются.
    boxes = [b for box in boxes for b in split_piece(solid, box, valley=valley)]

    index = 0
    for left_edge, top_edge, right_edge, bottom_edge in boxes:
        slice_y = slice(top_edge, bottom_edge)
        slice_x = slice(left_edge, right_edge)
        index += 1
        top = max(0, slice_y.start - pad)
        left = max(0, slice_x.start - pad)
        piece = image.crop(
            (left, top, min(image.width, slice_x.stop + pad),
             min(image.height, slice_y.stop + pad))
        )
        name = f'{path.stem}_{index:02d}.png'
        piece.save(out_dir / name)
        out.append((name, piece.width, piece.height))

    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sheet', type=Path)
    parser.add_argument('--out', type=Path, default=Path('assets/shop/cut'))
    parser.add_argument('--grow', type=int, default=10,
                        help='на сколько пикселей раздуть маску перед разметкой')
    parser.add_argument('--min-area', type=float, default=0.004,
                        help='доля листа, мельче которой кусок считается мусором')
    parser.add_argument('--alpha', type=int, default=60,
                        help='порог альфы: ниже — фон')
    parser.add_argument('--pad', type=int, default=8)
    parser.add_argument('--valley', type=float, default=0.04,
                        help='насколько глубоким должен быть провал между '
                             'соседями, в долях самого плотного столбца')
    args = parser.parse_args()

    pieces = cut(args.sheet, args.out, args.grow, args.min_area, args.alpha,
                 args.pad, args.valley)
    print(f'{args.sheet.name}: {len(pieces)} шт.')
    for name, width, height in pieces:
        print(f'  {name:28} {width} × {height}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
