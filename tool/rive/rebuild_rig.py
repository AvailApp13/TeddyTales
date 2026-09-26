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
import mesh_refine  # noqa: E402
import lids  # noqa: E402
import faces  # noqa: E402

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
    ('mouth',   'face',   (514, 504),   (514, 494)),
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
    # мимика тоньше (26.09, «живые эмоции»): уголки рта, подбородок, нос,
    # нижние веки, брови — в конце списка, чтобы id прежних костей не менялись
    ('mouth_l', 'face',   (502, 510),   (502, 500)),
    ('mouth_r', 'face',   (525, 512),   (525, 502)),
    ('chin',    'face',   (513, 523),   (513, 513)),
    ('muzzle',  'face',   (513, 468),   (513, 458)),
    ('lid_l',   'face',   (457, 441),   (457, 431)),
    ('lid_r',   'face',   (568, 441),   (568, 431)),
    ('brow_l',  'face',   (457, 379),   (457, 369)),
    ('brow_r',  'face',   (568, 379),   (568, 369)),
    ('ulid_l',  'face',   (457, 392),   (457, 382)),
    ('ulid_r',  'face',   (568, 392),   (568, 382)),
    # колени (26.09, топот в «Обиде»): голень от колена под шортами до
    # пятки; ступня держится за голень. Корневая кость внутри бедра — её
    # можно поднять целиком, спереди это читается как согнутое колено.
    ('shin_l',  'leg_l',  (430, 872),   (430, 952)),
    ('shin_r',  'leg_r',  (607, 872),   (607, 952)),
]

# Кость эмоции: у каждой кости родитель нулевой длины `e_<имя>` в той же
# точке. Покой (`idle_life`) двигает саму кость, эмоции — только `e_*`,
# и одно складывается с другим: во время улыбки мишка продолжает дышать,
# моргать и шевелить ушами (заказчик 26.09: эмоция не должна отличаться
# от покоя). У костей, которые покой сдвигает (x, y), кость эмоции без
# поворота — оси сдвига остаются прежними.
TRANSLATED = {'hips', 'face', 'cheek_l', 'cheek_r'}
E_REST = {}   # имя → поза покоя кости эмоции (заполняет main)
E_IDS = {}    # имя → id кости эмоции / обёртки

# Обёртки бусин и глазниц (id картинок из исходника)
WRAPS = {'bead_l': '0:112404', 'bead_r': '0:277344',
         'sock_l': '0:277340', 'sock_r': '0:277342'}
WRAP_IDS = {k: ident(260 + i) for i, k in enumerate(WRAPS)}

# Где сгущать сетку лица: (x, y, радиус, во сколько приёмов)
FACE_REFINE = [(514, 508, 18, 2), (513, 522, 11, 1), (513, 470, 30, 1),
               (457, 441, 26, 1), (568, 441, 26, 1), (457, 391, 26, 1), (568, 391, 26, 1)]


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


def pin(w, layer, x, y, r0=4, r1=62):
    """Стык уха с капюшоном: капюшон за ухом не ходит совсем, а кончик уха у
    стыка держится за конус капюшона. Ухо двигается, уголок остаётся
    прижат к капюшону и дышит вместе с ним. Раньше стык был общим на
    радиус ~60 px, и за ухом ходил большой кусок капюшона (заказчик
    26.09: «нужно короткое соединение»)."""
    if not layer.startswith('ear_'):
        return w
    d = min(math.hypot(x - px, y - py) for px, py in EAR_HOOD_CONTACTS)
    k = 1 - smooth(r0, r1, d)
    if k <= 0:
        return w
    w = {b: v * (1 - k) for b, v in w.items()}
    w['hood1'] = w.get('hood1', 0) + k
    return w


def weights_for(layer, x, y, B):
    return pin(_weights_for(layer, x, y, B), layer, x, y) if layer.startswith(('hood_img', 'hood_back', 'ear_')) \
        else _weights_for(layer, x, y, B)


def _weights_for(layer, x, y, B):
    if layer in ('face_img', 'lid_patch_img') or layer.startswith('face_'):
        d = math.hypot((x - 512) / 118, (y - 425) / 108)
        k = 1 - smooth(0.8, 1.22, d)
        w = {'face': k, 'head': 1 - k} if k < 1 else {'face': 1.0}
        zones = [('eye_l', 456, 416, 42, 34), ('eye_r', 568, 416, 42, 34),
                 ('cheek_l', 440, 470, 50, 38), ('cheek_r', 584, 470, 50, 38),
                 ('brow_l', 457, 377, 42, 12), ('brow_r', 568, 377, 42, 12),
                 ('ulid_l', 457, 392, 34, 10), ('ulid_r', 568, 392, 34, 10),
                 ('lid_l', 457, 443, 34, 13), ('lid_r', 568, 443, 34, 13),
                 ('muzzle', 513, 470, 34, 26),
                 ('mouth', 514, 504, 11, 8),
                 ('mouth_l', 501, 511, 11, 10), ('mouth_r', 526, 513, 11, 10),
                 ('chin', 513, 523, 32, 12)]
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
        side = 'l' if x < 518 else 'r'
        k = smooth(815, 880, y)          # таз → бедро
        s = smooth(840, 908, y)          # бедро → голень: низ штанины за коленом
        w = {'hips': 1 - k, f'leg_{side}': k * (1 - s), f'shin_{side}': k * s}
        return {b: v for b, v in w.items() if v > 1e-4}
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
    add('ear_l1', R, lambda t: rest['ear_l1']['rotation'] + 0.06 * wave(t, 26) + 0.07 * ear(t, 'l'))
    add('ear_l2', R, lambda t: rest['ear_l2']['rotation'] + 0.09 * wave(t, 38) + 0.12 * ear(t - 3, 'l'))
    add('ear_l1', SX, lambda t: 1 - 0.07 * (wave(t, 30) + 1) / 2 - 0.06 * ear(t, 'l'))
    add('ear_r1', R, lambda t: rest['ear_r1']['rotation'] - 0.06 * wave(t, 26) - 0.07 * ear(t, 'r'))
    add('ear_r2', R, lambda t: rest['ear_r2']['rotation'] - 0.09 * wave(t, 38) - 0.12 * ear(t - 3, 'r'))
    add('ear_r1', SX, lambda t: 1 - 0.07 * (wave(t, 30) + 1) / 2 - 0.06 * ear(t, 'r'))
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


# --- Эмоции -------------------------------------------------------------------
# Заказчик 26.09: «мимика должна отрабатывать себя, как на живом человеке».
# Лицо меняется целиком — глаза, брови, щёки и рот вместе (faces.py, фото-
# выражения Higgsfield); смена мгновенная и спрятана за морганием, плавных
# проявлений нет (от них были «полоски старого рта»). Кости эмоции `e_*`
# дают движение: голова, тело, уши, капюшон, подбородок и щёки в такт;
# всё складывается с покоем — дыхание и уши не замирают.

BEAD_H = 17   # половина видимой высоты бусины, px мира


class Emo:
    """Сборщик одной эмоции: ключи — смещения от покоя кости эмоции."""
    R, SX, SY, X, Y, OP = 15, 16, 17, 90, 91, 18

    def __init__(self, dur):
        self.dur, self.ch = dur, {}

    def track(self, name, key, pts):
        """pts: [(кадр, смещение[, кривая])]; начало и конец — покой."""
        r = E_REST[name]
        b = {15: r.get('rotation', 0.0), 90: r.get('x', 0.0), 91: r.get('y', 0.0)}.get(key, 1.0)
        frames = [(0, b, EI)]
        for p in pts:
            frames.append((p[0], b + p[1], p[2] if len(p) > 2 else EI))
        frames.append((self.dur - 2, b, None))
        self.ch[(E_IDS[name], key)] = frames
        return self

    def face(self, name, spans):
        """Выражение из `faces.py`: spans [(с кадра, по кадр)] — видно
        целиком, включается и гаснет мгновенно (ключи hold)."""
        frames = [(0, 0.0, None)]
        for on, off in spans:
            frames += [(on, 1.0, None), (off, 0.0, None)]
        self.ch[(E_IDS[f'face_{name}'], self.OP)] = frames
        return self

    def blinks(self, at, n=6):
        """Моргания (веки сомкнуты n кадров): под ними меняется лицо, и
        смена выражения не видна глазу — как у живого."""
        return self.face('blink', [(a, a + n) for a in at])

    def pair(self, name, key, pts, mirror=False):
        """Левая и правая кость; mirror — у правой знак обратный."""
        self.track(f'{name}_l', key, pts)
        self.track(f'{name}_r', key, [(p[0], -p[1] if mirror else p[1], *p[2:]) for p in pts])
        return self

    def eyes(self, pts, lid='low'):
        """Бусины: pts [(кадр, доля)] — прищур. lid='low' — поднимается
        нижнее веко (улыбка), 'top' — опускается верхнее (грусть, сон),
        'both' — зажмурился, 'wide' — глаза шире."""
        for side in ('l', 'r'):
            name = f'bead_{side}'
            if lid == 'wide':
                self.track(name, self.SX, pts)
                self.track(name, self.SY, pts)
                continue
            self.track(name, self.SY, [(p[0], -p[1], *p[2:]) for p in pts])
            shift = {'low': -BEAD_H, 'top': BEAD_H, 'both': 0}[lid]
            if shift:
                self.track(name, self.Y, [(p[0], shift * p[1], *p[2:]) for p in pts])
            # почти закрыт — бусина тает, остаётся веко (иначе чёрная черта)
            if any(p[1] > 0.8 for p in pts):
                self.track(name, self.OP, [(p[0], min(1.0, max(0.0, (0.9 - p[1]) / 0.12)) - 1, *p[2:]) for p in pts])
        return self

    def build(self):
        return self.dur, self.ch


def pulses(at, up, down, peak, low=0.0, ease_up=EO, ease_down=EI):
    """Ритм: в кадрах at пик peak через up кадров, спад к low через down."""
    pts = []
    for a in at:
        pts += [(a + up, peak, ease_up), (a + up + down, low, ease_down)]
    return pts


def emo_smile():
    """Улыбка, 2,5 с: моргнул — и уже улыбается всем лицом (щёки
    подпирают глаза, рот приоткрыт); голова наклоняется с пружинкой,
    тело приподнимается, уши и кончик капюшона догоняют. Моргнул — покой."""
    e = Emo(150)
    e.face('smile', [(12, 120)]).blinks([10, 118])
    e.pair('cheek', Emo.X, [(12, 1.5, EO), (104, 1.2)])
    e.track('head', Emo.R, [(8, -0.012), (40, 0.06, BACK), (80, 0.045), (104, 0.055)])
    e.track('face', Emo.X, [(40, 2), (104, 1.5)])
    e.track('face', Emo.Y, [(40, 3), (104, 2.5)])
    e.track('hips', Emo.Y, [(8, 2, EO), (32, -4), (104, -3)])
    e.track('breath', Emo.SY, [(8, 0.02), (38, 0.035), (104, 0.03)])
    e.track('hood2', Emo.R, [(22, 0), (46, -0.08), (72, 0.03), (96, -0.015)])
    e.track('hood1', Emo.R, [(40, -0.025), (76, 0.008)])
    e.track('ear_l1', Emo.R, [(18, -0.09, EO), (44, 0.03), (74, -0.03)])
    e.track('ear_r1', Emo.R, [(20, 0.09, EO), (46, -0.03), (76, 0.03)])
    e.track('ear_l2', Emo.R, [(24, -0.1, EO), (50, 0.04), (78, -0.02)])
    e.track('ear_r2', Emo.R, [(26, 0.1, EO), (52, -0.04), (80, 0.02)])
    e.track('arm_l1', Emo.R, [(40, 0.03), (104, 0.025)])
    e.track('arm_r1', Emo.R, [(40, -0.03), (104, -0.025)])
    return e.build()


def emo_laugh():
    """Смех, 2,8 с: зажмурился дугами, щёки круглые — и пять «ха-ха»:
    на каждом рот распахивается во всю ширь, между ними — поменьше;
    грудь, плечи и голова вздрагивают вместе, уши подпрыгивают следом."""
    e = Emo(168)
    g = [36, 54, 72, 90, 108]
    e.face('laugh', [(10, 146)]).blinks([8, 144])
    # между «ха» рот поменьше; на пике «ха» (a+2…a+12) — во всю ширь
    small = [(10, g[0] + 2)] + [(a + 12, b + 2) for a, b in zip(g, g[1:])] + [(g[-1] + 12, 146)]
    e.face('laugh2', small)
    e.track('chin', Emo.X, pulses(g, 6, 12, -1.2, 0.0))
    e.pair('cheek', Emo.X, pulses(g, 6, 12, 1.2, 0.2))
    e.track('breath', Emo.SY, [(20, 0.03)] + pulses(g, 5, 13, 0.05, 0.015) + [(140, 0.02)])
    e.track('chest', Emo.R, pulses(g, 5, 13, -0.015, 0.0))
    e.track('head', Emo.R, [(28, 0.05, BACK)] + pulses(g, 6, 12, 0.03, 0.05) + [(140, 0.045)])
    e.track('face', Emo.X, [(30, 2.5)] + pulses(g, 6, 12, 3.5, 2.2) + [(140, 2)])
    e.track('face', Emo.Y, [(30, 3), (140, 2.5)])
    e.track('hips', Emo.Y, [(8, 2, EO), (26, -3)] + pulses(g, 5, 13, -5, -2.5) + [(140, -2)])
    e.track('arm_l1', Emo.R, [(26, 0.02)] + pulses(g, 5, 13, 0.045, 0.02) + [(140, 0.02)])
    e.track('arm_r1', Emo.R, [(26, -0.02)] + pulses(g, 5, 13, -0.045, -0.02) + [(140, -0.02)])
    e.track('hood2', Emo.R, [(30, -0.06)] + pulses([a + 4 for a in g], 6, 12, -0.09, -0.04) + [(140, -0.02)])
    e.track('ear_l1', Emo.R, [(18, -0.08, EO)] + pulses([a + 3 for a in g], 6, 12, -0.1, -0.05))
    e.track('ear_r1', Emo.R, [(20, 0.08, EO)] + pulses([a + 3 for a in g], 6, 12, 0.1, 0.05))
    e.track('ear_l2', Emo.R, pulses([a + 6 for a in g], 6, 12, -0.08, -0.02))
    e.track('ear_r2', Emo.R, pulses([a + 6 for a in g], 6, 12, 0.08, 0.02))
    return e.build()


def emo_surprised():
    """Удивление, 2,2 с: короткое моргание — и глаза круглые, брови
    вверх, ротик «о»; мишка подпрыгивает и вытягивается, уши торчком,
    капюшон вздрагивает."""
    e = Emo(132)
    e.face('surprised', [(6, 108)]).blinks([3, 106])
    e.track('face', Emo.X, [(20, 5, BACK), (96, 3.5)])
    e.track('head', Emo.R, [(20, -0.035, BACK), (96, -0.025)])
    e.track('hips', Emo.Y, [(4, 3, EO), (18, -9, BACK), (40, -5), (96, -4)])
    e.track('breath', Emo.SY, [(18, 0.06), (96, 0.04)])
    e.track('chest', Emo.R, [(18, -0.02), (96, -0.015)])
    e.track('ear_l1', Emo.R, [(16, -0.13, BACK), (96, -0.09)])
    e.track('ear_r1', Emo.R, [(16, 0.13, BACK), (96, 0.09)])
    e.track('ear_l1', Emo.SX, [(16, 0.07, BACK), (96, 0.05)])
    e.track('ear_r1', Emo.SX, [(16, 0.07, BACK), (96, 0.05)])
    e.track('ear_l2', Emo.R, [(20, -0.1, BACK), (96, -0.07)])
    e.track('ear_r2', Emo.R, [(20, 0.1, BACK), (96, 0.07)])
    e.track('hood2', Emo.R, [(20, 0.09), (38, -0.06), (58, 0.03), (96, 0.01)])
    e.track('hood1', Emo.R, [(20, 0.03), (40, -0.015)])
    e.track('arm_l1', Emo.R, [(18, 0.07, BACK), (96, 0.05)])
    e.track('arm_r1', Emo.R, [(18, -0.07, BACK), (96, -0.05)])
    return e.build()


def emo_sad():
    """Грусть, 3 с: вздох, моргнул — брови домиком, глаза прикрыты и
    щурятся, уголки рта вниз; голова клонится и опускается, плечи, уши и
    кончик капюшона никнут; на выдохе ещё раз моргнул."""
    e = Emo(180)
    e.face('sad', [(26, 154)]).blinks([24, 88, 152])
    e.track('breath', Emo.SY, [(24, 0.035), (70, -0.035), (150, -0.03)])
    e.track('hips', Emo.Y, [(24, -2), (70, 4), (150, 3.5)])
    e.track('chest', Emo.R, [(60, -0.015), (150, -0.012)])
    e.track('head', Emo.R, [(50, 0.055), (110, 0.045), (150, 0.05)])
    e.track('face', Emo.X, [(50, -5), (150, -4.5)])
    e.track('face', Emo.Y, [(50, -2), (150, -1.5)])
    e.track('ear_l1', Emo.R, [(50, 0.14), (150, 0.12)])
    e.track('ear_r1', Emo.R, [(50, -0.14), (150, -0.12)])
    e.track('ear_l1', Emo.SX, [(50, -0.08), (150, -0.07)])
    e.track('ear_r1', Emo.SX, [(50, -0.08), (150, -0.07)])
    e.track('ear_l2', Emo.R, [(56, 0.12), (150, 0.1)])
    e.track('ear_r2', Emo.R, [(56, -0.12), (150, -0.1)])
    e.track('hood2', Emo.R, [(60, 0.07), (150, 0.06)])
    e.track('hood1', Emo.R, [(56, 0.02), (150, 0.018)])
    e.track('arm_l1', Emo.R, [(50, -0.03), (150, -0.025)])
    e.track('arm_r1', Emo.R, [(50, 0.03), (150, 0.025)])
    return e.build()


def emo_chew():
    """Жуёт, 2,8 с: довольно прищурился, щёки набиты — пять жевков:
    подбородок вниз — рот приоткрыт, вверх — губы сомкнуты; щёки
    надуваются по очереди, голова кивает в такт."""
    e = Emo(168)
    c = [18, 42, 66, 90, 114]
    e.face('chew', [(10, 150)]).blinks([8, 148])
    # подбородок внизу (a+16…a+30) — рот приоткрыт
    e.face('chew_open', [(a + 16, a + 30) for a in c])
    e.track('chin', Emo.X, pulses(c, 10, 14, 0.8, -2.2))
    e.track('cheek_l', Emo.SY, pulses(c[0::2], 10, 14, 0.06, 0.01))
    e.track('cheek_r', Emo.SY, pulses(c[1::2], 10, 14, 0.06, 0.01))
    e.track('head', Emo.R, [(12, 0.02)] + pulses(c, 10, 14, 0.032, 0.018) + [(140, 0.018)])
    e.track('face', Emo.X, pulses(c, 10, 14, 1, -0.4))
    e.track('ear_l1', Emo.R, pulses([a + 4 for a in c], 10, 14, -0.03, 0.0))
    e.track('ear_r1', Emo.R, pulses([a + 4 for a in c], 10, 14, 0.03, 0.0))
    e.track('hood2', Emo.R, pulses([a + 6 for a in c], 10, 14, -0.03, 0.01))
    return e.build()


def emo_lick():
    """Смакует, 2,2 с: моргнул — глаза блаженно прищурены, кончик языка
    облизывает губу; подбородок и щёки ходят, голова набок."""
    e = Emo(132)
    s = [18, 42, 66]
    e.face('lick', [(12, 112)]).blinks([10, 110])
    e.track('chin', Emo.X, pulses(s, 8, 16, 1.0, -0.3))
    e.pair('cheek', Emo.X, pulses(s, 8, 16, 1.0, 0.3))
    e.track('head', Emo.R, [(18, 0.045, BACK), (60, 0.035), (110, 0.04)])
    e.track('face', Emo.Y, [(18, 3), (110, 2.5)])
    e.track('hood2', Emo.R, [(24, -0.05), (44, 0.03), (62, -0.01)])
    e.track('ear_r1', Emo.R, [(18, 0.06), (40, -0.02)])
    e.track('ear_l1', Emo.R, [(20, -0.04), (42, 0.02)])
    return e.build()


def emo_yawn():
    """Зевок, 3,5 с: глубокий вдох — глаза зажмурились, рот широко
    раскрыт, мордочка вытягивается, голова назад, лапы в стороны;
    выдох — рот закрылся, глаза ещё сомкнуты, открыл, встряхнул головой."""
    e = Emo(210)
    e.face('yawn', [(38, 140)]).face('asleep', [(140, 152)]).blinks([36, 150])
    e.track('chin', Emo.X, [(38, -1.5), (60, -3.5), (125, -3), (140, 0)])
    e.track('chin', Emo.SX, [(60, 0.05), (125, 0.045), (140, 0)])
    e.track('breath', Emo.SY, [(60, 0.09), (120, 0.08), (160, -0.02)])
    e.track('chest', Emo.R, [(60, -0.035), (125, -0.03), (160, 0.005)])
    e.track('head', Emo.R, [(60, -0.05), (125, -0.045), (150, 0), (162, 0.015), (176, -0.012)])
    e.track('face', Emo.X, [(60, 5), (125, 4.5), (150, 0)])
    e.track('hips', Emo.Y, [(60, -5), (120, -4), (160, 2)])
    e.track('arm_l1', Emo.R, [(60, 0.05), (125, 0.045), (160, 0)])
    e.track('arm_r1', Emo.R, [(60, -0.05), (125, -0.045), (160, 0)])
    e.track('arm_l2', Emo.R, [(66, 0.07), (125, 0.06), (165, 0)])
    e.track('arm_r2', Emo.R, [(66, -0.07), (125, -0.06), (165, 0)])
    e.track('ear_l1', Emo.R, [(60, 0.1), (125, 0.08), (165, -0.02)])
    e.track('ear_r1', Emo.R, [(60, -0.1), (125, -0.08), (165, 0.02)])
    e.track('hood2', Emo.R, [(70, -0.07), (130, 0.04), (170, -0.015)])
    return e.build()


def emo_sleepy():
    """Сонный, 3,5 с: веки тяжелеют (полуприкрыты), голова клюёт вниз —
    глаза закрылись, задремал; вздрогнул — проснулся, глаза открыты,
    голова вверх; и снова веки тяжёлые."""
    e = Emo(210)
    e.face('sleepy', [(32, 100), (168, 198)]).face('asleep', [(100, 138)])
    e.blinks([30, 166, 196])
    e.track('face', Emo.X, [(90, -3), (126, -8), (138, 1, BACK), (170, -2)])
    e.track('head', Emo.R, [(126, 0.04), (138, -0.01, BACK), (170, 0.015)])
    e.track('hips', Emo.Y, [(126, 3), (138, -2, BACK), (170, 0.5)])
    e.track('breath', Emo.SY, [(60, 0.04), (110, -0.03), (138, 0.03), (170, 0)])
    e.track('chin', Emo.X, [(110, -1), (128, -1), (138, 0)])
    e.track('ear_l1', Emo.R, [(126, 0.12), (138, -0.04, BACK), (170, 0.05)])
    e.track('ear_r1', Emo.R, [(126, -0.12), (138, 0.04, BACK), (170, -0.05)])
    e.track('hood2', Emo.R, [(130, 0.06), (146, -0.05), (170, 0.02)])
    e.track('arm_l1', Emo.R, [(126, -0.03), (140, 0.01)])
    e.track('arm_r1', Emo.R, [(126, 0.03), (140, -0.01)])
    return e.build()


def emo_upset():
    """Обиделся, 3 с: моргнул — брови сдвинуты, взгляд исподлобья, уголки
    вниз, щёки надуты; топнул левой, правой, левой, правой (колено
    поднимается, вес переходит на другую ногу, удар — всё тело
    вздрагивает); фыркнул и отвернулся, уши прижаты."""
    e = Emo(180)
    e.face('upset', [(12, 152)]).blinks([10, 150])
    stomps = [(24, 'l'), (48, 'r'), (72, 'l'), (96, 'r')]

    def merged(base, bumps):
        """base [(кадр, уровень)] — держится; bumps [(кадр, прибавка[, кривая])]
        поверх уровня в этот кадр → ключи."""
        pts = [(0, 0.0)] + [(p[0], p[1]) for p in base]

        def level(fr):
            for (f0, v0), (f1, v1) in zip(pts, pts[1:]):
                if f0 <= fr <= f1:
                    return v0 + (v1 - v0) * (fr - f0) / (f1 - f0)
            return pts[-1][1]
        keys = {p[0]: (p[1], p[2] if len(p) > 2 else EI) for p in base}
        for p in bumps:
            keys[p[0]] = (level(p[0]) + p[1], p[2] if len(p) > 2 else EI)
        return [(fr, v, ez) for fr, (v, ez) in sorted(keys.items())]

    hips_x, hips_y, head_r, face_x, ears, arms = [], [], [], [], [], []
    legs = {}
    for at, side in stomps:
        out = 1 if side == 'l' else -1        # наружу: у левой — влево
        # голень: подъём (спереди — колено к нам), носок наружу, удар
        legs.setdefault((f'shin_{side}', Emo.X), []).extend(
            [(at, 0), (at + 9, -32, EO), (at + 12, -32), (at + 16, 2.0, EIN), (at + 20, 0)])
        legs.setdefault((f'shin_{side}', Emo.R), []).extend(
            [(at, 0), (at + 9, 0.05 * out, EO), (at + 12, 0.05 * out), (at + 16, 0.0, EIN)])
        legs.setdefault((f'shin_{side}', Emo.SY), []).extend(
            [(at, 0), (at + 9, 0.08, EO), (at + 16, 0.0, EIN)])
        legs.setdefault((f'leg_{side}', Emo.R), []).extend(
            [(at, 0), (at + 9, 0.07 * out, EO), (at + 16, 0.0, EIN)])
        # вес — на другую ногу; при подъёме чуть вверх, удар — осел
        hips_x += [(at + 6, -3 * out, EO), (at + 22, 0.0)]
        hips_y += [(at + 9, -2.0, EO), (at + 17, 3.5, EIN), (at + 23, 0.0)]
        head_r += [(at + 18, 0.022 * out, EO), (at + 27, 0.0)]
        face_x += [(at + 17, -2.0, EIN), (at + 22, 0.6), (at + 28, 0.0)]
        ears += [(at + 19, 0.05, EO), (at + 27, 0.0)]
        arms += [(at + 17, 0.03, EIN), (at + 24, 0.0)]
    for (name, key), pts in legs.items():
        e.track(name, key, pts)
    e.track('hips', Emo.X, hips_x)
    e.track('hips', Emo.Y, merged([(16, 3), (120, 3), (140, 3.5)], hips_y))
    e.track('head', Emo.R, merged([(20, -0.012), (124, -0.012), (134, -0.045, BACK), (160, -0.04)], head_r))
    e.track('face', Emo.X, face_x)
    e.track('face', Emo.Y, [(124, 0), (134, -6, BACK), (160, -5.5)])
    e.pair('cheek', Emo.SY, [(18, 0.05), (160, 0.04)])
    e.track('breath', Emo.SY, [(8, 0.03), (22, -0.02), (118, -0.02), (126, 0.035), (136, -0.03), (160, -0.02)])
    e.track('arm_l1', Emo.R, merged([(16, -0.04), (160, -0.035)], [(f, -v, *z) for f, v, *z in arms]))
    e.track('arm_r1', Emo.R, merged([(16, 0.04), (160, 0.035)], arms))
    e.track('ear_l1', Emo.R, merged([(16, 0.12), (160, 0.1)], ears))
    e.track('ear_r1', Emo.R, merged([(16, -0.12), (160, -0.1)], [(f, -v, *z) for f, v, *z in ears]))
    e.track('ear_l1', Emo.SX, [(16, -0.1), (160, -0.08)])
    e.track('ear_r1', Emo.SX, [(16, -0.1), (160, -0.08)])
    e.track('ear_l2', Emo.R, [(20, 0.1), (160, 0.08)])
    e.track('ear_r2', Emo.R, [(20, -0.1), (160, -0.08)])
    e.track('hood2', Emo.R, [(26, 0.06), (44, -0.03), (70, 0.03), (94, -0.02), (136, 0.04), (160, 0.02)])
    return e.build()


EMOTION_ANIMS = {
    'emo_smile': emo_smile, 'emo_laugh': emo_laugh, 'emo_surprised': emo_surprised,
    'emo_sad': emo_sad, 'emo_chew': emo_chew, 'emo_lick': emo_lick,
    'emo_yawn': emo_yawn, 'emo_sleepy': emo_sleepy, 'emo_upset': emo_upset,
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
        'leg_left': 'shin_l', 'leg_right': 'shin_r',
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

    # 3. Новый скелет в начале артборда; над каждой костью — кость эмоции
    #    нулевой длины (TRANSLATED выше).
    elems = {}
    for i, (name, b) in enumerate(B.items()):
        tag = 'RootBone' if b['is_root'] else 'Bone'
        local = dict(b['local'])
        e_local, own = {}, {}
        if b['is_root']:
            e_local = dict(x=local['x'], y=local['y'])
            own = dict(x=0.0, y=0.0)
        if name in TRANSLATED:
            e_local['rotation'] = 0.0
            own['rotation'] = local['rotation']
        else:
            e_local['rotation'] = local['rotation']
            own['rotation'] = 0.0
        E_REST[name] = dict(e_local)
        b['local'] = own
        helper = ET.Element(tag, {**{k: fmt(v) for k, v in e_local.items()}, 'length': '0',
                                  'name': f'e_{name}', 'id': ident(200 + i)})
        E_IDS[name] = ident(200 + i)
        attrs = {k: fmt(v) for k, v in own.items()}
        attrs.update(length=fmt(b['length']), name=f'b_{name}', id=b['id'])
        el = ET.Element(tag, attrs)
        helper.append(el)
        elems[name] = el
        if b['parent'] is None:
            ab.insert(0, helper)
        else:
            elems[b['parent']].append(helper)

    # 3б. Бусины глаз и «глазницы» под ними — в обёртки с центром в глазу:
    #     покой моргает самой бусиной, эмоция щурит обёртку.
    for key, img_id in WRAPS.items():
        img = next(e for e in ab.iter('Image') if e.attrib['id'] == img_id)
        holder = parent[img]
        x, y = f(img, 'x'), f(img, 'y')
        wrap = ET.Element('Node', {'x': fmt(x), 'y': fmt(y), 'name': f'e_{key}', 'id': WRAP_IDS[key]})
        holder.insert(list(holder).index(img), wrap)
        holder.remove(img)
        img.set('x', '0')
        img.set('y', '0')
        wrap.append(img)
        E_REST[key] = dict(x=x, y=y)
        E_IDS[key] = WRAP_IDS[key]

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

    # 4б. Сетка лица гуще у рта, век и бровей (mesh_refine.py).
    face = byname['face_img'].find('Mesh')
    fskin = face.find('Skin')
    fm = M(*[f(fskin, k) for k in ('xx', 'xy', 'yx', 'yy', 'tx', 'ty')])
    ids = iter(range(10000, 99999))
    added = mesh_refine.refine(face, fm.apply, FACE_REFINE, lambda: ident(next(ids)))
    print('face mesh +', added, 'points')
    eyes = [(byname['gaze_socket_l_img'], byname['gaze_bead_l_img']),
            (byname['gaze_socket_r_img'], byname['gaze_bead_r_img'])]
    byname['lid_patch_img'] = lids.build(project, root, ab, W, byname, fm, eyes, lambda: ident(next(ids)))
    # 4в. Выражения лица целиком поверх бусин и век (faces.py).
    for n, fid in faces.build(project, root, ab, byname, lambda: ident(next(ids))).items():
        E_IDS[f'face_{n}'] = fid

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
    builders = EMOTION_ANIMS
    for name, fn in builders.items():
        emo = anims.get(name)
        if emo is None:
            emo = ET.Element('LinearAnimation', {'duration': '1', 'loopValue': '0', 'name': name})
            ab.insert(list(ab).index(anims['idle_life']), emo)
        for ko in list(emo.findall('KeyedObject')):
            emo.remove(ko)
        dur, ch = fn()
        emo.set('duration', str(dur))
        for (target, key), frames in ch.items():
            oid = target
            ko = ET.SubElement(emo, 'KeyedObject', {'objectId': oid})
            kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
            for fr, val, ease in frames:
                cubic_key(kp, fr, val, ease)

    ET.indent(tree, space='    ')
    tree.write(path, encoding='unicode')
    print('bones', len(B), 'followers', len(followers))


if __name__ == '__main__':
    main(sys.argv[1])
