"""Пересборка скелета мишки в RML-проекте (заказчик 26.09: «удали кости и
сделай новые, чтобы было по-живому»).

    python3 tool/rive/rebuild_rig.py <project-dir>   # или через build_bear.py

1. Старые кости → неподвижные узлы (Node) с той же позой; кости ушей и
   живота удаляются.
2. Новый скелет (мировые координаты холста 1024×1024).
3. Все сетки заново привязаны к новым костям, веса считаются по положению
   вершины.
4. Жёсткие части (глаза и накладки лица, подкладка капюшона, лапы, стопы)
   едут за костями через TransformConstraint их контейнеров — порядок
   отрисовки не меняется.
5. idle_life — новое дыхание всем телом (моргание прежнее), из остальных
   анимаций убраны ключи старых костей.
"""
import math
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from xf import M, f, world_map  # noqa: E402

UP = -math.pi / 2


def ident(n):
    return f'9:{n}'


# --- Новый скелет: (имя, родитель, старт (x, y) в мире, конец (x, y)) ------
# Цепочка корпуса идёт вверх; дети-Bone стартуют с конца родителя, остальные
# (RootBone) — в своей точке.
CHAIN = [
    # имя       родитель  начало        конец
    ('hips',    None,     (517, 812),   (517, 742)),
    ('belly',   'hips',   None,         (517, 652)),
    ('chest',   'belly',  None,         (517, 560)),
    ('neck',    'chest',  None,         (517, 530)),
    ('head',    'neck',   None,         (517, 330)),
    ('hood1',   'head',   None,         (517, 185)),
    ('hood2',   'hood1',  None,         (517, 42)),
    ('breath',  'belly',  (517, 700),   (517, 600)),
    # лицо смещается внутри капюшона — поворот головы, взгляд вверх-вниз
    ('face',    'head',   (512, 430),   (512, 370)),
    # боковины капюшона от висков вниз к плечам
    ('hood_sl', 'head',   (338, 330),   (318, 530)),
    ('hood_sr', 'head',   (696, 330),   (716, 530)),
    ('ear_l1',  'head',   (420, 322),   (388, 290)),
    ('ear_l2',  'ear_l1', None,         (340, 238)),
    ('ear_r1',  'head',   (605, 322),   (637, 290)),
    ('ear_r2',  'ear_r1', None,         (688, 236)),
    ('arm_l1',  'chest',  (383, 540),   (323, 614)),
    ('arm_l2',  'arm_l1', None,         (268, 690)),
    ('arm_r1',  'chest',  (641, 540),   (703, 612)),
    ('arm_r2',  'arm_r1', None,         (760, 688)),
    ('leg_l',   None,     (430, 790),   (430, 930)),
    ('leg_r',   None,     (607, 790),   (607, 930)),
]


def build_bones():
    """{name: dict(world M, start, end, length, parent, is_root, elem attrs)}."""
    bones = {}
    for name, parent, start, end in CHAIN:
        p = bones.get(parent)
        if start is None:
            start = p['end']
            is_root = False
        else:
            is_root = True
        ang = math.atan2(end[1] - start[1], end[0] - start[0])
        length = math.hypot(end[0] - start[0], end[1] - start[1])
        world = M.trs(start[0], start[1], ang)
        b = dict(name=name, parent=parent, start=start, end=end, angle=ang,
                 length=length, world=world, is_root=is_root, id=None)
        if p is None:
            b['local'] = dict(x=start[0], y=start[1], rotation=ang)
        elif is_root:
            lx, ly = p['world'].inv().apply(*start)
            b['local'] = dict(x=lx, y=ly, rotation=ang - p['angle'])
        else:
            b['local'] = dict(rotation=ang - p['angle'])
        bones[name] = b
    for i, name in enumerate(bones):
        bones[name]['id'] = ident(100 + i)
    return bones


def decompose(m):
    xx, xy, yx, yy, tx, ty = m.v
    rot = math.atan2(xy, xx)
    sx = math.hypot(xx, xy)
    sy = (xx * yy - xy * yx) / sx
    return dict(x=tx, y=ty, rotation=rot, scaleX=sx, scaleY=sy)


def fmt(v):
    return f'{v:.7g}'


# --- Веса -------------------------------------------------------------------
def smooth(a, b, v):
    """0 при v<=a, 1 при v>=b, гладко между."""
    if b == a:
        return 1.0 if v >= b else 0.0
    t = min(1.0, max(0.0, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)


def chain_weights(y, spans, blend=22):
    """Вертикальная цепочка: spans = [(bone, y_top)] снизу вверх; вершина выше
    y_top переходит к следующей кости с мягкой полосой blend."""
    w = {spans[0][0]: 1.0}
    for (bone, y_top), (nxt, _) in zip(spans, spans[1:]):
        k = 1 - smooth(y_top - blend, y_top + blend, y)  # 1 выше границы
        if k <= 0:
            continue
        rest = {b: v * (1 - k) for b, v in w.items()}
        rest[nxt] = rest.get(nxt, 0) + k
        w = rest
    return w


def along(p, a, b):
    """Проекция точки на отрезок a→b, 0..1."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    return ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)


def weights_for(layer, x, y, B):
    if layer in ('face_img',):
        d = math.hypot((x - 512) / 118, (y - 425) / 108)
        k = 1 - smooth(0.8, 1.22, d)
        return {'face': k, 'head': 1 - k} if k < 1 else {'face': 1.0}
    if layer in ('hood_img', 'hood_back_img'):
        # конус вверх: голова → капюшон1 → капюшон2; низ, лежащий на плечах, —
        # за грудью, чтобы не отрывался от кофты при наклоне головы.
        w = chain_weights(y, [('head', 318), ('hood1', 185), ('hood2', -1e9)], blend=58)
        side = smooth(125, 195, abs(x - 517)) * smooth(300, 370, y)
        if side > 0:
            bone = 'hood_sl' if x < 517 else 'hood_sr'
            w = {b: v * (1 - side) for b, v in w.items()}
            w[bone] = w.get(bone, 0) + side
        drape = smooth(470, 545, y) * smooth(90, 170, abs(x - 517))
        if drape > 0:
            w = {b: v * (1 - drape) for b, v in w.items()}
            w['chest'] = w.get('chest', 0) + drape
        return w
    if layer.startswith('ear_l'):
        t = along((x, y), B['ear_l1']['start'], B['ear_l2']['end'])
        return blend3(t, 'head', 'ear_l1', 'ear_l2', a=0.22, b=0.5, c=0.58, d=0.88)
    if layer.startswith('ear_r'):
        t = along((x, y), B['ear_r1']['start'], B['ear_r2']['end'])
        return blend3(t, 'head', 'ear_r1', 'ear_r2', a=0.22, b=0.5, c=0.58, d=0.88)
    if layer == 'shirt_img':
        w = chain_weights(-y, [('hips', -742), ('belly', -652), ('chest', -1e9)], blend=26)
        # дыхание: грудь-живот в середине кофты
        d = math.hypot((x - 517) / 150, (y - 640) / 120)
        k = max(0.0, 1 - d) ** 1.5 * 0.7
        if k > 0:
            w = {b: v * (1 - k) for b, v in w.items()}
            w['breath'] = w.get('breath', 0) + k
        side = smooth(120, 185, abs(x - 517)) * smooth(495, 540, y) * (1 - smooth(640, 720, y)) * 0.6
        if side > 0:
            arm = 'arm_l1' if x < 517 else 'arm_r1'
            w = {b: v * (1 - side) for b, v in w.items()}
            w[arm] = w.get(arm, 0) + side
        return w
    if layer == 'sleeve_left_img':
        t = along((x, y), B['arm_l1']['start'], B['arm_l2']['end'])
        return blend3(t, 'chest', 'arm_l1', 'arm_l2', a=0.02, b=0.18, c=0.5, d=0.75)
    if layer == 'sleeve_right_img':
        t = along((x, y), B['arm_r1']['start'], B['arm_r2']['end'])
        return blend3(t, 'chest', 'arm_r1', 'arm_r2', a=0.02, b=0.18, c=0.5, d=0.75)
    if layer == 'shorts_img':
        leg = 'leg_l' if x < 518 else 'leg_r'
        k = smooth(815, 880, y)
        return {'hips': 1 - k, leg: k} if k < 1 else {leg: 1.0}
    raise KeyError(layer)


def blend3(t, a0, a1, a2, a=0.0, b=0.2, c=0.5, d=0.8):
    """0..1 вдоль цепочки: a0 → a1 (между a и b) → a2 (между c и d)."""
    k1 = smooth(a, b, t)
    k2 = smooth(c, d, t)
    w = {a0: 1 - k1, a1: k1 * (1 - k2), a2: k1 * k2}
    return {k: v for k, v in w.items() if v > 1e-4}


def pack(w, order):
    items = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    tot = sum(v for _, v in items)
    items = [(b, v / tot) for b, v in items]
    vals = [int(round(v * 255)) for _, v in items]
    vals[0] += 255 - sum(vals)
    idx = [order.index(b) + 1 for b, _ in items]
    pv = pi = 0
    for i, (v, j) in enumerate(zip(vals, idx)):
        pv |= v << (8 * i)
        pi |= j << (8 * i)
    return pv, pi


# --- Дыхание ------------------------------------------------------------------
FPS = 60
DUR = 720          # петля 12 с
PERIOD = 180       # вдох-выдох 3,0 с (было 3,6), четыре за петлю
SWAY = 360         # покачивание головы 6 с, два за петлю


def wave(t, lag=0.0, period=PERIOD):
    """-1 в конце выдоха, +1 на вершине вдоха; запаздывание lag в кадрах."""
    ph = 2 * math.pi * ((t - lag) % period) / period
    return -math.cos(ph)


def pulse(t, a, b, ramp):
    """0 → 1 за ramp кадров от a, держит, 1 → 0 к b."""
    return smooth(a, a + ramp, t) * (1 - smooth(b - ramp, b, t))


def twitch(t, at, dur=16):
    """Быстрое вздрагивание уха: 0 → 1 → лёгкий перелёт → 0."""
    if t < at or t > at + dur * 2:
        return 0.0
    u = (t - at) / dur
    return math.sin(math.pi * min(u, 1.0)) if u <= 1 else -0.25 * math.sin(math.pi * (u - 1))


# Осмотрелся: (начало, конец, сдвиг лица по горизонтали, по вертикали, наклон)
LOOKS = [(150, 260, -1, 0, -1), (430, 540, 1, 0, 1), (600, 660, 0, 1, 0)]
EAR_TWITCH = [('l', 120), ('r', 380), ('l', 560), ('r', 566)]


def breathing(B, rest):
    """{(bone, propertyKey): [(frame, value)]}."""
    ch = {}

    def add(bone, key, fn):
        ch[(bone, key)] = [(t, fn(t)) for t in range(0, DUR + 1, 4)]

    def look(t):
        return [sum(v[i] * pulse(t, a, b, 40) for a, b, *v in LOOKS) for i in range(3)]

    def ear(t, side):
        return sum(twitch(t, at) for s_, at in EAR_TWITCH if s_ == side)

    R, SX, SY, X, Y = 15, 16, 17, 90, 91
    # корпус: заметный вдох, на выдохе присел
    add('hips', Y, lambda t: rest['hips']['y'] - 5.0 * wave(t))
    add('belly', R, lambda t: rest['belly']['rotation'] - 0.012 * wave(t, 4))
    add('breath', SY, lambda t: 1 + 0.065 * (wave(t) + 1) / 2)              # грудь шире
    add('breath', SX, lambda t: 1 + 0.04 * (wave(t, 3) + 1) / 2)
    add('chest', R, lambda t: rest['chest']['rotation'] + 0.02 * wave(t, 6))
    add('neck', R, lambda t: rest['neck']['rotation'] - 0.014 * wave(t, 10))
    # голова: вдох + медленное покачивание + наклон, когда осматривается
    add('head', R, lambda t: rest['head']['rotation'] + 0.03 * wave(t, 14)
        + 0.016 * math.sin(2 * math.pi * t / SWAY) + 0.07 * look(t)[2])
    # лицо внутри капюшона: поворот влево-вправо, взгляд вверх
    add('face', Y, lambda t: rest['face']['y'] + 13 * look(t)[0])
    add('face', X, lambda t: rest['face']['x'] + 7 * look(t)[1] + 1.2 * wave(t, 12))
    # капюшон: кончик и боковины догоняют и перелетают
    add('hood1', R, lambda t: rest['hood1']['rotation'] - 0.018 * wave(t, 22)
        - 0.015 * math.sin(2 * math.pi * (t - 30) / SWAY) - 0.015 * look(t)[2])
    add('hood2', R, lambda t: rest['hood2']['rotation'] - 0.08 * wave(t, 34)
        - 0.025 * math.sin(2 * math.pi * (t - 45) / SWAY) + 0.015 * wave(t * 2, 60)
        - 0.05 * look(t - 12)[2])
    add('hood_sl', R, lambda t: rest['hood_sl']['rotation'] + 0.03 * wave(t, 20) - 0.025 * look(t - 8)[2])
    add('hood_sr', R, lambda t: rest['hood_sr']['rotation'] - 0.03 * wave(t, 20) - 0.025 * look(t - 8)[2])
    # уши: по диагонали к капюшону и складываются к основанию; иногда вздрагивают
    add('ear_l1', R, lambda t: rest['ear_l1']['rotation'] + 0.06 * wave(t, 26) + 0.14 * ear(t, 'l'))
    add('ear_l2', R, lambda t: rest['ear_l2']['rotation'] + 0.09 * wave(t, 38) + 0.18 * ear(t - 3, 'l'))
    add('ear_l1', SX, lambda t: 1 - 0.07 * (wave(t, 30) + 1) / 2 - 0.16 * ear(t, 'l'))
    add('ear_r1', R, lambda t: rest['ear_r1']['rotation'] - 0.06 * wave(t, 26) - 0.14 * ear(t, 'r'))
    add('ear_r2', R, lambda t: rest['ear_r2']['rotation'] - 0.09 * wave(t, 38) - 0.18 * ear(t - 3, 'r'))
    add('ear_r1', SX, lambda t: 1 - 0.07 * (wave(t, 30) + 1) / 2 - 0.16 * ear(t, 'r'))
    # плечи поднимаются на вдохе, лапы отходят
    add('arm_l1', R, lambda t: rest['arm_l1']['rotation'] + 0.024 * wave(t, 8))
    add('arm_l2', R, lambda t: rest['arm_l2']['rotation'] + 0.03 * wave(t, 20))
    add('arm_r1', R, lambda t: rest['arm_r1']['rotation'] - 0.024 * wave(t, 8))
    add('arm_r2', R, lambda t: rest['arm_r2']['rotation'] - 0.03 * wave(t, 20))
    return ch


# --- Сборка -------------------------------------------------------------------
def main(project):
    path = f'{project}/scene.rml'
    tree = ET.parse(path)
    root = tree.getroot()
    ab = root.find('Artboard')
    parent = {c: p for p in root.iter() for c in p}
    W = world_map(ab)
    byname = {}
    for e in ab.iter():
        if 'name' in e.attrib:
            byname.setdefault(e.attrib['name'], e)

    B = build_bones()

    # 1. Жёсткие контейнеры: их мир в покое (до правок).
    followers = {  # контейнер → новая кость
        'head': 'face', 'hood_lining': 'head',
        'forearm_left': 'arm_l2', 'forearm_right': 'arm_r2',
        'leg_left': 'leg_l', 'leg_right': 'leg_r',
    }
    follow_world = {n: W[byname[n]] for n in followers}

    # 2. Старые кости → узлы; кости ушей и живота — удалить.
    old_bone_ids = set()
    lengths = {e: f(e, 'length') for e in ab.iter() if e.tag in ('RootBone', 'Bone')}
    for e in list(ab.iter()):
        if e.tag not in ('RootBone', 'Bone'):
            continue
        old_bone_ids.add(e.attrib['id'])
        name = e.attrib.get('name', '')
        if name.startswith('root_ear') or name == 'root_belly':
            parent[e].remove(e)
            continue
        if e.tag == 'Bone':
            e.set('x', fmt(lengths[parent[e]]))
            e.set('y', '0')
        e.tag = 'Node'
        e.attrib.pop('length', None)
    # у бывших костей длина нужна детям-Bone — таких больше нет.

    # 3. Новый скелет в начале артборда.
    elems = {}
    for name, b in B.items():
        tag = 'RootBone' if b['is_root'] else 'Bone'
        attrs = {k: fmt(v) for k, v in b['local'].items()}
        attrs.update(length=fmt(b['length']), name=f'b_{name}', id=b['id'])
        el = ET.Element(tag, attrs)
        elems[name] = el
        if b['parent'] is None:
            ab.insert(0, el)
        else:
            elems[b['parent']].append(el)

    # 4. Якоря для жёстких частей + ограничители.
    n = 300
    for cname, bname in followers.items():
        local = B[bname]['world'].inv() * follow_world[cname]
        d = decompose(local)
        anchor_id = ident(n); n += 1
        ET.SubElement(elems[bname], 'Node', {**{k: fmt(v) for k, v in d.items()},
                      'name': f'anchor_{cname}', 'id': anchor_id})
        ET.SubElement(byname[cname], 'TransformConstraint',
                      {'targetId': anchor_id, 'name': f'follow_{bname}', 'id': ident(n)})
        n += 1

    # 5. Сетки: новые сухожилия и веса.
    for img in ab.iter('Image'):
        mesh = img.find('Mesh')
        if mesh is None:
            continue
        skin = mesh.find('Skin')
        sm = M(*[f(skin, k) for k in ('xx', 'xy', 'yx', 'yy', 'tx', 'ty')])
        layer = img.attrib['name']
        verts = [v for v in mesh if v.tag in ('ContourMeshVertex', 'MeshVertex')]
        ws = []
        for v in verts:
            x, y = sm.apply(f(v, 'x'), f(v, 'y'))
            ws.append(weights_for(layer, x, y, B))
        order = sorted({b for w in ws for b in w}, key=list(B).index)
        for tn in skin.findall('Tendon'):
            skin.remove(tn)
        for bname in order:
            m = B[bname]['world'].v
            ET.SubElement(skin, 'Tendon', {'boneId': B[bname]['id'], 'xx': fmt(m[0]), 'xy': fmt(m[1]),
                                           'yx': fmt(m[2]), 'yy': fmt(m[3]), 'tx': fmt(m[4]),
                                           'ty': fmt(m[5]), 'name': bname})
        for v, w in zip(verts, ws):
            wt = v.find('Weight')
            pv, pi = pack(w, order)
            wt.set('values', str(pv))
            wt.set('indices', str(pi))

    # 6. Анимации: убрать ключи старых костей.
    for an in root.iter('LinearAnimation'):
        for ko in list(an.findall('KeyedObject')):
            if ko.attrib['objectId'] in old_bone_ids:
                an.remove(ko)

    # 7. idle_life: дыхание поверх прежнего моргания.
    idle = next(a for a in root.iter('LinearAnimation') if a.attrib.get('name') == 'idle_life')
    old_dur = int(idle.attrib['duration'])
    idle.set('duration', str(DUR))
    for kp in idle.iter('KeyedProperty'):
        seen = set()
        for k in list(kp):
            fr = round(int(k.attrib.get('frame', '0')) * DUR / old_dur)
            if fr in seen:
                kp.remove(k)
                continue
            seen.add(fr)
            k.set('frame', str(fr))
    rest = {name: dict(b['local']) for name, b in B.items()}
    for (bname, key), frames in breathing(B, rest).items():
        ko = ET.SubElement(idle, 'KeyedObject', {'objectId': B[bname]['id']})
        kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
        for fr, val in frames:
            ET.SubElement(kp, 'KeyFrameDouble', {'value': fmt(val), 'frame': str(fr),
                                                 'interpolationType': 'linear'})

    ET.indent(tree, space='    ')
    tree.write(path, encoding='unicode')
    print('bones', len(B), 'followers', len(followers))


if __name__ == '__main__':
    main(sys.argv[1])
