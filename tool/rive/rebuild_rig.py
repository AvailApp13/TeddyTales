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
import crease  # noqa: E402
import mouth  # noqa: E402

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
    # руки (27.09, «три звена»): плечо → середина → предплечье до манжеты,
    # кисть — в конце списка (hand_l/r), за ней едет лапа
    # ось плеча — в середине толщины руки у корня (между верхом рукава и
    # подмышкой), как центр круглого сустава в Live2D/перекладке
    ('arm_l1',  'chest',  (368, 556),   (342, 591)),
    ('arm_l2',  'arm_l1', None,         (316, 626)),
    ('arm_r1',  'chest',  (656, 556),   (682, 591)),
    ('arm_r2',  'arm_r1', None,         (708, 626)),
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
    ('arm_l3',  'arm_l2', None,         (290, 662)),
    ('hand_l',  'arm_l3', None,         (258, 703)),
    ('arm_r3',  'arm_r2', None,         (734, 662)),
    ('hand_r',  'arm_r3', None,         (766, 703)),
    # бок кофты под рукой (поправочная кость, как в Spine/Live2D): пока
    # рука поднята немного, низ бока идёт за ней — рука не «отлипает»
    # трещиной; дальше кость упирается (SIDE_CAP), подмышка раскрывается
    ('side_l',  'chest',  (368, 556),   (340, 700)),
    ('side_r',  'chest',  (656, 556),   (684, 700)),
    # рот раскрывается масштабом этих костей (mouth.py): горизонтальные,
    # в покое сжаты до щёлочки (mouth.CAVITIES); open — смех и улыбка,
    # yawn — зевок, chew — жевание
] + [(f'mouth_{n}', 'face', mouth.center(n), (mouth.center(n)[0] + 20, mouth.center(n)[1]))
     for n in mouth.KINDS] + [
    # нижняя челюсть жевания: низ полости жевания (mouth.py)
    ('jaw_chew', 'mouth_chew', mouth.chew_rows()[::2], (mouth.chew_rows()[0] + 20, mouth.chew_rows()[2])),
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


def _pinned(layer, x, y, B):
    return pin(_weights_for(layer, x, y, B), layer, x, y) if layer.startswith(('hood_img', 'hood_back', 'ear_')) \
        else _weights_for(layer, x, y, B)


# Швы, где в покое просвечивал фон (заказчик 27.09: «исправь просветы»):
# две картинки сходятся краями у силуэта, и если их точки на шве
# держатся за разные кости, край одной отходит от края другой. Как
# «сварка» швов в Spine/Live2D: у шва все слои берут одинаковые веса —
# среднее весов сходящихся слоёв, — и ходят вместе; в 3–16 px от шва
# каждый слой снова свой. Линии швов — по точкам просветов в кадрах покоя.
# (линия шва в мире, какие слои сварить, чьи веса усреднить)
_HOOD = ('hood_img', 'hood_back_img')
_SHIRT = ('shirt_img', 'shirt_flat_l_img', 'shirt_flat_r_img')
SEAMS = [
    ([(366, 224), (401, 205), (412, 198)], ('ear_l',) + _HOOD, ('ear_left_img', 'hood_img')),
    ([(621, 208), (639, 216), (647, 210)], ('ear_r',) + _HOOD, ('ear_right_img', 'hood_img')),
    ([(663, 522), (675, 527)], _HOOD + _SHIRT + ('sleeve_right_img',), ('hood_img', 'shirt_img')),
    ([(359, 527), (371, 522)], _HOOD + _SHIRT + ('sleeve_left_img',), ('hood_img', 'shirt_img')),
    ([(324, 684), (324, 700)], _SHIRT + ('sleeve_left_img',), ('shirt_img', 'sleeve_left_img')),
    ([(709, 697), (709, 704)], _SHIRT + ('sleeve_right_img',), ('shirt_img', 'sleeve_right_img')),
]
SEAM_R = (3, 16)


def _seg_dist(p, line):
    d = 1e9
    for a, b in zip(line, line[1:]):
        t = min(1.0, max(0.0, along(p, a, b)))
        d = min(d, math.hypot(p[0] - a[0] - t * (b[0] - a[0]), p[1] - a[1] - t * (b[1] - a[1])))
    return d


def weights_for(layer, x, y, B):
    w = _pinned(layer, x, y, B)
    for line, members, reps in SEAMS:
        if not layer.startswith(members):
            continue
        k = 1 - smooth(*SEAM_R, _seg_dist((x, y), line))
        if k <= 0:
            continue
        avg = {}
        for r in reps:
            for bone, v in _pinned(r, x, y, B).items():
                avg[bone] = avg.get(bone, 0) + v / len(reps)
        w = {bone: w.get(bone, 0) * (1 - k) + avg.get(bone, 0) * k for bone in set(w) | set(avg)}
        w = {bone: v for bone, v in w.items() if v > 1e-4}
    return w


def _weights_for(layer, x, y, B):
    if layer == 'mouth_chew_img':      # верх — губа, низ — челюсть
        _, top, bot = mouth.chew_rows()
        k = min(1.0, max(0.0, (y - top) / (bot - top)))
        return {b: v for b, v in (('mouth_chew', 1 - k), ('jaw_chew', k)) if v > 1e-4}
    if layer.startswith('mouth_') and layer.endswith('_img'):
        return {layer[:-4]: 1.0}
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
    if layer in ('shirt_img', 'shirt_flat_l_img', 'shirt_flat_r_img'):
        side = 'l' if x < 512 else 'r'
        w = stretch(torso_weights(x, y), arm_weights(side, x, y, B), armness('shirt', x, y))
        k = side_share(x, y)
        if k > 0:
            w = {b: v * (1 - k) for b, v in w.items()}
            w[f'side_{side}'] = w.get(f'side_{side}', 0) + k
        return w
    if layer in ('sleeve_left_img', 'sleeve_right_img'):
        side = 'l' if layer == 'sleeve_left_img' else 'r'
        return stretch(torso_weights(x, y), arm_weights(side, x, y, B), armness('sleeve', x, y))
    if layer == 'shorts_img':
        side = 'l' if x < 518 else 'r'
        k = smooth(815, 880, y)          # таз → бедро
        s = smooth(840, 908, y)          # бедро → голень: низ штанины за коленом
        w = {'hips': 1 - k, f'leg_{side}': k * (1 - s), f'shin_{side}': k * s}
        return {b: v for b, v in w.items() if v > 1e-4}
    raise KeyError(layer)


def torso_weights(x, y):
    """Туловище под кофтой: таз → живот → грудь, в середине — «вдох».
    Низ кофты — за тазом, верх у плеч — за грудью (до 27.09 было
    наоборот: знак y перевёрнут, подол ходил за грудью)."""
    w = chain_weights(y, [('hips', 742), ('belly', 652), ('chest', -1e9)], blend=26)
    d = math.hypot((x - 517) / 150, (y - 640) / 120)
    k = max(0.0, 1 - d) ** 1.5 * 0.7
    if k > 0:
        w = {b: v * (1 - k) for b, v in w.items()}
        w['breath'] = w.get('breath', 0) + k
    return w


def arm_weights(side, x, y, B):
    """Рука дугой: плечо → середина → предплечье, мягкие полосы вдоль руки."""
    t = along((x, y), B[f'arm_{side}1']['start'], B[f'arm_{side}3']['end'])
    return blend_chain(t, [f'arm_{side}1', f'arm_{side}2', f'arm_{side}3'], [(0.24, 0.44), (0.56, 0.76)])


# Растяжка у подмышки (27.09, как в Spine/Rive: вершины у сустава тянут и
# туловище, и плечо; шов кофты и рукава — с одинаковыми весами, поэтому не
# расходится). Шов — край кофты: половина ширины кофты от оси x = 512
# по высоте y (замер по текстуре, слева и справа почти одинаково).
SEAM = [(480, 131), (500, 133), (520, 136), (540, 136), (560, 139), (580, 143),
        (600, 146), (620, 148), (640, 151), (660, 160), (680, 173), (700, 183)]
STRETCH_IN, STRETCH_OUT = 50, 35   # ширина растяжки в кофту и в рукав, px


def seam_half(y):
    for (y0, h0), (y1, h1) in zip(SEAM, SEAM[1:]):
        if y <= y1:
            return h0 + (h1 - h0) * max(0.0, (y - y0) / (y1 - y0))
    return SEAM[-1][1]


def armness(kind, x, y):
    """Доля руки в весах вершины: на шве 0,5, в кофту — к 0, в рукав — к 1.
    До подмышки (y < 585) у кофты и рукава одна и та же доля — шов не
    расходится. Ниже рукав отходит от бока, а бок кофты тянется за ним
    всё слабее к подолу (заказчик 27.09: «в этой зоне майка должна
    растянуться»)."""
    out = abs(x - 512) - seam_half(y)          # >0 — снаружи кофты
    g = 0.5 + 0.5 * smooth(0, STRETCH_OUT, out) if out >= 0 else 0.5 * (1 - smooth(0, STRETCH_IN, -out))
    top = smooth(470, 495, y)
    if kind == 'shirt':
        # бок кофты под мышкой (от подмышки к подолу) тянется за рукой всё
        # слабее книзу — ткань расправляется, бок выпрямляется
        return top * (1 - smooth(588, 725, y)) * g
    # рукав снизу от подмышки отходит от бока — подмышка раскрывается
    return 1 - top * (1 - smooth(585, 690, y)) * (1 - g)


def side_share(x, y):
    """Доля кости бока у вершин кофты: вместе с растяжкой (armness) даёт
    на шве ту же долю руки, что у рукава, — при малом подъёме бок идёт
    за рукой без щели. Ниже подмышки, у шва, к подолу гаснет."""
    out = abs(x - 512) - seam_half(y)
    g = 0.5 if out >= 0 else 0.5 * (1 - smooth(0, STRETCH_IN, -out))
    s1, s2 = smooth(585, 690, y), smooth(588, 725, y)
    return min(1.0, (s1 + s2) * g) * (1 - smooth(705, 760, y))


def stretch(torso, arm, g):
    w = {b: v * (1 - g) for b, v in torso.items()}
    for b, v in arm.items():
        w[b] = w.get(b, 0) + v * g
    return {b: v for b, v in w.items() if v > 1e-4}


def blend3(t, a0, a1, a2, a=0.0, b=0.2, c=0.5, d=0.8):
    """0..1 вдоль цепочки: a0 → a1 (между a и b) → a2 (между c и d)."""
    k1 = smooth(a, b, t)
    k2 = smooth(c, d, t)
    w = {a0: 1 - k1, a1: k1 * (1 - k2), a2: k1 * k2}
    return {k: v for k, v in w.items() if v > 1e-4}


def blend_chain(t, bones, spans):
    """0..1 вдоль цепочки: bones[i] → bones[i+1] в полосе spans[i]."""
    w = {bones[0]: 1.0}
    for (a, b), nxt in zip(spans, bones[1:]):
        k = smooth(a, b, t)
        if k <= 0:
            break
        w = {bn: v * (1 - k) for bn, v in w.items()}
        w[nxt] = w.get(nxt, 0) + k
    return {bn: v for bn, v in w.items() if v > 1e-4}


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
    # плечи поднимаются на вдохе, лапы отходят; звенья руки догоняют друг
    # друга с запаздыванием — рука мягкая, как у плюшевой игрушки
    for s, sg in (('l', 1), ('r', -1)):
        for bone, amp, lag in ((f'arm_{s}1', 0.02, 8), (f'side_{s}', 0.02, 8), (f'arm_{s}2', 0.014, 15),
                               (f'arm_{s}3', 0.014, 22), (f'hand_{s}', 0.03, 32)):
            add(bone, R, lambda t, b=bone, a=amp * sg, g=lag: rest[b]['rotation'] + a * wave(t, g))
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


RAISE_FULL = 0.6   # при подъёме плеча на столько (рад, ~35°) складка расправлена
SIDE_CAP = 0.08    # бок кофты идёт за рукой до такого подъёма (рад, ~4,5°)


class Emo:
    """Сборщик одной эмоции: ключи — смещения от покоя кости эмоции."""
    R, SX, SY, X, Y, OP = 15, 16, 17, 90, 91, 18

    def __init__(self, dur):
        self.dur, self.ch = dur, {}
        self.mouth_h = {}     # вид рта → [(кадр, высота)] — для ротика покоя

    def track(self, name, key, pts):
        """pts: [(кадр, смещение[, кривая])]; начало и конец — покой."""
        r = E_REST[name]
        b = {15: r.get('rotation', 0.0), 90: r.get('x', 0.0), 91: r.get('y', 0.0)}.get(key, 1.0)
        frames = [(0, b, EI)]
        for p in pts:
            frames.append((p[0], b + p[1], p[2] if len(p) > 2 else EI))
        frames.append((self.dur - 2, b, None))
        self.ch[(E_IDS[name], key)] = frames
        if key == self.R and name in ('arm_l1', 'arm_r1'):
            # складка под мышкой расправляется вместе с подъёмом плеча
            side, sg = name[4], (1 if name == 'arm_l1' else -1)
            op = [(0, 0.0, EI)] + [(p[0], min(1.0, max(0.0, sg * p[1] / RAISE_FULL)), p[2] if len(p) > 2 else EI)
                                   for p in pts] + [(self.dur - 2, 0.0, None)]
            self.ch[(E_IDS[f'flat_{side}'], self.OP)] = op
            # поправочная кость бока: тот же подъём, но не больше SIDE_CAP
            b = E_REST[f'side_{side}']['rotation']
            self.ch[(E_IDS[f'side_{side}'], self.R)] = (
                [(0, b, EI)] + [(p[0], b + max(-SIDE_CAP, min(SIDE_CAP, p[1])), p[2] if len(p) > 2 else EI)
                                for p in pts] + [(self.dur - 2, b, None)])
        return self

    def face(self, name, spans):
        """Выражение из `faces.py`: spans [(с кадра, по кадр)] — видно
        целиком, включается и гаснет мгновенно (ключи hold)."""
        frames = [(0, 0.0, None)]
        for on, off in spans:
            frames += [(on, 1.0, None), (off, 0.0, None)]
        self.ch[(E_IDS[f'face_{name}'], self.OP)] = frames
        return self

    def mouths(self, seq, end):
        """Рты-ступени поверх лица: seq [(с кадра, имя или None)] — рот
        держится до следующей записи, последний — до end; None — рот
        самого лица."""
        spans = {}
        for (on, name), nxt in zip(seq, [s[0] for s in seq[1:]] + [end]):
            if not name:
                continue
            sp = spans.setdefault(name, [])
            if sp and sp[-1][1] == on:
                sp[-1] = (sp[-1][0], nxt)
            else:
                sp.append((on, nxt))
        for name, sp in spans.items():
            self.face(name, sp)
        return self

    def mouth_open(self, pts, kind='open'):
        """Рот раскрывает кость (`mouth.py`), без смены картинок: pts
        [(кадр, ширина, высота[, кривая])], 0 — ротик покоя, 1 — полость
        целиком; kind — какой рот (`mouth.KINDS`: полости open — смех,
        yawn, chew; линии губ sad, pout, sleepy, content). Щёлочка
        проявляется, пока совсем тонкая."""
        sx0, sy0 = mouth.closed(kind)
        bone = f'mouth_{kind}'

        def ez(p):
            return p[3] if len(p) > 3 else EI
        self.track(bone, self.SX, [(p[0], (sx0 + (1 - sx0) * p[1]) / sx0 - 1, ez(p)) for p in pts])
        self.track(bone, self.SY, [(p[0], (sy0 + (1 - sy0) * p[2]) / sy0 - 1, ez(p)) for p in pts])
        self.ch[(E_IDS[f'{bone}_img'], self.OP)] = (
            [(0, 0.0, EI)] + [(p[0], min(1.0, p[2] / 0.1), ez(p)) for p in pts] + [(self.dur - 2, 0.0, None)])
        self.mouth_h[kind] = [(p[0], p[2]) for p in pts]
        return self

    def _rest_mouth(self):
        """Ротик покоя гаснет, пока любой рот эмоции ещё щёлочка (mouth.py)."""
        if not self.mouth_h:
            return
        end = self.dur - 2

        def h_at(pts, fr):
            pts = [(0, 0.0)] + pts + [(end, 0.0)]
            for (f0, v0), (f1, v1) in zip(pts, pts[1:]):
                if f0 <= fr <= f1:
                    return v0 + (v1 - v0) * (fr - f0) / max(1, f1 - f0)
            return 0.0
        frames = sorted({f for pts in self.mouth_h.values() for f, _ in pts} | {0, end})
        self.ch[(E_IDS['mouth_rest_img'], self.OP)] = [
            (fr, max(0.0, 1 - max(h_at(p, fr) for p in self.mouth_h.values()) / 0.15), EI if fr < end else None)
            for fr in frames]

    def arms(self, pts, follow=0.25, lag=3):
        """Обе руки: pts [(кадр, подъём плеча, кривая)] — для левой руки,
        правая зеркально. Середина, предплечье и кисть догоняют плечо с
        запаздыванием lag кадров на звено и поворачиваются на долю follow —
        рука гнётся мягкой дугой, кисть чуть «перелетает» (как уши)."""
        last = self.dur - 3
        for s, sg in (('l', 1), ('r', -1)):
            self.track(f'arm_{s}1', self.R, [(f, v * sg, *z) for f, v, *z in pts])
            for i, (bone, k) in enumerate(((f'arm_{s}2', 1.0), (f'arm_{s}3', 1.0), (f'hand_{s}', 1.6)), 1):
                seq, prev = [], 0
                for f, v, *z in pts:
                    fr = min(f + lag * i, last)
                    if fr > prev:
                        seq.append((fr, v * sg * follow * k, *z))
                        prev = fr
                self.track(bone, self.R, seq)
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
            # закрытый глаз — бусина сплющена в тёмную черту, как в моргании
            # покоя (27.09: бусина, которая таяла, оставляла бледный пустой
            # овал)
        return self

    def build(self):
        self._rest_mouth()
        return self.dur, self.ch


def pulses(at, up, down, peak, low=0.0, ease_up=EO, ease_down=EI):
    """Ритм: в кадрах at пик peak через up кадров, спад к low через down."""
    pts = []
    for a in at:
        pts += [(a + up, peak, ease_up), (a + up + down, low, ease_down)]
    return pts


def emo_smile():
    """Улыбка, 2,5 с (заказчик 27.09: фото-улыбка смотрела «как лиса» —
    глаза заменить мимикой костями). Без смены картинок: уголки рта
    поднимаются, ротик чуть приоткрывается костью (`Emo.mouth_open`),
    нижние веки и щёки слегка подпирают глаза, брови чуть вверх — взгляд
    открытый и добрый, без прищура. Голова мягко наклоняется, тело
    приподнимается, уши и кончик капюшона догоняют."""
    e = Emo(150)
    e.mouth_open([(6, 0.05, 0.0), (34, 0.95, 0.5, EO), (110, 0.92, 0.46), (134, 0.25, 0.0)])
    e.pair('mouth', Emo.X, [(10, 0), (34, 9, EO), (110, 8.5), (136, 0.5)])
    e.pair('mouth', Emo.Y, [(34, -2), (110, -1.8), (136, 0)], mirror=True)
    e.track('chin', Emo.X, [(34, -1), (110, -0.8), (136, 0)])
    e.track('muzzle', Emo.X, [(34, 0.8), (110, 0.7), (136, 0)])
    e.eyes([(8, 0.0), (34, 0.2, EO), (110, 0.18), (140, 0.0)])
    e.pair('lid', Emo.X, [(34, 6, EO), (110, 5.5), (140, 0)])
    e.pair('eye', Emo.SX, [(34, -0.03), (110, -0.025), (140, 0)])
    e.pair('cheek', Emo.X, [(10, 0), (36, 4, EO), (110, 3.6), (140, 0)])
    e.pair('cheek', Emo.SY, [(36, 0.05), (110, 0.045), (140, 0)])
    e.pair('brow', Emo.X, [(36, 2.5, EO), (110, 2.2), (140, 0)])
    e.track('head', Emo.R, [(8, -0.012), (44, 0.06, EO), (80, 0.05), (104, 0.055)])
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
    """Смех, 4,2 с (заказчик 27.09: «плавно, как в покое, без подмен»;
    затем — «чуть медленнее, рот мягче»). Ни одной смены картинки: лицо
    остаётся лицом покоя, всё делают кости. Глаза щурятся (нижние веки и
    щёки поднимаются), уголки рта вверх, рот раскрывается костью от
    щёлочки до широкого (`Emo.mouth_open`), и пять мягких «ха-ха» —
    волной, как дыхание: рот, подбородок, щёки, грудь, плечи и голова
    вместе, уши и кончик капюшона догоняют. Каждое «ха» чуть слабее
    прежнего, в конце рот смыкается, глаза открываются. Прыжка и подъёма
    рук нет."""
    e = Emo(252)
    g = [60, 84, 108, 132, 156]                # «ха» каждые 0,4 с: пик через 11 кадров, спад через 13
    fade = [1 - 0.08 * i for i in range(len(g))]

    def beats(peak, low, lag=0, up=11, down=13):
        pts = []
        for a, k in zip(g, fade):
            pts += [(a + lag + up, low + (peak - low) * k), (a + lag + up + down, low)]
        return pts

    mo = [(8, 0.05, 0.0), (30, 0.6, 0.25), (56, 0.95, 0.85)]
    for a, k in zip(g, fade):
        mo += [(a + 11, 1.0, 0.78 + 0.22 * k), (a + 24, 0.95, 0.78)]
    mo += [(196, 0.9, 0.55), (214, 0.7, 0.18), (230, 0.45, 0.04), (242, 0.15, 0.0)]
    e.mouth_open(mo)
    # глаза: щурятся от смеха, веки и щёки подпирают снизу
    e.eyes([(4, 0.0), (36, 0.45, EO), (186, 0.45), (236, 0.05)])
    e.pair('lid', Emo.X, [(36, 12, EO), (186, 12), (236, 1)])
    e.pair('eye', Emo.SX, [(36, -0.08), (186, -0.08), (236, -0.01)])
    e.pair('cheek', Emo.X, [(36, 5, EO)] + beats(6.5, 5) + [(196, 5), (236, 0.5)])
    e.pair('cheek', Emo.SY, [(36, 0.06), (186, 0.06), (236, 0.01)])
    e.pair('brow', Emo.X, [(36, 1.5), (186, 1.5), (236, 0.2)])
    # уголки рта вверх и в стороны, подбородок ходит с «ха»
    e.pair('mouth', Emo.X, [(28, 7, EO), (186, 7), (236, 1)])
    e.pair('mouth', Emo.Y, [(28, -2), (186, -2), (236, 0)], mirror=True)
    e.track('chin', Emo.X, [(56, -2.5)] + beats(-3.5, -2) + [(196, -2), (236, 0)])
    e.track('muzzle', Emo.X, [(36, 1), (186, 1), (236, 0)])
    # тело: вдох перед смехом, «ха» — грудь и плечи мягко вздрагивают
    e.track('breath', Emo.SY, [(6, -0.01), (30, 0.04, EO)] + beats(0.055, 0.02, -2) + [(196, 0.02), (244, 0)])
    e.track('chest', Emo.R, [(32, 0)] + beats(-0.012, 0.0, -2) + [(244, 0)])
    e.track('hips', Emo.Y, [(14, 1.5), (40, -2.5, EO)] + beats(-3.5, -1.5, -2) + [(196, -1.5), (244, 0)])
    e.track('head', Emo.R, [(40, 0.04, EO)] + beats(0.05, 0.035) + [(196, 0.035), (244, 0)])
    e.track('face', Emo.X, [(40, 2.5, EO)] + beats(3.5, 2.2) + [(196, 2), (244, 0)])
    e.track('face', Emo.Y, [(40, 2), (196, 2), (244, 0)])
    # капюшон и уши догоняют с запаздыванием
    e.track('hood1', Emo.R, [(44, -0.02), (196, -0.015), (244, 0)])
    e.track('hood2', Emo.R, [(44, -0.05)] + beats(-0.07, -0.03, 5) + [(212, -0.02)])
    e.track('ear_l1', Emo.R, [(40, -0.06)] + beats(-0.09, -0.04, 3) + [(212, -0.02)])
    e.track('ear_r1', Emo.R, [(40, 0.06)] + beats(0.09, 0.04, 3) + [(212, 0.02)])
    e.track('ear_l2', Emo.R, [(44, -0.05)] + beats(-0.07, -0.02, 6) + [(214, -0.01)])
    e.track('ear_r2', Emo.R, [(44, 0.05)] + beats(0.07, 0.02, 6) + [(214, 0.01)])
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
    return e.build()


def emo_sad():
    """Грусть, 3 с (27.09: без подмен, всё костями). Вздох — верхние веки
    тяжелеют, брови домиком (внутренние концы вверх), уголки рта вниз,
    подбородок чуть поджат, щёки опускаются; голова клонится и опускается,
    плечи, уши и кончик капюшона никнут."""
    e = Emo(180)
    e.eyes([(10, 0.0), (50, 0.4, EO), (150, 0.38), (172, 0.0)], lid='top')
    # рот: ротик покоя переходит в широкую грустную дугу уголками вниз, и
    # нижняя губа мелко дрожит — вот-вот заплачет (обида — другой рот:
    # узкие надутые губы вбок)
    mo = [(14, 0.1, 0.0), (56, 1.15, 1.0, EO), (70, 1.15, 1.0)]
    for i, fr in enumerate(range(76, 136, 6)):
        mo.append((fr, 1.15, 1.07 if i % 2 == 0 else 0.94))
    mo += [(150, 1.1, 0.97), (172, 0.1, 0.0)]
    e.mouth_open(mo, kind='sad')
    e.track('mouth_sad', Emo.X, [(20, 0), (56, -1.5, EO), (150, -1.4), (172, 0)])
    e.pair('ulid', Emo.X, [(50, -4.5, EO), (150, -4.2), (172, 0)])
    e.track('brow_l', Emo.R, [(14, 0), (50, -0.16, EO), (150, -0.15), (172, 0)])
    e.track('brow_r', Emo.R, [(14, 0), (50, 0.16, EO), (150, 0.15), (172, 0)])
    e.pair('brow', Emo.X, [(50, 1.5), (150, 1.4), (172, 0)])
    e.pair('mouth', Emo.X, [(20, 0), (56, -3, EO), (150, -2.8), (172, 0)])
    e.track('chin', Emo.X, [(56, 1.2), (150, 1.1), (172, 0)])
    e.pair('cheek', Emo.X, [(56, -1.5), (150, -1.3), (172, 0)])
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


LIN = '0 0 1 1'


def emo_chew():
    """Жуёт, 4,1 с (заказчик 27.09: «не просто рот вверх-вниз, а прям
    эффект жевания; ротик побольше»). Как жуют в анимации: челюсть ходит
    не вверх-вниз, а по кругу — вниз-вбок, вверх через середину, и каждый
    следующий жевок в другую сторону («восьмёрка»); щёки надуваются там,
    где еда, и еда перекатывается на другую сторону; на смыкании уголки
    рта напрягаются, нос чуть поднимается, веки сжимаются; голова кивает
    в такт, уши и капюшон догоняют.

    Ход: откусил («ам» — рот широко, 0,45 с) → пять жевков по 0,6 с
    (полость жевания крупная: до 1,55 ширины и 1,4 высоты рта с фото;
    верхняя губа стоит, раскрывает рот нижняя челюсть `jaw_chew`) →
    проглотил (подбородок и голова чуть вниз, довольная улыбка) → покой.
    Все каналы — гладкие функции времени, ключи через 3 кадра, линейно:
    движение по кругу без остановок в ключах."""
    DUR = 248
    e = Emo(DUR)
    T, C0, N = 36, 30, 5                      # жевок, начало, сколько
    C1 = C0 + T * N
    side = [1, -1, 1, -1, 1]                  # куда уходит челюсть в каждом жевке
    food = [1, 1, -1, -1, 1]                  # за какой щекой еда

    def ss(a, b, t):
        return smooth(a, b, t)

    def bump(t, a, b):
        """0 → 1 → 0 синусом на [a, b]."""
        return math.sin(math.pi * (t - a) / (b - a)) ** 2 if a <= t <= b else 0.0

    def M(t):                                 # «рот полон»: держится весь жевательный отрезок
        return ss(4, 14, t) * (1 - ss(214, 236, t))

    def Env(t):                               # жевки
        return ss(26, 40, t) * (1 - ss(C1 - 12, C1 + 4, t))

    def v(t):                                 # челюсть открыта 0..1
        return (1 - math.cos(2 * math.pi * (t - C0) / T)) / 2 if C0 <= t <= C1 else 0.0

    def lat(t):                               # челюсть вбок −1..1 (по кругу)
        if not C0 <= t <= C1:
            return 0.0
        k = min(N - 1, int((t - C0) // T))
        return side[k] * math.sin(2 * math.pi * (t - C0) / T)

    def fd(t):                                # еда за щекой: −1 справа … 1 слева, перекатывается
        k = (t - C0) / T - 0.5
        i = max(0, min(N - 1, math.floor(k)))
        j = max(0, min(N - 1, i + 1))
        u = ss(0.0, 1.0, k - math.floor(k)) if k >= 0 else 0.0
        return food[i] * (1 - u) + food[j] * u

    def bite(t):
        return bump(t, 2, 28)

    def swallow(t):
        return bump(t, 210, 240)

    def content(t):
        return ss(214, 226, t) * (1 - ss(232, 244, t))

    def samp(fn, lag=0):
        return [(f, fn(f - lag), LIN) for f in range(3, DUR - 3, 3)]

    # рот (заказчик 27.09: «рот целиком ездит влево-вправо — так не
    # должно быть»): верхняя губа на месте под носом, двигается только
    # нижняя челюсть — рот раскрывается вниз, низ уходит вбок и чуть
    # наклоняется; подбородок идёт с челюстью, нос стоит
    _, top, bot = mouth.chew_rows()
    H = bot - top                              # полость жевания с фото, px

    def opn(t):                                # насколько раскрыт (1 — как на фото)
        return 0.15 * M(t) + 1.4 * bite(t) + 1.3 * Env(t) * v(t)
    e.mouth_open([(f, 1.3 * M(f) + 0.25 * bite(f) + 0.2 * Env(f) * v(f), opn(f), LIN)
                  for f in range(3, DUR - 3, 3)], kind='chew')
    # верхняя губа — к ротику покоя (его верх), дальше не двигается
    e.track('mouth_chew', Emo.X, [(2, -12.0, LIN), (DUR - 6, -12.0, LIN)])
    e.track('jaw_chew', Emo.Y, samp(lambda t: H * opn(t)))
    e.track('jaw_chew', Emo.X, samp(lambda t: 3.2 * Env(t) * lat(t)))
    e.track('jaw_chew', Emo.R, samp(lambda t: 0.09 * Env(t) * lat(t)))
    # подбородок — с челюстью: вниз и вбок; нос на смыкании чуть вверх
    e.track('chin', Emo.X, samp(lambda t: -0.32 * H * opn(t) + 0.6 * Env(t) * (1 - v(t)) - 2 * swallow(t)))
    e.track('chin', Emo.Y, samp(lambda t: 3.0 * Env(t) * lat(t)))
    e.track('muzzle', Emo.X, samp(lambda t: 0.5 * M(t) + 0.9 * Env(t) * (1 - v(t))))
    # щёки: надуты там, где еда; на смыкании сильнее
    e.track('cheek_l', Emo.SY, samp(lambda t: M(t) * (0.08 + 0.08 * max(0.0, fd(t))) + 0.05 * Env(t) * (1 - v(t))))
    e.track('cheek_r', Emo.SY, samp(lambda t: M(t) * (0.08 + 0.08 * max(0.0, -fd(t))) + 0.05 * Env(t) * (1 - v(t))))
    e.pair('cheek', Emo.X, samp(lambda t: 1.5 * M(t) + 1.0 * Env(t) * (1 - v(t))))
    # уголки рта напрягаются на смыкании; после глотка — довольная улыбка
    e.pair('mouth', Emo.X, samp(lambda t: 1.0 * M(t) + 1.5 * Env(t) * (1 - v(t)) + 2.5 * content(t)))
    # глаза: довольный прищур, на смыкании веки чуть сжимаются
    e.eyes(samp(lambda t: 0.22 * M(t) + 0.06 * Env(t) * (1 - v(t)) + 0.1 * content(t)))
    e.pair('lid', Emo.X, samp(lambda t: 5 * M(t) + 2 * Env(t) * (1 - v(t)) + 2 * content(t)))
    # голова кивает в такт и чуть покачивается за челюстью; на откусе и
    # глотке — вниз
    e.track('face', Emo.X, samp(lambda t: Env(t) * (0.8 * v(t) - 0.4) - 1.5 * bite(t) - 2 * swallow(t)))
    e.track('head', Emo.R, samp(lambda t: 0.015 * M(t) + 0.01 * Env(t) * lat(t)))
    e.track('breath', Emo.SY, samp(lambda t: 0.015 * M(t) + 0.008 * Env(t) * v(t) + 0.02 * swallow(t)))
    e.track('ear_l1', Emo.R, samp(lambda t: -0.03 * Env(t) * v(t), 4))
    e.track('ear_r1', Emo.R, samp(lambda t: 0.03 * Env(t) * v(t), 4))
    e.track('hood2', Emo.R, samp(lambda t: -0.025 * Env(t) * v(t) + 0.02 * swallow(t), 6))
    return e.build()


def emo_lick():
    """Смакует, 2,6 с (27.09: без подмен; язык, который просто появлялся,
    убран). Блаженно прищурился, щёки подняты, ротик покоя переходит в
    сомкнутую довольную улыбку, и два «ням» — губы поджимаются и
    отпускаются, подбородок и нос ходят, голова покачивается набок."""
    e = Emo(156)
    s_ = [22, 58]                              # «ням»: губы поджаты через 12 кадров, отпущены через 30
    # рот: сомкнутая довольная улыбка; на «ням» губы поджимаются и
    # растягиваются, затем отпускаются
    mo = [(8, 0.1, 0.0), (22, 1.0, 1.0, EO)]
    for a in s_:
        mo += [(a + 12, 1.1, 0.7), (a + 30, 1.0, 1.0)]
    mo += [(124, 1.0, 1.0), (146, 0.1, 0.0)]
    e.mouth_open(mo, kind='content')
    e.eyes([(6, 0.0), (30, 0.4, EO), (124, 0.38), (148, 0.0)])
    e.pair('lid', Emo.X, [(30, 10, EO), (124, 9.5), (148, 0)])
    e.pair('eye', Emo.SX, [(30, -0.05), (124, -0.045), (148, 0)])
    e.pair('cheek', Emo.X, [(30, 4, EO), (124, 3.8), (148, 0)])
    e.pair('cheek', Emo.SY, [(30, 0.06), (124, 0.055), (148, 0)])
    e.pair('mouth', Emo.X, [(14, 4, EO), (124, 4), (148, 0)])
    pts_c, pts_m = [(10, 0)], [(10, 0)]
    for a in s_:
        pts_c += [(a + 12, -2.2), (a + 30, 0.6)]
        pts_m += [(a + 12, -0.4), (a + 30, 1.0)]
    e.track('chin', Emo.X, pts_c + [(120, 0)])
    e.track('muzzle', Emo.X, pts_m + [(120, 0)])
    e.track('head', Emo.R, [(24, 0.04, EO), (60, 0.025), (94, 0.045), (130, 0.035)])
    e.track('face', Emo.Y, [(24, 3), (60, 1.5), (94, 3), (130, 2.5)])
    e.track('face', Emo.X, [(24, 1.5), (130, 1.2)])
    e.track('breath', Emo.SY, [(20, 0.025), (90, 0.02), (130, 0.015)])
    e.track('hood2', Emo.R, [(28, -0.05), (50, 0.03), (70, -0.02), (100, 0.02)])
    e.track('ear_r1', Emo.R, [(22, 0.06), (44, -0.02), (96, 0.04)])
    e.track('ear_l1', Emo.R, [(24, -0.04), (46, 0.02), (98, -0.03)])
    return e.build()


def emo_yawn():
    """Зевок, 3,6 с (заказчик 27.09: без подмен, мягко — «растяжками,
    ригом»). Лицо покоя, всё костями: глубокий вдох — глаза зажмуриваются
    (веки из меха сходятся), рот медленно раскрывается костью в высокое
    «о» (`Emo.mouth_open`, полость зевка), подбородок опускается,
    мордочка вытягивается, щёки сужаются, брови вверх, голова запрокинута,
    грудь полная. На вершине рот чуть дрожит; выдох — рот медленно
    смыкается, глаза ещё закрыты, открыл, встряхнул головой, уши
    хлопнули. Руки не поднимает."""
    e = Emo(216)
    e.mouth_open([(10, 0.1, 0.0), (40, 0.6, 0.35), (74, 1.0, 1.0, EO), (104, 0.96, 0.93),
                  (120, 1.0, 0.98), (148, 0.6, 0.3), (166, 0.3, 0.0)], kind='yawn')
    # полость опускается вместе с челюстью — верх рта не наползает на нос
    e.track('mouth_yawn', Emo.X, [(10, 0), (74, -6, EO), (120, -5.6), (160, 0)])
    # глаза зажмурились: бусины сплющены, нижние и верхние веки сходятся
    e.eyes([(6, 0.0), (44, 0.72, EO), (150, 0.7), (180, 0.0)], lid='both')
    e.pair('lid', Emo.X, [(44, 9, EO), (150, 8.5), (180, 0)])
    e.pair('ulid', Emo.X, [(44, -5, EO), (150, -4.5), (180, 0)])
    e.pair('eye', Emo.SX, [(44, -0.1), (150, -0.09), (180, 0)])
    e.pair('brow', Emo.X, [(50, 3, EO), (140, 2.5), (176, 0)])
    # челюсть вниз, мордочка тянется, щёки уже
    e.track('chin', Emo.X, [(20, -1), (74, -5, EO), (120, -4.6), (160, 0)])
    e.track('chin', Emo.SX, [(74, 0.06), (120, 0.055), (160, 0)])
    e.track('muzzle', Emo.SX, [(74, 0.08, EO), (120, 0.075), (160, 0)])
    e.pair('cheek', Emo.SY, [(74, -0.04), (120, -0.035), (160, 0)])
    e.pair('cheek', Emo.X, [(74, -1.5), (120, -1.3), (160, 0)])
    e.pair('mouth', Emo.Y, [(74, 1.5), (120, 1.4), (160, 0)], mirror=True)
    e.pair('mouth', Emo.X, [(24, 3), (74, 1), (150, 1), (170, 0)])
    # тело: глубокий вдох, потянулся вверх, голова назад; выдох — осел
    e.track('breath', Emo.SY, [(20, 0.03), (74, 0.09, EO), (120, 0.08), (166, -0.02), (190, 0)])
    e.track('chest', Emo.R, [(74, -0.035), (125, -0.03), (166, 0.005)])
    e.track('hips', Emo.Y, [(74, -5, EO), (120, -4), (166, 2), (190, 0)])
    e.track('face', Emo.X, [(74, 5, EO), (125, 4.5), (160, 0)])
    # встряхнул головой после зевка
    e.track('head', Emo.R, [(74, -0.05, EO), (125, -0.045), (158, 0), (170, 0.018), (182, -0.014),
                            (194, 0.006), (204, 0)])
    e.track('ear_l1', Emo.R, [(74, 0.1), (125, 0.08), (172, -0.05), (184, 0.04), (196, -0.01)])
    e.track('ear_r1', Emo.R, [(74, -0.1), (125, -0.08), (172, 0.05), (184, -0.04), (196, 0.01)])
    e.track('ear_l2', Emo.R, [(80, 0.06), (130, 0.05), (176, -0.05), (188, 0.03)])
    e.track('ear_r2', Emo.R, [(80, -0.06), (130, -0.05), (176, 0.05), (188, -0.03)])
    e.track('hood2', Emo.R, [(80, -0.07), (130, 0.04), (176, -0.04), (190, 0.02)])
    return e.build()


def emo_sleepy():
    """Сонный, 3,5 с (27.09: без подмен). Верхние веки тяжелеют, голова
    клюёт вниз — веки сомкнулись, задремал; мягко вздрогнул (0,4 с) —
    глаза открылись, голова вверх; и снова веки медленно тяжелеют. Рот:
    ротик покоя переходит в расслабленную сонную линию, в дрёме она
    чуть опускается."""
    e = Emo(210)
    e.mouth_open([(16, 0.1, 0.0), (56, 1.0, 1.0, EO), (118, 1.05, 1.3), (132, 1.05, 1.3),
                  (160, 1.0, 1.0), (194, 1.0, 1.0), (206, 0.1, 0.0)], kind='sleepy')
    e.eyes([(8, 0.0), (40, 0.45, EO), (84, 0.5), (118, 0.9), (132, 0.9), (156, 0.02),
            (172, 0.1), (196, 0.45)], lid='top')
    e.pair('ulid', Emo.X, [(40, -4, EO), (84, -4.5), (118, -8), (132, -8), (156, 0),
                           (172, -1), (196, -4)])
    e.pair('lid', Emo.X, [(84, 0), (118, 3), (132, 3), (156, 0)])
    e.pair('brow', Emo.X, [(40, -0.8), (118, -1.2), (156, 1.5), (172, 0.5), (196, -0.6)])
    e.track('face', Emo.X, [(90, -3), (126, -8), (156, 0), (176, -2)])
    e.track('head', Emo.R, [(126, 0.04), (156, 0), (176, 0.015)])
    e.track('hips', Emo.Y, [(126, 3), (156, -1), (176, 0.5)])
    e.track('breath', Emo.SY, [(60, 0.04), (110, -0.03), (156, 0.02), (176, 0)])
    e.track('chin', Emo.X, [(110, -1), (128, -1), (156, 0)])
    e.track('ear_l1', Emo.R, [(126, 0.12), (156, -0.02), (176, 0.05)])
    e.track('ear_r1', Emo.R, [(126, -0.12), (156, 0.02), (176, -0.05)])
    e.track('hood2', Emo.R, [(130, 0.06), (152, -0.03), (176, 0.02)])
    e.track('arm_l1', Emo.R, [(126, -0.03), (140, 0.01)])
    e.track('arm_r1', Emo.R, [(126, 0.03), (140, -0.01)])
    return e.build()


def emo_upset():
    """Обиделся, 3 с: моргнул — надулся: веки тяжёлые, губы надуты, щёки
    круглые; топнул левой, правой, левой, правой — мягко (колено поднимается,
    вес переходит на другую ногу, ступня встаёт, тело чуть вздрагивает); «хмф!» —
    отвернулся и закрыл глаза, уши прижаты."""
    e = Emo(180)
    # надулся (27.09: без подмен, костями): веки тяжёлые, щёки круглые,
    # губы поджаты — уголки вниз и к середине, подбородок вверх; на «хмф!» —
    # отвернулся, глаза закрыл (заказчик 26.09: злые глаза не нужны)
    # рот: надутые губы поджаты — короткие, узкие, сдвинуты вбок с перекосом, как у
    # дующегося ребёнка; на «хмф!» — ещё дальше вбок и туже (грусть —
    # другой рот: широкая дрожащая дуга)
    e.mouth_open([(8, 0.1, 0.0), (24, 0.62, 0.55, EO), (124, 0.62, 0.55), (140, 0.5, 0.7, EO),
                  (160, 0.5, 0.7), (174, 0.1, 0.0)], kind='pout')
    e.track('mouth_pout', Emo.Y, [(8, 0), (24, 6, EO), (124, 6), (140, 8, EO), (160, 8), (174, 0)])
    e.track('mouth_pout', Emo.R, [(8, 0), (24, 0.13, EO), (124, 0.13), (140, 0.2, EO), (160, 0.2), (174, 0)])
    e.eyes([(6, 0.0), (22, 0.32, EO), (124, 0.3), (140, 0.88, EO), (152, 0.88), (170, 0.0)], lid='top')
    e.pair('ulid', Emo.X, [(22, -3, EO), (124, -3), (140, -8, EO), (152, -8), (170, 0)])
    e.pair('lid', Emo.X, [(124, 0), (140, 3), (152, 3), (170, 0)])
    e.pair('cheek', Emo.X, [(20, 1, EO), (160, 0.8)])
    e.pair('mouth', Emo.X, [(20, -2.5, EO), (160, -2.2), (172, 0)])
    e.pair('mouth', Emo.Y, [(20, 1.8, EO), (160, 1.6), (172, 0)], mirror=True)
    e.track('chin', Emo.X, [(20, 2, EO), (160, 1.8), (172, 0)])
    e.track('muzzle', Emo.SX, [(20, 0.04, EO), (160, 0.035), (172, 0)])
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
            [(at, 0), (at + 10, -17, EO), (at + 13, -17), (at + 20, 0.5), (at + 24, 0)])
        legs.setdefault((f'shin_{side}', Emo.R), []).extend(
            [(at, 0), (at + 10, 0.035 * out, EO), (at + 13, 0.035 * out), (at + 19, 0.0)])
        legs.setdefault((f'shin_{side}', Emo.SY), []).extend(
            [(at, 0), (at + 10, 0.05, EO), (at + 19, 0.0)])
        legs.setdefault((f'leg_{side}', Emo.R), []).extend(
            [(at, 0), (at + 10, 0.045 * out, EO), (at + 19, 0.0)])
        # вес — на другую ногу; при подъёме чуть вверх, удар — осел
        hips_x += [(at + 7, -2 * out, EO), (at + 23, 0.0)]
        hips_y += [(at + 10, -0.8, EO), (at + 20, 1.0), (at + 26, 0.0)]
        head_r += [(at + 20, 0.01 * out), (at + 29, 0.0)]
        face_x += [(at + 20, -0.6), (at + 26, 0.0)]
        ears += [(at + 20, 0.035), (at + 28, 0.0)]
        arms += [(at + 19, 0.02), (at + 25, 0.0)]
    for (name, key), pts in legs.items():
        e.track(name, key, pts)
    e.track('hips', Emo.X, hips_x)
    e.track('hips', Emo.Y, merged([(16, 3), (120, 3), (140, 3.5)], hips_y))
    e.track('head', Emo.R, merged([(20, -0.012), (124, -0.012), (140, -0.045, EO), (160, -0.04)], head_r))
    e.track('face', Emo.X, face_x)
    e.track('face', Emo.Y, [(124, 0), (140, -6, EO), (160, -5.5)])
    e.pair('cheek', Emo.SY, [(18, 0.12, EO), (160, 0.1)])
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
        'forearm_left': 'hand_l', 'forearm_right': 'hand_r',
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
        if name.startswith('mouth_') and name[6:] in mouth.KINDS:   # в покое рот сомкнут
            sx, sy = mouth.closed(name[6:])
            attrs.update(scaleX=fmt(sx), scaleY=fmt(sy))
        if name == 'jaw_chew':        # в покое челюсть поднята к губе — полость сомкнута
            _, top, bot = mouth.chew_rows()
            attrs['y'] = fmt(top - bot)
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
    ids = iter(range(10000, 10 ** 7))
    added = mesh_refine.refine(face, fm.apply, FACE_REFINE, lambda: ident(next(ids)))
    print('face mesh +', added, 'points')
    eyes = [(byname['gaze_socket_l_img'], byname['gaze_bead_l_img']),
            (byname['gaze_socket_r_img'], byname['gaze_bead_r_img'])]
    byname['lid_patch_img'] = lids.build(project, root, ab, W, byname, fm, eyes, lambda: ident(next(ids)))
    # 4в. Выражения лица целиком поверх бусин и век (faces.py).
    for n, fid in faces.build(project, root, ab, byname, lambda: ident(next(ids))).items():
        E_IDS[f'face_{n}'] = fid
    # 4в'. Полость рта над лицом, под выражениями (mouth.py).
    for n, mid in mouth.build(project, root, ab, byname, lambda: ident(next(ids))).items():
        E_IDS[f'mouth_{n}_img'] = mid
    # 4г. Расправленная кофта у подмышек поверх кофты (crease.py).
    for side, cid in crease.build(project, root, ab, byname, lambda: ident(next(ids))).items():
        E_IDS[f'flat_{side}'] = cid

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
