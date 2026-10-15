#!/usr/bin/env python3
"""Пересобирает сабсет эмодзи-шрифта под символы, которые есть в коде.

Зачем. В Roboto эмодзи нет, а веб-движок Flutter за недостающими глифами ходит
на fonts.gstatic.com — офлайн вместо иконок получаются квадраты. Полный
Noto Color Emoji весит 10,7 МБ, что неприемлемо и для приложения, и тем более
для упаковки в один файл. Сабсет ровно под используемые символы — около 200 КБ.

Запускать после того, как в интерфейсе появились новые эмодзи:

    python3 tool/subset_emoji.py

Требует fonttools (pip install fonttools) и исходный Noto Color Emoji.
Путь к исходнику задаётся --source, по умолчанию берётся системный.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Диапазоны, которые считаем эмодзи. Взяты шире, чем нужно: лучше положить в
# шрифт лишний символ, чем поймать квадрат в проде.
EMOJI_RANGES = [
    (0x1F000, 0x1FAFF),  # пиктограммы, символы, еда, животные
    (0x2600, 0x27BF),  # погода, знаки, стрелки
    (0x1F1E6, 0x1F1FF),  # флаги
]
EXTRA_CODEPOINTS = {
    0x2B50,  # ⭐
    0x2764,  # ❤
    0xFE0F,  # селектор варианта: без него ❤️ распадается
    0x200D,  # zero-width joiner: составные эмодзи
    0x20E3,  # клавишная рамка
}


def is_emoji(code: int) -> bool:
    if code in EXTRA_CODEPOINTS:
        return True
    return any(low <= code <= high for low, high in EMOJI_RANGES)


def collect(lib_dir: Path) -> set[int]:
    found: set[int] = set()
    # И код, и ARB-словари: после локализации часть эмодзи живёт в переводах.
    for pattern in ('*.dart', '*.arb'):
        for path in sorted(lib_dir.rglob(pattern)):
            for char in path.read_text(encoding='utf-8'):
                code = ord(char)
                if is_emoji(code):
                    found.add(code)
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--lib', default='lib', type=Path)
    ap.add_argument(
        '--source',
        default=Path('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'),
        type=Path,
    )
    ap.add_argument(
        '--out',
        default=Path('assets/fonts/NotoColorEmoji-Subset.ttf'),
        type=Path,
    )
    args = ap.parse_args()

    try:
        from fontTools import subset
    except ImportError:
        print('Нужен fonttools: pip install fonttools', file=sys.stderr)
        return 1

    if not args.source.exists():
        print(f'Нет исходного шрифта: {args.source}', file=sys.stderr)
        print('Скачайте Noto Color Emoji и укажите путь через --source.', file=sys.stderr)
        return 1

    codepoints = collect(args.lib)
    if not codepoints:
        print('В коде не найдено ни одного эмодзи — сабсет не нужен.')
        return 0

    print(f'Найдено символов: {len(codepoints)}')
    args.out.parent.mkdir(parents=True, exist_ok=True)

    subset.main([
        str(args.source),
        '--unicodes=' + ','.join(f'U+{c:04X}' for c in sorted(codepoints)),
        '--output-file=' + str(args.out),
        '--drop-tables+=DSIG',
    ])

    size = args.out.stat().st_size
    print(f'Готово: {args.out} — {size / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    sys.exit(main())
