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
    # мимика: мех вокруг глаз, щёки, рот (дети кости лица)
    ('eye_l',   'face',   (456, 418),   (456, 388)),
    ('eye_r',   'face',   (568, 418),   (568, 388)),
    ('cheek_l', 'face',   (442, 470),   (442, 440)),
    ('cheek_r', 'face',   (584, 470),   (584, 440)),
    ('mouth',   'face',   (512, 500),   (512, 470)),
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


# Где верх уха касается конуса капюшона (по контурам слоёв). Вокруг этих
# точек и капюшон, и ухо держатся за голову, иначе стык расходится
# (заказчик 26.09 обвёл на скриншотах).
EAR_HOOD_CONTACTS = [(394, 204), (619, 205)]


def pin(w, x, y, r0=26, r1=70):
    """У стыка и капюшон, и ухо получают одинаковую привязку — наполовину
    к уху, наполовину к конусу капюшона: стык движется вместе с ними и не
    расходится (заказчик 26.09: «уголки неподвижны — сделай правильно»)."""
    d = min(math.hypot(x - px, y - py) for px, py in EAR_HOOD_CONTACTS)
    k = 1 - smooth(r0, r1, d)
    if k <= 0:
        return w
    ear = 'ear_l1' if x < 517 else 'ear_r1'
    shared = {'hood1': 0.5, ear: 0.5}
    w = {b: v * (1 - k) for b, v in w.items()}
    for b, v in shared.items():
        w[b] = w.get(b, 0) + v * k
    return w


def weights_for(layer, x, y, B):
    return pin(_weights_for(layer, x, y, B), x, y) if layer.startswith(('hood_img', 'hood_back', 'ear_')) \
        else _weights_for(layer, x, y, B)


def _weights_for(layer, x, y, B):
    if layer in ('face_img',):
        d = math.hypot((x - 512) / 118, (y - 425) / 108)
        k = 1 - smooth(0.8, 1.22, d)
        w = {'face': k, 'head': 1 - k} if k < 1 else {'face': 1.0}
        zones = [('eye_l', 456, 416, 42, 34), ('eye_r', 568, 416, 42, 34),
                 ('cheek_l', 440, 470, 50, 38), ('cheek_r', 584, 470, 50, 38),
                 ('mouth', 512, 502, 40, 24)]
        gs = {}
        for bone, cx, cy, rx, ry in zones:
            g = 1 - smooth(0.45, 1.0, math.hypot((x - cx) / rx, (y - cy) / ry))
            if g > 0:
                gs[bone] = g
        if gs:
            tot = sum(gs.values())
            share = w.get('face', 0) * min(1.0, tot)
            w['face'] = w.get('face', 0) - share
            for bone, g in gs.items():
                w[bone] = share * g / tot
        return {b: v for b, v in w.items() if v > 1e-4}
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


# --- Мимика -------------------------------------------------------------------
BEAD_L, BEAD_R = '0:112404', '0:277344'   # бусины глаз
BEAD_REST = {BEAD_L: 0.63041645, BEAD_R: 0.63351262}
FX_LOVE = '0:107294'                      # глаза-дуги + румянец
# моргания в idle_life (кадр, когда бусины сплющены сильнее всего; 12 с)
BLINKS = [63, 223, 255, 455, 588]

EI = '0.42 0 0.58 1'
EO = '0 0 0.58 1'
EIN = '0.42 0 1 1'
BACK = '0.34 1.56 0.64 1'


def blink_face(rest):
    """Мех вокруг глаз прищуривается и щёки чуть поднимаются вместе с
    морганием — веко «мягкое», а не только сплющенная бусина."""
    ch = {}
    SX, X = 16, 90   # у костей лица ось x смотрит вверх: scaleX — по высоте

    def bump(t, amp):
        return sum(amp * max(0.0, 1 - abs(t - b) / 9) ** 2 for b in BLINKS)

    for eye in ('eye_l', 'eye_r'):
        ch[(eye, SX)] = [(t, 1 - bump(t, 0.1)) for t in range(0, DUR + 1, 2)]
    for cheek in ('cheek_l', 'cheek_r'):
        ch[(cheek, X)] = [(t, rest[cheek]['x'] + bump(t, 1.6)) for t in range(0, DUR + 1, 2)]
    return ch


def smile(rest):
    """Улыбка всем телом, 1,8 с: замах → щёки вверх, рот шире, глаза
    прищуриваются, под это проявляются глаза-дуги с румянцем; голова
    наклоняется с пружинкой, кончик капюшона догоняет, уши приподнимаются.
    Возврат такой же мягкий. {(bone или id, key): [(кадр, значение, кривая)]}"""
    R, SX, SY, X, Y, OP = 15, 16, 17, 90, 91, 18
    r = rest
    ch = {
        (BEAD_L, SY): [(0, BEAD_REST[BEAD_L], EIN), (10, 0.3, EO), (16, 0.02, None),
                       (90, 0.02, EO), (100, BEAD_REST[BEAD_L], None)],
        (BEAD_R, SY): [(0, BEAD_REST[BEAD_R], EIN), (10, 0.3, EO), (16, 0.02, None),
                       (90, 0.02, EO), (100, BEAD_REST[BEAD_R], None)],
        (BEAD_L, OP): [(0, 1, None), (16, 0, None), (90, 1, None)],
        (BEAD_R, OP): [(0, 1, None), (16, 0, None), (90, 1, None)],
        (FX_LOVE, OP): [(0, 0, None), (11, 0, EI), (22, 1, None), (84, 1, EI), (96, 0, None)],
        ('eye_l', SX): [(0, 1, EI), (6, 1.04, EI), (20, 0.84, EI), (88, 0.87, EI), (102, 1, None)],
        ('eye_r', SX): [(0, 1, EI), (6, 1.04, EI), (20, 0.84, EI), (88, 0.87, EI), (102, 1, None)],
        ('cheek_l', X): [(0, r['cheek_l']['x'], EI), (6, r['cheek_l']['x'] - 1, BACK),
                         (24, r['cheek_l']['x'] + 6, EI), (60, r['cheek_l']['x'] + 5, EI),
                         (88, r['cheek_l']['x'] + 6, EI), (104, r['cheek_l']['x'], None)],
        ('cheek_r', X): [(0, r['cheek_r']['x'], EI), (6, r['cheek_r']['x'] - 1, BACK),
                         (24, r['cheek_r']['x'] + 6, EI), (60, r['cheek_r']['x'] + 5, EI),
                         (88, r['cheek_r']['x'] + 6, EI), (104, r['cheek_r']['x'], None)],
        ('cheek_l', SY): [(0, 1, EI), (24, 1.06, EI), (88, 1.05, EI), (104, 1, None)],
        ('cheek_r', SY): [(0, 1, EI), (24, 1.06, EI), (88, 1.05, EI), (104, 1, None)],
        ('mouth', SY): [(0, 1, EI), (22, 1.1, EI), (88, 1.09, EI), (104, 1, None)],
        ('mouth', X): [(0, r['mouth']['x'], EI), (22, r['mouth']['x'] + 2.5, EI),
                       (88, r['mouth']['x'] + 2, EI), (104, r['mouth']['x'], None)],
        ('head', R): [(0, r['head']['rotation'], EI), (8, r['head']['rotation'] - 0.015, BACK),
                      (28, r['head']['rotation'] + 0.07, EI), (70, r['head']['rotation'] + 0.055, EI),
                      (104, r['head']['rotation'], None)],
        ('face', Y): [(0, r['face']['y'], EI), (28, r['face']['y'] + 4, EI), (80, r['face']['y'] + 3, EI),
                      (104, r['face']['y'], None)],
        ('face', X): [(0, r['face']['x'], EI), (28, r['face']['x'] + 3, EI), (80, r['face']['x'] + 2, EI),
                      (104, r['face']['x'], None)],
        ('hood2', R): [(0, r['hood2']['rotation'], EI), (16, r['hood2']['rotation'], EI),
                       (36, r['hood2']['rotation'] - 0.09, EI), (60, r['hood2']['rotation'] + 0.035, EI),
                       (82, r['hood2']['rotation'] - 0.02, EI), (106, r['hood2']['rotation'], None)],
        ('hood1', R): [(0, r['hood1']['rotation'], EI), (30, r['hood1']['rotation'] - 0.03, EI),
                       (64, r['hood1']['rotation'] + 0.01, EI), (104, r['hood1']['rotation'], None)],
        ('ear_l1', R): [(0, r['ear_l1']['rotation'], EI), (18, r['ear_l1']['rotation'] - 0.1, EO),
                        (40, r['ear_l1']['rotation'] + 0.03, EI), (70, r['ear_l1']['rotation'] - 0.02, EI),
                        (104, r['ear_l1']['rotation'], None)],
        ('ear_r1', R): [(0, r['ear_r1']['rotation'], EI), (20, r['ear_r1']['rotation'] + 0.1, EO),
                        (42, r['ear_r1']['rotation'] - 0.03, EI), (72, r['ear_r1']['rotation'] + 0.02, EI),
                        (104, r['ear_r1']['rotation'], None)],
        ('ear_l2', R): [(0, r['ear_l2']['rotation'], EI), (24, r['ear_l2']['rotation'] - 0.12, EO),
                        (48, r['ear_l2']['rotation'] + 0.05, EI), (104, r['ear_l2']['rotation'], None)],
        ('ear_r2', R): [(0, r['ear_r2']['rotation'], EI), (26, r['ear_r2']['rotation'] + 0.12, EO),
                        (50, r['ear_r2']['rotation'] - 0.05, EI), (104, r['ear_r2']['rotation'], None)],
    }
    return 108, ch


# Накладки лица (исходник): у каких есть свои глаза — бусины тогда прячем.
FX = {'laugh': '0:107284', 'surprised': '0:107320', 'sad': '0:107303', 'chew': '0:107276',
      'lick': '0:107291', 'yawn': '0:107334', 'eyes_closed': '0:107279', 'upset': '0:107327'}
FX_WITH_EYES = {'laugh', 'surprised', 'sad', 'yawn', 'eyes_closed', 'upset'}


class Emo:
    """Сборщик одной эмоции: ключи — смещения от покоя."""
    R, SX, SY, X, Y, OP = 15, 16, 17, 90, 91, 18

    def __init__(self, rest, dur):
        self.rest, self.dur, self.ch = rest, dur, {}

    def base(self, bone, key):
        r = self.rest[bone]
        return {15: r.get('rotation', 0), 90: r.get('x', 0), 91: r.get('y', 0)}.get(key, 1.0)

    def track(self, bone, key, pts):
        """pts: [(кадр, смещение[, кривая])]; начало и конец — покой."""
        b = self.base(bone, key)
        frames = [(0, b, EI)]
        for p in pts:
            fr, off = p[0], p[1]
            ease = p[2] if len(p) > 2 else EI
            frames.append((fr, b + off, ease))
        frames.append((self.dur - 2, b, None))
        self.ch[(bone, key)] = frames

    def face(self, fx, a, b, c, d, hide_beads=None):
        """Накладка: проявляется a→b, держится, уходит c→d."""
        self.ch[(FX[fx], self.OP)] = [(0, 0, None), (a, 0, EI), (b, 1, None), (c, 1, EI), (d, 0, None)]
        if hide_beads is None:
            hide_beads = fx in FX_WITH_EYES
        if hide_beads:
            for bead, rest_v in BEAD_REST.items():
                self.ch[(bead, self.SY)] = [(0, rest_v, EIN), (a, rest_v * 0.5, EO), (b, 0.02, None),
                                            (c, 0.02, EO), (d + 4, rest_v, None)]
                self.ch[(bead, self.OP)] = [(0, 1, None), (b, 0, None), (c + 2, 1, None)]
        return self

    def build(self):
        return self.dur, self.ch


def emo_laugh(rest):
    e = Emo(rest, 96)
    e.face('laugh', 4, 12, 78, 90)
    for c in ('cheek_l', 'cheek_r'):
        e.track(c, Emo.X, [(14, 7), (40, 5), (58, 7), (84, 6)])
        e.track(c, Emo.SY, [(14, 0.07), (84, 0.06)])
    e.track('mouth', Emo.SY, [(12, 0.12), (84, 0.1)])
    e.track('mouth', Emo.X, [(12, 3), (84, 2)])
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(12, -0.18), (84, -0.16)])
    # два мягких подскока «хи-хи»
    e.track('hips', Emo.Y, [(6, 2, EO), (18, -7, EIN), (30, 0, EO), (40, -5, EIN), (52, 0, EO), (70, -1)])
    e.track('head', Emo.R, [(8, 0.02), (22, -0.05, BACK), (46, 0.03), (70, -0.02)])
    e.track('face', Emo.X, [(22, 4), (70, 2)])
    e.track('breath', Emo.SY, [(18, 0.05), (40, 0.02), (58, 0.05)])
    e.track('hood2', Emo.R, [(24, 0.08), (42, -0.06), (60, 0.05), (78, -0.02)])
    e.track('hood1', Emo.R, [(24, 0.03), (48, -0.02)])
    e.track('ear_l1', Emo.R, [(16, -0.12, EO), (36, 0.04), (56, -0.06)])
    e.track('ear_r1', Emo.R, [(18, 0.12, EO), (38, -0.04), (58, 0.06)])
    e.track('arm_l1', Emo.R, [(18, 0.05), (60, 0.03)])
    e.track('arm_r1', Emo.R, [(18, -0.05), (60, -0.03)])
    return e.build()


def emo_surprised(rest):
    e = Emo(rest, 90)
    e.face('surprised', 2, 8, 70, 82)
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(4, -0.05, EO), (12, 0.14, BACK), (70, 0.12)])
        e.track(eye, Emo.SY, [(12, 0.08, BACK), (70, 0.06)])
    e.track('mouth', Emo.SX, [(10, 0.12, BACK), (70, 0.1)])
    e.track('mouth', Emo.SY, [(10, -0.06), (70, -0.05)])
    for c in ('cheek_l', 'cheek_r'):
        e.track(c, Emo.X, [(10, -2), (70, -2)])
    e.track('hips', Emo.Y, [(5, 3, EO), (14, -10, BACK), (30, -4), (60, -3)])
    e.track('head', Emo.R, [(12, -0.04, BACK), (60, -0.03)])
    e.track('face', Emo.X, [(12, 6, BACK), (66, 4)])
    e.track('breath', Emo.SY, [(12, 0.07), (64, 0.05)])
    e.track('hood2', Emo.R, [(16, 0.1), (32, -0.07), (50, 0.03)])
    e.track('hood1', Emo.R, [(16, 0.035), (36, -0.02)])
    for side, sgn in (('l', 1), ('r', -1)):
        e.track(f'ear_{side}1', Emo.R, [(10, -0.14 * sgn, BACK), (66, -0.1 * sgn)])
        e.track(f'ear_{side}1', Emo.SX, [(10, 0.08, BACK), (66, 0.06)])
        e.track(f'ear_{side}2', Emo.R, [(14, -0.12 * sgn, BACK), (66, -0.08 * sgn)])
    e.track('arm_l1', Emo.R, [(12, 0.08, BACK), (64, 0.06)])
    e.track('arm_r1', Emo.R, [(12, -0.08, BACK), (64, -0.06)])
    return e.build()


def emo_sad(rest):
    e = Emo(rest, 132)
    e.face('sad', 10, 30, 104, 122)
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(30, -0.06), (104, -0.05)])
    e.track('mouth', Emo.X, [(30, -2), (104, -2)])
    for c in ('cheek_l', 'cheek_r'):
        e.track(c, Emo.X, [(30, -3), (104, -2)])
    e.track('hips', Emo.Y, [(40, 4), (104, 3)])
    e.track('breath', Emo.SY, [(40, -0.03), (104, -0.02)])
    e.track('chest', Emo.R, [(40, -0.02), (104, -0.015)])
    e.track('head', Emo.R, [(40, 0.05), (80, 0.045), (104, 0.05)])
    e.track('face', Emo.X, [(40, -6), (104, -5)])
    e.track('hood2', Emo.R, [(50, 0.07), (104, 0.06)])
    e.track('hood1', Emo.R, [(46, 0.02), (104, 0.02)])
    for side, sgn in (('l', 1), ('r', -1)):
        e.track(f'ear_{side}1', Emo.R, [(40, 0.14 * sgn), (104, 0.12 * sgn)])
        e.track(f'ear_{side}1', Emo.SX, [(40, -0.1), (104, -0.08)])
        e.track(f'ear_{side}2', Emo.R, [(48, 0.12 * sgn), (104, 0.1 * sgn)])
    e.track('arm_l1', Emo.R, [(40, -0.03), (104, -0.025)])
    e.track('arm_r1', Emo.R, [(40, 0.03), (104, 0.025)])
    return e.build()


def emo_chew(rest):
    e = Emo(rest, 96)
    e.face('chew', 4, 12, 80, 90)
    # челюсть: три жевка, щёки раздуваются по очереди
    e.track('mouth', Emo.X, [(12, -3), (22, 1), (32, -3), (42, 1), (52, -3), (62, 1), (72, -2)])
    e.track('mouth', Emo.SY, [(12, 0.06), (22, 0.02), (32, 0.06), (42, 0.02), (52, 0.06), (72, 0.03)])
    e.track('cheek_l', Emo.SY, [(14, 0.08), (24, 0.02), (34, 0.03), (44, 0.08), (54, 0.02), (74, 0.04)])
    e.track('cheek_r', Emo.SY, [(14, 0.02), (24, 0.08), (34, 0.02), (44, 0.03), (54, 0.08), (74, 0.03)])
    e.track('head', Emo.R, [(12, 0.01), (22, -0.012), (32, 0.012), (42, -0.012), (52, 0.012), (70, 0)])
    e.track('face', Emo.X, [(12, -1.5), (22, 1), (32, -1.5), (42, 1), (52, -1.5), (70, 0)])
    e.track('hood2', Emo.R, [(20, 0.02), (40, -0.02), (60, 0.015)])
    e.track('ear_l1', Emo.R, [(22, -0.03), (42, 0.02), (62, -0.02)])
    e.track('ear_r1', Emo.R, [(24, 0.03), (44, -0.02), (64, 0.02)])
    return e.build()


def emo_lick(rest):
    e = Emo(rest, 84)
    e.face('lick', 4, 12, 66, 76)
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(12, -0.08), (66, -0.06)])
    e.track('mouth', Emo.SY, [(12, 0.06), (40, 0.08), (66, 0.05)])
    e.track('cheek_l', Emo.X, [(14, 3), (66, 2)])
    e.track('cheek_r', Emo.X, [(14, 4), (66, 3)])
    e.track('head', Emo.R, [(16, 0.05, BACK), (50, 0.04), (66, 0.045)])
    e.track('face', Emo.Y, [(16, 3), (66, 2)])
    e.track('hood2', Emo.R, [(24, -0.05), (44, 0.03), (62, -0.01)])
    e.track('ear_r1', Emo.R, [(18, 0.06), (40, -0.02)])
    e.track('ear_l1', Emo.R, [(20, -0.04), (42, 0.02)])
    return e.build()


def emo_yawn(rest):
    e = Emo(rest, 120)
    e.face('yawn', 14, 30, 86, 102)
    # рот не растягиваем: нарисованный зевок не тянется, края бы разошлись
    e.track('mouth', Emo.X, [(30, -1), (86, -1)])
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(30, -0.14), (86, -0.12)])
    for c in ('cheek_l', 'cheek_r'):
        e.track(c, Emo.X, [(30, 3), (86, 2)])
    # потягивается: грудь набирает воздух, голова назад, лапы в стороны
    e.track('breath', Emo.SY, [(30, 0.09), (70, 0.08), (96, 0)])
    e.track('breath', Emo.SX, [(30, 0.05), (70, 0.04)])
    e.track('hips', Emo.Y, [(30, -5), (70, -4), (96, 2)])
    e.track('chest', Emo.R, [(30, 0.02), (80, 0.015)])
    e.track('head', Emo.R, [(30, -0.05), (80, -0.04), (100, 0.01)])
    e.track('face', Emo.X, [(30, 5), (80, 4)])
    e.track('arm_l1', Emo.R, [(34, 0.1), (80, 0.08)])
    e.track('arm_r1', Emo.R, [(34, -0.1), (80, -0.08)])
    e.track('arm_l2', Emo.R, [(40, 0.08), (80, 0.06)])
    e.track('arm_r2', Emo.R, [(40, -0.08), (80, -0.06)])
    e.track('hood2', Emo.R, [(40, 0.07), (70, 0.05), (96, -0.04)])
    for side, sgn in (('l', 1), ('r', -1)):
        e.track(f'ear_{side}1', Emo.R, [(34, 0.1 * sgn), (80, 0.08 * sgn)])
        e.track(f'ear_{side}1', Emo.SX, [(34, -0.12), (80, -0.1)])
    return e.build()


def emo_sleepy(rest):
    e = Emo(rest, 132)
    # глаза медленно закрываются, голова клюёт, потом просыпается
    e.face('eyes_closed', 20, 50, 92, 104)
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(50, -0.12), (92, -0.1), (106, 0.03)])
    e.track('head', Emo.R, [(50, 0.04), (80, 0.07), (92, 0.075), (100, -0.01, BACK)])
    e.track('face', Emo.X, [(50, -3), (92, -5), (102, 2)])
    e.track('hips', Emo.Y, [(60, 3), (92, 3), (102, -2)])
    e.track('breath', Emo.SY, [(50, -0.02), (92, -0.02)])
    e.track('hood2', Emo.R, [(64, 0.07), (96, 0.08), (110, -0.04)])
    for side, sgn in (('l', 1), ('r', -1)):
        e.track(f'ear_{side}1', Emo.R, [(56, 0.1 * sgn), (92, 0.12 * sgn), (104, -0.04 * sgn)])
        e.track(f'ear_{side}1', Emo.SX, [(56, -0.08), (92, -0.1)])
    return e.build()


def emo_upset(rest):
    e = Emo(rest, 90)
    e.face('upset', 4, 12, 70, 82)
    for eye in ('eye_l', 'eye_r'):
        e.track(eye, Emo.SX, [(12, -0.2), (70, -0.18)])
        e.track(eye, Emo.SY, [(12, -0.06), (70, -0.05)])
    for c in ('cheek_l', 'cheek_r'):
        e.track(c, Emo.X, [(12, 4), (70, 3)])
    e.track('mouth', Emo.SY, [(12, -0.06), (70, -0.05)])
    # сжался: присел, плечи вверх, уши прижаты
    e.track('hips', Emo.Y, [(12, 5), (70, 4)])
    e.track('breath', Emo.SY, [(12, -0.03), (70, -0.02)])
    e.track('head', Emo.R, [(12, 0.015), (40, -0.015), (70, 0)])
    e.track('face', Emo.X, [(12, -3), (70, -2)])
    e.track('arm_l1', Emo.R, [(12, -0.05), (70, -0.04)])
    e.track('arm_r1', Emo.R, [(12, 0.05), (70, 0.04)])
    e.track('hood2', Emo.R, [(18, -0.05), (36, 0.03), (56, -0.01)])
    for side, sgn in (('l', 1), ('r', -1)):
        e.track(f'ear_{side}1', Emo.R, [(12, 0.12 * sgn), (70, 0.1 * sgn)])
        e.track(f'ear_{side}1', Emo.SX, [(12, -0.14), (70, -0.12)])
    return e.build()


EMOTION_ANIMS = {
    'emo_laugh': emo_laugh, 'emo_surprised': emo_surprised, 'emo_sad': emo_sad,
    'emo_chew': emo_chew, 'emo_lick': emo_lick, 'emo_yawn': emo_yawn,
    'emo_sleepy': emo_sleepy, 'emo_upset': emo_upset,
}


def cubic_key(parent, frame, value, ease):
    if ease is None:
        ET.SubElement(parent, 'KeyFrameDouble', {'value': fmt(value), 'frame': str(frame),
                                                 'interpolationType': 'hold'})
        return
    k = ET.SubElement(parent, 'KeyFrameDouble', {'value': fmt(value), 'frame': str(frame),
                                                 'interpolationType': 'cubic'})
    x1, y1, x2, y2 = ease.split()
    ET.SubElement(k, 'CubicEaseInterpolator', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2})


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
    for (bname, key), frames in {**breathing(B, rest), **blink_face(rest)}.items():
        ko = ET.SubElement(idle, 'KeyedObject', {'objectId': B[bname]['id']})
        kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
        for fr, val in frames:
            ET.SubElement(kp, 'KeyFrameDouble', {'value': fmt(val), 'frame': str(fr),
                                                 'interpolationType': 'linear'})

    # 8. Эмоции на новых костях: emo_smile заново, остальные — новые.
    anims = {a.attrib.get('name'): a for a in root.iter('LinearAnimation')}
    builders = {'emo_smile': smile, **EMOTION_ANIMS}
    for name, fn in builders.items():
        emo = anims.get(name)
        if emo is None:
            emo = ET.Element('LinearAnimation', {'duration': '1', 'loopValue': '0', 'name': name})
            ab.insert(list(ab).index(anims['idle_life']), emo)
        for ko in list(emo.findall('KeyedObject')):
            emo.remove(ko)
        dur, ch = fn(rest)
        emo.set('duration', str(dur))
        for (target, key), frames in ch.items():
            oid = B[target]['id'] if target in B else target
            ko = ET.SubElement(emo, 'KeyedObject', {'objectId': oid})
            kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
            for fr, val, ease in frames:
                cubic_key(kp, fr, val, ease)

    ET.indent(tree, space='    ')
    tree.write(path, encoding='unicode')
    print('bones', len(B), 'followers', len(followers))


if __name__ == '__main__':
    main(sys.argv[1])
