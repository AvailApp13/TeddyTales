#!/usr/bin/env python3
"""Собирает мишку в формате Spine: атлас и скелет.

Зачем это рядом с `riv_build.py`. Rive хранит риг закрытым бинарником, и
собрать его можно только наощупь: ошибку видно не в файле, а на рендере,
через полчаса после сборки. Месяц работы показал, чем это кончается — кость
сидит не там, куда её ставили, и понять это можно лишь по картинке.

Spine хранит риг обычным JSON. Его читают глазами, проверяют до сборки и
правят в редакторе мышкой. Разница не в красоте формата, а в том, что
ошибка перестаёт быть невидимой.

## Что здесь принципиально иначе

**У каждой кости есть свои координаты.** В Rive обычная кость их не имеет:
рантайм берёт `x` из длины родителя, то есть кость всегда сидит в его
конце. Ветку приходится делать корневой костью, а та не наследует поворот
родителя — на этом у нас разлетались руки и ноги. В Spine кость задаётся
парой `x, y` в системе родителя, и ветка ничем не отличается от
продолжения.

**Ось Y смотрит вверх.** Наши детали размечены в координатах артборда, где
Y растёт вниз. Перевод собран в одном месте — `to_spine()`, — чтобы знак не
приходилось держать в голове по всему файлу.

**Вторичное движение считается физикой.** Уши, лапы и живот не
выписываются ключами: на кость вешается ограничитель с инерцией и
затуханием, и она догоняет тело сама. Это то, чего ручными ключами
добиться нельзя — отставание должно зависеть от того, куда тело поехало, а
не от номера кадра.

    python3 tool/spine_build.py out/

Части берутся из каталога `BEAR_PARTS` (по умолчанию
`docs/reference/parts-v7`).
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import riv_skeleton as bones  # noqa: E402

PARTS_DIR = os.environ.get('BEAR_PARTS') or 'docs/reference/parts-v7'

# --- совмещение листов (замеры те же, что в riv_build) ---------------------

HEAD_SCALE = 1 / 2.1039
HEAD_SHIFT = (732.0, -88.0)
HEAD_SHEET = {'b1-head', 'b3-eyes-half', 'b4-eyes-shut', 'b5-happy',
              'b6-sad', 'b7-chew', 'b8-surprise'}

BODY_CENTRE = 1435.0
BODY_BASELINE = 2780.0
BODY_HEIGHT = 2643.0

STAGE_CENTRE = bones.STAGE_CENTRE
STAGE_BASELINE = bones.STAGE_BASELINE
STAGE_HEIGHT = 1310.0
STAGE_SCALE = STAGE_HEIGHT / BODY_HEIGHT

TEXEL = 1.25
"""Пикселей текстуры на одну единицу сцены.

Мишка ростом 1310 единиц занимает на телефоне 600–700 точек, то есть
пол-пикселя на единицу. Полтора даёт двойной запас на поворот и приближение
и втрое меньший атлас, чем исходные листы.
"""

PAGE = 2048
PAD = 2
"""Зазор между соседями в атласе: без него билинейная фильтрация подхватывает
кромку соседней детали и по краю идёт цветная нить."""

# Деталь -> кость. Порядок словаря — порядок отрисовки, записанный раньше
# лежит ПОВЕРХ записанных следом (как в riv_build, чтобы номенклатура не
# разъезжалась между двумя сборщиками).
MOUNT = {
    'mouth': 'b_jaw',
    'nose': 'b_head',
    'eye_left': 'b_pupil_left',
    'eye_right': 'b_pupil_right',
    'muzzle': 'b_head',
    'head': 'b_head',
    'ear_left': 'b_ear_left',
    'ear_right': 'b_ear_right',
    'paw_left': 'b_paw_left',
    'arm_left_lower': 'b_arm_left_lower',
    'arm_left_upper': 'b_arm_left_upper',
    'paw_right': 'b_paw_right',
    'arm_right_lower': 'b_arm_right_lower',
    'arm_right_upper': 'b_arm_right_upper',
    'torso': 'b_spine',
    'foot_left': 'b_foot_left',
    'leg_left_lower': 'b_leg_left_lower',
    'leg_left_upper': 'b_leg_left_upper',
    'foot_right': 'b_foot_right',
    'leg_right_lower': 'b_leg_right_lower',
    'leg_right_upper': 'b_leg_right_upper',
}

# Сменные лица: висят на тех же костях, но в своём слоте, и переключаются
# подменой прикрепления, а не прозрачностью.
FACE_SLOTS = {
    'eye_left': ('b_pupil_left',
                 ['eye_left', 'eye_left_half', 'eye_left_shut',
                  'eye_left_happy', 'eye_left_sad']),
    'eye_right': ('b_pupil_right',
                  ['eye_right', 'eye_right_half', 'eye_right_shut',
                   'eye_right_happy', 'eye_right_sad']),
    'mouth': ('b_jaw',
              ['mouth', 'mouth_smile', 'mouth_sad', 'mouth_open', 'mouth_o']),
}

# --- физика ----------------------------------------------------------------

PHYSICS = [
    # кость,               инерция, упругость, затухание, масса, предел
    ('b_ear_left',          0.72,   38.0,      0.62,      0.9,   400),
    ('b_ear_right',         0.72,   38.0,      0.62,      0.9,   400),
    ('b_arm_left_lower',    0.55,   60.0,      0.70,      1.3,   300),
    ('b_arm_right_lower',   0.55,   60.0,      0.70,      1.3,   300),
    ('b_paw_left',          0.68,   45.0,      0.64,      1.0,   300),
    ('b_paw_right',         0.68,   45.0,      0.64,      1.0,   300),
    ('b_head',              0.40,   90.0,      0.78,      2.2,   200),
]
"""Что именно должно догонять тело.

Уши — мягче всего: у плюшевой игрушки они почти невесомые и отстают
заметнее прочего, на этом отставании и держится ощущение набивки. Предплечья
и лапы тяжелее и гасятся быстрее. Голова качается едва-едва: сильная
инерция на ней читается как отвалившаяся, а не как живая.

Числа — отправная точка для правки в редакторе, а не истина: физику
подбирают глазом, гоняя анимацию, и это ровно та работа, которую в закрытом
формате сделать было негде.
"""


def to_spine(x: float, y: float) -> tuple[float, float]:
    """Точка сцены (Y вниз, начало в углу) -> точка Spine (Y вверх, ноги в 0)."""
    return (x - STAGE_CENTRE, STAGE_BASELINE - y)


def angle_spine(start, end) -> float:
    """Угол кости в градусах против часовой, как принято в Spine."""
    return math.degrees(math.atan2(start[1] - end[1], end[0] - start[0]))


class Part:
    def __init__(self, name: str, path: Path, centre, size) -> None:
        self.name = name
        self.path = path
        self.x, self.y = centre          # центр в координатах Spine
        self.width, self.height = size   # размер в единицах сцены
        self.box = None                  # место в атласе, ставится упаковкой


def load_parts() -> dict[str, Part]:
    from PIL import Image  # noqa: PLC0415

    root = Path(PARTS_DIR)
    if not root.is_absolute():
        root = Path(__file__).resolve().parent.parent / root
    placements = json.loads((root / 'placements.json').read_text())

    parts: dict[str, Part] = {}
    for name, place in placements.items():
        path = root / f'{name}.webp'
        sheet = place['sheet']
        x = place['x'] + place['w'] / 2
        y = place['y'] + place['h'] / 2
        scale = STAGE_SCALE
        if sheet in HEAD_SHEET:
            x = x * HEAD_SCALE + HEAD_SHIFT[0]
            y = y * HEAD_SCALE + HEAD_SHIFT[1]
            scale *= HEAD_SCALE
        centre = to_spine((x - BODY_CENTRE) * STAGE_SCALE + STAGE_CENTRE,
                          (y - BODY_BASELINE) * STAGE_SCALE + STAGE_BASELINE)
        with Image.open(path) as image:
            size = (image.width * scale, image.height * scale)
        parts[name] = Part(name, path, centre, size)
    return parts


def stage_parts(parts: dict[str, Part]) -> dict:
    """Переводит детали обратно в координаты артборда — их ждёт `from_parts`."""
    class Box:
        pass

    out = {}
    for name, part in parts.items():
        box = Box()
        box.x = part.x + STAGE_CENTRE
        box.y = STAGE_BASELINE - part.y
        box.width, box.height = part.width, part.height
        box.scale = 1.0
        out[name] = box
    return out


# --- атлас -----------------------------------------------------------------


def pack(parts: dict[str, Part]) -> tuple[int, int]:
    """Раскладывает детали по странице полками.

    Полки — самый простой приём упаковки: детали сортируются по высоте и
    кладутся рядами. Для трёх десятков картинок разница с умным алгоритмом
    в несколько процентов площади, а поведение предсказуемое.
    """
    from PIL import Image  # noqa: PLC0415

    sizes = {}
    for name, part in parts.items():
        with Image.open(part.path) as image:
            sizes[name] = (max(1, round(part.width * TEXEL)),
                           max(1, round(part.height * TEXEL)), image.size)

    order = sorted(parts, key=lambda n: -sizes[n][1])
    x = y = shelf = 0
    used_width = 0
    for name in order:
        w, h, _ = sizes[name]
        if x + w + PAD > PAGE:
            x = 0
            y += shelf + PAD
            shelf = 0
        if y + h > PAGE:
            raise SystemExit(f'Не влезает в страницу {PAGE}: {name}')
        parts[name].box = (x, y, w, h)
        x += w + PAD
        shelf = max(shelf, h)
        used_width = max(used_width, x)
    return used_width, y + shelf


def draw_atlas(parts: dict[str, Part], png: Path) -> tuple[int, int]:
    from PIL import Image  # noqa: PLC0415

    width, height = pack(parts)
    # Страницу обрезаем до занятого прямоугольника, округляя вверх до
    # степени двойки: часть видеокарт до сих пор требует её для текстур.
    page_w = 1 << (width - 1).bit_length()
    page_h = 1 << (height - 1).bit_length()
    sheet = Image.new('RGBA', (page_w, page_h), (0, 0, 0, 0))
    for part in parts.values():
        x, y, w, h = part.box
        with Image.open(part.path) as image:
            sheet.paste(image.convert('RGBA').resize((w, h), Image.LANCZOS),
                        (x, y))
    sheet.save(png, optimize=True)
    return page_w, page_h


def write_atlas(parts: dict[str, Part], path: Path, png_name: str,
                size: tuple[int, int]) -> None:
    lines = [png_name,
             f'\tsize: {size[0]}, {size[1]}',
             '\tfilter: Linear, Linear',
             '\tpma: false']
    for name in sorted(parts):
        x, y, w, h = parts[name].box
        lines += [name, f'\tbounds: {x}, {y}, {w}, {h}']
    path.write_text('\n'.join(lines) + '\n')


# --- скелет ----------------------------------------------------------------


def skeleton(parts: dict[str, Part]) -> dict:
    chain = bones.from_parts(stage_parts(parts))
    bones.adopt(chain)

    world: dict[str, tuple[float, float, float]] = {}
    bone_list = []
    for name, (parent, start, end) in chain.items():
        origin = to_spine(*start)
        tip = to_spine(*end)
        angle = angle_spine(origin, tip)
        length = math.dist(origin, tip)

        if parent is None:
            entry = {'name': name}
            local_x, local_y, local_angle = origin[0], origin[1], angle
        else:
            px, py, pangle = world[parent]
            dx, dy = origin[0] - px, origin[1] - py
            rad = math.radians(-pangle)
            local_x = dx * math.cos(rad) - dy * math.sin(rad)
            local_y = dx * math.sin(rad) + dy * math.cos(rad)
            local_angle = (angle - pangle + 180) % 360 - 180
            entry = {'name': name, 'parent': parent}

        if abs(local_x) > 1e-6:
            entry['x'] = round(local_x, 2)
        if abs(local_y) > 1e-6:
            entry['y'] = round(local_y, 2)
        if abs(local_angle) > 1e-6:
            entry['rotation'] = round(local_angle, 2)
        entry['length'] = round(length, 2)
        bone_list.append(entry)
        world[name] = (origin[0], origin[1], angle)

    # Слоты: порядок в списке — порядок отрисовки, первый лежит ниже всех.
    # В MOUNT записано наоборот, поэтому разворачиваем.
    slots = []
    skin: dict[str, dict] = {}
    for name in reversed(list(MOUNT)):
        if name in FACE_SLOTS:
            continue
        slots.append({'name': name, 'bone': MOUNT[name], 'attachment': name})
        skin[name] = {name: attachment(parts[name], MOUNT[name], world)}

    for slot, (bone, variants) in FACE_SLOTS.items():
        slots.append({'name': slot, 'bone': bone, 'attachment': variants[0]})
        skin[slot] = {v: attachment(parts[v], bone, world) for v in variants}

    return {
        'skeleton': {
            'spine': '4.3',
            'x': -STAGE_CENTRE, 'y': 0,
            'width': STAGE_CENTRE * 2, 'height': STAGE_BASELINE,
            'images': './', 'audio': '',
        },
        'bones': bone_list,
        'slots': slots,
        'constraints': [physics(*row) for row in PHYSICS],
        'skins': [{'name': 'default', 'attachments': skin}],
        'animations': animations(chain, world),
    }


def attachment(part: Part, bone: str, world: dict) -> dict:
    """Прикрепление: где деталь сидит в системе своей кости.

    Разворот на минус угол кости возвращает деталь в вертикаль: кость
    лежит вдоль собственной оси X, а картинка снята стоя.
    """
    bx, by, angle = world[bone]
    dx, dy = part.x - bx, part.y - by
    rad = math.radians(-angle)
    return {
        'x': round(dx * math.cos(rad) - dy * math.sin(rad), 2),
        'y': round(dx * math.sin(rad) + dy * math.cos(rad), 2),
        'rotation': round(-angle, 2),
        'width': round(part.width, 2),
        'height': round(part.height, 2),
    }


def physics(bone: str, inertia: float, strength: float, damping: float,
            mass: float, limit: float) -> dict:
    return {
        'type': 'physics', 'name': bone.replace('b_', 'phys_'), 'bone': bone,
        'rotate': 1, 'inertia': inertia, 'strength': strength,
        'damping': damping, 'mass': mass, 'limit': limit, 'fps': 60,
    }


# --- движение --------------------------------------------------------------

BREATH_CYCLE = 3.0
"""Секунды на полный вдох-выдох. Spine считает время в секундах, не в кадрах."""


def curve(keys: list[dict]) -> list[dict]:
    """Ставит всем ключам, кроме последнего, плавную дугу.

    `stepped` дало бы рывок, линейная — механическое равномерное движение.
    Дыхание же замедляется на верхней точке.
    """
    for key in keys[:-1]:
        key['curve'] = 'stepped' if key.get('stepped') else [
            key['time'] + 0.25, key.get('value', 0), key['time'] + 0.75,
            key.get('value', 0)]
    return keys


def wave(cycle: float, amplitude: float, key: str = 'value',
         turns: int = 2) -> list[dict]:
    """Синусоида ключами: подъём, спад, возврат."""
    out = []
    steps = 4
    for turn in range(turns):
        for step in range(steps):
            phase = step / steps
            out.append({'time': round(cycle * (turn + phase), 3),
                        key: round(amplitude * math.sin(2 * math.pi * phase),
                                   4)})
    out.append({'time': round(cycle * turns, 3), key: 0.0})
    return out


def animations(chain: dict, world: dict) -> dict:
    """Дыхание и покачивание. Всё остальное досчитает физика.

    Ключей здесь намеренно мало. В Rive приходилось выписывать руками и
    отставание ушей, и догон лап — теперь это делают ограничители, а
    анимация задаёт только то, что мишка делает сам: дышит и переступает.
    """
    cycle = BREATH_CYCLE

    def scale_keys(amount: float) -> list[dict]:
        out = []
        for turn in range(2):
            out += [
                {'time': round(cycle * turn, 3), 'y': 1.0},
                {'time': round(cycle * (turn + 0.38), 3), 'y': 1 + amount},
            ]
        out.append({'time': round(cycle * 2, 3), 'y': 1.0})
        return out

    idle = {
        'bones': {
            'b_spine': {
                'scale': curve(scale_keys(0.055)),
                'rotate': curve(wave(cycle * 2, 0.9, 'value', turns=1)),
            },
            'b_hip': {'scale': curve(scale_keys(0.018))},
            'b_neck': {
                'rotate': curve([
                    {'time': 0.0, 'value': 0.0},
                    {'time': round(cycle * 0.45, 3), 'value': -1.6},
                    {'time': round(cycle, 3), 'value': 0.0},
                    {'time': round(cycle * 1.45, 3), 'value': -1.6},
                    {'time': round(cycle * 2, 3), 'value': 0.0},
                ]),
            },
            'b_root': {
                'translate': curve(wave(cycle * 2, 2.2, 'x', turns=1)),
            },
        },
    }

    giggle_cycle = 0.42
    giggle = {
        'bones': {
            'b_root': {
                'translate': curve([
                    {'time': 0.0, 'y': 0.0},
                    {'time': round(giggle_cycle * 0.35, 3), 'y': 26.0},
                    {'time': round(giggle_cycle * 0.8, 3), 'y': 0.0},
                    {'time': round(giggle_cycle * 1.15, 3), 'y': 9.0},
                    {'time': round(giggle_cycle * 1.6, 3), 'y': 0.0},
                ]),
            },
            'b_spine': {
                'scale': curve([
                    {'time': 0.0, 'x': 1.0, 'y': 1.0},
                    {'time': round(giggle_cycle * 0.18, 3),
                     'x': 1.06, 'y': 0.95},
                    {'time': round(giggle_cycle * 0.35, 3),
                     'x': 0.96, 'y': 1.05},
                    {'time': round(giggle_cycle * 0.8, 3),
                     'x': 1.04, 'y': 0.97},
                    {'time': round(giggle_cycle * 1.6, 3),
                     'x': 1.0, 'y': 1.0},
                ]),
            },
        },
        'slots': {
            'eye_left': {'attachment': [
                {'time': 0.0, 'name': 'eye_left_happy'},
                {'time': round(giggle_cycle * 1.6, 3), 'name': 'eye_left'}]},
            'eye_right': {'attachment': [
                {'time': 0.0, 'name': 'eye_right_happy'},
                {'time': round(giggle_cycle * 1.6, 3), 'name': 'eye_right'}]},
            'mouth': {'attachment': [
                {'time': 0.0, 'name': 'mouth_smile'},
                {'time': round(giggle_cycle * 1.6, 3), 'name': 'mouth'}]},
        },
    }

    blink = {
        'slots': {
            'eye_left': {'attachment': [
                {'time': 0.0, 'name': 'eye_left'},
                {'time': 0.06, 'name': 'eye_left_half'},
                {'time': 0.11, 'name': 'eye_left_shut'},
                {'time': 0.18, 'name': 'eye_left_half'},
                {'time': 0.24, 'name': 'eye_left'}]},
            'eye_right': {'attachment': [
                {'time': 0.0, 'name': 'eye_right'},
                {'time': 0.06, 'name': 'eye_right_half'},
                {'time': 0.11, 'name': 'eye_right_shut'},
                {'time': 0.18, 'name': 'eye_right_half'},
                {'time': 0.24, 'name': 'eye_right'}]},
        },
    }

    return {'idle': idle, 'giggle': giggle, 'blink': blink}


def build(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    parts = load_parts()
    size = draw_atlas(parts, out_dir / 'bear.png')
    write_atlas(parts, out_dir / 'bear.atlas', 'bear.png', size)
    data = skeleton(parts)
    (out_dir / 'bear.json').write_text(
        json.dumps(data, ensure_ascii=False, indent=1))

    png = (out_dir / 'bear.png').stat().st_size
    rig = (out_dir / 'bear.json').stat().st_size
    print(f'Атлас {size[0]}×{size[1]}, {png / 1e6:.2f} МБ, '
          f'{len(parts)} деталей')
    print(f'Скелет {rig / 1024:.0f} КБ, {len(data["bones"])} костей, '
          f'{len(data["slots"])} слотов, '
          f'{len(data["constraints"])} ограничителей физики, '
          f'{len(data["animations"])} анимации')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    return build(Path(sys.argv[1]))


if __name__ == '__main__':
    sys.exit(main())
