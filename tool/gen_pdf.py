"""Печатает HTML-документ из `docs/` в PDF тем же движком, что и браузер.

Нужен для бумаг, которые уходят заказчику: опросники, брифы, размерные
таблицы. Вёрстка живёт в HTML — её видно в правках и можно пересобрать, —
а на выходе получается файл, который открывается на любом телефоне.

    python3 tool/gen_pdf.py docs/kitchen-questions.html

Шрифт берётся из самого проекта (`assets/fonts/Nunito.ttf`), поэтому бумага
выглядит как приложение, а кириллица не рассыпается на квадратики.
"""

from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'


async def render(source: Path, target: Path) -> None:
    from playwright.async_api import async_playwright

    async with async_playwright() as play:
        browser = await play.chromium.launch(
            executable_path=CHROME,
            args=['--no-sandbox', '--font-render-hinting=none'],
        )
        page = await browser.new_page()
        await page.goto(source.resolve().as_uri(), wait_until='networkidle')
        # Шрифт подгружается через @font-face — без этого первая страница
        # успевает напечататься системным.
        await page.evaluate('document.fonts.ready')
        await page.pdf(
            path=str(target),
            format='A4',
            print_background=True,
            prefer_css_page_size=True,
        )
        await browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()

    target = args.out or args.source.with_suffix('.pdf')
    asyncio.run(render(args.source, target))
    print(f'{target} — {target.stat().st_size / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
