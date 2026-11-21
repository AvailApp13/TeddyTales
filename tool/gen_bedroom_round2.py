"""Чертежи ко второй партии слоёв спальни.

Первая партия разбиралась `tool/gen_bedroom_brief.py`. Здесь то же самое для
второй: что прислали, из одного ли файла сделаны варианты, и как выглядит
собранный набор в комнате.

    python3 tool/gen_bedroom_round2.py <папка-первой-партии> <папка-второй>

Первая партия нужна целиком: комната, край одеяла и свет ночника приняты
ещё тогда и в переделку не ходили.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets' / 'rooms' / 'bedroom.jpg'
FONT = ROOT / 'assets' / 'fonts' / 'Nunito.ttf'
OUT = ROOT / 'docs' / 'bedroom-brief'

W, H = 941, 1672
BEAR = (355, 690, 591, 950)
FIT = (236, 260)

# Вторая партия: файл -> подпись.
SENT = {
    '03-open.png': 'глаза открыты',
    '02-half.png': 'полуприкрытые',
    '01-yawn.png': 'зевок',
}

# Рот берём у полуприкрытых, глаза у зевка — получается «глаза закрыты».
MOUTH = (405, 1030, 560, 1180)

INK = (26, 32, 46)
RED = (214, 69, 54)
GREEN = (46, 138, 94)
GREY = (120, 132, 152)
PAPER = (255, 255, 255)


def font(size):
    return ImageFont.truetype(str(FONT), size)


def caption(draw, xy, text, size=23, fill=INK, anchor='ma'):
    draw.text(xy, text, font=font(size), fill=fill, anchor=anchor)


def cut(path):
    """Фигура без пустых полей — как её прислали."""
    im = Image.open(path).convert('RGBA')
    box = im.getchannel('A').point(lambda v: 255 if v > 64 else 0).getbbox()
    return im.crop(box)


def fitted(path):
    """Фигура, приведённая к размеру, который нужен комнате."""
    return cut(path).resize(FIT, Image.LANCZOS)


def closed_from(folder):
    """Собрать «глаза закрыты» из двух присланных файлов.

    Полуприкрытые и зевок сделаны из одного файла: они отличаются ровно
    глазами и ртом. Значит, глаза можно взять у зевка (закрытые), а рот —
    у полуприкрытых (закрытый), и шва не будет.
    """
    half = Image.open(folder / '02-half.png').convert('RGBA')
    yawn = Image.open(folder / '01-yawn.png').convert('RGBA')
    mask = Image.new('L', half.size, 0)
    ImageDraw.Draw(mask).ellipse(list(MOUTH), fill=255)
    return Image.composite(half, yawn, mask.filter(ImageFilter.GaussianBlur(9)))


# --- 1. Размеры второй партии ----------------------------------------------

def sheet_sizes(folder) -> Image.Image:
    k = 0.30
    cw, ch = int(W * k), int(H * k)
    gap, top, bottom = 34, 78, 96
    items = [(folder / n, t) for n, t in SENT.items()]
    width = (len(items) + 1) * cw + len(items) * gap
    img = Image.new('RGB', (width, ch + top + bottom), PAPER)
    d = ImageDraw.Draw(img)

    for i, (path, title) in enumerate(items + [(None, 'как надо')]):
        ox = i * (cw + gap)
        d.rectangle([ox, top, ox + cw - 1, top + ch - 1], outline=GREY, width=2)
        if path is None:
            art = Image.open(SRC).convert('RGBA').crop(BEAR)
            x, y, w, h = BEAR[0], BEAR[1], FIT[0], FIT[1]
            colour = GREEN
        else:
            im = Image.open(path).convert('RGBA')
            box = im.getchannel('A').point(lambda v: 255 if v > 64 else 0).getbbox()
            art = im.crop(box)
            x, y = box[0], box[1]
            w, h = box[2] - box[0], box[3] - box[1]
            colour = RED
        art = art.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
        img.paste(art, (ox + int(x * k), top + int(y * k)), art)
        d.rectangle([ox + int(x * k), top + int(y * k),
                     ox + int((x + w) * k), top + int((y + h) * k)],
                    outline=colour, width=3)
        caption(d, (ox + cw / 2, top - 46), title, 22)
        caption(d, (ox + cw / 2, top + ch + 14), f'{w} × {h}', 24, colour)
        caption(d, (ox + cw / 2, top + ch + 48), f'угол {x}, {y}', 20, GREY)

    return img


# --- 2. Из одного ли файла сделаны варианты --------------------------------

def sheet_same(folder) -> Image.Image:
    """Карты отличий: пара из одного файла против пары из разных."""
    pairs = [
        ('02-half.png', '01-yawn.png',
         'полуприкрытые против зевка',
         'один файл: внутри фигуры — только глаза и рот', GREEN),
        ('02-half.png', '03-open.png',
         'полуприкрытые против открытых',
         'разные рисунки: гуляет контур, мордочка и лапы', RED),
    ]
    tiles = []
    for a, b, title, note, colour in pairs:
        ia = Image.open(folder / a).convert('RGBA')
        ib = Image.open(folder / b).convert('RGBA')
        diff = ImageChops.difference(ia, ib).convert('L').point(
            lambda v: 255 if v > 40 else 0)
        # Чуть утолщаем, иначе на уменьшении тонкие линии пропадают.
        # Больше трёх брать нельзя: волосок по краю раздувается до полосы
        # и становится неотличим от настоящего расхождения.
        diff = diff.filter(ImageFilter.MaxFilter(3))
        plate = Image.new('RGB', (W, H), (20, 24, 34))
        plate.paste(Image.new('RGB', (W, H), colour), (0, 0), diff)
        tiles.append((plate.crop((40, 340, 940, 1380)), title, note, colour))

    tw, th = tiles[0][0].size
    scale = 520 / tw
    tw, th = int(tw * scale), int(th * scale)
    top = 84
    img = Image.new('RGB', (tw * 2 + 40, th + top + 20), PAPER)
    d = ImageDraw.Draw(img)
    for i, (plate, title, note, colour) in enumerate(tiles):
        ox = i * (tw + 40)
        img.paste(plate.resize((tw, th), Image.LANCZOS), (ox, top))
        caption(d, (ox + tw / 2, 10), title, 24)
        caption(d, (ox + tw / 2, 44), note, 21, colour)
    return img


# --- 3. Четыре мордочки крупно ---------------------------------------------

def sheet_faces(folder) -> Image.Image:
    k = 3
    items = [
        (Image.open(SRC).convert('RGB').crop(BEAR).resize(
            (FIT[0] * k, FIT[1] * k), Image.LANCZOS), 'мишка на исходной картинке', GREY),
        (None, 'глаза открыты', RED),
        (None, 'полуприкрытые', GREEN),
        (None, 'зевок', GREEN),
    ]
    art = {
        'глаза открыты': folder / '03-open.png',
        'полуприкрытые': folder / '02-half.png',
        'зевок': folder / '01-yawn.png',
    }
    tiles = []
    for plate, title, colour in items:
        if plate is None:
            s = fitted(art[title]).resize((FIT[0] * k, FIT[1] * k), Image.LANCZOS)
            plate = Image.new('RGBA', s.size, (240, 242, 246, 255))
            plate.alpha_composite(s)
            plate = plate.convert('RGB')
        tiles.append((plate, title, colour))

    tw, th = tiles[0][0].size
    top = 46
    img = Image.new('RGB', (tw * 4 + 30, th + top), PAPER)
    d = ImageDraw.Draw(img)
    for i, (plate, title, colour) in enumerate(tiles):
        ox = i * (tw + 10)
        img.paste(plate, (ox, top))
        caption(d, (ox + tw / 2, 8), title, 26, colour)
    return img


# --- 4. Собранный набор в комнате ------------------------------------------

def sheet_scene(first, second) -> Image.Image:
    room = Image.open(first / 'room.png').convert('RGBA')
    blanket = Image.open(first / 'blanket_front.png').convert('RGBA')
    glow = Image.open(first / 'lamp_glow.png').convert('RGBA')
    closed = closed_from(second)

    def frame(layer):
        canvas = room.copy()
        canvas.alpha_composite(layer, (BEAR[0], BEAR[1]))
        canvas.alpha_composite(blanket)
        canvas.alpha_composite(glow)
        return canvas.convert('RGB')

    box = (230, 620, 720, 1010)
    panes = [(Image.open(SRC).convert('RGB').crop(box), 'исходник как был', GREY)]
    order = [
        (fitted(second / '02-half.png'), 'полуприкрытые', GREEN),
        (closed.crop(closed.getchannel('A').point(
            lambda v: 255 if v > 64 else 0).getbbox()).resize(FIT, Image.LANCZOS),
         'глаза закрыты — собрал из двух', GREEN),
        (fitted(second / '01-yawn.png'), 'зевок', GREEN),
    ]
    for layer, title, colour in order:
        panes.append((frame(layer).crop(box), title, colour))

    tw, th = panes[0][0].size
    top = 46
    img = Image.new('RGB', (tw * 4 + 30, th + top), PAPER)
    d = ImageDraw.Draw(img)
    for i, (plate, title, colour) in enumerate(panes):
        ox = i * (tw + 10)
        img.paste(plate, (ox, top))
        caption(d, (ox + tw / 2, 8), title, 24, colour)
    return img


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('first', type=Path, help='папка первой партии')
    parser.add_argument('second', type=Path, help='папка второй партии')
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    sheets = {
        'v2-sizes': sheet_sizes(args.second),
        'v2-same': sheet_same(args.second),
        'v2-faces': sheet_faces(args.second),
        'v2-scene': sheet_scene(args.first, args.second),
    }
    for name, image in sheets.items():
        if image.width > 2000:
            image = image.resize(
                (2000, round(image.height * 2000 / image.width)), Image.LANCZOS)
        path = OUT / f'{name}.jpg'
        image.convert('RGB').save(path, quality=92, subsampling=0, optimize=True)
        print(f'{path} — {image.width} × {image.height}, '
              f'{path.stat().st_size / 1024:.0f} КБ')

    # Заодно кладём рядом сам собранный слой: он пригодится в сборке.
    closed_from(args.second).save(args.second / '10-closed.png')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
