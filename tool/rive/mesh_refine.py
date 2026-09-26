"""Сгущение сетки картинки в нужных местах (рот, веки, брови).

Сетка лица из исходника редкая: у рта ~6 единиц между точками, уголок рта
не согнуть. Здесь треугольники рядом с зонами делятся на четыре (середины
рёбер), соседи — пополам, чтобы не было Т-стыков (red-green). Новые точки
лежат ровно на рёбрах, u/v — тоже середины: в покое картинка не меняется
ни на пиксель.
"""

import base64
import math
import xml.etree.ElementTree as ET

VERT_TAGS = ('ContourMeshVertex', 'MeshVertex')


def _read_indices(s):
    out, v, sh = [], 0, 0
    for byte in base64.b64decode(s):
        v |= (byte & 0x7F) << sh
        sh += 7
        if not byte & 0x80:
            out.append(v)
            v = sh = 0
    return out


def _write_indices(idx):
    b = bytearray()
    for v in idx:
        while True:
            byte = v & 0x7F
            v >>= 7
            if v:
                b.append(byte | 0x80)
            else:
                b.append(byte)
                break
    return base64.b64encode(bytes(b)).decode()


def refine(mesh, to_world, zones, next_id):
    """zones: [(x, y, радиус, уровней)] в мире; next_id() — новый id.
    Возвращает, сколько точек добавлено."""
    verts = [v for v in mesh if v.tag in VERT_TAGS]
    first_after = list(mesh).index(verts[-1]) + 1
    pts = [(float(v.get('x')), float(v.get('y')), float(v.get('u')), float(v.get('v'))) for v in verts]
    world = [to_world(p[0], p[1]) for p in pts]
    tris = _read_indices(mesh.get('triangleIndexBytes'))
    tris = [tuple(tris[i:i + 3]) for i in range(0, len(tris), 3)]
    added = []
    n0 = len(pts)

    def edge(a, b):
        return (a, b) if a < b else (b, a)

    depth = max(z[3] for z in zones)
    for level in range(1, depth + 1):
        live = [z for z in zones if z[3] >= level]
        count = {}
        for t in tris:
            for e in (edge(t[0], t[1]), edge(t[1], t[2]), edge(t[2], t[0])):
                count[e] = count.get(e, 0) + 1
        marked = set()
        for t in tris:
            cx = sum(world[i][0] for i in t) / 3
            cy = sum(world[i][1] for i in t) / 3
            if any(math.hypot(cx - x, cy - y) < r for x, y, r, _ in live):
                marked.update((edge(t[0], t[1]), edge(t[1], t[2]), edge(t[2], t[0])))
        # два размеченных ребра — делим треугольник на четыре
        while True:
            grown = False
            for t in tris:
                es = (edge(t[0], t[1]), edge(t[1], t[2]), edge(t[2], t[0]))
                k = sum(e in marked for e in es)
                if k == 2:
                    marked.update(es)
                    grown = True
            if not grown:
                break
        assert all(count[e] == 2 for e in marked), 'зона задела край сетки'
        mid = {}
        for a, b in sorted(marked):
            pa, pb = pts[a], pts[b]
            mid[(a, b)] = len(pts)
            pts.append(tuple((pa[i] + pb[i]) / 2 for i in range(4)))
            world.append(((world[a][0] + world[b][0]) / 2, (world[a][1] + world[b][1]) / 2))
        new = []
        for a, b, c in tris:
            ab, bc, ca = edge(a, b), edge(b, c), edge(c, a)
            m = [e in marked for e in (ab, bc, ca)]
            if all(m):
                x, y, z = mid[ab], mid[bc], mid[ca]
                new += [(a, x, z), (x, b, y), (z, y, c), (x, y, z)]
            elif m[0]:
                new += [(a, mid[ab], c), (mid[ab], b, c)]
            elif m[1]:
                new += [(a, b, mid[bc]), (a, mid[bc], c)]
            elif m[2]:
                new += [(a, b, mid[ca]), (mid[ca], b, c)]
            else:
                new.append((a, b, c))
        tris = new

    for i, (x, y, u, v) in enumerate(pts[n0:]):
        el = ET.Element('MeshVertex', {'u': f'{u:.8g}', 'v': f'{v:.8g}', 'x': f'{x:.8g}',
                                       'y': f'{y:.8g}', 'name': 'Component', 'id': next_id()})
        ET.SubElement(el, 'Weight', {'indices': '1', 'name': 'Component', 'id': next_id(),
                                     'values': '255'})
        mesh.insert(first_after + i, el)
        added.append(el)
    mesh.set('triangleIndexBytes', _write_indices([i for t in tris for i in t]))
    return len(added)
