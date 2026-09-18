#!/usr/bin/env python3
"""Собирает CJK-сабсет под иероглифы, которые реально есть в переводах.

Зачем. Roboto покрывает кириллицу и латиницу, но не иероглифы: китайская
локаль без CJK-шрифта рисуется квадратами. Полный CJK-шрифт — десятки
мегабайт, для приложения и тем более для упаковки в один файл это
неприемлемо. Сабсет ровно под использованные символы — сотня-другая
килобайт. Тот же приём, что в tool/subset_emoji.py.

Источник символов — китайский ARB (lib/l10n/app_zh.arb) плюс китайские
строки в lib/**/*.dart (реплики питомца лежат в коде). Запускать после
каждого пополнения переводов:

    python3 tool/subset_cjk.py

Требует fonttools и исходный шрифт WenQuanYi Zen Hei (лицензия GPL с
font-embedding exception — встраивание в приложение разрешено явно).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def is_cjk(code: int) -> bool:
    return (
        0x3000 <= code <= 0x303F  # знаки препинания CJK
        or 0x4E00 <= code <= 0x9FFF  # основной массив иероглифов
        or 0x3400 <= code <= 0x4DBF  # расширение A
        or 0xFF00 <= code <= 0xFFEF  # полноширинные формы
    )


def collect(root: Path) -> set[int]:
    found: set[int] = set()

    arb = root / 'lib' / 'l10n' / 'app_zh.arb'
    if arb.exists():
        data = json.loads(arb.read_text(encoding='utf-8'))
        for key, value in data.items():
            if key.startswith('@') or not isinstance(value, str):
                continue
            found.update(ord(c) for c in value if is_cjk(ord(c)))

    for path in sorted((root / 'lib').rglob('*.dart')):
        for char in path.read_text(encoding='utf-8'):
            if is_cjk(ord(char)):
                found.add(ord(char))

    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', default=Path('.'), type=Path)
    ap.add_argument(
        '--source',
        default=Path('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'),
        type=Path,
    )
    ap.add_argument(
        '--out',
        default=Path('assets/fonts/CJK-Subset.ttf'),
        type=Path,
    )
    args = ap.parse_args()

    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError:
        print('Нужен fonttools: pip install fonttools', file=sys.stderr)
        return 1

    if not args.source.exists():
        print(f'Нет исходного шрифта: {args.source}', file=sys.stderr)
        return 1

    codepoints = collect(args.root)
    if not codepoints:
        print('Иероглифов не найдено — сабсет не нужен.')
        return 0

    print(f'Найдено символов: {len(codepoints)}')
    args.out.parent.mkdir(parents=True, exist_ok=True)

    # .ttc — коллекция из трёх начертаний; вынимаем первое в отдельный ttf,
    # subset с коллекциями не работает.
    source = args.source
    if source.suffix.lower() == '.ttc':
        single = args.out.parent / '_cjk_face0.ttf'
        TTFont(str(source), fontNumber=0).save(str(single))
        source = single

    subset.main([
        str(source),
        '--unicodes=' + ','.join(f'U+{c:04X}' for c in sorted(codepoints)),
        '--output-file=' + str(args.out),
        '--drop-tables+=DSIG',
        '--no-hinting',
    ])

    if source.name == '_cjk_face0.ttf':
        source.unlink()

    size = args.out.stat().st_size
    print(f'Готово: {args.out} — {size / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    sys.exit(main())
