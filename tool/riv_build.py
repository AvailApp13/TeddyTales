#!/usr/bin/env python3
"""Собирает `bear_main.riv` заново из деталей набора v6.

Почему заново, а не правкой прежнего файла. Риг v4 был сложён из девяти
кусков: голова, два уха, две лапы, рот, пара глаз, кофта, ноги. Каждый кусок
жил своей дорожкой, и чтобы девять кусков читались одним телом, они обязаны
были совпадать до пикселя в каждом кадре. Они не совпадали.

Набор v6 режется в двух местах: по шее и по поясу. Лицо не собирается из
черт — оно подменяется целым снимком настоящей игрушки, и семь выражений
сведены на одну сетку, так что смена лица не двигает мишку ни на пиксель.

Держит всё это скелет (`tool/riv_skeleton.py`). Вершины кофты и ног
привязаны к цепочке костей плавными весами, голова висит на кости шеи.
Анимируются кости, а не куски: дышит позвоночник — вместе с ним едет всё
остальное, потому что всё остальное на нём и держится. Разъехаться детали
не могут по построению, а не потому, что движение урезано до незаметного.

    python3 tool/riv_build.py assets/rive/bear_main.riv

Детали берутся из каталога `BEAR_PARTS` (по умолчанию
`docs/reference/parts-v6`); там же лежит `placements.json` от
`tool/cut_parts.py`.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import riv_skeleton as bones  # noqa: E402
from riv_paint import find_runtime, load_registry  # noqa: E402
from riv_rig import (  # noqa: E402
    DRAW_ORDER, GLANCE, HEAD_LAYERS, MOODS, Rig, Scene, get, varuint,
)

PARTS_DIR = os.environ.get('BEAR_PARTS') or 'docs/reference/parts-v6'

# --- посадка ---------------------------------------------------------------

CANVAS_BASELINE = 3250.0
CANVAS_CENTRE = 1240.0
CANVAS_BODY = 3150.0
"""Ступни, центр по ногам и рост мишки на холсте нарезки — те же величины,
что в align_plush.py."""

STAGE_BASELINE = bones.STAGE_BASELINE
STAGE_CENTRE = bones.STAGE_CENTRE
STAGE_BODY = 1310.0
"""Мишка на сцене. Прежний герой занимал по высоте 38…1353 — новый встаёт
туда же, чтобы смена набора не поменяла его размер на экране."""

DOWNSAMPLE = 1.4
"""Во сколько раз детали ужимаются относительно холста нарезки.

Голова на холсте — 1370 пикселей, на сцене она занимает 570, а сцена на
телефоне показывается примерно один к одному с физическими пикселями. То
есть в исходном разрешении заложен двойной запас, который весит три
мегабайта. При 1.4 голова остаётся 979 пикселей — всё ещё в полтора раза
больше, чем нужно экрану.
"""

WEBP_QUALITY = 90

STAGE_SCALE = STAGE_BODY / CANVAS_BODY
PART_SCALE = STAGE_SCALE * DOWNSAMPLE

# Сетки деформации: частота узлов и кости, к которым привязаны вершины.
# Чем чаще сетка, тем плавнее ткань между узлами; на фотографии меха любая
# складка между редкими узлами читается как залом.
MESHES = {
    'torso': {'grid': (9, 7), 'bones': ['hips', 'spine', 'chest', 'neck']},
    'legs': {'grid': (7, 5), 'bones': ['root', 'hips']},
}

# --- ключи свойств ---------------------------------------------------------

PARENT = 5
X, Y, ROTATION, SCALE_X, SCALE_Y, OPACITY = 13, 14, 15, 16, 17, 18
VERTEX_X, VERTEX_Y = 24, 25
VERTEX_U, VERTEX_V = 215, 216
ASSET_NAME, ASSET_ID, CONTENTS = 203, 206, 212
ANIM_NAME, ANIM_DURATION, ANIM_LOOP = 55, 57, 59
OBJECT_ID, PROPERTY_KEY = 51, 53
FRAME, INTERPOLATION, INTERPOLATOR, VALUE = 67, 68, 69, 70
INPUT_NAME, INPUT_VALUE = 138, 140
STATE_ANIMATION, TRANSITION_TO = 149, 151
TRANSITION_FLAGS, TRANSITION_DURATION = 152, 158
TRANSITION_EXIT, CONDITION_INPUT = 160, 155
CONDITION_OP, CONDITION_VALUE = 156, 157
BONE_LENGTH, ROOT_X, ROOT_Y = 89, 90, 91
TENDON_BONE = 95
TENDON_MATRIX = (96, 97, 98, 99, 100, 101)
SKIN_MATRIX = (104, 105, 106, 107, 108, 109)
WEIGHT_VALUES, WEIGHT_INDICES = 102, 103
MESH_TRIANGLES = 223

HOLD, CUBIC = 0, 2
"""Тип интерполяции кейфрейма. Подмена лица — только HOLD: выражение
меняется мгновенно, как у живого, а не расплывается через полупрозрачность.
"""


def rgba(path: Path):
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
    """Забирает сердечки из прежнего файла: к набору деталей они не относятся."""
    index = next(i for i in scene.images if scene.image_name(i) == 'hearts')
    props = rig.objects[index][1]
    asset = scene.assets[get(props, ASSET_ID)]
    blob = get(rig.objects[asset + 1][1], CONTENTS)
    asset_props = rig.objects[asset][1]
    size = (int(get(asset_props, 208)), int(get(asset_props, 207)))
    return Part('hearts', blob, size,
                (get(props, X), get(props, Y)), get(props, SCALE_X))


def mesh_for(part: Part, grid: tuple[int, int]):
    """Сетка детали: треугольники и вершины в пикселях картинки."""
    columns, rows = grid
    xs = [part.width * (c / (columns - 1) - 0.5) for c in range(columns)]
    ys = [part.height * (r / (rows - 1) - 0.5) for r in range(rows)]
    triangles: list[int] = []
    for r in range(rows - 1):
        for c in range(columns - 1):
            corner = r * columns + c
            triangles += [corner, corner + 1, corner + columns,
                          corner + 1, corner + columns + 1, corner + columns]
    return triangles, [(x, y) for y in ys for x in xs]


# --- движение --------------------------------------------------------------
#
# Анимируются кости, а не куски. Поэтому дыхание — это три дорожки вместо
# сорока, а швы не расходятся: детали висят на общей цепочке.

BREATH = {
    # Живот и грудь: главный объём вдоха. scale_x — вдоль кости, то есть
    # вверх; scale_y — поперёк, то есть вширь.
    'spine': {'scale_x': 0.032, 'scale_y': 0.050},
    # Таз чуть расходится следом.
    'hips': {'scale_y': 0.014},
}

BREATH_NOD = 0.022
"""Кивок шеи на вдохе, радианы (около 1,3°).

Голова не должна повторять вдох один в один: живое тело поднимает грудь, а
голова доходит следом и чуть запаздывает. Отсюда и отдельная фаза.
"""

PEAK = {'hips': 62, 'spine': 70, 'neck': 88}
"""Вершина вдоха у каждой кости своя, в кадрах от начала цикла. Ровно
одновременное движение читается как механизм."""

SWAY_TILT = 0.0045
SWAY_SHIFT = 1.6
SWAY_SHOULDER = 0.008
"""Покачивание в покое: крен всего тела, переступание с ноги на ногу и
асимметрия плеч.

Величины намеренно крошечные — четверть градуса крена и полтора пикселя
сдвига. Их не видно как движение, но без них мишка стоит как вкопанный:
живое тело никогда не держит вес ровно, оно всё время его перекладывает.
Период покачивания не равен периоду вдоха, поэтому цикл не читается.
"""


def sway(duration: int, amplitude: float, base: float = 0.0,
         turns: float = 1.0, phase: float = 0.0) -> list:
    """Плавная синусоида на всю длину анимации.

    Ключей восемь на оборот: меньше — и кубическая кривая между ними
    заметно «ступает», больше — только вес файла.
    """
    steps = max(8, int(round(8 * turns)))
    keys = []
    for step in range(steps + 1):
        share = step / steps
        angle = 2 * math.pi * (turns * share + phase)
        keys.append((round(duration * share),
                     base + amplitude * math.sin(angle)))
    return keys


class Animator:
    """Пишет дорожки анимаций поверх готового скелета."""

    def __init__(self, builder, parts: dict[str, Part],
                 interpolator: int) -> None:
        self.b = builder
        self.parts = parts
        self.interpolator = interpolator

    def track(self, local: int, tracks: dict) -> list:
        """Дорожки одного объекта: {ключ свойства: [(кадр, значение, тип)]}."""
        out = [('KeyedObject', [(OBJECT_ID, 'Uint', local)])]
        for property_key, keys in tracks.items():
            out.append(('KeyedProperty',
                        [(PROPERTY_KEY, 'Uint', property_key)]))
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

    def bone(self, name: str, tracks: dict) -> list:
        return self.track(self.b.local[f'bone:{name}'], tracks)

    # --- покой ---------------------------------------------------------

    def idle(self, mood: dict) -> tuple[list, int]:
        """Дыхание, посадка головы и лицо одного настроения."""
        cycle = mood['cycle']
        duration = 2 * cycle
        stretch = cycle / 180
        # Два вдоха подряд, нарочно неодинаковых: второй мельче и позже.
        # Ровно одинаковые вдохи читаются как работа мотора.
        cycles = ((0, 1.0, 0), (cycle, 0.85, round(6 * stretch)))
        amp = mood['amp']

        def waves(peak, value_at):
            peak = round(peak * stretch)
            keys = [(0, value_at(0.0))]
            for start, share, shift in cycles:
                keys.append((start + peak + shift, value_at(share * amp)))
                keys.append((start + cycle, value_at(0.0)))
            return keys

        blocks: list = []

        # Мишка стоит, а не позирует: тело всё время чуть перекладывает вес.
        # Полтора оборота на анимацию — чтобы покачивание не совпало с
        # дыханием и цикл не читался.
        blocks += self.bone('root', {
            ROTATION: sway(duration, SWAY_TILT, -math.pi / 2, turns=1.5),
            ROOT_X: sway(duration, SWAY_SHIFT, STAGE_CENTRE,
                         turns=1.5, phase=0.25),
        })

        hips = BREATH['hips']
        blocks += self.bone('hips', {
            SCALE_Y: waves(PEAK['hips'], lambda k: 1 + hips['scale_y'] * k),
        })

        spine = BREATH['spine']
        blocks += self.bone('spine', {
            SCALE_X: waves(PEAK['spine'], lambda k: 1 + spine['scale_x'] * k),
            SCALE_Y: waves(PEAK['spine'], lambda k: 1 + spine['scale_y'] * k),
        })

        # Грудь гасит масштаб позвоночника: иначе он дотянулся бы по цепочке
        # до головы и раздувал её вместе с животом. Подъём при этом
        # сохраняется — он идёт от удлинения кости, а не от масштаба.
        blocks += self.bone('chest', {
            SCALE_X: waves(PEAK['spine'],
                           lambda k: 1 / (1 + spine['scale_x'] * k)),
            SCALE_Y: waves(PEAK['spine'],
                           lambda k: 1 / (1 + spine['scale_y'] * k)),
            # Плечи ведёт чуть в сторону: дыхание живого тела никогда не
            # бывает идеально симметричным.
            ROTATION: sway(duration, SWAY_SHOULDER, turns=1.0, phase=0.6),
        })

        # Шея: наклон настроения плюс кивок с запаздыванием.
        tilt = mood['tilt']
        blocks += self.bone('neck', {
            ROTATION: waves(PEAK['neck'], lambda k: tilt - BREATH_NOD * k),
        })

        # Голова сидит на шее; по вертикали её двигает только настроение.
        # Ось кости смотрит вверх, поэтому «опустить» — это уменьшить x.
        head_x, head_y = bones.to_bone_space('neck', self.parts['head_calm'].x,
                                             self.parts['head_calm'].y)
        for name in HEAD_LAYERS:
            blocks += self.track(self.b.local[name], {
                X: [(0, head_x - mood['head_dy'])],
                Y: [(0, head_y)],
            })

        for name, keys in self.faces(mood, cycle, duration).items():
            blocks += self.track(self.b.local[name], {OPACITY: keys})

        return blocks, duration

    def faces(self, mood: dict, cycle: int, duration: int) -> dict:
        """Прозрачность каждой из семи голов по всему циклу.

        Дорожка пишется для всех семи в каждом настроении, а не только для
        видимой: иначе голова, зажжённая прошлой анимацией, останется гореть
        после перехода — рантайм держит последнее применённое значение.
        """
        visible = f'head_{mood["face"]}'
        keys = {name: [(0, 1.0 if name == visible else 0.0, HOLD)]
                for name in HEAD_LAYERS}

        if mood['glance']:
            for share, face in zip(GLANCE['at'], GLANCE['faces']):
                start = round(share * cycle)
                stop = start + GLANCE['hold']
                if stop >= duration:
                    continue
                keys[f'head_{face}'] += [(start, 1.0, HOLD), (stop, 0.0, HOLD)]
                keys[visible] += [(start, 0.0, HOLD), (stop, 1.0, HOLD)]
            for name in keys:
                keys[name].sort(key=lambda item: item[0])

        return keys

    # --- смех ----------------------------------------------------------

    def giggle(self) -> tuple[list, int]:
        """Мишка подпрыгивает как одно упругое тело.

        Никаких отдельных дуг для лапы и подскоков для головы: всё тело
        держится на цепочке костей, поэтому прыжок — это четыре дорожки.
        Корень едет вверх и кренится, позвоночник приседает и вытягивается,
        шея отстаёт. Швы не расходятся, потому что расходиться нечему.
        """
        blocks: list = []

        root_y = [(frame, STAGE_BASELINE - jump)
                  for frame, _, jump, _ in GIGGLE_SCORE]
        root_rot = [(frame, -math.pi / 2 + tilt)
                    for frame, _, _, tilt in GIGGLE_SCORE]
        blocks += self.bone('root', {ROOT_Y: root_y, ROTATION: root_rot})

        # Приседание и вытяжение с сохранением объёма: сжался по высоте —
        # разошёлся вширь.
        blocks += self.bone('spine', {
            SCALE_X: [(frame, squash) for frame, squash, _, _ in GIGGLE_SCORE],
            SCALE_Y: [(frame, 1 + (1 - squash) * 0.7)
                      for frame, squash, _, _ in GIGGLE_SCORE],
        })
        blocks += self.bone('hips', {
            SCALE_Y: [(frame, 1 + (1 - squash) * 0.4)
                      for frame, squash, _, _ in GIGGLE_SCORE],
        })

        # Шея догоняет тело с отставанием: голова мотается сама собой, без
        # отдельной анимации головы.
        lag = dict(zip((f for f, _, _, _ in GIGGLE_SCORE),
                       (0.0, 0.05, -0.07, 0.05, -0.04, 0.03, -0.02,
                        0.01, 0.0, 0.0)))
        blocks += self.bone('neck', {
            ROTATION: [(frame, lag[frame] - tilt * 1.6)
                       for frame, _, _, tilt in GIGGLE_SCORE],
        })
        return blocks, GIGGLE_DURATION

    # --- сердечки ------------------------------------------------------

    def emo_love(self) -> tuple[list, int]:
        hearts = self.parts['hearts']
        return self.track(self.b.local['hearts'], {
            OPACITY: [(0, 0.0), (10, 1.0), (85, 1.0), (115, 0.0),
                      (EMO_DURATION, 0.0)],
            Y: [(0, hearts.y), (EMO_DURATION, hearts.y - 240.0)],
            X: [(0, hearts.x), (32, hearts.x + 12.0), (64, hearts.x - 10.0),
                (96, hearts.x + 8.0), (EMO_DURATION, hearts.x)],
            SCALE_X: [(0, hearts.scale * 0.75), (25, hearts.scale * 1.05),
                      (EMO_DURATION, hearts.scale)],
            SCALE_Y: [(0, hearts.scale * 0.75), (25, hearts.scale * 1.05),
                      (EMO_DURATION, hearts.scale)],
        }), EMO_DURATION


GIGGLE_DURATION = 150
"""Смех по тапу — две с половиной секунды."""

# Партитура прыжка: (кадр, сжатие по высоте, подъём, крен в радианах).
# Присел, вытянулся на взлёте, смялся при приземлении, коротко подскочил
# ещё раз и успокоился.
GIGGLE_SCORE = [
    (0,   1.000,  0.0,  0.000),
    (16,  0.955,  0.0,  0.004),
    (30,  1.045, 26.0, -0.010),
    (46,  0.968,  0.0,  0.008),
    (60,  1.026, 10.0, -0.006),
    (76,  0.986,  0.0,  0.004),
    (92,  1.010,  0.0, -0.002),
    (112, 0.996,  0.0,  0.001),
    (132, 1.000,  0.0,  0.000),
    (GIGGLE_DURATION, 1.000, 0.0, 0.000),
]

EMO_DURATION = 120


# --- стейт-машина ----------------------------------------------------------

ANIMATIONS = ('idle', 'idle_happy', 'idle_sad', 'giggle', 'emo_love', 'rest')
ANIM = {name: index for index, name in enumerate(ANIMATIONS)}

INPUT_MOOD, INPUT_PET, INPUT_LOVE = 0, 1, 2

MOOD_BLEND = 350
"""Сведение между настроениями, миллисекунды."""


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
              (CONDITION_OP, 'Uint', 0),
              (CONDITION_VALUE, 'Double', float(value))])]


def on_trigger(input_index: int) -> list:
    return [('TransitionTriggerCondition',
             [(CONDITION_INPUT, 'Uint', input_index)])]


def state_machine() -> list:
    """Две дорожки поведения: тело и эмо-акцент."""
    out: list = [
        ('StateMachine', [(ANIM_NAME, 'String', b'bear_main')]),
        ('StateMachineNumber', [(INPUT_NAME, 'String', b'mood'),
                                (INPUT_VALUE, 'Double', 0.0)]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_pet')]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_emo_love')]),
        ('StateMachineLayer', [(INPUT_NAME, 'String', b'body')]),
    ]

    for name, mood_value in (('idle', 0), ('idle_happy', 1), ('idle_sad', 2)):
        out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM[name])]))
        for other, other_value in ((0, 0), (1, 1), (2, 2)):
            if other_value == mood_value:
                continue
            out += transition(other, MOOD_BLEND) + on_mood(other_value)
        out += transition(3, 120) + on_trigger(INPUT_PET)

    out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM['giggle'])]))
    out += transition(0, 300, exit_time=2400)
    out.append(('EntryState', []))
    out += transition(0)
    out.append(('AnyState', []))
    out.append(('ExitState', []))

    out.append(('StateMachineLayer', [(INPUT_NAME, 'String', b'emo')]))
    out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM['rest'])]))
    out += transition(1, 80) + on_trigger(INPUT_LOVE)
    out.append(('AnimationState',
                [(STATE_ANIMATION, 'Uint', ANIM['emo_love'])]))
    out += transition(0, 200, exit_time=1900)
    out.append(('EntryState', []))
    out += transition(0)
    out.append(('AnyState', []))
    out.append(('ExitState', []))
    return out


# --- сборка ----------------------------------------------------------------


class Builder:
    """Накопитель объектов с автоматическим счётом локальных номеров."""

    def __init__(self, types: dict[int, str]) -> None:
        self.by_name = {name: key for key, name in types.items()}
        self.local: dict[str, int] = {}

    def mark(self, label: str, local: int) -> None:
        self.local[label] = local


def skeleton_objects(builder: Builder, items: list) -> None:
    """Ставит цепочку костей от пола до шеи.

    Только корень стоит на артборде своими координатами; каждая следующая
    кость сидит в конце предыдущей — рантайм берёт её x из длины родителя,
    поэтому цепочку достаточно перечислить по порядку.
    """
    parent = 0
    for index, (name, length) in enumerate(bones.CHAIN):
        local = len(items)
        builder.mark(f'bone:{name}', local)
        if index == 0:
            kind = 'RootBone'
            props = [
                (PARENT, 'Uint', 0),
                (ROOT_X, 'Double', STAGE_CENTRE),
                (ROOT_Y, 'Double', STAGE_BASELINE),
                # Кость смотрит вдоль своей оси X. Минус девяносто
                # градусов ставят цепочку вертикально, осью вверх.
                (ROTATION, 'Double', -math.pi / 2),
            ]
        else:
            kind = 'Bone'
            props = [(PARENT, 'Uint', parent), (ROTATION, 'Double', 0.0)]
        props += [(SCALE_X, 'Double', 1.0), (SCALE_Y, 'Double', 1.0),
                  (BONE_LENGTH, 'Double', length)]
        items.append((builder.by_name[kind], props))
        parent = local


def skinned_mesh(builder: Builder, items: list, part: Part,
                 spec: dict, image_local: int) -> None:
    """Сетка детали, привязанная к костям.

    Вершина не двигается дорожкой — её положение считает рантайм по
    матрицам костей и весам. Поэтому анимировать нужно кости, а вершин
    может быть сколько угодно: на вес файла они не влияют.
    """
    triangles, vertices = mesh_for(part, spec['grid'])
    mesh_local = len(items)
    items.append((builder.by_name['Mesh'], [
        (PARENT, 'Uint', image_local),
        (MESH_TRIANGLES, 'Bytes', b''.join(varuint(i) for i in triangles)),
    ]))

    # Скин переводит вершины из пикселей картинки на сцену; в покое этим всё
    # и ограничивается, потому что кости стоят там же, где их bind-матрицы.
    skin_local = len(items)
    items.append((builder.by_name['Skin'], [
        (PARENT, 'Uint', mesh_local),
        *((key, 'Double', value) for key, value in
          zip(SKIN_MATRIX, bones.skin_bind(part.x, part.y, part.scale))),
    ]))
    for name in spec['bones']:
        items.append((builder.by_name['Tendon'], [
            (PARENT, 'Uint', skin_local),
            (TENDON_BONE, 'Uint', builder.local[f'bone:{name}']),
            *((key, 'Double', value) for key, value in
              zip(TENDON_MATRIX, bones.bone_bind(name))),
        ]))

    for vx, vy in vertices:
        items.append((builder.by_name['MeshVertex'], [
            (PARENT, 'Uint', mesh_local),
            (VERTEX_X, 'Double', vx), (VERTEX_Y, 'Double', vy),
            (VERTEX_U, 'Double', vx / part.width + 0.5),
            (VERTEX_V, 'Double', vy / part.height + 0.5),
        ]))
        world_y = part.y + vy * part.scale
        indices, values = bones.pack(
            bones.influences(world_y, spec['bones']))
        items.append((builder.by_name['Weight'], [
            (PARENT, 'Uint', len(items) - 1),
            (WEIGHT_VALUES, 'Uint', values),
            (WEIGHT_INDICES, 'Uint', indices),
        ]))


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

    assets: list = []
    for index, name in enumerate(DRAW_ORDER):
        part = parts[name]
        assets.append((by_name['ImageAsset'], [
            (ASSET_NAME, 'String', name.encode()),
            (204, 'Uint', 6650000 + index),
            # В этом файле 207 — высота, 208 — ширина. Порядок снят с
            # прежних ассетов, а не угадан.
            (207, 'Double', float(part.height)),
            (208, 'Double', float(part.width)),
        ]))
        assets.append((by_name['FileAssetContents'],
                       [(CONTENTS, 'Bytes', part.blob)]))

    items: list = [rig.objects[scene.artboard],
                   rig.objects[scene.artboard + 1]]
    skeleton_objects(builder, items)

    head_x, head_y = bones.to_bone_space('neck', parts['head_calm'].x,
                                         parts['head_calm'].y)
    for index, name in enumerate(DRAW_ORDER):
        part = parts[name]
        local = len(items)
        builder.mark(name, local)

        if name in HEAD_LAYERS:
            # Голова висит на шее и едет вместе с телом сама — ни одной
            # дорожки положения ей не нужно.
            place = [(PARENT, 'Uint', builder.local['bone:neck']),
                     (X, 'Double', head_x), (Y, 'Double', head_y),
                     (ROTATION, 'Double', bones.HEAD_UPRIGHT)]
        else:
            place = [(PARENT, 'Uint', 0),
                     (X, 'Double', part.x), (Y, 'Double', part.y),
                     (ROTATION, 'Double', 0.0)]

        items.append((by_name['Image'], place + [
            (SCALE_X, 'Double', part.scale), (SCALE_Y, 'Double', part.scale),
            # Видна одна голова из семи, остальные ждут своего настроения.
            # Сердечки тоже погашены: они живут только в эмо-акценте.
            (OPACITY, 'Double',
             0.0 if name in ('hearts', *HEAD_LAYERS[1:]) else 1.0),
            (ASSET_ID, 'Uint', index),
        ]))

        spec = MESHES.get(name)
        if spec is not None:
            skinned_mesh(builder, items, part, spec, local)

    interpolator = len(items)
    items.append((by_name['CubicEaseInterpolator'], []))

    animator = Animator(builder, parts, interpolator)
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
    written: list = []
    for name in ANIMATIONS:
        blocks, duration = plans[name]()
        head = [(ANIM_NAME, 'String', name.encode()),
                (ANIM_DURATION, 'Uint', duration)]
        if name in looped:
            head.append((ANIM_LOOP, 'Uint', 1))
        written.append((by_name['LinearAnimation'], head))
        written += [(by_name[kind], props) for kind, props in blocks]

    machine = [(by_name[kind], props) for kind, props in state_machine()]

    keep_before = [rig.objects[i] for i in range(scene.artboard)
                   if i not in set(scene.assets)
                   and i - 1 not in set(scene.assets)]

    rig.objects = keep_before[:1] + assets + keep_before[1:] + items \
        + written + machine
    path.write_bytes(rig.dumps())

    print(f'Собран {path}: {path.stat().st_size / 1e6:.2f} МБ, '
          f'{len(DRAW_ORDER)} деталей ({len(HEAD_LAYERS)} лиц), '
          f'{len(bones.CHAIN)} костей, {len(ANIMATIONS)} анимаций')
    for name, spec in MESHES.items():
        columns, rows = spec['grid']
        print(f'  {name:6s} сетка {columns}x{rows} на костях '
              f'{", ".join(spec["bones"])}')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    return build(Path(sys.argv[1]))


if __name__ == '__main__':
    sys.exit(main())
