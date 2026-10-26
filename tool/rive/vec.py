"""Свой рисунок на костях — мимика v2 (заказчик 26.10: «всё, что я прислал,
один в один… глазки, всё»; разбор — `docs/mimika-v2.md`).

В видео Ирины шов от носа, ротик, бровки и дужки закрытых глаз — тёмные
вышитые линии поверх меха. Здесь они — векторные пути Rive (Shape →
PointsPath → Skin) на тех же костях, что и сетки лица: линия гнётся вместе
с мимикой, «домик» ∧ переходит в улыбку без смены картинки (заказчик
27.09: «без подмен»). Вершины задаются в мире холста, веса — как у меха в
этой точке, привязка — поза покоя костей (как у сеток в `rebuild_rig`).
"""
import xml.etree.ElementTree as ET

from xf import M


def _f(v):
    return f'{v:.7g}'


def argb(rgb, alpha=1.0):
    """'#rrggbb' и непрозрачность → 'AARRGGBB' для colorValue."""
    return f'{round(alpha * 255):02X}{rgb.lstrip("#").upper()}'


def shape(name, pts, *, bones, weights, pack, next_id, holder_world=None,
          closed=False, stroke=None, fill=None, opacity=1.0):
    """Путь по точкам pts (мир холста) на костях.

    stroke — (толщина, '#rrggbb'[, непрозрачность]), концы и стыки круглые;
    fill — ('#rrggbb'[, непрозрачность]); weights(x, y) → {кость: доля};
    bones — B из `rebuild_rig` (мир покоя костей и их id); holder_world —
    мир узла, куда кладётся фигура (привязка пути — в нём)."""
    hw = holder_world or M()
    inv = hw.inv()
    el = ET.Element('Shape', {'name': name, 'id': next_id()})
    if opacity != 1.0:
        el.set('opacity', _f(opacity))
    path = ET.SubElement(el, 'PointsPath', {'isClosed': 'true' if closed else 'false',
                                            'name': f'{name}_path', 'id': next_id()})
    ws = [weights(x, y) for x, y in pts]
    order = sorted({b for w in ws for b in w}, key=list(bones).index)
    for (x, y), w in zip(pts, ws):
        lx, ly = inv.apply(x, y)
        v = ET.SubElement(path, 'StraightVertex', {'x': _f(lx), 'y': _f(ly), 'name': 'v', 'id': next_id()})
        pv, pi = pack(w, order)
        ET.SubElement(v, 'Weight', {'values': str(pv), 'indices': str(pi), 'name': 'w', 'id': next_id()})
    skin = ET.SubElement(path, 'Skin', {k: _f(val) for k, val in zip(('xx', 'xy', 'yx', 'yy', 'tx', 'ty'), hw.v)})
    skin.set('name', 'Skin')
    skin.set('id', next_id())
    for b in order:
        m = bones[b]['world'].v
        ET.SubElement(skin, 'Tendon', {'boneId': bones[b]['id'], 'xx': _f(m[0]), 'xy': _f(m[1]),
                                       'yx': _f(m[2]), 'yy': _f(m[3]), 'tx': _f(m[4]), 'ty': _f(m[5]),
                                       'name': b, 'id': next_id()})
    if fill:
        paint = ET.SubElement(el, 'Fill', {'name': 'Fill', 'id': next_id()})
        ET.SubElement(paint, 'SolidColor', {'colorValue': argb(*fill), 'name': 'C', 'id': next_id()})
    if stroke:
        width, *color = stroke
        paint = ET.SubElement(el, 'Stroke', {'thickness': _f(width), 'cap': 'round', 'join': 'round',
                                             'name': 'Stroke', 'id': next_id()})
        ET.SubElement(paint, 'SolidColor', {'colorValue': argb(*color), 'name': 'C', 'id': next_id()})
    return el


def arc(center, radius, a0, a1, n):
    """n точек дуги (углы в радианах, 0 — вправо, по часовой — вниз)."""
    import math
    cx, cy = center
    rx, ry = radius if isinstance(radius, tuple) else (radius, radius)
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / (n - 1)),
             cy + ry * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]
