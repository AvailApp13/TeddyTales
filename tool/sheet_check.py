#!/usr/bin/env python3
"""Проверяет сгенерированный лист персонажа до нарезки.

Ловит то, что дешевле перегенерировать, чем чинить после нарезки: несимметричный
силуэт, неровный фон, контактную тень под лапами, слишком светлый мех у White.
Требования — раздел 2.2 `docs/tz-animator-v2.md`, порядок работы —
`docs/graphics-brief.md`.

    python3 tool/sheet_check.py graphics/source/slow_child.png
    python3 tool/sheet_check.py graphics/source/joy_child.png --white

Симметрию считаем относительно центра силуэта, а не центра холста: модель
почти никогда не ставит персонажа ровно посередине, и от центра холста
проверка врала бы на каждом листе.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print('Нужен Pillow: pip install pillow', file=sys.stderr)
    raise SystemExit(1)

BACKGROUND = (0x80, 0x80, 0x80)

# Насколько пиксель должен отличаться от фона, чтобы считаться персонажем.
# Порог по сумме модулей отклонений каналов: мягкая кромка попадает в силуэт,
# шум компрессии — нет.
SILHOUETTE_THRESHOLD = 40

# Допуски из раздела 2.2 ТЗ.
MAX_ASYMMETRY = 0.02
MAX_EAR_OFFSET = 0.01
MAX_WHITE_LUMA = 0xF0  # самая светлая точка меха JOY — не светлее #F0EAE2

# Ниже силуэта не должно быть ничего: контактную тень рисует приложение.
SHADOW_SCAN_ROWS = 40


def load_mask(path: Path, scale: int) -> tuple[list[list[bool]], Image.Image]:
    """Маска силуэта: True там, где персонаж. Лист уменьшается для скорости."""
    image = Image.open(path).convert('RGBA')
    if scale > 1:
        image = image.resize(
            (image.width // scale, image.height // scale), Image.LANCZOS
        )
    pixels = image.load()

    mask = []
    for y in range(image.height):
        row = []
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a < 128:
                row.append(False)
                continue
            distance = (
                abs(r - BACKGROUND[0])
                + abs(g - BACKGROUND[1])
                + abs(b - BACKGROUND[2])
            )
            row.append(distance > SILHOUETTE_THRESHOLD)
        mask.append(row)
    return mask, image


def bounds(mask: list[list[bool]]) -> tuple[int, int, int, int] | None:
    top = bottom = left = right = None
    for y, row in enumerate(mask):
        if not any(row):
            continue
        if top is None:
            top = y
        bottom = y
        first = row.index(True)
        last = len(row) - 1 - row[::-1].index(True)
        left = first if left is None else min(left, first)
        right = last if right is None else max(right, last)
    if top is None:
        return None
    return left, top, right, bottom


def check(path: Path, white: bool, scale: int) -> list[tuple[bool, str]]:
    mask, image = load_mask(path, scale)
    width, height = image.width, image.height
    results: list[tuple[bool, str]] = []

    box = bounds(mask)
    if box is None:
        return [(False, 'Силуэт не найден: лист пустой или фон не отличается')]
    left, top, right, bottom = box

    # --- фон ----------------------------------------------------------------
    pixels = image.load()
    corners = [
        pixels[0, 0][:3],
        pixels[width - 1, 0][:3],
        pixels[0, height - 1][:3],
        pixels[width - 1, height - 1][:3],
    ]
    worst = max(
        sum(abs(c[i] - BACKGROUND[i]) for i in range(3)) for c in corners
    )
    results.append((
        worst <= 12,
        f'Фон в углах: отклонение от #808080 до {worst} '
        f'(нужно ≤ 12) — {", ".join("#%02X%02X%02X" % c for c in corners)}',
    ))

    # --- симметрия ----------------------------------------------------------
    total = sum(sum(row) for row in mask)
    weighted = sum(x for row in mask for x, on in enumerate(row) if on)
    axis = round(weighted / total)

    reach = min(axis - left, right - axis)
    mismatch = 0
    overlap = 0
    for row in mask:
        for offset in range(1, reach + 1):
            a = row[axis - offset]
            b = row[axis + offset]
            if a or b:
                overlap += 1
                if a != b:
                    mismatch += 1
    asymmetry = mismatch / overlap if overlap else 1.0
    results.append((
        asymmetry <= MAX_ASYMMETRY,
        f'Симметрия силуэта: расхождение {asymmetry * 100:.1f}% '
        f'(допуск {MAX_ASYMMETRY * 100:.0f}%), ось x={axis * scale}',
    ))

    # --- уши на одной горизонтали -------------------------------------------
    def topmost(x_from: int, x_to: int) -> int | None:
        for y, row in enumerate(mask):
            if any(row[x_from:x_to]):
                return y
        return None

    left_top = topmost(left, axis)
    right_top = topmost(axis, right + 1)
    if left_top is not None and right_top is not None:
        offset = abs(left_top - right_top) / height
        results.append((
            offset <= MAX_EAR_OFFSET,
            f'Верхние точки половин: расхождение {offset * 100:.1f}% высоты '
            f'(допуск {MAX_EAR_OFFSET * 100:.0f}%)',
        ))

    # --- контактная тень ----------------------------------------------------
    #
    # Тень нельзя искать «ниже силуэта»: если она непрозрачная, она сама
    # попадает в силуэт и растягивает его вниз. Отличаем по цветности —
    # тень серая и темнее фона, а мех хроматичный (Milk Tea) или светлый
    # (White). Смотрим только нижнюю десятую часть фигуры и полосу под ней:
    # выше в эту ловушку попали бы зрачки, они тоже тёмные и серые.
    background_luma = round(
        0.2126 * BACKGROUND[0] + 0.7152 * BACKGROUND[1] + 0.0722 * BACKGROUND[2]
    )
    scan_from = top + int((bottom - top) * 0.9)
    scan_to = min(height, bottom + 1 + SHADOW_SCAN_ROWS)
    shadow = 0
    for y in range(scan_from, scan_to):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue
            if max(r, g, b) - min(r, g, b) > 10:
                continue  # цветное — это мех, не тень
            luma = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            if luma < background_luma - 8:
                shadow += 1
    limit = width // 8
    results.append((
        shadow <= limit,
        f'Серые тёмные пиксели под фигурой: {shadow} (порог {limit})'
        + (' — похоже на контактную тень, её рисует приложение'
           if shadow > limit else ''),
    ))

    # --- яркость меха -------------------------------------------------------
    brightest = 0
    for y, row in enumerate(mask):
        for x, on in enumerate(row):
            if not on:
                continue
            r, g, b, _ = pixels[x, y]
            luma = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            brightest = max(brightest, luma)
    if white:
        results.append((
            brightest <= MAX_WHITE_LUMA,
            f'Самая светлая точка: {brightest} (для White нужно ≤ '
            f'{MAX_WHITE_LUMA}) — иначе силуэт теряется на кремовом фоне',
        ))
    else:
        results.append((True, f'Самая светлая точка: {brightest}'))

    results.append((
        True,
        f'Силуэт: {(right - left) * scale}×{(bottom - top) * scale} px, '
        f'поля слева {left * scale}, справа {(width - right) * scale}, '
        f'сверху {top * scale}, снизу {(height - bottom) * scale}',
    ))
    return results


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('file', type=Path)
    ap.add_argument('--white', action='store_true',
                    help='лист героя JOY: проверить потолок яркости меха')
    ap.add_argument('--scale', type=int, default=2,
                    help='во сколько раз уменьшить лист перед проверкой')
    args = ap.parse_args()

    image = Image.open(args.file)
    print(f'{args.file} — {image.width}×{image.height}\n')
    if min(image.width, image.height) < 2048:
        print('  ⚠  Лист меньше 2048 по короткой стороне — по ТЗ так нельзя\n')

    results = check(args.file, args.white, max(1, args.scale))
    failed = 0
    for ok, text in results:
        print(f'  {"·" if ok else "✗"}  {text}')
        if not ok:
            failed += 1

    print()
    if failed:
        print(f'Лист не принят: нарушений {failed}. Перегенерировать — '
              'после нарезки это уже не чинится.')
        return 1
    print('Лист принят, можно резать.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
