"""Чертежи к брифу на слои спальни: схемы, обмеры, наглядные сравнения.

Заказчик отдаёт бриф в GPT одним файлом, поэтому всё, что раньше было
объяснением на словах, должно быть нарисовано и подписано прямо на картинке.
Скрипт собирает эти картинки в `docs/bedroom-brief/`, откуда их забирает
`docs/bedroom-brief.html` и дальше `tool/gen_pdf.py`.

    python3 tool/gen_bedroom_brief.py <папка-с-присланными-слоями>

В папке ожидаются файлы от подрядчика: room.png, blanket_front.png,
lamp_glow.png и четыре варианта мишки got_eyes_open / got_eyes_half /
got_eyes_closed / got_yawn.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets' / 'rooms' / 'bedroom.jpg'
FONT = ROOT / 'assets' / 'fonts' / 'Nunito.ttf'
OUT = ROOT / 'docs' / 'bedroom-brief'

W, H = 941, 1672

# Обмеры сняты с исходной картинки спальни. Меняются только вместе с ней.
BEAR = (355, 690, 591, 950)
FACE = (420, 830, 530, 915)
TIP = (463, 690)
EYE_L = (444, 857, 15, 13)      # центр x, центр y, ширина, высота
EYE_R = (502, 849, 14, 13)
NOSE = (464, 864, 491, 885)
MOUTH = (460, 878, 514, 901)
BLANKET_TOP = 912
GLOW = (785, 740, 880, 942)

# Что прислали: имя файла -> (ширина, высота, левый край, верх).
GOT = {
    'got_eyes_open.png': ('глаза открыты', 860, 946, 65, 400),
    'got_eyes_half.png': ('глаза полуприкрыты', 862, 958, 60, 374),
    'got_eyes_closed.png': ('глаза закрыты', 594, 650, 203, 508),
    'got_yawn.png': ('зевок', 590, 644, 194, 508),
}

INK = (26, 32, 46)
RED = (214, 69, 54)
GREEN = (46, 138, 94)
BLUE = (38, 106, 189)
GREY = (120, 132, 152)
PAPER = (255, 255, 255)


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size)


def label(draw, xy, text, size=22, fill=INK, anchor='la', pad=4, back=PAPER):
    """Подпись на плашке — иначе цифры теряются на пёстрой картинке.

    Многострочные подписи Pillow с якорем не рисует, поэтому строки
    раскладываем сами: так у подписи остаётся та же точка привязки.
    """
    f = font(size)
    lines = text.split('\n')
    step = size * 1.3
    # Якорь по вертикали задаёт, от чего отсчитывать первую строку.
    shift = {'a': 0.0, 't': 0.0, 'm': -(len(lines) - 1) / 2,
             's': 0.0, 'b': -(len(lines) - 1), 'd': -(len(lines) - 1)}
    first = shift.get(anchor[1], 0.0) * step
    spots = [(xy[0], xy[1] + first + i * step) for i in range(len(lines))]

    boxes = [draw.textbbox(spot, line, font=f, anchor=anchor)
             for spot, line in zip(spots, lines)]
    draw.rectangle(
        [min(b[0] for b in boxes) - pad, min(b[1] for b in boxes) - pad,
         max(b[2] for b in boxes) + pad, max(b[3] for b in boxes) + pad],
        fill=back,
    )
    for spot, line in zip(spots, lines):
        draw.text(spot, line, font=f, fill=fill, anchor=anchor)


def dashed(draw, box, fill, width=3, dash=14):
    """Пунктирная рамка: сплошная читается как часть картинки."""
    if len(box) == 2:
        box = (box[0][0], box[0][1], box[1][0], box[1][1])
    x0, y0, x1, y1 = box
    for x in range(int(x0), int(x1), dash * 2):
        draw.line([(x, y0), (min(x + dash, x1), y0)], fill=fill, width=width)
        draw.line([(x, y1), (min(x + dash, x1), y1)], fill=fill, width=width)
    for y in range(int(y0), int(y1), dash * 2):
        draw.line([(x0, y), (x0, min(y + dash, y1))], fill=fill, width=width)
        draw.line([(x1, y), (x1, min(y + dash, y1))], fill=fill, width=width)


def arrow(draw, a, b, fill, width=3, head=9):
    """Стрелка с двумя наконечниками — ею показываем размеры."""
    draw.line([a, b], fill=fill, width=width)
    for tip, other in ((a, b), (b, a)):
        dx, dy = other[0] - tip[0], other[1] - tip[1]
        length = max(1.0, (dx * dx + dy * dy) ** 0.5)
        ux, uy = dx / length, dy / length
        px, py = -uy, ux
        draw.polygon(
            [
                tip,
                (tip[0] + ux * head * 2 + px * head, tip[1] + uy * head * 2 + py * head),
                (tip[0] + ux * head * 2 - px * head, tip[1] + uy * head * 2 - py * head),
            ],
            fill=fill,
        )


# --- 1. Холст целиком: где стоит мишка ------------------------------------

def sheet_canvas() -> Image.Image:
    """Исходная спальня с разметкой: поля, прямоугольник мишки, размеры."""
    scale = 1
    pad_left, pad_top, pad_right, pad_bottom = 150, 110, 90, 90
    room = Image.open(SRC).convert('RGB')
    img = Image.new('RGB', (W + pad_left + pad_right, H + pad_top + pad_bottom), PAPER)
    img.paste(room, (pad_left, pad_top))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (pad_left + x * scale, pad_top + y * scale)

    # Рамка холста и его размер.
    d.rectangle([P(0, 0), P(W - 1, H - 1)], outline=GREY, width=2)
    arrow(d, (pad_left, pad_top - 46), (pad_left + W, pad_top - 46), INK, 3)
    label(d, (pad_left + W / 2, pad_top - 46), '941 точка', 26, INK, 'mm')
    arrow(d, (pad_left - 96, pad_top), (pad_left - 96, pad_top + H), INK, 3)
    label(d, (pad_left - 96, pad_top + H / 2), '1672', 26, INK, 'mm')

    # Прямоугольник мишки.
    x0, y0, x1, y1 = BEAR
    d.rectangle([P(x0, y0), P(x1, y1)], outline=RED, width=4)

    # Отступы от краёв холста.
    d.line([P(0, y0), P(x0, y0)], fill=RED, width=2)
    arrow(d, P(0, y0 - 26), P(x0, y0 - 26), RED, 3)
    label(d, P(x0 / 2, y0 - 26), '355', 24, RED, 'mm')
    d.line([P(x0, 0), P(x0, y0)], fill=RED, width=2)
    arrow(d, P(x0 - 26, 0), P(x0 - 26, y0), RED, 3)
    label(d, P(x0 - 26, y0 / 2), '690', 24, RED, 'mm')

    # Размеры самой фигуры.
    arrow(d, P(x0, y1 + 34), P(x1, y1 + 34), RED, 3)
    label(d, P((x0 + x1) / 2, y1 + 34), '236', 24, RED, 'mm')
    arrow(d, P(x1 + 30, y0), P(x1 + 30, y1), RED, 3)
    label(d, P(x1 + 30, (y0 + y1) / 2), '260', 24, RED, 'mm')

    # Углы прямоугольника — подписи внутрь, чтобы не спорить с выносками.
    label(d, P(x0 + 8, y0 + 8), '355, 690', 24, RED, 'lt')
    label(d, P(x1 - 8, y1 - 8), '591, 950', 24, RED, 'rd')

    # Кончик колпака.
    tx, ty = TIP
    d.line([P(tx, ty - 46), P(tx, ty + 10)], fill=BLUE, width=3)
    label(d, P(tx, ty - 58), 'кончик колпака 463, 690', 22, BLUE, 'mb')

    # Кромка одеяла.
    d.line([P(0, BLANKET_TOP), P(W, BLANKET_TOP)], fill=GREEN, width=3)
    label(d, P(20, BLANKET_TOP + 10), 'одеяло перекрывает мишку от y = 912', 22, GREEN)

    # Свет ночника.
    g = GLOW
    dashed(d, [P(g[0], g[1]), P(g[2], g[3])], (214, 150, 40), 3)
    label(d, P(g[0] - 10, g[1]), 'ядро света ночника\n785–880 × 740–942',
          20, (170, 116, 26), 'rt')

    return img


# --- 2. Мордочка крупно ----------------------------------------------------

def sheet_face() -> Image.Image:
    """Зона лица с обмерами глаз, носа и рта."""
    k = 6                                  # во сколько раз увеличиваем
    box = (400, 810, 550, 930)
    pad = 120
    crop = Image.open(SRC).convert('RGB').crop(box)
    crop = crop.resize(((box[2] - box[0]) * k, (box[3] - box[1]) * k), Image.LANCZOS)
    img = Image.new('RGB', (crop.size[0] + pad * 2, crop.size[1] + pad * 2), PAPER)
    img.paste(crop, (pad, pad))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (pad + (x - box[0]) * k, pad + (y - box[1]) * k)

    # Зона, которую можно менять.
    fx0, fy0, fx1, fy1 = FACE
    dashed(d, [P(fx0, fy0), P(fx1, fy1)], RED, 5, 22)
    label(d, P(fx0, fy0 - 12), 'менять можно только здесь:  420, 830  —  530, 915',
          26, RED, 'lb')

    # Глаза.
    for (cx, cy, w, h), name in ((EYE_L, 'левый глаз'), (EYE_R, 'правый глаз')):
        d.ellipse([P(cx - w / 2, cy - h / 2), P(cx + w / 2, cy + h / 2)],
                  outline=BLUE, width=4)
        d.line([P(cx - 3, cy), P(cx + 3, cy)], fill=BLUE, width=3)
        d.line([P(cx, cy - 3), P(cx, cy + 3)], fill=BLUE, width=3)
    label(d, P(EYE_L[0] - 12, EYE_L[1] + 16), f'{EYE_L[0]}, {EYE_L[1]}\n{EYE_L[2]} × {EYE_L[3]}',
          24, BLUE, 'rt')
    label(d, P(EYE_R[0] + 12, EYE_R[1] - 16), f'{EYE_R[0]}, {EYE_R[1]}\n{EYE_R[2]} × {EYE_R[3]}',
          24, BLUE, 'lb')

    # Наклон головы: глаза не на одной высоте.
    d.line([P(fx0 + 4, EYE_L[1]), P(fx1 - 4, EYE_L[1])], fill=(190, 205, 225), width=2)
    d.line([P(fx0 + 4, EYE_R[1]), P(fx1 - 4, EYE_R[1])], fill=(190, 205, 225), width=2)
    arrow(d, P(fx1 - 16, EYE_R[1]), P(fx1 - 16, EYE_L[1]), GREEN, 3)
    label(d, P(fx1 - 10, (EYE_L[1] + EYE_R[1]) / 2),
          'правый глаз\nвыше на 8', 22, GREEN, 'lm')

    # Нос и рот.
    d.rectangle([P(NOSE[0], NOSE[1]), P(NOSE[2], NOSE[3])], outline=GREEN, width=4)
    label(d, P(NOSE[2] + 12, NOSE[1] + 8), 'нос 464–491 × 864–885\nне трогать',
          24, GREEN, 'lt')
    d.rectangle([P(MOUTH[0], MOUTH[1]), P(MOUTH[2], MOUTH[3])], outline=(150, 90, 170), width=4)
    label(d, P((MOUTH[0] + MOUTH[2]) / 2, MOUTH[3] + 14), 'рот 460–514 × 878–901',
          24, (150, 90, 170), 'ma')

    return img


# --- 3. Что прислали против того, что нужно --------------------------------

def sheet_scale(folder: Path) -> Image.Image:
    """Пять холстов в ряд: четыре присланных и один правильный."""
    k = 0.30
    cw, ch = int(W * k), int(H * k)
    gap, top, bottom = 34, 78, 96
    items = list(GOT.items()) + [(None, ('как надо', 236, 260, 355, 690))]
    img = Image.new('RGB',
                    (len(items) * cw + (len(items) - 1) * gap, ch + top + bottom),
                    PAPER)
    d = ImageDraw.Draw(img)

    for i, (name, (title, w, h, x, y)) in enumerate(items):
        ox = i * (cw + gap)
        d.rectangle([ox, top, ox + cw - 1, top + ch - 1], outline=GREY, width=2)
        colour = GREEN if name is None else RED
        if name is None:
            art = Image.open(SRC).convert('RGB').crop(BEAR)
        else:
            art = Image.open(folder / name).convert('RGBA').crop((x, y, x + w, y + h))
        art = art.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
        if art.mode == 'RGBA':
            img.paste(art, (ox + int(x * k), top + int(y * k)), art)
        else:
            img.paste(art, (ox + int(x * k), top + int(y * k)))
        d.rectangle(
            [ox + int(x * k), top + int(y * k),
             ox + int((x + w) * k), top + int((y + h) * k)],
            outline=colour, width=3,
        )
        label(d, (ox + cw / 2, top - 46), title, 22, INK, 'ma')
        label(d, (ox + cw / 2, top + ch + 14), f'{w} × {h}', 24, colour, 'ma')
        label(d, (ox + cw / 2, top + ch + 48), f'угол {x}, {y}', 20, GREY, 'ma')

    return img


# --- 4. Как складывается сейчас --------------------------------------------

def sheet_stack(folder: Path) -> Image.Image:
    """Слева исходник, справа стопка присланных слоёв без правок."""
    room = Image.open(folder / 'room.png').convert('RGBA')
    bear = Image.open(folder / 'got_eyes_closed.png').convert('RGBA')
    blanket = Image.open(folder / 'blanket_front.png').convert('RGBA')
    glow = Image.open(folder / 'lamp_glow.png').convert('RGBA')
    stack = room.copy()
    for layer in (bear, blanket, glow):
        stack.alpha_composite(layer)

    cut = (0, 430, W, 1180)
    left = Image.open(SRC).convert('RGB').crop(cut)
    right = stack.convert('RGB').crop(cut)
    cw, chh = left.size
    top = 54
    img = Image.new('RGB', (cw * 2 + 26, chh + top), PAPER)
    img.paste(left, (0, top))
    img.paste(right, (cw + 26, top))
    d = ImageDraw.Draw(img)
    label(d, (cw / 2, 8), 'как должно быть', 26, GREEN, 'ma')
    label(d, (cw + 26 + cw / 2, 8), 'как сложились присланные слои', 26, RED, 'ma')
    return img


# --- 5. Почему варианты нельзя рисовать заново ------------------------------

def sheet_jitter(folder: Path) -> Image.Image:
    """Два варианта, подогнанные под общий размер, и их разошедшиеся контуры."""
    size = (236 * 3, 260 * 3)

    def fitted(name):
        im = Image.open(folder / name).convert('RGBA')
        b = im.getchannel('A').point(lambda v: 255 if v > 64 else 0).getbbox()
        return im.crop(b).resize(size, Image.LANCZOS)

    a = fitted('got_eyes_open.png')
    b = fitted('got_eyes_closed.png')

    def flat(layer, back):
        plate = Image.new('RGBA', size, back + (255,))
        plate.alpha_composite(layer)
        return plate.convert('RGB')

    # Третья клетка: контуры двух вариантов разными цветами.
    edge = Image.new('RGB', size, PAPER)
    ed = ImageDraw.Draw(edge)
    for layer, colour in ((a, (214, 69, 54)), (b, (38, 106, 189))):
        mask = layer.getchannel('A').point(lambda v: 255 if v > 110 else 0)
        px = mask.load()
        for y in range(1, size[1] - 1):
            for x in range(1, size[0] - 1):
                if px[x, y] and not (px[x - 1, y] and px[x + 1, y]
                                     and px[x, y - 1] and px[x, y + 1]):
                    ed.point((x, y), fill=colour)

    top = 54
    img = Image.new('RGB', (size[0] * 3 + 52, size[1] + top), PAPER)
    img.paste(flat(a, (238, 241, 246)), (0, top))
    img.paste(flat(b, (238, 241, 246)), (size[0] + 26, top))
    img.paste(edge, (size[0] * 2 + 52, top))
    d = ImageDraw.Draw(img)
    label(d, (size[0] / 2, 8), 'глаза открыты', 24, INK, 'ma')
    label(d, (size[0] * 1.5 + 26, 8), 'глаза закрыты', 24, INK, 'ma')
    label(d, (size[0] * 2.5 + 52, 8), 'контуры наложены друг на друга', 24, INK, 'ma')
    return img


# --- 6. Порядок слоёв -------------------------------------------------------

def sheet_order(folder: Path) -> Image.Image:
    """Порядок слоёв: комната + мишка + одеяло + свет = кадр.

    Раскладка в строку, а не стопкой «в перспективе»: слои полупрозрачные,
    и наложенные друг на друга они превращаются в кашу.
    """
    k = 0.19
    tile = (int(W * k), int(H * k))
    gap, top, bottom = 76, 70, 84

    steps = [
        ('room.png', '1. комната без мишки', GREEN, 'готово'),
        (None, '2. мишка', RED, 'переделать'),
        ('blanket_front.png', '3. край одеяла', GREEN, 'готово'),
        ('lamp_glow.png', '4. свет ночника', GREEN, 'готово'),
    ]

    def plate_of(name):
        if name is None:
            plate = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            plate.paste(Image.open(SRC).convert('RGBA').crop(BEAR), (BEAR[0], BEAR[1]))
            return plate
        return Image.open(folder / name).convert('RGBA')

    def checker(size):
        """Шахматка под прозрачным слоем — иначе не видно, где пустота."""
        back = Image.new('RGB', size, (246, 247, 250))
        dd = ImageDraw.Draw(back)
        cell = 10
        for y in range(0, size[1], cell):
            for x in range(0, size[0], cell):
                if (x // cell + y // cell) % 2:
                    dd.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(231, 234, 240))
        return back

    cells = len(steps) + 1
    side = 70                              # поля, чтобы подписи не обрезало
    width = cells * tile[0] + (cells - 1) * gap + side * 2
    img = Image.new('RGB', (width, tile[1] + top + bottom), PAPER)
    d = ImageDraw.Draw(img)

    result = plate_of('room.png')
    for name, *_ in steps[1:]:
        result.alpha_composite(plate_of(name))

    for i, (name, title, colour, state) in enumerate(steps):
        ox = side + i * (tile[0] + gap)
        plate = plate_of(name).resize(tile, Image.LANCZOS)
        back = checker(tile)
        back.paste(plate, (0, 0), plate)
        img.paste(back, (ox, top))
        d.rectangle([ox, top, ox + tile[0] - 1, top + tile[1] - 1],
                    outline=(190, 199, 214), width=2)
        label(d, (ox + tile[0] / 2, top - 52), title, 23, INK, 'ma')
        label(d, (ox + tile[0] / 2, top - 22), state, 20, colour, 'ma')
        sign = '+' if i < len(steps) - 1 else '='
        label(d, (ox + tile[0] + gap / 2, top + tile[1] / 2), sign, 44, GREY, 'mm')

    ox = side + len(steps) * (tile[0] + gap)
    img.paste(result.convert('RGB').resize(tile, Image.LANCZOS), (ox, top))
    d.rectangle([ox, top, ox + tile[0] - 1, top + tile[1] - 1], outline=INK, width=3)
    label(d, (ox + tile[0] / 2, top - 52), 'кадр в игре', 23, INK, 'ma')

    label(d, (width / 2, top + tile[1] + 26),
          'Мишка двигается вверх-вниз на 1–2% высоты — это дыхание.\n'
          'Варианты лица подменяются между собой — это моргание и зевок.',
          22, GREY, 'ma')
    return img


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path, help='папка с присланными слоями')
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    sheets = {
        'canvas': sheet_canvas(),
        'face': sheet_face(),
        'scale': sheet_scale(args.folder),
        'stack': sheet_stack(args.folder),
        'jitter': sheet_jitter(args.folder),
        'order': sheet_order(args.folder),
    }
    for name, image in sheets.items():
        # Чертежи уходят в PDF, поэтому ширину держим в разумных пределах.
        if image.width > 2000:
            image = image.resize(
                (2000, round(image.height * 2000 / image.width)), Image.LANCZOS
            )
        # JPEG без прореживания цвета: на фотографии комнаты PNG весит втрое
        # больше, а тонкие выноски на таком качестве не страдают.
        path = OUT / f'{name}.jpg'
        image.convert('RGB').save(path, quality=92, subsampling=0, optimize=True)
        print(f'{path} — {image.width} × {image.height}, '
              f'{path.stat().st_size / 1024:.0f} КБ')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
