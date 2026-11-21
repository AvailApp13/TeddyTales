#!/usr/bin/env python3
"""Собирает `bear_main.riv` из частей набора v7.

Против прежней сборки изменилось главное: мишка больше не три куска, а
двадцать одна деталь на двадцати двух костях. Руки разгибаются в локте,
уши подрагивают, глаза ездят по морде, челюсть открывает рот — всё это
теперь физически возможно, потому что части сняты порознь и под каждой
нарисовано то, что раньше было закрыто соседней.

## Как деталь держится

Почти каждая деталь просто висит на своей кости: её положение задано в
координатах кости, и когда кость поворачивается, деталь едет с ней целиком.
Деформация сеткой нужна там, где деталь обязана гнуться, а не двигаться —
это корпус на вдохе. Остальному она только вредит: фотографию меха нельзя
тянуть, любая волна по ней читается как резина.

## Два листа, одна сцена

Тело снято на одном листе, голова крупным планом на другом, и масштабы у
них разные. Коэффициент замерен по ширине головы на обоих листах, а
совмещение — по носу: это самая контрастная деталь, её центр находится
надёжнее любой другой точки.

    python3 tool/riv_build.py assets/rive/bear_main.riv

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
from riv_paint import find_runtime, load_registry  # noqa: E402
from riv_rig import Rig, Scene, get, varuint  # noqa: E402

PARTS_DIR = os.environ.get('BEAR_PARTS') or 'docs/reference/parts-v7'

# --- совмещение листов -----------------------------------------------------

HEAD_SCALE = 1 / 2.1039
"""Во сколько раз уменьшить детали с листа головы. Замерено по ширине
головы: 2268 пикселей на крупном плане против 1078 на общем."""

HEAD_SHIFT = (732.0, -88.0)
"""Куда сдвинуть уменьшённую голову, чтобы нос сел в нос."""

HEAD_SHEET = {'b1-head', 'b3-eyes-half', 'b4-eyes-shut', 'b5-happy',
              'b6-sad', 'b7-chew', 'b8-surprise'}

# --- посадка на сцену ------------------------------------------------------

BODY_CENTRE = 1435.0
BODY_BASELINE = 2780.0
BODY_HEIGHT = 2643.0
"""Мишка на листе тела: центр по ширине, пол под ступнями, полный рост."""

STAGE_CENTRE = bones.STAGE_CENTRE
STAGE_BASELINE = bones.STAGE_BASELINE
STAGE_HEIGHT = 1310.0

STAGE_SCALE = STAGE_HEIGHT / BODY_HEIGHT
DOWNSAMPLE = 1.6
"""Во сколько раз ужимается картинка детали относительно листа.

На сцене мишка занимает 1310 единиц при артборде 1350, а сцена на телефоне
показывается примерно один к одному с физическими пикселями. Лист снят
вдвое крупнее нужного, и полтора-два раза ужатия проходят незаметно, зато
режут вес вчетверо.
"""

WEBP_QUALITY = 90

# Деталь -> кость, на которой она висит. Порядок словаря задаёт порядок
# отрисовки: записанный раньше рисуется ПОВЕРХ записанных следом.
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

SPRITES = {
    'eye_left_half': 'b_pupil_left', 'eye_right_half': 'b_pupil_right',
    'eye_left_shut': 'b_pupil_left', 'eye_right_shut': 'b_pupil_right',
    'eye_left_happy': 'b_pupil_left', 'eye_right_happy': 'b_pupil_right',
    'eye_left_sad': 'b_pupil_left', 'eye_right_sad': 'b_pupil_right',
    'mouth_smile': 'b_jaw', 'mouth_sad': 'b_jaw',
    'mouth_open': 'b_jaw', 'mouth_o': 'b_jaw',
}

TORSO_MESH = {'grid': (7, 9),
              'bones': ['b_hip', 'b_spine', 'b_neck']}
"""Единственная сетка в риге. Корпус обязан гнуться на вдохе, остальным
деталям сетка только вредит: фотографию меха нельзя тянуть."""

# --- ключи свойств ---------------------------------------------------------

PARENT = 5
X, Y, ROTATION, SCALE_X, SCALE_Y, OPACITY = 13, 14, 15, 16, 17, 18
VERTEX_X, VERTEX_Y, VERTEX_U, VERTEX_V = 24, 25, 215, 216
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


def to_stage(x: float, y: float, sheet: str) -> tuple[float, float]:
    """Точка на листе -> точка на сцене."""
    if sheet in HEAD_SHEET:
        x = x * HEAD_SCALE + HEAD_SHIFT[0]
        y = y * HEAD_SCALE + HEAD_SHIFT[1]
    return ((x - BODY_CENTRE) * STAGE_SCALE + STAGE_CENTRE,
            (y - BODY_BASELINE) * STAGE_SCALE + STAGE_BASELINE)


class Part:
    """Деталь, посаженная на сцену."""

    def __init__(self, name: str, blob: bytes, stored: tuple[int, int],
                 centre: tuple[float, float], scale: float) -> None:
        self.name = name
        self.blob = blob
        self.width, self.height = stored
        self.x, self.y = centre
        self.scale = scale


def load_parts() -> dict[str, Part]:
    from PIL import Image  # noqa: PLC0415
    import io  # noqa: PLC0415

    root = Path(PARTS_DIR)
    if not root.is_absolute():
        root = Path(__file__).resolve().parent.parent / root
    placements = json.loads((root / 'placements.json').read_text())

    parts: dict[str, Part] = {}
    for name, place in placements.items():
        image = Image.open(root / f'{name}.webp').convert('RGBA')
        image = image.resize(
            (max(1, round(image.width / DOWNSAMPLE)),
             max(1, round(image.height / DOWNSAMPLE))), Image.LANCZOS)
        buffer = io.BytesIO()
        image.save(buffer, 'WEBP', quality=WEBP_QUALITY, method=6)

        sheet = place['sheet']
        centre = to_stage(place['x'] + place['w'] / 2,
                          place['y'] + place['h'] / 2, sheet)
        scale = STAGE_SCALE * DOWNSAMPLE
        if sheet in HEAD_SHEET:
            scale *= HEAD_SCALE
        parts[name] = Part(name, buffer.getvalue(), image.size, centre, scale)
    return parts


# --- движение --------------------------------------------------------------

BREATH = {'spine_y': 0.055, 'spine_x': 0.028, 'hip_y': 0.016}
"""Вдох: позвоночник раздаётся вширь и вытягивается, таз идёт следом.
Ось X кости смотрит вдоль неё, то есть вверх; Y — поперёк, вширь."""

NOD = 0.026
EAR_SWING = 0.075
"""Кивок шеи и качание ушей на вдохе, радианы. Уши мягкие и отстают —
именно это отставание и читается как плюш."""

SWAY_TILT = 0.005
SWAY_SHIFT = 1.8
"""Покачивание в покое: крен всего тела и переступание с ноги на ногу.
Величины крошечные, но без них мишка стоит как вкопанный: живое тело всё
время перекладывает вес."""

GLANCE_SHIFT = 7.0
"""На сколько зрачки уезжают в сторону при взгляде. Единицы сцены."""

PEAK = {'hip': 62, 'spine': 70, 'neck': 88, 'ear': 104}

GIGGLE_DURATION = 150
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

MOODS = {
    'idle':       {'cycle': 180, 'amp': 1.00, 'tilt': 0.000,
                   'eyes': '', 'mouth': 'mouth', 'glance': True},
    'idle_happy': {'cycle': 132, 'amp': 1.15, 'tilt': -0.020,
                   'eyes': '_happy', 'mouth': 'mouth_smile', 'glance': False},
    'idle_sad':   {'cycle': 230, 'amp': 0.70, 'tilt': 0.045,
                   'eyes': '_sad', 'mouth': 'mouth_sad', 'glance': False},
}

EYE_STATES = ('', '_half', '_shut', '_happy', '_sad')
MOUTH_STATES = ('mouth', 'mouth_smile', 'mouth_sad', 'mouth_open', 'mouth_o')


def sway(duration: int, amplitude: float, base: float = 0.0,
         turns: float = 1.0, phase: float = 0.0) -> list:
    """Плавная синусоида на всю длину анимации."""
    steps = max(8, int(round(8 * turns)))
    return [(round(duration * step / steps),
             base + amplitude * math.sin(2 * math.pi
                                         * (turns * step / steps + phase)))
            for step in range(steps + 1)]


class Animator:
    def __init__(self, builder, parts, interpolator) -> None:
        self.b = builder
        self.parts = parts
        self.interpolator = interpolator

    def track(self, local: int, tracks: dict) -> list:
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

    def visible(self, name: str, keys: list) -> list:
        return self.track(self.b.local[name], {OPACITY: keys})

    def idle(self, mood: dict) -> tuple[list, int]:
        cycle = mood['cycle']
        duration = 2 * cycle
        stretch = cycle / 180
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

        # Тело всё время перекладывает вес. Полтора оборота на анимацию —
        # чтобы покачивание не совпало с дыханием и петля не читалась.
        blocks += self.bone('b_root', {
            ROTATION: sway(duration, SWAY_TILT,
                           bones.local_rotation('b_root'), turns=1.5),
            ROOT_X: sway(duration, SWAY_SHIFT, STAGE_CENTRE,
                         turns=1.5, phase=0.25),
        })

        blocks += self.bone('b_hip', {
            SCALE_Y: waves(PEAK['hip'], lambda k: 1 + BREATH['hip_y'] * k),
        })
        blocks += self.bone('b_spine', {
            SCALE_X: waves(PEAK['spine'], lambda k: 1 + BREATH['spine_x'] * k),
            SCALE_Y: waves(PEAK['spine'], lambda k: 1 + BREATH['spine_y'] * k),
        })
        # Шея гасит масштаб позвоночника: иначе он дотянулся бы по цепочке
        # до головы и раздувал её вместе с животом. Подъём при этом
        # сохраняется — он идёт от удлинения кости, а не от масштаба.
        blocks += self.bone('b_neck', {
            SCALE_X: waves(PEAK['spine'],
                           lambda k: 1 / (1 + BREATH['spine_x'] * k)),
            SCALE_Y: waves(PEAK['spine'],
                           lambda k: 1 / (1 + BREATH['spine_y'] * k)),
            ROTATION: waves(PEAK['neck'],
                            lambda k, t=mood['tilt']:
                            bones.local_rotation('b_neck') + t - NOD * k),
        })

        # Уши отстают от головы — на этом отставании и держится плюшевость.
        for side, sign in (('left', 1.0), ('right', -1.0)):
            name = f'b_ear_{side}'
            base = bones.local_rotation(name)
            blocks += self.bone(name, {
                ROTATION: waves(PEAK['ear'],
                                lambda k, b=base, s=sign:
                                b + s * EAR_SWING * k),
            })

        # Руки качаются от плеча, кисти догоняют.
        for side, sign in (('left', -1.0), ('right', 1.0)):
            for part, peak, share in (('upper', PEAK['spine'], 0.5),
                                      ('lower', PEAK['neck'], 0.8),
                                      ('', PEAK['ear'], 1.0)):
                name = (f'b_arm_{side}_{part}' if part
                        else f'b_paw_{side}')
                base = bones.local_rotation(name)
                blocks += self.bone(name, {
                    ROTATION: waves(peak, lambda k, b=base, s=sign, w=share:
                                    b + s * 0.030 * w * k),
                })

        blocks += self.faces(mood, cycle, duration)
        return blocks, duration

    def faces(self, mood: dict, cycle: int, duration: int) -> list:
        """Показывает нужное лицо и прячет остальные состояния.

        Дорожка пишется для каждого состояния в каждом настроении, а не
        только для видимого: иначе деталь, зажжённая прошлой анимацией,
        останется гореть после перехода — рантайм держит последнее
        применённое значение.
        """
        blocks: list = []
        for state in EYE_STATES:
            on = state == mood['eyes']
            for side in ('left', 'right'):
                blocks += self.visible(f'eye_{side}{state}',
                                       [(0, 1.0 if on else 0.0, HOLD)])
        for state in MOUTH_STATES:
            blocks += self.visible(
                state, [(0, 1.0 if state == mood['mouth'] else 0.0, HOLD)])

        if mood['glance']:
            # Взгляд уводится зрачками, а не подменой головы: глаза ездят
            # по морде сами.
            for side, phase in (('left', 0.0), ('right', 0.0)):
                name = f'b_pupil_{side}'
                _, start, _ = bones.CHAIN[name]
                blocks += self.bone(name, {
                    ROOT_X: [(0, start[0]),
                             (round(cycle * 0.62), start[0] + GLANCE_SHIFT),
                             (round(cycle * 0.62) + 44, start[0]
                              + GLANCE_SHIFT),
                             (round(cycle * 0.75) + 44, start[0]),
                             (round(cycle * 1.58), start[0] - GLANCE_SHIFT),
                             (round(cycle * 1.58) + 44, start[0]
                              - GLANCE_SHIFT),
                             (round(cycle * 1.72) + 44, start[0]),
                             (duration, start[0])],
                })
        return blocks

    def giggle(self) -> tuple[list, int]:
        """Мишка подпрыгивает как одно упругое тело."""
        blocks: list = []
        blocks += self.bone('b_root', {
            ROOT_Y: [(f, STAGE_BASELINE - jump)
                     for f, _, jump, _ in GIGGLE_SCORE],
            ROTATION: [(f, bones.local_rotation('b_root') + tilt)
                       for f, _, _, tilt in GIGGLE_SCORE],
        })
        blocks += self.bone('b_spine', {
            SCALE_X: [(f, squash) for f, squash, _, _ in GIGGLE_SCORE],
            SCALE_Y: [(f, 1 + (1 - squash) * 0.7)
                      for f, squash, _, _ in GIGGLE_SCORE],
        })
        blocks += self.bone('b_hip', {
            SCALE_Y: [(f, 1 + (1 - squash) * 0.4)
                      for f, squash, _, _ in GIGGLE_SCORE],
        })
        lag = dict(zip((f for f, _, _, _ in GIGGLE_SCORE),
                       (0.0, 0.05, -0.07, 0.05, -0.04, 0.03, -0.02, 0.01,
                        0.0, 0.0)))
        blocks += self.bone('b_neck', {
            ROTATION: [(f, bones.local_rotation('b_neck') + lag[f] - tilt * 1.6)
                       for f, _, _, tilt in GIGGLE_SCORE],
        })
        for side, sign in (('left', 1.0), ('right', -1.0)):
            name = f'b_ear_{side}'
            base = bones.local_rotation(name)
            blocks += self.bone(name, {
                ROTATION: [(f, base + sign * lag[f] * 2.2)
                           for f, _, _, _ in GIGGLE_SCORE],
            })
        # Смеющиеся глаза и открытый рот — подменой, а не анимацией.
        for state in EYE_STATES:
            on = state == '_happy'
            for side in ('left', 'right'):
                blocks += self.visible(f'eye_{side}{state}',
                                       [(0, 1.0 if on else 0.0, HOLD)])
        for state in MOUTH_STATES:
            blocks += self.visible(
                state, [(0, 1.0 if state == 'mouth_smile' else 0.0, HOLD)])
        return blocks, GIGGLE_DURATION

    def emo_love(self) -> tuple[list, int]:
        hearts = self.parts['hearts']
        return self.track(self.b.local['hearts'], {
            OPACITY: [(0, 0.0), (10, 1.0), (85, 1.0), (115, 0.0),
                      (EMO_DURATION, 0.0)],
            Y: [(0, hearts.y), (EMO_DURATION, hearts.y - 240.0)],
            X: [(0, hearts.x), (32, hearts.x + 12.0), (64, hearts.x - 10.0),
                (96, hearts.x + 8.0), (EMO_DURATION, hearts.x)],
        }), EMO_DURATION


# --- стейт-машина ----------------------------------------------------------

ANIMATIONS = ('idle', 'idle_happy', 'idle_sad', 'giggle', 'emo_love', 'rest')
ANIM = {name: index for index, name in enumerate(ANIMATIONS)}
INPUT_MOOD, INPUT_PET, INPUT_LOVE = 0, 1, 2
MOOD_BLEND = 350


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


def on_trigger(index: int) -> list:
    return [('TransitionTriggerCondition', [(CONDITION_INPUT, 'Uint', index)])]


def state_machine() -> list:
    out: list = [
        ('StateMachine', [(ANIM_NAME, 'String', b'bear_main')]),
        ('StateMachineNumber', [(INPUT_NAME, 'String', b'mood'),
                                (INPUT_VALUE, 'Double', 0.0)]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_pet')]),
        ('StateMachineTrigger', [(INPUT_NAME, 'String', b'trg_emo_love')]),
        ('StateMachineLayer', [(INPUT_NAME, 'String', b'body')]),
    ]
    for name, value in (('idle', 0), ('idle_happy', 1), ('idle_sad', 2)):
        out.append(('AnimationState', [(STATE_ANIMATION, 'Uint', ANIM[name])]))
        for other, other_value in ((0, 0), (1, 1), (2, 2)):
            if other_value != value:
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
    def __init__(self, types: dict[int, str]) -> None:
        self.by_name = {name: key for key, name in types.items()}
        self.local: dict[str, int] = {}

    def mark(self, label: str, local: int) -> None:
        self.local[label] = local


def carry_hearts(rig: Rig, scene: Scene) -> Part:
    """Забирает сердечки из прежнего файла: к набору частей они не относятся."""
    index = next(i for i in scene.images if scene.image_name(i) == 'hearts')
    props = rig.objects[index][1]
    asset = scene.assets[get(props, ASSET_ID)]
    blob = get(rig.objects[asset + 1][1], CONTENTS)
    asset_props = rig.objects[asset][1]
    size = (int(get(asset_props, 208)), int(get(asset_props, 207)))
    return Part('hearts', blob, size,
                (get(props, X), get(props, Y)), get(props, SCALE_X))


BRANCH_GAP = 1.0
"""Насколько далеко начало кости может отстоять от конца родителя, чтобы
её всё ещё можно было считать продолжением цепочки."""


def skeleton_objects(builder: Builder, items: list) -> None:
    """Ставит дерево костей.

    Обычная кость в Rive не имеет собственных координат: рантайм берёт её
    `x` из длины родителя, то есть она всегда сидит ровно в его конце. Для
    цепочки позвоночника это и нужно, а для ветки — нет: ухо растёт из
    виска, рука из плеча, и ни то, ни другое не совпадает с концом
    родительской кости.

    Поэтому ветка начинается с `RootBone`. Это единственная кость, которой
    можно задать положение, и единственная, которой разрешено висеть не на
    кости. Так же устроен демо-дракон: четырнадцать корневых костей на
    восемнадцать узлов — по одной на каждую ветку.

    Без этого ветки молча съезжают в конец родителя: уши уходят на макушку,
    зрачки — в лоб, и деталь, посаженная по своим координатам, расходится с
    тем местом, где её ждут.
    """
    for name, (parent, start, end) in bones.CHAIN.items():
        local = len(items)
        builder.mark(f'bone:{name}', local)
        if parent is None:
            items.append((builder.by_name['RootBone'], [
                (PARENT, 'Uint', 0),
                (ROOT_X, 'Double', start[0]), (ROOT_Y, 'Double', start[1]),
                (ROTATION, 'Double', bones.local_rotation(name)),
                (SCALE_X, 'Double', 1.0), (SCALE_Y, 'Double', 1.0),
                (BONE_LENGTH, 'Double', bones.length_of(start, end)),
            ]))
            continue

        _, parent_start, parent_end = bones.CHAIN[parent]
        parent_local = builder.local[f'bone:{parent}']
        continues = bones.length_of(parent_end, start) <= BRANCH_GAP

        if continues:
            # Продолжение цепочки: сидит в конце родителя, угол — от него.
            props = [(PARENT, 'Uint', parent_local),
                     (ROTATION, 'Double', bones.local_rotation(name))]
            kind = 'Bone'
        else:
            # Ветка. Корневая кость не наследует трансформ родителя: и
            # положение, и угол задаются в мировых величинах. Проверено
            # дорогой ценой — от относительного угла ветки разлетались, а
            # у зрачков это долго не замечалось, потому что круглый глаз
            # выглядит одинаково под любым поворотом.
            props = [(PARENT, 'Uint', parent_local),
                     (ROOT_X, 'Double', start[0]), (ROOT_Y, 'Double', start[1]),
                     (ROTATION, 'Double', bones.angle_of(start, end))]
            kind = 'RootBone'

        props += [(SCALE_X, 'Double', 1.0), (SCALE_Y, 'Double', 1.0),
                  (BONE_LENGTH, 'Double', bones.length_of(start, end))]
        items.append((builder.by_name[kind], props))


def skinned_torso(builder: Builder, items: list, part: Part,
                  image_local: int) -> None:
    """Сетка корпуса, привязанная к костям таза, позвоночника и шеи."""
    columns, rows = TORSO_MESH['grid']
    xs = [part.width * (c / (columns - 1) - 0.5) for c in range(columns)]
    ys = [part.height * (r / (rows - 1) - 0.5) for r in range(rows)]
    triangles: list[int] = []
    for r in range(rows - 1):
        for c in range(columns - 1):
            corner = r * columns + c
            triangles += [corner, corner + 1, corner + columns,
                          corner + 1, corner + columns + 1, corner + columns]

    mesh_local = len(items)
    items.append((builder.by_name['Mesh'], [
        (PARENT, 'Uint', image_local),
        (MESH_TRIANGLES, 'Bytes', b''.join(varuint(i) for i in triangles)),
    ]))
    skin_local = len(items)
    items.append((builder.by_name['Skin'], [
        (PARENT, 'Uint', mesh_local),
        *((key, 'Double', value) for key, value in
          zip(SKIN_MATRIX, bones.skin_bind(part.x, part.y, part.scale))),
    ]))
    for name in TORSO_MESH['bones']:
        items.append((builder.by_name['Tendon'], [
            (PARENT, 'Uint', skin_local),
            (TENDON_BONE, 'Uint', builder.local[f'bone:{name}']),
            *((key, 'Double', value) for key, value in
              zip(TENDON_MATRIX, bones.bone_bind(name))),
        ]))

    for vy in ys:
        for vx in xs:
            items.append((builder.by_name['MeshVertex'], [
                (PARENT, 'Uint', mesh_local),
                (VERTEX_X, 'Double', vx), (VERTEX_Y, 'Double', vy),
                (VERTEX_U, 'Double', vx / part.width + 0.5),
                (VERTEX_V, 'Double', vy / part.height + 0.5),
            ]))
            point = (part.x + vx * part.scale, part.y + vy * part.scale)
            indices, values = bones.pack(
                bones.influences(point, TORSO_MESH['bones']))
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
    # Скелет выводится из фактических габаритов деталей — единственный
    # способ гарантировать, что кость проходит внутри той детали, которую
    # несёт.
    bones.adopt(bones.from_parts(parts))
    parts['hearts'] = carry_hearts(rig, scene)

    draw_order = ['hearts'] + list(SPRITES) + list(MOUNT)
    missing = [n for n in draw_order if n not in parts]
    if missing:
        raise SystemExit(f'Нет частей: {", ".join(missing)}')

    builder = Builder(types)
    by_name = builder.by_name

    assets: list = []
    for index, name in enumerate(draw_order):
        part = parts[name]
        assets.append((by_name['ImageAsset'], [
            (ASSET_NAME, 'String', name.encode()),
            (204, 'Uint', 6650000 + index),
            (207, 'Double', float(part.height)),
            (208, 'Double', float(part.width)),
        ]))
        assets.append((by_name['FileAssetContents'],
                       [(CONTENTS, 'Bytes', part.blob)]))

    items: list = [rig.objects[scene.artboard], rig.objects[scene.artboard + 1]]
    skeleton_objects(builder, items)

    mounts = dict(SPRITES)
    mounts.update(MOUNT)
    for index, name in enumerate(draw_order):
        part = parts[name]
        local = len(items)
        builder.mark(name, local)

        bone = mounts.get(name)
        if bone is None:
            place = [(PARENT, 'Uint', 0),
                     (X, 'Double', part.x), (Y, 'Double', part.y),
                     (ROTATION, 'Double', 0.0)]
        else:
            # Деталь висит на кости: её координаты — в системе этой кости,
            # а разворот возвращает её в вертикаль, потому что кость лежит
            # на боку (её ось X смотрит вдоль кости).
            local_x, local_y = bones.to_bone_space(bone, part.x, part.y)
            place = [(PARENT, 'Uint', builder.local[f'bone:{bone}']),
                     (X, 'Double', local_x), (Y, 'Double', local_y),
                     (ROTATION, 'Double', bones.upright(bone))]

        hidden = name == 'hearts' or name in SPRITES
        items.append((by_name['Image'], place + [
            (SCALE_X, 'Double', part.scale), (SCALE_Y, 'Double', part.scale),
            (OPACITY, 'Double', 0.0 if hidden else 1.0),
            (ASSET_ID, 'Uint', index),
        ]))

        if name == 'torso':
            skinned_torso(builder, items, part, local)

    interpolator = len(items)
    items.append((by_name['CubicEaseInterpolator'], []))

    animator = Animator(builder, parts, interpolator)
    plans = {
        'idle': lambda: animator.idle(MOODS['idle']),
        'idle_happy': lambda: animator.idle(MOODS['idle_happy']),
        'idle_sad': lambda: animator.idle(MOODS['idle_sad']),
        'giggle': animator.giggle,
        'emo_love': animator.emo_love,
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
          f'{len(draw_order)} деталей, {len(bones.CHAIN)} костей, '
          f'{len(ANIMATIONS)} анимаций')
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    return build(Path(sys.argv[1]))


if __name__ == '__main__':
    sys.exit(main())
