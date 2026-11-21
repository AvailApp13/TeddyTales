"""Лапы кухни: убрать с кромки спрайта пиксели скатерти и рукава.

Спрайты лап от GPT вырезаны с припуском: по краю остаётся полоска скатерти
(бледная, зеленоватая) и серо-голубая кромка рукава. Пока лапа лежит, эти
пиксели совпадают с фоном; стоит ей качнуться — полоска едет вместе с
лапой и накрывает настоящую скатерть (заказчик 23.09: «лапки закрывают
скатерть»). Оставляем только мех: тёплый бежевый, насыщенность выше
бледной клетки, — и мягко сводим край.

    python3 tool/trim_kitchen_paws.py            # правит на месте
    python3 tool/trim_kitchen_paws.py --preview  # только картинка проверки
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / 'assets/rooms/kitchen'
PREVIEW = Path('/tmp/claude-0/-home-user-TeddyTales/80e45046-6c08-58de-a596-b9d2149c09f8/scratchpad/kitchenshot/paws_trim.png')


def fur_mask(rgb: np.ndarray) -> np.ndarray:
    r, g, b = [rgb[..., i].astype(float) for i in range(3)]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1)
    warm = (r > g) & (g > b)          # бежевый мех: R > G > B
    greenish = g >= r                  # клетка скатерти
    pale = (sat < 0.10)                # белёсая клетка или блик рукава
    bluish = b > r                     # кромка рукава
    return warm & ~greenish & ~pale & ~bluish


def trim(path: Path, preview: bool):
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im).copy()
    alpha = a[..., 3].astype(float) / 255
    keep = fur_mask(a[..., :3]) & (alpha > 0.5)
    # Дырки внутри меха (тени, складки) оставляем: заполняем маску по
    # связной области, а не по цвету пикселя.
    m = Image.fromarray((keep * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(7))
    m = m.filter(ImageFilter.GaussianBlur(1.0))
    new_alpha = np.minimum(alpha * 255, np.asarray(m).astype(float))
    a[..., 3] = new_alpha.astype(np.uint8)
    out = Image.fromarray(a)
    if not preview:
        out.save(path)
    return im, out


def main():
    preview = '--preview' in sys.argv
    tiles = []
    for name in ['paw_left', 'paw_right']:
        before, after = trim(DIR / f'{name}.png', preview)
        for im in (before, after):
            bg = Image.new('RGBA', im.size, (255, 0, 255, 255))
            bg.paste(im, (0, 0), im)
            tiles.append(bg.resize((im.width * 4, im.height * 4), Image.NEAREST))
    w = sum(t.width + 10 for t in tiles)
    sheet = Image.new('RGBA', (w, max(t.height for t in tiles)), (60, 60, 60, 255))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 10
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print('preview', PREVIEW)


if __name__ == '__main__':
    main()
