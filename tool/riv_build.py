#!/usr/bin/env python3
"""Собирает `bear_main.riv` заново из деталей набора v6.

Почему заново, а не правкой прежнего файла. Риг v4 был сложён из девяти
кусков: голова, два уха, две лапы, рот, пара глаз, кофта, ноги. Каждый кусок
жил своей жизнью — у каждого своя дорожка, свой угол, своя сетка. Именно
поэтому мишка и разваливался на части: чтобы девять независимых кусков
читались одним телом, они обязаны совпадать до пикселя в каждом кадре, а
они не совпадали.

Набор v6 устроен иначе. Мишка снят целиком в семи выражениях, кадры сведены
на одну сетку, и разрез проходит всего в двух местах — по шее и по поясу.
Двигать нужно три детали вместо девяти, а лицо не собирается из черт, а
подменяется целым снимком. Мутировать прежний файл под это бессмысленно:
из него пришлось бы удалить почти всё. Проще собрать заново.

От старого файла берётся скелет — то, что от набора деталей не зависит:

* `Backboard` и заголовок,
* `ViewModel` с пятью числовыми свойствами (привязка данных к приложению),
* `Artboard` 1080 × 1350 и его `LayoutComponentStyle`,
* `CubicEaseInterpolator` — кривая разгона, общая на все кейфреймы.

Заново строится всё остальное: ассеты с картинками, узлы `Image`, сетки
деформации, анимации и стейт-машина.

    python3 tool/riv_build.py assets/rive/bear_main.riv

Детали берутся из каталога `BEAR_PARTS` (по умолчанию
`docs/reference/parts-v6`); там же должен лежать `placements.json`, который
пишет `tool/cut_parts.py`.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from riv_paint import find_runtime, load_registry  # noqa: E402
from riv_rig import (  # noqa: E402
    BREATH_LIFT, DRAW_ORDER, GLANCE, HEAD_LAYERS, MESHES, MOODS, PEAK,
    Rig, Scene, TORSO_RISE, get, put, varuint,
)

PARTS_DIR = os.environ.get('BEAR_PARTS') or 'docs/reference/parts-v6'

# --- посадка ---------------------------------------------------------------
#
# Детали нарезаны на холсте 2480 × 3307, артборд — 1080 × 1350. Пропорции у
# них разные, поэтому вписываем не холст в артборд, а мишку: ступни на пол,
# макушку под верхний край, центр по ногам в середину сцены.

CANVAS_BASELINE = 3250.0
"""Ступни на холсте нарезки — та же величина, что в align_plush.py."""

CANVAS_CENTRE = 1240.0
"""Центр мишки по ногам на холсте нарезки."""

CANVAS_BODY = 3150.0
"""Макушка капюшона до ступней на холсте нарезки."""

STAGE_BASELINE = 1350.0
STAGE_CENTRE = 540.0
STAGE_BODY = 1310.0
"""Мишка на сцене. Прежний герой занимал по высоте 38…1353 — новый встаёт
туда же, чтобы смена набора не поменяла его размер на экране."""

DOWNSAMPLE = 1.4
"""Во сколько раз детали ужимаются относительно холста нарезки.

Голова на холсте — 1370 пикселей, на сцене она занимает 570, а сцена на
телефоне показывается примерно один к одному с физическими пикселями. То
есть в исходном разрешении заложен двойной запас, который весит три
мегабайта. При 1.4 голова остаётся 979 пикселей — всё ещё в полтора раза
больше, чем нужно экрану, — а весь набор худеет с 5,5 МБ до 3,2 МБ.
"""

WEBP_QUALITY = 90

STAGE_SCALE = STAGE_BODY / CANVAS_BODY
"""Холст нарезки -> артборд."""

PART_SCALE = STAGE_SCALE * DOWNSAMPLE
"""Картинка детали -> артборд: ужатую картинку надо вернуть в размер."""

# --- ключи свойств ---------------------------------------------------------

PARENT = 5
X, Y, ROTATION, SCALE_X, SCALE_Y, OPACITY = 13, 14, 15, 16, 17, 18
VERTEX_X, VERTEX_Y = 24, 25
VERTEX_U, VERTEX_V = 215, 216
NAME, ASSET_NAME, ASSET_ID, CONTENTS = 4, 203, 206, 212
ANIM_NAME, ANIM_DURATION, ANIM_LOOP = 55, 57, 59
OBJECT_ID, PROPERTY_KEY = 51, 53
FRAME, INTERPOLATION, INTERPOLATOR, VALUE = 67, 68, 69, 70
INPUT_NAME, INPUT_VALUE = 138, 140
STATE_ANIMATION, TRANSITION_TO = 149, 151
TRANSITION_FLAGS, TRANSITION_DURATION = 152, 158
TRANSITION_EXIT, CONDITION_INPUT = 160, 155
CONDITION_OP, CONDITION_VALUE = 156, 157

HOLD, CUBIC = 0, 2
"""Тип интерполяции кейфрейма. Подмена лица — только HOLD: выражение
меняется мгновенно, как у живого, а не расплывается через полупрозрачность.
"""


def rgba(path: Path):
    """Открывает деталь и ужимает её до рабочего разрешения."""
    from PIL import Image  # noqa: PLC0415

    image = Image.open(path).convert('RGBA')
    if DOWNSAMPLE != 1.0:
        image = image.resize(
            (round(image.width / DOWNSAMPLE), round(image.height / DOWNSAMPLE)),
            Image.LANCZOS,
        )
    return image


def webp(image) -> bytes:
    import io  # noqa: PLC0415

    buffer = io.BytesIO()
    image.save(buffer, 'WEBP', quality=WEBP_QUALITY, method=6)
    return buffer.getvalue()


class Part:
    """Деталь, посаженная на сцену: картинка, её место и размер."""

    def __init__(self, name: str, blob: bytes, stored: tuple[int, int],
                 centre: tuple[float, float], scale: float) -> None:
        self.name = name
        self.blob = blob
        self.width, self.height = stored
        self.x, self.y = centre
        self.scale = scale

    @property
    def stage_size(self) -> tuple[float, float]:
        return self.width * self.scale, self.height * self.scale


def load_parts() -> dict[str, Part]:
    """Читает нарезку и считает, где каждая деталь стоит на сцене."""
    root = Path(PARTS_DIR)
    if not root.is_absolute():
        root = Path(__file__).resolve().parent.parent / root
    placements = json.loads((root / 'placements.json').read_text())

    parts: dict[str, Part] = {}
    for name, place in placements.items():
        image = rgba(root / f'{name}.webp')
        # Центр детали на холсте нарезки -> точка на сцене.
        centre_x = place['x'] + place['w'] / 2
        centre_y = place['y'] + place['h'] / 2
        parts[name] = Part(
            name, webp(image), image.size,
            ((centre_x - CANVAS_CENTRE) * STAGE_SCALE + STAGE_CENTRE,
             (centre_y - CANVAS_BASELINE) * STAGE_SCALE + STAGE_BASELINE),
            PART_SCALE,
        )
    return parts


def carry_hearts(rig: Rig, scene: Scene) -> Part:
    """Забирает сердечки из прежнего файла: к набору деталей они не относятся.

    Это единственная картинка рига, которая не есть часть мишки, — облачко
    сердец над головой в эмо-акценте. Перерисовывать её незачем.
    """
    index = next(i for i in scene.images if scene.image_name(i) == 'hearts')
    props = rig.objects[index][1]
    asset = scene.assets[get(props, ASSET_ID)]
    blob = get(rig.objects[asset + 1][1], CONTENTS)
    asset_props = rig.objects[asset][1]
    size = (int(get(asset_props, 207)), int(get(asset_props, 208)))
    return Part('hearts', blob, size,
                (get(props, X), get(props, Y)), get(props, SCALE_X))


class Builder:
    """Накопитель объектов с автоматическим счётом локальных номеров.

    Локальный номер компонента — его позиция относительно артборда. На них
    ссылаются сетки (на свою картинку), дорожки анимаций (на свой объект) и
    кейфреймы (на кривую разгона), поэтому считаем их здесь же, а не потом.
    """

    def __init__(self, types: dict[int, str]) -> None:
        self.by_name = {name: key for key, name in types.items()}
        self.objects: list[tuple[int, list]] = []
        self.local: dict[str, int] = {}

    def add(self, kind: str, props: list) -> int:
        self.objects.append((self.by_name[kind], props))
        return len(self.objects) - 1

    def mark(self, label: str, local: int) -> None:
        self.local[label] = local


def mesh_for(part: Part, spec: dict) -> tuple[list, list[tuple[float, float]]]:
    """Сетка детали: треугольники и координаты вершин в пикселях картинки."""
    columns, rows = spec['grid']
    xs = [part.width * (c / (columns - 1) - 0.5) for c in range(columns)]
    ys = [part.height * (r / (rows - 1) - 0.5) for r in range(rows)]
    triangles: list[int] = []
    for r in range(rows - 1):
        for c in range(columns - 1):
            corner = r * columns + c
            triangles += [corner, corner + 1, corner + columns,
                          corner + 1, corner + columns + 1, corner + columns]
    vertices = [(x, y) for y in ys for x in xs]
    return triangles, vertices


def vertex_weight(spec: dict, vx: float, vy: float,
                  part: Part) -> tuple[float, float]:
    """Вес раздувания и провисания вершины: колонка на ряд.

    Вширь деталь дышит тем сильнее, чем дальше вершина от середины, — так
    ведёт себя набитая ткань. Вдоль высоты вес задан рядами: у кофты живот
    гуляет, плечи стоят; у ног работают только бёдра.
    """
    column = abs(vx) / (part.width / 2)
    dead = spec['centre_dead']
    if column <= dead:
        column = 0.0
    else:
        column = (column - dead) / (1 - dead)

    rows = spec['rows']
    position = (vy / (part.height / 2) + 1) / 2 * (len(rows) - 1)
    low = min(int(position), len(rows) - 2)
    row = rows[low] + (rows[low + 1] - rows[low]) * (position - low)

    sag = spec['sag'] * max(0.0, vy / (part.height / 2))
    return column * row, sag


# --- анимации --------------------------------------------------------------
#
# Все три покоя строит один генератор: параметры темпа, размаха и посадки
# головы лежат в MOODS. Отличать настроения позой мало — их отличает лицо,
# и лицо здесь подменяется целиком.

GIGGLE_DURATION = 150
"""Смех по тапу — две с половиной секунды."""

# Партитура прыжка: (кадр, сжатие по вертикали, высота, крен в радианах).
# Присел, вытянулся на взлёте, смялся при приземлении, коротко подскочил
# ещё раз и успокоился. Одна формула на все детали — потому границы между
# ними и не расходятся.
GIGGLE_SCORE = [
    (0,   1.000,  0.0,  0.000),
    (16,  0.958,  0.0,  0.005),
    (30,  1.040,  9.0, -0.009),
    (46,  0.972,  0.0,  0.007),
    (60,  1.022,  3.0, -0.006),
    (76,  0.988,  0.0,  0.004),
    (92,  1.008,  0.0, -0.002),
    (112, 0.997,  0.0,  0.001),
    (132, 1.000,  0.0,  0.000),
    (GIGGLE_DURATION, 1.000, 0.0, 0.000),
]

JELLY_LAG = 3.0
JELLY_AMP = 90.0
"""Желе: ряды сетки отстают от тела, нижние сильнее. Размах — в пикселях
картинки детали."""

EMO_DURATION = 120


class Animator:
    """Пишет дорожки анимаций поверх готовой раскладки деталей."""

    def __init__(self, builder: Builder, parts: dict[str, Part],
                 interpolator: int) -> None:
        self.b = builder
        self.parts = parts
        self.interpolator = interpolator

    def track(self, local: int, tracks: dict) -> list:
        """Дорожки одного объекта: {ключ свойства: [(кадр, значение, тип)]}."""
        out = [('KeyedObject', [(OBJECT_ID, 'Uint', local)])]
        for property_key, keys in tracks.items():
            out.append(('KeyedProperty', [(PROPERTY_KEY, 'Uint', property_key)]))
            for key in keys:
                frame, value = key[0], key[1]
                kind = key[2] if len(key) > 2 else CUBIC
                props = []
                if frame:
                    props.append((FRAME, 'Uint', int(round(frame))))
                props.append((INTERPOLATION, 'Uint', kind))
                if kind == CUBIC:
                    props.append((INTERPOLATOR, 'Uint', self.interpolator))
                props.append((VALUE, 'Double', float(value)))
                out.append(('KeyFrameDouble', props))
        return out

    # --- покой ---------------------------------------------------------

    def idle(self, mood: dict) -> tuple[list, int]:
        """Дыхание, посадка головы и лицо одного настроения."""
        cycle = mood['cycle']
        duration = 2 * cycle
        stretch = cycle / 180
        # Два вдоха подряд, нарочно неодинаковых: второй мельче и позже.
        # Ровно одинаковые вдохи читаются как работа мотора.
        cycles = ((0, 1.0, 0), (cycle, 0.85, round(6 * stretch)))

        def waves(peak, value_at):
            peak = round(peak * stretch)
            keys = [(0, value_at(0.0))]
            for start, amp, shift in cycles:
                keys.append((start + peak + shift,
                             value_at(amp * mood['amp'])))
                keys.append((start + cycle, value_at(0.0)))
            return keys

        blocks: list = []

        # Кофта: узел приподнимается, контур дышит вершинами сетки.
        torso = self.parts['torso']
        blocks += self.track(self.b.local['torso'], {
            Y: waves(PEAK['torso'], lambda k: torso.y - TORSO_RISE * k),
        })
        for piece, spec in MESHES.items():
            part = self.parts[piece]
            for local, vx, vy in self.b.local[f'{piece}:vertices']:
                weight, sag = vertex_weight(spec, vx, vy, part)
                # Размах задан в пикселях сцены — переводим в пиксели
                # картинки, иначе ужатая деталь дышала бы слабее.
                out = ((1 if vx >= 0 else -1) * spec['swell'] / part.scale
                       * weight)
                tracks = {}
                if abs(out) > 0.3:
                    tracks[VERTEX_X] = waves(
                        PEAK['torso'], lambda k, v=vx, o=out: v + o * k)
                if sag > 0.3:
                    tracks[VERTEX_Y] = waves(
                        PEAK['torso'], lambda k, v=vy, g=sag: v + g * k)
                if tracks:
                    blocks += self.track(local, tracks)

        # Головы: вся стопка идёт вверх на вдохе, иначе при подмене
        # видимая голова прыгнула бы на место соседней.
        for name in HEAD_LAYERS:
            base = self.parts[name].y + mood['head_dy']
            blocks += self.track(self.b.local[name], {
                Y: waves(PEAK['head'], lambda k, b=base: b - BREATH_LIFT * k),
            })

        # Лицо. Видна ровно одна голова; переключение — ступенькой.
        for name, keys in self.faces(mood, cycle, duration).items():
            blocks += self.track(self.b.local[name], {OPACITY: keys})

        return blocks, duration

    def faces(self, mood: dict, cycle: int, duration: int) -> dict:
        """Прозрачность каждой из семи голов по всему циклу.

        Дорожка пишется для всех семи в каждом настроении, а не только для
        видимой. Иначе голова, зажжённая прошлой анимацией, останется гореть
        после перехода: рантайм держит последнее применённое значение.
        """
        visible = f'head_{mood["face"]}'
        keys = {name: [(0, 1.0 if name == visible else 0.0, HOLD)]
                for name in HEAD_LAYERS}

        if mood['glance']:
            # Мишка отводит глаза и возвращает их. Взгляд уводится вместе с
            # мордой — это подмена кадра, снятого с поворотом головы, а не
            # сдвиг зрачка по лицу.
            for share, face in zip(GLANCE['at'], GLANCE['faces']):
                start = round(share * cycle)
                stop = start + GLANCE['hold']
                if stop >= duration:
                    continue
                keys[f'head_{face}'] += [(start, 1.0, HOLD),
                                         (stop, 0.0, HOLD)]
                keys[visible] += [(start, 0.0, HOLD), (stop, 1.0, HOLD)]
            for name in keys:
                keys[name].sort(key=lambda item: item[0])

        return keys

    # --- смех ----------------------------------------------------------

    def giggle(self) -> tuple[list, int]:
        """Мишка подпрыгивает как одно упругое тело.

        Никаких отдельных дуг для лапы и подскоков для головы: каждый ключ
        задаёт общее преобразование от точки опоры под ступнями — приседание,
        вытяжение в полёте, смятие при приземлении. Все детали получают одну
        и ту же формулу, поэтому швы не расходятся ни на пиксель.
        """
        ground = (STAGE_CENTRE, STAGE_BASELINE)

        def posed(base_x, base_y, squash, jump, tilt):
            stretch = 1 + (1 - squash) * 0.7    # объём примерно сохраняется
            dx = (base_x - ground[0]) * stretch
            dy = (base_y - ground[1]) * squash
            cos, sin = math.cos(tilt), math.sin(tilt)
            return (ground[0] + dx * cos - dy * sin,
                    ground[1] + dx * sin + dy * cos - jump)

        blocks: list = []
        for name in DRAW_ORDER:
            part = self.parts[name]
            xs, ys, sxs, sys_, rots = [], [], [], [], []
            for frame, squash, jump, tilt in GIGGLE_SCORE:
                px, py = posed(part.x, part.y, squash, jump, tilt)
                xs.append((frame, px))
                ys.append((frame, py))
                sxs.append((frame, part.scale * (1 + (1 - squash) * 0.7)))
                sys_.append((frame, part.scale * squash))
                rots.append((frame, tilt))
            blocks += self.track(self.b.local[name], {
                X: xs, Y: ys, SCALE_X: sxs, SCALE_Y: sys_, ROTATION: rots,
            })

        # Желе: при подскоках нижние ряды сетки отстают от тела и ткань
        # доигрывает после остановки.
        def squash_at(frame: float) -> float:
            for (f0, s0, *_), (f1, s1, *_) in zip(GIGGLE_SCORE,
                                                  GIGGLE_SCORE[1:]):
                if f0 <= frame <= f1:
                    if f1 == f0:
                        return s0
                    return s0 + (s1 - s0) * (frame - f0) / (f1 - f0)
            return 1.0

        for piece in MESHES:
            part = self.parts[piece]
            for local, vx, vy in self.b.local[f'{piece}:vertices']:
                depth = (vy / (part.height / 2) + 1) / 2
                if depth < 0.2:
                    continue
                lag = JELLY_LAG * (1 + 2 * depth)
                keys = [(frame,
                         vy + (squash_at(max(0.0, frame - lag)) - squash)
                         * JELLY_AMP / part.scale * depth)
                        for frame, squash, _, _ in GIGGLE_SCORE]
                blocks += self.track(local, {VERTEX_Y: keys})

        return blocks, GIGGLE_DURATION

    # --- сердечки ------------------------------------------------------

    def emo_love(self) -> tuple[list, int]:
        hearts = self.parts['hearts']
        blocks = self.track(self.b.local['hearts'], {
            OPACITY: [(0, 0.0), (10, 1.0), (85, 1.0), (115, 0.0),
                      (EMO_DURATION, 0.0)],
            Y: [(0, hearts.y), (EMO_DURATION, hearts.y - 240.0)],
            X: [(0, hearts.x), (32, hearts.x + 12.0), (64, hearts.x - 10.0),
                (96, hearts.x + 8.0), (EMO_DURATION, hearts.x)],
            SCALE_X: [(0, hearts.scale * 0.75), (25, hearts.scale * 1.05),
                      (EMO_DURATION, hearts.scale)],
            SCALE_Y: [(0, hearts.scale * 0.75), (25, hearts.scale * 1.05),
                      (EMO_DURATION, hearts.scale)],
        })
        return blocks, EMO_DURATION


# --- стейт-машина ----------------------------------------------------------
#
# Номера анимаций — их порядок в файле; на них ссылаются состояния. Номера
# входов — порядок объявления; на них ссылаются условия переходов.

ANIMATIONS = ('idle', 'idle_happy', 'idle_sad', 'giggle', 'emo_love', 'rest')
ANIM = {name: index for index, name in enumerate(ANIMATIONS)}

INPUT_MOOD, INPUT_PET, INPUT_LOVE = 0, 1, 2

MOOD_BLEND = 350
"""Сведение между настроениями, миллисекунды. Настроение меняется не рывком:
за треть секунды одно лицо растворяется в другом, и тело перестраивает темп
дыхания.
"""


def transition(to_state: int, duration: int = 0,
               exit_time: int | None = None) -> list:
    props = [(TRANSITION_TO, 'Uint', to_state)]
    if exit_time is not None:
        props.append((TRANSITION_FLAGS, 'Uint', 4))
    if duration:
        props.append((TRANSITION_DURATION, 'Uint', duration))
    if exit_time is not None:
        props.append((TRANSITION_EXIT, 'Uint', exit_time))
    return [('StateTransition', props)]


def on_mood(value: int) -> list:
    return [('TransitionNumberCondition',
             [(CONDITION_INPUT, 'Uint', INPUT_MOOD),
              (CONDITION_OP, 'Uint', 0), (CONDITION_VALUE, 'Double',
                                          float(value))])]


def on_trigger(input_index: int) -> list:
    return [('TransitionTriggerCondition',
             [(CONDITION_INPUT, 'Uint', input_index)])]


def state_machine() -> list:
    """Две дорожки поведения: тело и эмо-акцент.

    Тело живёт в трёх настроениях и подпрыгивает от поглаживания. Сердечки
    вынесены в отдельный слой, чтобы всплывать поверх любого настроения и не
    прерывать дыхание.
    """
    out: list = [
        ('StateMachine', [(ANIM_NAME, 'String', b'bear_main')]),
        ('StateMachineNumber', [(INPUT_NAME, 'String', b'mood'),
                                (INPUT_VALUE, 'Double', 0.0)]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_pet')]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_emo_love')]),
    ]

    # Слой body. Состояния по порядку объявления: 0 покой, 1 радость,
    # 2 грусть, 3 смех, дальше служебная тройка.
    out.append(('StateMachineLayer', [(INPUT_NAME, 'String', b'body')]))

    for index, (name, mood_value) in enumerate(
            (('idle', 0), ('idle_happy', 1), ('idle_sad', 2))):
        out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM[name])]))
        # В два соседних настроения — по значению входа.
        for other, other_value in ((0, 0), (1, 1), (2, 2)):
            if other_value == mood_value:
                continue
            out += transition(other, MOOD_BLEND) + on_mood(other_value)
        # И в смех — по поглаживанию, из любого настроения.
        out += transition(3, 120) + on_trigger(INPUT_PET)

    # 3 — смех. Возвращается сам, доиграв: 2400 мс из 2500.
    out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM['giggle'])]))
    out += transition(0, 300, exit_time=2400)

    out.append(('EntryState', []))          # 4
    out += transition(0)
    out.append(('AnyState', []))            # 5
    out.append(('ExitState', []))           # 6

    # Слой emo: тишина, пока не попросят сердечек.
    out.append(('StateMachineLayer', [(INPUT_NAME, 'String', b'emo')]))
    out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM['rest'])]))
    out += transition(1, 80) + on_trigger(INPUT_LOVE)
    out.append(('AnimationState',
                [(STATE_ANIMATION, 'Uint', ANIM['emo_love'])]))
    out += transition(0, 200, exit_time=1900)
    out.append(('EntryState', []))          # 2
    out += transition(0)
    out.append(('AnyState', []))            # 3
    out.append(('ExitState', []))           # 4
    return out


# --- сборка ----------------------------------------------------------------


def build(path: Path) -> int:
    fields, types = load_registry(find_runtime(None))
    data = path.read_bytes()
    rig = Rig(data, fields)
    rig.types = types
    if rig.dumps() != data:
        raise SystemExit('Round-trip скелета не сошёлся: файл трогать не буду')
    scene = Scene(rig, types)

    parts = load_parts()
    parts['hearts'] = carry_hearts(rig, scene)
    missing = [name for name in DRAW_ORDER if name not in parts]
    if missing:
        raise SystemExit(f'Нет деталей: {", ".join(missing)}')

    builder = Builder(types)
    by_name = builder.by_name

    # Ассеты в порядке отрисовки: номер ассета — позиция в этом списке.
    assets: list = []
    for index, name in enumerate(DRAW_ORDER):
        part = parts[name]
        assets.append((by_name['ImageAsset'], [
            (ASSET_NAME, 'String', name.encode()),
            (204, 'Uint', 6650000 + index),
            # В этом файле 207 — высота, 208 — ширина. Порядок снят с
            # прежних ассетов, а не угадан: у legs 849 x 546 записано
            # 207=546, 208=849.
            (207, 'Double', float(part.height)),
            (208, 'Double', float(part.width)),
        ]))
        assets.append((by_name['FileAssetContents'],
                       [(CONTENTS, 'Bytes', part.blob)]))

    # Содержимое артборда. Позиция в этом списке и есть локальный номер.
    items: list = [rig.objects[scene.artboard],
                   rig.objects[scene.artboard + 1]]
    for index, name in enumerate(DRAW_ORDER):
        part = parts[name]
        local = len(items)
        builder.mark(name, local)
        items.append((by_name['Image'], [
            (PARENT, 'Uint', 0),
            (X, 'Double', part.x), (Y, 'Double', part.y),
            (ROTATION, 'Double', 0.0),
            (SCALE_X, 'Double', part.scale), (SCALE_Y, 'Double', part.scale),
            # Видна одна голова из семи, остальные ждут своего настроения.
            # Сердечки тоже погашены: они живут только в эмо-акценте.
            (OPACITY, 'Double', 0.0 if name in ('hearts', *HEAD_LAYERS[1:])
             else 1.0),
            (ASSET_ID, 'Uint', index),
        ]))

        spec = MESHES.get(name)
        if spec is None:
            continue
        triangles, vertices = mesh_for(part, spec)
        mesh_local = len(items)
        items.append((by_name['Mesh'], [
            (PARENT, 'Uint', local),
            (223, 'Bytes', b''.join(varuint(i) for i in triangles)),
        ]))
        placed = []
        for vx, vy in vertices:
            placed.append((len(items), vx, vy))
            items.append((by_name['MeshVertex'], [
                (PARENT, 'Uint', mesh_local),
                (VERTEX_X, 'Double', vx), (VERTEX_Y, 'Double', vy),
                (VERTEX_U, 'Double', vx / part.width + 0.5),
                (VERTEX_V, 'Double', vy / part.height + 0.5),
            ]))
        builder.mark(f'{name}:vertices', placed)

    interpolator = len(items)
    items.append((by_name['CubicEaseInterpolator'], []))

    # Анимации. Порядок обязан совпасть с ANIMATIONS: состояния машины
    # ссылаются на анимации номером, а не именем.
    animator = Animator(builder, parts, interpolator)
    written: list = []
    plans = {
        'idle': lambda: animator.idle(MOODS['idle']),
        'idle_happy': lambda: animator.idle(MOODS['idle_happy']),
        'idle_sad': lambda: animator.idle(MOODS['idle_sad']),
        'giggle': animator.giggle,
        'emo_love': animator.emo_love,
        # Пустышка для слоя эмо: слой обязан что-то играть в покое, а
        # играть настоящий покой он не может — тот уже идёт в слое body.
        'rest': lambda: ([], 1),
    }
    looped = {'idle', 'idle_happy', 'idle_sad', 'rest'}
    for name in ANIMATIONS:
        blocks, duration = plans[name]()
        head = [(ANIM_NAME, 'String', name.encode()),
                (ANIM_DURATION, 'Uint', duration)]
        if name in looped:
            head.append((ANIM_LOOP, 'Uint', 1))
        written.append((by_name['LinearAnimation'], head))
        written += [(by_name[kind], props) for kind, props in blocks]

    machine = [(by_name[kind], props) for kind, props in state_machine()]

    # Всё, что до артборда и не является ассетом: Backboard и ViewModel.
    keep_before = [rig.objects[i] for i in range(scene.artboard)
                   if i not in set(scene.assets)
                   and i - 1 not in set(scene.assets)]

    rig.objects = keep_before[:1] + assets + keep_before[1:] + items \
        + written + machine
    path.write_bytes(rig.dumps())

    heads = len(HEAD_LAYERS)
    print(f'Собран {path}: {path.stat().st_size / 1e6:.2f} МБ, '
          f'{len(DRAW_ORDER)} деталей ({heads} лиц), '
          f'{len(ANIMATIONS)} анимаций')
    for name in DRAW_ORDER:
        part = parts[name]
        width, height = part.stage_size
        print(f'  {name:12s} {part.width:4d}x{part.height:<4d} -> '
              f'{width:5.0f}x{height:<5.0f} @ {part.x:5.0f},{part.y:<6.0f}')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    return build(Path(sys.argv[1]))


if __name__ == '__main__':
    sys.exit(main())
