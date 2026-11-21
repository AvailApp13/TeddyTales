"""Чертежи к третьей партии слоёв спальни: уши отдельно и взгляд в сторону.

Исходник этого раунда — не картинка комнаты, а наш собранный файл мишки с
открытыми глазами (`bear_open` в полном размере 941 × 1672): подрядчик
правит его, а не рисует заново.

    python3 tool/gen_bedroom_round3.py <bear_open_941.png>
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / 'assets' / 'fonts' / 'Nunito.ttf'
OUT = ROOT / 'docs' / 'bedroom-brief'

W, H = 941, 1672

# Обмеры по собранному файлу с открытыми глазами.
EAR_L = (75, 680, 250, 900)
EAR_R = (690, 610, 900, 860)
EYE_L = (392, 982, 22)          # центр x, центр y, радиус
EYE_R = (585, 950, 22)
EYE_ZONE_L = (355, 945, 430, 1020)
EYE_ZONE_R = (548, 913, 622, 988)
PUPIL_SHIFT = 10

INK = (26, 32, 46)
RED = (214, 69, 54)
GREEN = (46, 138, 94)
BLUE = (38, 106, 189)
GREY = (120, 132, 152)
PAPER = (255, 255, 255)


def font(size):
    return ImageFont.truetype(str(FONT), size)


def label(draw, xy, text, size=22, fill=INK, anchor='la', pad=4):
    f = font(size)
    lines = text.split('\n')
    step = size * 1.3
    shift = {'m': -(len(lines) - 1) / 2, 'b': -(len(lines) - 1), 'd': -(len(lines) - 1)}
    first = shift.get(anchor[1], 0.0) * step
    spots = [(xy[0], xy[1] + first + i * step) for i in range(len(lines))]
    boxes = [draw.textbbox(s, l, font=f, anchor=anchor) for s, l in zip(spots, lines)]
    draw.rectangle([min(b[0] for b in boxes) - pad, min(b[1] for b in boxes) - pad,
                    max(b[2] for b in boxes) + pad, max(b[3] for b in boxes) + pad],
                   fill=PAPER)
    for s, l in zip(spots, lines):
        draw.text(s, l, font=f, fill=fill, anchor=anchor)


def dashed(draw, box, fill, width=4, dash=16):
    x0, y0, x1, y1 = box
    for x in range(int(x0), int(x1), dash * 2):
        draw.line([(x, y0), (min(x + dash, x1), y0)], fill=fill, width=width)
        draw.line([(x, y1), (min(x + dash, x1), y1)], fill=fill, width=width)
    for y in range(int(y0), int(y1), dash * 2):
        draw.line([(x0, y), (x0, min(y + dash, y1))], fill=fill, width=width)
        draw.line([(x1, y), (x1, min(y + dash, y1))], fill=fill, width=width)


def on_checker(image):
    """Прозрачный файл на шахматке — видно, где пустота."""
    back = Image.new('RGB', image.size, (238, 240, 244))
    d = ImageDraw.Draw(back)
    for y in range(0, image.size[1], 24):
        for x in range(0, image.size[0], 24):
            if (x // 24 + y // 24) % 2:
                d.rectangle([x, y, x + 23, y + 23], fill=(222, 225, 231))
    back.paste(image, (0, 0), image)
    return back


# --- 1. Исходник и что в нём меняется --------------------------------------

def sheet_source(bear) -> Image.Image:
    pad = 90
    img = Image.new('RGB', (W + pad * 2, H + pad * 2), PAPER)
    img.paste(on_checker(bear), (pad, pad))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (pad + x, pad + y)

    d.rectangle([P(0, 0), P(W - 1, H - 1)], outline=GREY, width=2)
    label(d, (pad + W / 2, pad - 40), 'исходник этого раунда: bear_open_941.png, 941 × 1672', 26, INK, 'mm')

    for box, name in ((EAR_L, 'левое ухо'), (EAR_R, 'правое ухо')):
        dashed(d, (P(box[0], box[1]) + P(box[2], box[3])), GREEN, 5)
    label(d, P(EAR_L[0], EAR_L[3] + 12), 'левое ухо\n75–250 × 680–900', 22, GREEN, 'lt')
    label(d, P(EAR_R[2], EAR_R[1] - 12), 'правое ухо\n690–900 × 610–860', 22, GREEN, 'rb')

    zone = (min(EYE_ZONE_L[0], EYE_ZONE_R[0]), min(EYE_ZONE_L[1], EYE_ZONE_R[1]),
            max(EYE_ZONE_L[2], EYE_ZONE_R[2]), max(EYE_ZONE_L[3], EYE_ZONE_R[3]))
    dashed(d, (P(zone[0], zone[1]) + P(zone[2], zone[3])), RED, 5)
    label(d, P(zone[2] + 14, zone[1]), 'глаза\n355–622 × 913–1020', 22, RED, 'lt')

    label(d, P(20, H - 20), 'Всё, что вне пунктира, во всех файлах остаётся точка в точку.',
          22, INK, 'ld')
    return img


# --- 2. Уши крупно ---------------------------------------------------------

def sheet_ears(bear) -> Image.Image:
    k = 2
    box = (40, 560, 940, 940)
    crop = on_checker(bear.crop(box)).resize(((box[2] - box[0]) * k, (box[3] - box[1]) * k), Image.LANCZOS)
    pad = 110
    img = Image.new('RGB', (crop.size[0] + pad * 2, crop.size[1] + pad * 2), PAPER)
    img.paste(crop, (pad, pad))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (pad + (x - box[0]) * k, pad + (y - box[1]) * k)

    for ear, name, anchor, spot in (
        (EAR_L, 'левое ухо: 75–250 × 680–900', 'lb', (EAR_L[0], EAR_L[1] - 14)),
        (EAR_R, 'правое ухо: 690–900 × 610–860', 'rb', (EAR_R[2], EAR_R[1] - 14)),
    ):
        dashed(d, (P(ear[0], ear[1]) + P(ear[2], ear[3])), GREEN, 6, 22)
        label(d, P(*spot), name, 26, GREEN, anchor)

    # Где ухо уходит под капюшон — там его надо продлить.
    label(d, P(262, 800), 'здесь ухо уходит под капюшон:\nв файле уха продлить его под\nкапюшон ещё на 25 точек', 22, BLUE, 'lm')
    label(d, P(678, 740), 'здесь ухо уходит под капюшон:\nв файле уха продлить его под\nкапюшон ещё на 25 точек', 22, BLUE, 'rm')
    return img


# --- 3. Глаза крупно: куда двигать зрачки -----------------------------------

def sheet_eyes(bear) -> Image.Image:
    k = 5
    box = (330, 890, 650, 1050)
    crop = bear.convert('RGB').crop(box).resize(((box[2] - box[0]) * k, (box[3] - box[1]) * k), Image.LANCZOS)
    pad = 110
    img = Image.new('RGB', (crop.size[0] + pad * 2, crop.size[1] + pad * 2), PAPER)
    img.paste(crop, (pad, pad))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (pad + (x - box[0]) * k, pad + (y - box[1]) * k)

    for zone in (EYE_ZONE_L, EYE_ZONE_R):
        dashed(d, (P(zone[0], zone[1]) + P(zone[2], zone[3])), RED, 5, 20)
    label(d, P(EYE_ZONE_L[0], EYE_ZONE_L[1] - 12), 'менять можно только внутри пунктира', 26, RED, 'lb')

    for cx, cy, r in (EYE_L, EYE_R):
        d.ellipse([P(cx - r, cy - r), P(cx + r, cy + r)], outline=BLUE, width=4)
        # Стрелки: куда уходит зрачок при взгляде влево и вправо.
        for sign in (-1, 1):
            a = P(cx, cy)
            b = P(cx + sign * PUPIL_SHIFT, cy)
            d.line([a, b], fill=GREEN, width=5)
            d.ellipse([b[0] - 6, b[1] - 6, b[0] + 6, b[1] + 6], fill=GREEN)
    label(d, P(EYE_L[0], EYE_L[1] + 30), f'зрачок {EYE_L[0]}, {EYE_L[1]}\nсдвиг на {PUPIL_SHIFT} влево или вправо',
          22, BLUE, 'mt')
    label(d, P(EYE_R[0], EYE_R[1] + 30), f'зрачок {EYE_R[0]}, {EYE_R[1]}\nсдвиг на {PUPIL_SHIFT} влево или вправо',
          22, BLUE, 'mt')
    label(d, P(box[0] + 6, box[3] - 8), 'Веки, мех, нос, рот — не трогать. Двигается только тёмный зрачок с бликом.',
          22, INK, 'ld')
    return img


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='bear_open в размере 941 × 1672')
    args = parser.parse_args()
    bear = Image.open(args.source).convert('RGBA')
    assert bear.size == (W, H), bear.size

    OUT.mkdir(parents=True, exist_ok=True)
    sheets = {
        'v3-source': sheet_source(bear),
        'v3-ears': sheet_ears(bear),
        'v3-eyes': sheet_eyes(bear),
    }
    for name, image in sheets.items():
        if image.width > 2000:
            image = image.resize((2000, round(image.height * 2000 / image.width)), Image.LANCZOS)
        path = OUT / f'{name}.jpg'
        image.convert('RGB').save(path, quality=92, subsampling=0, optimize=True)
        print(f'{path} — {image.width} × {image.height}, {path.stat().st_size / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
