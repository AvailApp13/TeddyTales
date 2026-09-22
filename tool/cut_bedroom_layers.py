"""Готовит слои спальни для приложения из того, что прислал подрядчик.

Спальня раньше была одной плоской картинкой вместе с мишкой. Чтобы он дышал
и моргал, картинка разобрана на слои; здесь они приводятся к виду, в котором
их грузит приложение.

    python3 tool/cut_bedroom_layers.py <папка-первой-партии> <папка-второй>

На выходе:
    assets/rooms/bedroom.jpg              комната без мишки
    assets/rooms/bedroom/bear_open.png    глаза открыты (глаза пересажены)
    assets/rooms/bedroom/bear_half.png    полуприкрытые глаза
    assets/rooms/bedroom/bear_closed.png  глаза закрыты
    assets/rooms/bedroom/bear_yawn.png    зевок
    assets/rooms/bedroom/bear_paws.png    лапы отдельно, поверх головы
    assets/rooms/bedroom/blanket_front.png передний край одеяла
    assets/rooms/bedroom/lamp_glow.png    свет ночника

Скрипт печатает доли кадра для каждого слоя — их же держит
`lib/widgets/bedroom_scene.dart`. Если пересобираешь слои, сверь числа.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets' / 'rooms' / 'bedroom'

W, H = 941, 1672

# Куда встаёт мишка на картинке комнаты. Снято подгонкой присланной фигуры
# к тому мишке, который был впечатан в фон: см. docs/bedroom-brief.pdf.
BEAR = (354, 690, 234, 263)

# Мишку кладём вдвое крупнее, чем он занимает на фоне: фон и так мягкий,
# а морда — единственное, что зритель разглядывает вблизи.
BEAR_SCALE = 2

# Рот берём у полуприкрытых, глаза у зевка — выходит «глаза закрыты».
# Работает потому, что эти два файла сделаны из одного.
MOUTH = (405, 1030, 560, 1180)

# «Глаза открыты» подрядчик нарисовал отдельным рисунком — он не совпадает
# с остальными по контуру, и подменять его целиком нельзя. Зато сами глаза
# у него на месте: пересаживаем только их в базовый файл, двумя пятнами
# по векам. Координаты — в файле полуприкрытых (941 × 1672).
EYES = ((348, 944, 440, 1020), (535, 905, 648, 1000))

# Лапы — отдельный слой поверх головы: когда мишка, засыпая, клюёт носом,
# голова двигается, а лапы лежат на одеяле, где лежали. Два пятна в файле
# полуприкрытых; их край перекрывает капюшон, потому и с растушёвкой.
PAWS = ((95, 1120, 305, 1330), (665, 1115, 890, 1330))


def cut(image, floor=8):
    """Обрезать до содержимого и вернуть вместе с местом.

    Порог нужен: после пересохранения по всему полю остаётся альфа в
    единицу-две, и обрезка по «хоть что-нибудь» не обрезает ничего.
    """
    mask = image.getchannel('A').point(lambda v: 255 if v > floor else 0)
    box = mask.getbbox()
    return image.crop(box), box


def share(box):
    """Доли кадра 941 × 1672 — в таком виде их держит Dart."""
    left, top, right, bottom = box
    return (f'left: {left / W:.6f}, top: {top / H:.6f}, '
            f'width: {(right - left) / W:.6f}, height: {(bottom - top) / H:.6f}')


def closed_face(folder):
    """Собрать «глаза закрыты» из полуприкрытых и зевка."""
    half = Image.open(folder / '02-half.png').convert('RGBA')
    yawn = Image.open(folder / '01-yawn.png').convert('RGBA')
    mask = Image.new('L', half.size, 0)
    ImageDraw.Draw(mask).ellipse(list(MOUTH), fill=255)
    return Image.composite(half, yawn, mask.filter(ImageFilter.GaussianBlur(9)))


def open_face(folder):
    """Собрать «глаза открыты»: глаза из чужого рисунка на нашей морде.

    Чужой рисунок сначала подгоняется под фигуру базового файла по
    габаритам — они расходятся на десяток точек, — и только потом из него
    вырезаются два пятна с глазами.
    """
    half = Image.open(folder / '02-half.png').convert('RGBA')
    other = Image.open(folder / '03-open.png').convert('RGBA')
    _, box = cut(half, floor=64)
    figure, _ = cut(other, floor=64)
    aligned = Image.new('RGBA', half.size, (0, 0, 0, 0))
    aligned.paste(figure.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS),
                  (box[0], box[1]))
    mask = Image.new('L', half.size, 0)
    for eye in EYES:
        ImageDraw.Draw(mask).ellipse(list(eye), fill=255)
    return Image.composite(aligned, half, mask.filter(ImageFilter.GaussianBlur(8)))


def paws_only(folder):
    """Только лапы, всё остальное прозрачно."""
    half = Image.open(folder / '02-half.png').convert('RGBA')
    mask = Image.new('L', half.size, 0)
    for paw in PAWS:
        ImageDraw.Draw(mask).ellipse(list(paw), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(6))
    half.putalpha(ImageChops.multiply(half.getchannel('A'), mask))
    return half


def put_bear(image, box, name):
    """Вырезать фигуру по общей рамке и сохранить в размере ассета.

    Рамка у всех слоёв мишки одна — иначе лапы, вырезанные по своему
    содержимому, сели бы не туда, где лежат на голове.
    """
    size = (BEAR[2] * BEAR_SCALE, BEAR[3] * BEAR_SCALE)
    path = OUT / name
    image.crop(box).resize(size, Image.LANCZOS).save(path, optimize=True)
    print(f'{path.name:22} {size[0]} × {size[1]}, {path.stat().st_size / 1024:.0f} КБ')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('first', type=Path, help='папка первой партии')
    parser.add_argument('second', type=Path, help='папка второй партии')
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)

    # Комната без мишки. Альфа ей не нужна — это самый нижний слой, и в
    # JPEG она весит вчетверо меньше.
    room = Image.open(args.first / 'room.png').convert('RGB')
    room_path = ROOT / 'assets' / 'rooms' / 'bedroom.jpg'
    room.save(room_path, quality=92, subsampling=0, optimize=True)
    print(f'{room_path.name:22} {room.size[0]} × {room.size[1]}, '
          f'{room_path.stat().st_size / 1024:.0f} КБ')

    half = Image.open(args.second / '02-half.png').convert('RGBA')
    _, box = cut(half)
    put_bear(open_face(args.second), box, 'bear_open.png')
    put_bear(half, box, 'bear_half.png')
    put_bear(Image.open(args.second / '01-yawn.png').convert('RGBA'), box, 'bear_yawn.png')
    put_bear(closed_face(args.second), box, 'bear_closed.png')
    put_bear(paws_only(args.second), box, 'bear_paws.png')

    left, top, width, height = BEAR
    print(f'  мишка: {share((left, top, left + width, top + height))}')

    # Передний край одеяла — как есть, он ложится ровно на свой кусок фона.
    blanket, box = cut(Image.open(args.first / 'blanket_front.png').convert('RGBA'))
    path = OUT / 'blanket_front.png'
    blanket.save(path, optimize=True)
    print(f'{path.name:22} {blanket.size[0]} × {blanket.size[1]}, '
          f'{path.stat().st_size / 1024:.0f} КБ')
    print(f'  одеяло: {share(box)}')

    # Свет ночника — мягкое пятно без единой резкой границы, так что
    # половинного разрешения ему хватает с запасом.
    # Порог ниже: у свечения край и должен уходить в ничто плавно.
    glow, box = cut(Image.open(args.first / 'lamp_glow.png').convert('RGBA'), floor=3)
    glow = glow.resize((glow.size[0] // 2, glow.size[1] // 2), Image.LANCZOS)
    path = OUT / 'lamp_glow.png'
    glow.save(path, optimize=True)
    print(f'{path.name:22} {glow.size[0]} × {glow.size[1]}, '
          f'{path.stat().st_size / 1024:.0f} КБ')
    print(f'  свет: {share(box)}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
