"""Готовит слои спальни для приложения из присланных подрядчиком файлов.

Спальня раньше была одной плоской картинкой вместе с мишкой. Чтобы он дышал
и моргал, картинка разобрана на слои; здесь они приводятся к виду, в котором
их грузит приложение.

    python3 tool/cut_bedroom_layers.py <папка-мишки> [--room <папка-комнаты>]

Папка мишки (основа 22.09, «гладкий капюшон»):
    base.png        мишка без ушей, глаза открыты, 941 × 1672, фон прозрачный
    ear_l.png       левое ухо (для зрителя) в той же рамке
    ear_r.png       правое ухо
    eyes/r<N><L|R>.jpg
                    зоны глаз из Higgsfield: N — правка (1–2 закрыты,
                    3–4 полуприкрыты, не используются, 5 влево, 6 вправо,
                    7 вниз), L/R — глаз.
                    Кропы ровно по EYES, в координатах основы.

Папка комнаты (первая партия): room.png, blanket_front.png, lamp_glow.png.
Без неё комната, одеяло и свет не пересобираются — они уже в ассетах.

На выходе в assets/rooms/bedroom/:
    bear_open.png    глаза открыты (основа как есть)
    bear_closed.png  закрыты
    bear_left.png    взгляд влево (для зрителя)
    bear_right.png   взгляд вправо
    bear_down.png    взгляд вниз
    bear_paws.png    лапы отдельно, поверх головы
    ear_left.png     левое ухо, слой за головой
    ear_right.png    правое ухо

Скрипт печатает доли кадра для каждого слоя — их же держит
`lib/widgets/bedroom_scene.dart`. Если пересобираешь слои, сверь числа.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets' / 'rooms' / 'bedroom'

W, H = 941, 1672

# Куда встаёт мишка на картинке комнаты: высота снята подгонкой присланной
# фигуры к тому мишке, который был впечатан в фон (docs/bedroom-brief.pdf),
# ширина — по пропорциям основы, чтобы её не сплющивать.
BEAR = (359, 690, 224, 263)

# Мишку кладём вдвое крупнее, чем он занимает на фоне: фон и так мягкий,
# а морда — единственное, что зритель разглядывает вблизи.
BEAR_SCALE = 2

# Зоны глаз в основе. Higgsfield отдаёт всю картинку, но брать из неё можно
# только глаза: остальной ворс он перерисовывает по-своему.
EYES = ((333, 957, 443, 1057), (544, 933, 654, 1033))

# Какая правка Higgsfield идёт на какое лицо. Из двух закрытых выбрана
# та, где веки ровнее. Полуприкрытых (3–4) в наборе нет: веко приложение
# опускает само, шторкой из «закрытых» поверх открытых, — так оно идёт
# плавно, а не тремя кадрами (заказчик 22.09: «как будто покадрово»).
FACES = {'closed': 1, 'left': 5, 'right': 6, 'down': 7}

# Лапы — отдельный слой поверх головы: когда мишка, засыпая, клюёт носом,
# голова двигается, а лапы лежат на одеяле, где лежали. Два пятна в основе;
# их край перекрывает капюшон, потому и с растушёвкой.
PAWS = ((45, 1140, 265, 1375), (650, 1140, 895, 1375))


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


def to_room(point, figure):
    """Точка основы → точка кадра комнаты: фигура вписана в BEAR."""
    left, top, width, height = BEAR
    x0, y0, x1, y1 = figure
    return (left + (point[0] - x0) * width / (x1 - x0),
            top + (point[1] - y0) * height / (y1 - y0))


def eye_mask(size, box):
    """Мягкое пятно по глазу — внутри кропа, чтобы шов не вылезал за него."""
    mask = Image.new('L', size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(mask).ellipse((x0 + 16, y0 + 16, x1 - 16, y1 - 16), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(5))


def face(base, folder, round_no):
    """Основа с пересаженными глазами из правки Higgsfield."""
    result = base
    for box, side in zip(EYES, 'LR'):
        crop = Image.open(folder / 'eyes' / f'r{round_no}{side}.jpg').convert('RGBA')
        layer = Image.new('RGBA', base.size, (0, 0, 0, 0))
        layer.paste(crop, box[:2])
        result = Image.composite(layer, result, eye_mask(base.size, box))
    # Альфа — от основы: у кропов её нет, а край фигуры глаза не задевают.
    result.putalpha(base.getchannel('A'))
    return result


def paws_only(base):
    """Только лапы, всё остальное прозрачно."""
    mask = Image.new('L', base.size, 0)
    for paw in PAWS:
        ImageDraw.Draw(mask).ellipse(list(paw), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(6))
    result = base.copy()
    result.putalpha(ImageChops.multiply(base.getchannel('A'), mask))
    return result


def put_bear(image, box, name):
    """Вырезать фигуру по общей рамке и сохранить в размере ассета.

    Рамка у всех слоёв мишки одна — иначе лапы, вырезанные по своему
    содержимому, сели бы не туда, где лежат на голове.
    """
    size = (BEAR[2] * BEAR_SCALE, BEAR[3] * BEAR_SCALE)
    path = OUT / name
    image.crop(box).resize(size, Image.LANCZOS).save(path, optimize=True)
    print(f'{path.name:22} {size[0]} × {size[1]}, {path.stat().st_size / 1024:.0f} КБ')


def whole_ear(base, ear):
    """Собрать ухо целиком и вернуть его вместе с головой без него.

    Подрядчик вырезал ухо из основы прямоугольником: то, что торчит над
    капюшоном, ушло в файл уха, а низ уха — там, где он уходит под край
    капюшона, — остался в основе. Слой, который дёргается, должен быть
    всем ухом, иначе его низ стоит на месте (заказчик 22.09: «30 % нижней
    части правого уха остаётся»). Поэтому ворс основы, примыкающий к
    вырезанному уху, переносится в слой уха, а в голове стирается.
    Капюшон не ворс — по цвету, — и через него заливка не проходит.
    """
    b = np.asarray(base).astype(int)
    e = np.asarray(ear).astype(int)
    opaque = b[..., 3] > 32
    fur = opaque & (b[..., 0] > b[..., 2] + 10)
    have = e[..., 3] > 32
    # Заливка только рядом с ухом: дальше ворс — уже морда.
    x0, y0, x1, y1 = ear.getchannel('A').getbbox()
    pad = 120
    window = np.zeros_like(fur)
    window[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad] = True
    labels, _ = ndimage.label(fur & window)
    touching = np.unique(labels[ndimage.binary_dilation(have, iterations=2) & (labels > 0)])
    rest = np.isin(labels, touching[touching > 0])
    # Край в полтона: с резким краем при повороте видна ступенька.
    soft = ndimage.gaussian_filter(rest.astype(float), 1.2)
    rest_alpha = (np.clip(soft, 0, 1) * 255).astype(np.uint8)

    full = e.copy()
    take = rest & ~have
    full[take, :3] = b[take, :3]
    full[..., 3] = np.maximum(e[..., 3], np.where(rest, np.minimum(b[..., 3], rest_alpha), 0))
    head = b.copy()
    head[..., 3] = np.where(rest, np.maximum(0, b[..., 3] - rest_alpha), b[..., 3])
    return (Image.fromarray(full.astype(np.uint8), 'RGBA'),
            Image.fromarray(head.astype(np.uint8), 'RGBA'))


def put_ear(image, figure, name):
    """Ухо — по своему содержимому, в том же масштабе, что и мишка."""
    ear, box = cut(image)
    scale = BEAR[2] * BEAR_SCALE / (figure[2] - figure[0])
    size = (round(ear.size[0] * scale), round(ear.size[1] * scale))
    path = OUT / name
    ear.resize(size, Image.LANCZOS).save(path, optimize=True)
    print(f'{path.name:22} {size[0]} × {size[1]}, {path.stat().st_size / 1024:.0f} КБ')
    x0, y0 = to_room(box[:2], figure)
    x1, y1 = to_room(box[2:], figure)
    print(f'  {name}: {share((x0, y0, x1, y1))}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bear', type=Path, help='папка с основой, ушами и глазами')
    parser.add_argument('--room', type=Path, help='папка первой партии: комната, одеяло, свет')
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)

    base = Image.open(args.bear / 'base.png').convert('RGBA')
    _, figure = cut(base, floor=64)

    # Сначала уши: голова, из которой режутся лица, — уже без них.
    ears = []
    for source in ('ear_l.png', 'ear_r.png'):
        ear, base = whole_ear(base, Image.open(args.bear / source).convert('RGBA'))
        ears.append(ear)

    put_bear(base, figure, 'bear_open.png')
    for name, round_no in FACES.items():
        put_bear(face(base, args.bear, round_no), figure, f'bear_{name}.png')
    put_bear(paws_only(base), figure, 'bear_paws.png')

    left, top, width, height = BEAR
    print(f'  мишка: {share((left, top, left + width, top + height))}')
    # Зоны глаз — в долях слоя мишки: по ним приложение опускает веко.
    for side, (x0, y0, x1, y1) in zip(('левый глаз', 'правый глаз'), EYES):
        fx0, fy0, fx1, fy1 = figure
        print(f'  {side}: left: {(x0 - fx0) / (fx1 - fx0):.4f}, '
              f'top: {(y0 - fy0) / (fy1 - fy0):.4f}, '
              f'width: {(x1 - x0) / (fx1 - fx0):.4f}, '
              f'height: {(y1 - y0) / (fy1 - fy0):.4f}')

    put_ear(ears[0], figure, 'ear_left.png')
    put_ear(ears[1], figure, 'ear_right.png')

    if args.room is None:
        return 0

    # Комната без мишки. Альфа ей не нужна — это самый нижний слой, и в
    # JPEG она весит вчетверо меньше.
    room = Image.open(args.room / 'room.png').convert('RGB')
    room_path = ROOT / 'assets' / 'rooms' / 'bedroom.jpg'
    room.save(room_path, quality=92, subsampling=0, optimize=True)
    print(f'{room_path.name:22} {room.size[0]} × {room.size[1]}, '
          f'{room_path.stat().st_size / 1024:.0f} КБ')

    # Передний край одеяла — как есть, он ложится ровно на свой кусок фона.
    blanket, box = cut(Image.open(args.room / 'blanket_front.png').convert('RGBA'))
    path = OUT / 'blanket_front.png'
    blanket.save(path, optimize=True)
    print(f'{path.name:22} {blanket.size[0]} × {blanket.size[1]}, '
          f'{path.stat().st_size / 1024:.0f} КБ')
    print(f'  одеяло: {share(box)}')

    # Свет ночника — мягкое пятно без единой резкой границы, так что
    # половинного разрешения ему хватает с запасом.
    # Порог ниже: у свечения край и должен уходить в ничто плавно.
    glow, box = cut(Image.open(args.room / 'lamp_glow.png').convert('RGBA'), floor=3)
    glow = glow.resize((glow.size[0] // 2, glow.size[1] // 2), Image.LANCZOS)
    path = OUT / 'lamp_glow.png'
    glow.save(path, optimize=True)
    print(f'{path.name:22} {glow.size[0]} × {glow.size[1]}, '
          f'{path.stat().st_size / 1024:.0f} КБ')
    print(f'  свет: {share(box)}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
