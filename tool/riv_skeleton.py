#!/usr/bin/env python3
"""Скелет мишки: 22 кости по ТЗ 3.1, привязка вершин, матрицы.

Зачем скелет. Сетка двигает вершины поодиночке, и каждая деталь живёт своей
дорожкой: кофта раздувается по своим ключам, голова едет по своим. Стоит им
разойтись на десяток пикселей — по плечу идёт засветка, на стыке видна
ступенька. Лечить это приходилось, урезая движение, то есть отнимая у мишки
жизнь. Скелет снимает вопрос по построению: детали висят на общей цепочке и
разъехаться не могут.

Имена костей заданы в ТЗ 3.1 и менять их нельзя — по ним линтер проверяет
комплектность рига. Дерево:

    b_root
    └ b_hip
      ├ b_spine
      │ ├ b_neck → b_head
      │ │           ├ b_ear_left / b_ear_right
      │ │           ├ b_pupil_left / b_pupil_right
      │ │           └ b_jaw
      │ ├ b_arm_left_upper → b_arm_left_lower → b_paw_left
      │ └ b_arm_right_upper → b_arm_right_lower → b_paw_right
      ├ b_leg_left_upper → b_leg_left_lower → b_foot_left
      └ b_leg_right_upper → b_leg_right_lower → b_foot_right

`b_brow_left` и `b_brow_right` из ТЗ не воспроизводятся: у настоящей игрушки
бровей нет, над глазами-бусинами просто мех.

## Как кость устроена в файле

Кость в Rive смотрит вдоль своей локальной оси X и сидит в конце
родительской: собственных координат у неё нет, рантайм берёт `x` из длины
родителя. Поэтому скелет здесь задан не углами, а точками: у каждой кости
указано, откуда и куда она идёт в координатах сцены. Углы и длины
вычисляются из них, и правка позы сводится к сдвигу точки, а не к подбору
градусов.

## Как считается деформация

    world = Σ w_i · (Bone_i.world · Tendon_i.inverseBind) · (Skin.world · v)

В покое `Bone.world` равна `Tendon.bind`, произведение вырождается в
единицу, и вершина стоит там, куда её ставит `Skin.world`. Отсюда два
следствия: bind-матрицы тендонов — это в точности мировые матрицы костей в
покое, а `Skin.world` — посадка детали на сцену.
"""

from __future__ import annotations

import math

STAGE_CENTRE = 540.0
STAGE_BASELINE = 1350.0
"""Точка опоры: пол под ступнями мишки, середина по ширине."""

# Скелет точками: кость -> (родитель, начало, конец) в координатах сцены.
# Ось Y направлена вниз, как в артборде.
CHAIN: dict[str, tuple[str | None, tuple[float, float], tuple[float, float]]] = {
    'b_root':  (None,     (540.0, 1350.0), (540.0, 1140.0)),
    'b_hip':   ('b_root', (540.0, 1140.0), (540.0, 1010.0)),
    'b_spine': ('b_hip',  (540.0, 1010.0), (540.0,  740.0)),
    'b_neck':  ('b_spine', (540.0, 740.0), (540.0,  660.0)),
    'b_head':  ('b_neck', (540.0,  660.0), (540.0,  430.0)),

    # Голова: уши по бокам, зрачки в глазах, челюсть под мордой.
    'b_ear_left':   ('b_head', (395.0, 500.0), (330.0, 420.0)),
    'b_ear_right':  ('b_head', (685.0, 500.0), (750.0, 420.0)),
    'b_pupil_left': ('b_head', (470.0, 566.0), (470.0, 546.0)),
    'b_pupil_right': ('b_head', (610.0, 566.0), (610.0, 546.0)),
    'b_jaw':        ('b_head', (540.0, 600.0), (540.0, 655.0)),

    # Руки идут вниз и чуть наружу — как они и стоят на листе A-позы.
    'b_arm_left_upper':  ('b_spine', (430.0,  790.0), (352.0,  962.0)),
    'b_arm_left_lower':  ('b_arm_left_upper', (352.0, 962.0), (318.0, 1090.0)),
    'b_paw_left':        ('b_arm_left_lower', (318.0, 1090.0), (310.0, 1165.0)),
    'b_arm_right_upper': ('b_spine', (650.0,  790.0), (728.0,  962.0)),
    'b_arm_right_lower': ('b_arm_right_upper', (728.0, 962.0), (762.0, 1090.0)),
    'b_paw_right':       ('b_arm_right_lower', (762.0, 1090.0), (770.0, 1165.0)),

    # Ноги — вниз, чуть расходясь.
    'b_leg_left_upper':  ('b_hip', (468.0, 1010.0), (452.0, 1152.0)),
    'b_leg_left_lower':  ('b_leg_left_upper', (452.0, 1152.0), (444.0, 1272.0)),
    'b_foot_left':       ('b_leg_left_lower', (444.0, 1272.0), (440.0, 1345.0)),
    'b_leg_right_upper': ('b_hip', (612.0, 1010.0), (628.0, 1152.0)),
    'b_leg_right_lower': ('b_leg_right_upper', (628.0, 1152.0), (636.0, 1272.0)),
    'b_foot_right':      ('b_leg_right_lower', (636.0, 1272.0), (640.0, 1345.0)),
}

NAMES = list(CHAIN)


def angle_of(start: tuple[float, float], end: tuple[float, float]) -> float:
    return math.atan2(end[1] - start[1], end[0] - start[0])


def length_of(start: tuple[float, float], end: tuple[float, float]) -> float:
    return math.hypot(end[0] - start[0], end[1] - start[1])


def local_rotation(name: str) -> float:
    """Угол кости относительно родителя — то, что пишется в файл."""
    parent, start, end = CHAIN[name]
    mine = angle_of(start, end)
    if parent is None:
        return mine
    _, parent_start, parent_end = CHAIN[parent]
    return mine - angle_of(parent_start, parent_end)


def bone_bind(name: str) -> tuple[float, ...]:
    """Мировая матрица кости в покое: (xx, yx, xy, yy, tx, ty)."""
    _, start, end = CHAIN[name]
    theta = angle_of(start, end)
    cos, sin = math.cos(theta), math.sin(theta)
    return (cos, -sin, sin, cos, start[0], start[1])


def skin_bind(centre_x: float, centre_y: float,
              scale: float) -> tuple[float, ...]:
    """Матрица посадки детали: пиксели картинки -> сцена."""
    return (scale, 0.0, 0.0, scale, centre_x, centre_y)


def to_bone_space(name: str, x: float, y: float) -> tuple[float, float]:
    """Точку сцены — в локальные координаты кости."""
    _, start, end = CHAIN[name]
    theta = angle_of(start, end)
    dx, dy = x - start[0], y - start[1]
    cos, sin = math.cos(-theta), math.sin(-theta)
    return (dx * cos - dy * sin, dx * sin + dy * cos)


def upright(name: str) -> float:
    """Разворот, возвращающий висящий на кости узел в вертикаль."""
    _, start, end = CHAIN[name]
    return -angle_of(start, end)


def influences(point: tuple[float, float],
               bones: list[str]) -> list[tuple[int, int]]:
    """Кости, которые тянут вершину, и их веса 0…255.

    Вес распределяется между двумя ближайшими костями по расстоянию до их
    отрезков. Двух достаточно: кости у нас тонкие и вытянутые, третья
    оказывается дальше своего пролёта и её вклад всё равно обнулился бы.

    ТЗ 3.3 требует мягкого скиннинга: в зоне перехлёста вершина обязана
    слушаться не меньше двух костей, и ни одно влияние не равно ста
    процентам. Жёсткая привязка на границе двух костей даёт излом ткани.
    """
    distances = []
    for index, name in enumerate(bones):
        _, start, end = CHAIN[name]
        distances.append((_distance_to_segment(point, start, end), index + 1))
    distances.sort()

    (near, first), (far, second) = distances[0], distances[1]
    if far <= 1e-6:
        return [(first, 255)]
    # Обратное расстояние: чем ближе кость, тем сильнее тянет.
    share = far / (near + far)
    share = min(max(share, 0.55), 0.92)
    mine = int(round(255 * share))
    return [(first, mine), (second, 255 - mine)]


def _distance_to_segment(point, start, end) -> float:
    px, py = point
    ax, ay = start
    bx, by = end
    dx, dy = bx - ax, by - ay
    span = dx * dx + dy * dy
    if span < 1e-9:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / span))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def pack(pairs: list[tuple[int, int]]) -> tuple[int, int]:
    """Упаковывает привязку в пару uint32: индексы и веса, по байту на кость."""
    indices = values = 0
    for slot, (index, weight) in enumerate(pairs[:4]):
        indices |= (index & 0xFF) << (slot * 8)
        values |= (weight & 0xFF) << (slot * 8)
    return indices, values
