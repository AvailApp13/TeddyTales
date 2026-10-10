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
import os

import numpy as np
from PIL import Image
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from xf import M, f, world_map  # noqa: E402
import mesh_refine  # noqa: E402
import lids  # noqa: E402
import faces  # noqa: E402
import crease  # noqa: E402
import mouth  # noqa: E402
import underpaint  # noqa: E402

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
    ('hood2',   'hood1',  None,         (517, 110)),     # кончик — hood3 (10.10)
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
    ('ear_l2',  'ear_l1', None,         (362, 261)),     # кончик — ear_l3 (10.10)
    ('ear_r1',  'head',   (605, 322),   (637, 290)),
    ('ear_r2',  'ear_r1', None,         (665, 260)),     # кончик — ear_r3 (10.10)
    # руки (27.09, «три звена»): плечо → середина → предплечье до манжеты,
    # кисть — в конце списка (hand_l/r), за ней едет лапа
    # ось плеча — в середине толщины руки у корня (между верхом рукава и
    # подмышкой), как центр круглого сустава в Live2D/перекладке
    # ключицы (10.10): плечи поднимаются и опускаются — вдох, вздох, смех,
    # зевок, грусть; рука держится за ключицу
    ('clav_l',  'chest',  (470, 548),   (368, 556)),
    ('clav_r',  'chest',  (564, 548),   (656, 556)),
    ('arm_l1',  'clav_l', (368, 556),   (342, 591)),
    ('arm_l2',  'arm_l1', None,         (316, 626)),
    ('arm_r1',  'clav_r', (656, 556),   (682, 591)),
    ('arm_r2',  'arm_r1', None,         (708, 626)),
    # ноги (10.10): бедро держится за таз, колено — с небольшим запасом
    # изгиба наружу (KNEE_OUT), иначе прямая нога не знала бы, куда гнуться;
    # стопы — свои кости в конце списка, стоят на полу (leg_ik)
    ('leg_l',   'hips',   (430, 790),   (430 - 16, 872)),
    ('leg_r',   'hips',   (607, 790),   (607 + 16, 872)),
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
    ('shin_l',  'leg_l',  None,         (430, 952)),
    ('shin_r',  'leg_r',  None,         (607, 952)),
    ('arm_l3',  'arm_l2', None,         (290, 662)),
    ('hand_l',  'arm_l3', None,         (258, 703)),
    ('arm_r3',  'arm_r2', None,         (734, 662)),
    ('hand_r',  'arm_r3', None,         (766, 703)),
    # бок кофты под рукой (поправочная кость, как в Spine/Live2D): пока
    # рука поднята немного, низ бока идёт за ней — рука не «отлипает»
    # трещиной; дальше кость упирается (SIDE_CAP), подмышка раскрывается.
    # Держится за ключицу, как и рука: плечо поднимается — бок под рукой
    # поднимается вместе с рукавом (10.10: за грудью он оставался на месте,
    # и в смехе и зевке под мышкой открывалась щель)
    ('side_l',  'clav_l', (368, 556),   (340, 700)),
    ('side_r',  'clav_r', (656, 556),   (684, 700)),
    # рот раскрывается масштабом этих костей (mouth.py): горизонтальные,
    # в покое сжаты до щёлочки (mouth.CAVITIES); open — смех и улыбка,
    # yawn — зевок, chew — жевание
] + [(f'mouth_{n}', 'face', mouth.center(n), (mouth.center(n)[0] + 20, mouth.center(n)[1]))
     for n in mouth.KINDS] + [
] + [
    # нижняя челюсть жевания и зевка: низ полости (mouth.py)
    (f'jaw_{n}', f'mouth_{n}', mouth.rows(n)[::2], (mouth.rows(n)[0] + 20, mouth.rows(n)[2]))
    for n in mouth.JAW
] + [
    # Живое лицо (заказчик 10.10: «двигается только кусочек лица — лоб,
    # щёки, подбородок как будто стоят»): лоб — середина и бока, «яблочки»
    # щёк под глазами, скулы у края капюшона, челюсть под ротиком, кончик
    # носа. Все — дети лица, как прежняя мимика; ведут их связки COUPLE.
    ('fore_c',  'face',   (512, 343),   (512, 333)),
    ('fore_l',  'face',   (452, 354),   (452, 344)),
    ('fore_r',  'face',   (573, 354),   (573, 344)),
    ('apple_l', 'face',   (450, 457),   (450, 447)),
    ('apple_r', 'face',   (575, 457),   (575, 447)),
    ('zyg_l',   'face',   (404, 448),   (404, 438)),
    ('zyg_r',   'face',   (621, 448),   (621, 438)),
    ('jaw',     'face',   (513, 534),   (513, 524)),
    ('nose',    'face',   (513, 468),   (513, 458)),
    # стопы (10.10): стоят на полу, за ними едут лапы ног; притоп и шаг —
    # подъём стопы, колено сгибается само (leg_ik)
    ('foot_l',  None,     (430, 952),   (430, 982)),
    ('foot_r',  None,     (607, 952),   (607, 982)),
    # кончики ушей и капюшона (10.10): их докачивает пружина в приложении
    # (rive_bear_trial.dart, «Докачка») — по настоящему движению головы
    ('ear_l3',  'ear_l2', None,         (340, 238)),
    ('ear_r3',  'ear_r2', None,         (688, 236)),
    ('hood3',   'hood2',  None,         (517, 42)),
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
# 290+: кости эмоций занимают 200 + номер кости, и с 10.10 их больше 60.
WRAP_IDS = {k: ident(290 + i) for i, k in enumerate(WRAPS)}
# Обёртки — Node, а не кости: сдвиг у Node — ключи 13/14 (x/y), у кости —
# 90/91. Эмоции пишут сдвиг бусин «костяным» ключом, как у всех, а при
# записи он переводится. До 10.10 не переводился, и рантайм молча
# пропускал ключ: в улыбке и смехе глаза не поднимались, в грусти не
# опускались (заказчик 10.10: «включить»). Ловит check_keys.
NODE_XY = {90: 13, 91: 14}

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


# Воротник (заказчик 27.09, обвёл зону под подбородком: «практически везде,
# где есть движение головы, — разрывы»). Нижний край капюшона, низ мордочки
# и задняя часть капюшона ходили за головой, а воротник кофты под ними — за
# грудью: голова наклоняется, край капюшона уезжает на 5–10 px по бокам, и
# из-под него показывается срезанный верх кофты. Как «сварка» швов в
# Spine/Live2D, только полосой: у линии воротника все эти слои берут веса
# кофты в той же точке и ходят вместе с ней, а выше, на 22 px, плавно
# переходят к своим — это растяжка, а не разрыв. Линия — нижний край
# капюшона в покое (по кадру): в середине y 553, к бокам 535.
COLLAR_RAMP = (34, 4)          # растяжка мордочки над воротником: выше линии, ниже линии, px


def collar_y(x):
    """Горловина — нижний край капюшона в покое: в середине y 553, к бокам
    поднимается до 535 (x ± 177), дальше уходит вниз к плечу."""
    dx = abs(x - 517)
    if dx <= 177:
        return 553 - 18 * (dx / 177) ** 2
    return 535 + (dx - 177)


def collar_share(x, y):
    """Доля весов кофты у мордочки над воротником (только середина)."""
    dx = abs(x - 517)
    yc = collar_y(x)
    up = COLLAR_RAMP[0] + 30 * min(1.0, dx / 177) ** 2
    return smooth(yc - up, yc + COLLAR_RAMP[1], y) * (1 - smooth(115, 160, dx))


def hood_neck(x, y):
    """Капюшон пришит к кофте по горловине (заказчик 27.09: «излом», «как
    у человека: голова — шея подтягивается»). Доля весов кофты у точки
    капюшона: 1 на горловине и ниже, 0 у виска и выше, между ними —
    плавная растяжка, как шея: посередине короткая (45 px над
    воротником), по бокам длинная (до 175 px — от плеча почти до виска).
    Одно поле на весь низ капюшона — без границы «пришито / свободно»,
    на которой ломался контур. Поверх этого боковины и конус ходят за
    головой, а вся кромка стоит на кофте и дышит с ней."""
    dx = abs(x - 517)
    yc = collar_y(x)
    ramp = 45 + 130 * smooth(50, 177, dx)
    return 1 - smooth(0, ramp, yc - y)


# Текстура → мир у всех слоёв тела одна (подобрано по сеткам, ошибка 0):
# мир = TEX_K · пиксель + TEX_T. Карта расстояний до контура мордочки
# (в пикселях мира) — заполняет main(), для `face_dist`.
TEX_K, TEX_T = 0.6298, (85.9289, -149.3001)
FACE_DIST = None


def face_dist(x, y):
    """Расстояние от точки мира до контура мордочки, px (0 внутри)."""
    if FACE_DIST is None:
        return 1e9
    u = int(round((x - TEX_T[0]) / TEX_K))
    v = int(round((y - TEX_T[1]) / TEX_K))
    h, w = FACE_DIST.shape
    if 0 <= u < w and 0 <= v < h:
        return float(FACE_DIST[v, u]) * TEX_K
    return 1e9


def weights_for(layer, x, y, B):
    w = _pinned(layer, x, y, B)
    if layer.startswith(_HOOD):
        k = hood_neck(x, y)
        # кромка капюшона вокруг лица обнимает мордочку и ходит с ней
        # (иначе между лицом и кромкой просвет): в 8 px от контура лица —
        # веса лица в этой точке, к 45 px — свои
        rim = 1 - smooth(8, 45, face_dist(x, y))
        if rim > 0:
            fw = _weights_for('face_img', x, y, B)
            fk = collar_share(x, y)
            if fk > 0:
                sh = _weights_for('shirt_img', x, y, B)
                fw = {b: fw.get(b, 0) * (1 - fk) + sh.get(b, 0) * fk for b in set(fw) | set(sh)}
            w = {b: w.get(b, 0) * (1 - rim) + fw.get(b, 0) * rim for b in set(w) | set(fw)}
            k *= 1 - rim
    elif layer.startswith('face_') and not layer.startswith('face_mouth'):
        k = collar_share(x, y)
    else:
        k = 0.0
    if k > 0:
        shirt = _weights_for('shirt_img', x, y, B)
        w = {b: w.get(b, 0) * (1 - k) + shirt.get(b, 0) * k for b in set(w) | set(shirt)}
        w = {b: v for b, v in w.items() if v > 1e-4}
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
    if layer[6:-4] in mouth.JAW and layer.startswith('mouth_'):   # верх — губа, низ — челюсть
        n = layer[6:-4]
        _, top, bot = mouth.rows(n)
        k = min(1.0, max(0.0, (y - top) / (bot - top)))
        return {b: v for b, v in ((f'mouth_{n}', 1 - k), (f'jaw_{n}', k)) if v > 1e-4}
    if layer.startswith('mouth_') and layer.endswith('_img'):
        return {layer[:-4]: 1.0}
    if layer in ('face_img', 'lid_patch_img') or layer.startswith('face_'):
        d = math.hypot((x - 512) / 118, (y - 425) / 108)
        k = 1 - smooth(0.8, 1.22, d)
        w = {'face': k, 'head': 1 - k} if k < 1 else {'face': 1.0}
        # Зоны влияния мимики. С 10.10 лицо покрыто почти целиком: лоб,
        # «яблочки» под глазами, скулы, челюсть и нос — свои зоны, брови и
        # подбородок шире; соседние зоны перекрываются, и ткань лица
        # тянется целиком, а не пятнами вокруг точек.
        zones = [('eye_l', 456, 416, 42, 34), ('eye_r', 568, 416, 42, 34),
                 ('cheek_l', 440, 470, 50, 38), ('cheek_r', 584, 470, 50, 38),
                 ('brow_l', 457, 377, 46, 16), ('brow_r', 568, 377, 46, 16),
                 ('ulid_l', 457, 392, 34, 10), ('ulid_r', 568, 392, 34, 10),
                 ('lid_l', 457, 443, 34, 13), ('lid_r', 568, 443, 34, 13),
                 ('muzzle', 513, 470, 34, 26),
                 ('mouth', 514, 504, 11, 8),
                 ('mouth_l', 501, 511, 11, 10), ('mouth_r', 526, 513, 11, 10),
                 ('chin', 513, 523, 38, 16),
                 ('fore_c', 512, 340, 74, 30),
                 ('fore_l', 452, 352, 46, 26), ('fore_r', 573, 352, 46, 26),
                 ('apple_l', 450, 458, 34, 18), ('apple_r', 575, 458, 34, 18),
                 ('zyg_l', 402, 448, 36, 58), ('zyg_r', 623, 448, 36, 58),
                 ('jaw', 513, 536, 84, 24),
                 ('nose', 513, 468, 26, 18)]
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
        w = chain_weights(y, [('head', 318), ('hood1', 185), ('hood2', 110), ('hood3', -1e9)], blend=58)
        side = smooth(125, 195, abs(x - 517)) * smooth(300, 370, y)
        if side > 0:
            bone = 'hood_sl' if x < 517 else 'hood_sr'
            w = {b: v * (1 - side) for b, v in w.items()}
            w[bone] = w.get(bone, 0) + side
        # низ, лежащий на плечах, держится за кофту — полосой воротника
        # в weights_for (раньше — «драпировкой» к груди только по бокам, и
        # мордочка рядом ходила за головой — у скул был разрыв)
        return w
    if layer.startswith('ear_l') or layer.startswith('ear_r'):
        # голова → основание → середина → кончик (кончик с 10.10 — своё
        # звено, его докачивает пружина)
        s_ = layer[4]
        t = along((x, y), B[f'ear_{s_}1']['start'], B[f'ear_{s_}3']['end'])
        return {b: v for b, v in blend_chain(t, ['head', f'ear_{s_}1', f'ear_{s_}2', f'ear_{s_}3'],
                                             [(0.22, 0.5), (0.58, 0.88), (0.82, 0.98)]).items() if v > 1e-4}
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

# Объёмный поворот головы (заказчик 10.10). Лицо в капюшоне сдвигается
# вбок (y кости лица) или вверх (x) — детали ближе к зрителю уходят дальше,
# дальние отстают: нос дальше всех, мордочка — меньше, лоб, скулы и челюсть
# отстают, уши поворачиваются в обратную сторону. (кость, ключ, от какого
# сдвига лица — 'y' вбок / 'x' вверх, доля).
TURN = [('nose', 91, 'y', 0.35), ('muzzle', 91, 'y', 0.18), ('fore_c', 91, 'y', -0.12),
        ('zyg_l', 91, 'y', -0.15), ('zyg_r', 91, 'y', -0.15), ('jaw', 91, 'y', -0.08),
        ('nose', 90, 'x', 0.3), ('fore_c', 90, 'x', -0.15), ('jaw', 90, 'x', -0.1)]
EAR_TURN = -0.004   # рад на пиксель сдвига лица вбок: 13 px — ~3° против поворота
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
    # корпус: заметный вдох, на выдохе присел — колени чуть сгибаются (leg_ik)
    add('hips', Y, lambda t: rest['hips']['y'] - 5.0 * wave(t))
    for side in ('l', 'r'):
        add(f'leg_{side}', R, lambda t, s_=side: rest[f'leg_{s_}']['rotation']
            + leg_ik(s_, dy=-5.0 * wave(t), bend=KNEE_BEND_BREATH)[0])
        add(f'shin_{side}', R, lambda t, s_=side: rest[f'shin_{s_}']['rotation']
            + leg_ik(s_, dy=-5.0 * wave(t), bend=KNEE_BEND_BREATH)[1])
        add(f'leg_{side}', SX, lambda t, s_=side: leg_ik(s_, dy=-5.0 * wave(t), bend=KNEE_BEND_BREATH)[2])
    add('belly', R, lambda t: rest['belly']['rotation'] - 0.012 * wave(t, 4))
    add('breath', SY, lambda t: 1 + 0.065 * (wave(t) + 1) / 2)              # грудь шире
    # плечи на вдохе чуть поднимаются — ключицы (10.10)
    add('clav_l', R, lambda t: rest['clav_l']['rotation'] + 0.5 * 0.065 * (wave(t, 6) + 1) / 2)
    add('clav_r', R, lambda t: rest['clav_r']['rotation'] - 0.5 * 0.065 * (wave(t, 6) + 1) / 2)
    add('breath', SX, lambda t: 1 + 0.04 * (wave(t, 3) + 1) / 2)
    add('chest', R, lambda t: rest['chest']['rotation'] + 0.02 * wave(t, 6))
    add('neck', R, lambda t: rest['neck']['rotation'] - 0.014 * wave(t, 10))
    # голова: вдох + медленное покачивание + наклон, когда осматривается
    add('head', R, lambda t: rest['head']['rotation'] + 0.03 * wave(t, 14)
        + 0.016 * math.sin(2 * math.pi * t / SWAY) + 0.07 * look(t)[2])
    # лицо внутри капюшона: поворот влево-вправо, взгляд вверх
    add('face', Y, lambda t: rest['face']['y'] + 13 * look(t)[0])
    add('face', X, lambda t: rest['face']['x'] + 7 * look(t)[1] + 1.2 * wave(t, 12))
    # Живое лицо в покое (заказчик 10.10: «лоб, щёки, подбородок будто
    # стоят»). Объёмный поворот: нос — ближе всех к зрителю — уходит дальше
    # лица, лоб, скулы и челюсть отстают (доли TURN, те же, что у эмоций).
    # И лицо дышит вместе с мишкой: брови и лоб чуть поднимаются на вдохе и
    # когда он смотрит вверх, мордочка и нос приподнимаются, челюсть на
    # выдохе мягко опускается, дважды за петлю он принюхивается.
    life = {}

    def more(name, key, fn):
        life.setdefault((name, key), []).append(fn)

    for name, key, src, k in TURN:
        more(name, key, lambda t, i=src, kk=k: kk * (13 * look(t)[0] if i == 'y' else 7 * look(t)[1]))

    def brow(t):
        return 0.6 * wave(t, 40) + 1.6 * look(t)[1]

    for side in ('l', 'r'):
        more(f'brow_{side}', X, brow)
        more(f'fore_{side}', X, brow)
    more('fore_c', X, brow)
    more('muzzle', X, lambda t: 0.35 * wave(t, 10))
    sniffs = [(300, 1.4), (318, 1.0), (640, 1.2)]
    more('nose', X, lambda t: 0.35 * wave(t, 10)
         + sum(a * max(0.0, 1 - abs(t - c) / 7) ** 2 for c, a in sniffs))
    more('jaw', X, lambda t: -0.9 * (1 - wave(t, 24)) / 2)
    more('zyg_l', X, lambda t: 0.45 * 0.6 * wave(t, 18))
    more('zyg_r', X, lambda t: 0.45 * 0.6 * wave(t, 18))
    for (name, key), fns in life.items():
        if name in rest:
            add(name, key, lambda t, n=name, ky=key, fs=fns:
                rest[n].get({X: 'x', Y: 'y', R: 'rotation'}[ky], 0.0) + sum(fn(t) for fn in fs))
    # капюшон: кончик и боковины догоняют и перелетают
    add('hood1', R, lambda t: rest['hood1']['rotation'] - 0.018 * wave(t, 22)
        - 0.015 * math.sin(2 * math.pi * (t - 30) / SWAY) - 0.015 * look(t)[2])
    add('hood2', R, lambda t: rest['hood2']['rotation'] - 0.08 * wave(t, 34)
        - 0.025 * math.sin(2 * math.pi * (t - 45) / SWAY) + 0.015 * wave(t * 2, 60)
        - 0.05 * look(t - 12)[2])
    add('hood_sl', R, lambda t: rest['hood_sl']['rotation'] + 0.03 * wave(t, 20) - 0.025 * look(t - 8)[2])
    add('hood_sr', R, lambda t: rest['hood_sr']['rotation'] - 0.03 * wave(t, 20) - 0.025 * look(t - 8)[2])
    # уши: по диагонали к капюшону и складываются к основанию; иногда вздрагивают
    add('ear_l1', R, lambda t: rest['ear_l1']['rotation'] + 0.06 * wave(t, 26) + 0.07 * ear(t, 'l')
        + EAR_TURN * 13 * look(t)[0])
    add('ear_l2', R, lambda t: rest['ear_l2']['rotation'] + 0.09 * wave(t, 38) + 0.12 * ear(t - 3, 'l'))
    add('ear_l1', SX, lambda t: 1 - 0.07 * (wave(t, 30) + 1) / 2 - 0.06 * ear(t, 'l'))
    add('ear_r1', R, lambda t: rest['ear_r1']['rotation'] - 0.06 * wave(t, 26) - 0.07 * ear(t, 'r')
        + EAR_TURN * 13 * look(t)[0])
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
# моргания в idle_life (кадр, когда бусины сплющены сильнее всего; 12 с);
# 603 — второе, быстрое, сразу за 588: двойное моргание (10.10)
BLINKS = [63, 223, 255, 455, 588, 603]
DOUBLE_BLINK = (588, 15)     # какое моргание повторить и через сколько кадров

# Быстрые движения глаз (10.10, «мелочи живости»): бусины чуть
# перескакивают по горизонтали и держатся, раз в 1–3 с; перед поворотом
# головы глаза уходят туда первыми. (кадр, сдвиг px)
SACCADES = [(0, 0.0), (44, 1.2), (128, -0.9), (300, 0.7), (352, -1.1), (470, 0.9),
            (612, -0.6), (690, 0.0)]
EYES_LEAD = 10        # на сколько кадров глаза опережают поворот головы
EYES_TURN = 2.6       # px сдвига бусин при полном повороте

EI = '0.42 0 0.58 1'
EO = '0 0 0.58 1'
EIN = '0.42 0 1 1'
BACK = '0.34 1.56 0.64 1'


def saccades():
    """Бусины по горизонтали в покое: скачки SACCADES (переход за 4 кадра) и
    упреждение поворота головы."""
    def look_x(t):
        return sum(v * pulse(t, a, b, 40) for a, b, v, *_ in LOOKS)

    def jump(t):
        prev = SACCADES[0][1]
        for (f0, v0), (f1, v1) in zip(SACCADES, SACCADES[1:]):
            if t < f1:
                return v0
            if t < f1 + 4:
                return v0 + (v1 - v0) * smooth(f1, f1 + 4, t)
            prev = v1
        return prev

    out = {}
    for wrap in ('bead_l', 'bead_r'):
        x0 = E_REST[wrap]['x']
        out[wrap] = [(t, x0 + jump(t) + EYES_TURN * look_x(t + EYES_LEAD)) for t in range(0, DUR + 1, 2)]
    return out


def double_blink(idle):
    """Повторить моргание DOUBLE_BLINK через несколько кадров — двойное.
    Ключи бусин в покое плотные (из исходника): новое значение — меньшее из
    своего и сдвинутого."""
    at, lag = DOUBLE_BLINK
    for bead in (BEAD_L, BEAD_R):
        ko = next((k for k in idle.findall('KeyedObject') if k.get('objectId') == bead), None)
        if ko is None:
            continue
        for kp in ko.findall('KeyedProperty'):
            if kp.get('propertyKey') not in ('17', '18'):
                continue
            keys = sorted(((int(k.get('frame', '0')), float(k.get('value', '0'))) for k in kp))

            def val(fr):
                for (f0, v0), (f1, v1) in zip(keys, keys[1:]):
                    if f0 <= fr <= f1:
                        return v0 + (v1 - v0) * (fr - f0) / max(1, f1 - f0)
                return keys[-1][1] if fr > keys[-1][0] else keys[0][1]
            lo, hi = at - 12, at + 12
            new = {fr: v for fr, v in keys}
            for fr in range(lo + lag, hi + lag + 1):
                new[fr] = min(val(fr), val(fr - lag))
            for k in list(kp):
                kp.remove(k)
            for fr, v in sorted(new.items()):
                ET.SubElement(kp, 'KeyFrameDouble', {'value': fmt(v), 'frame': str(fr),
                                                     'interpolationType': 'linear'})


def blink_face(rest):
    """Мех вокруг глаз прищуривается и щёки чуть поднимаются вместе с
    морганием — веко «мягкое», а не только сплющенная бусина."""
    ch = {}
    SX, X = 16, 90   # у костей лица ось x смотрит вверх: scaleX — по высоте

    def bump(t, amp):
        return sum(amp * max(0.0, 1 - abs(t - b) / 9) ** 2 for b in BLINKS)

    for eye in ('eye_l', 'eye_r'):
        ch[(eye, SX)] = [(t, 1 - bump(t, 0.1)) for t in range(0, DUR + 1, 2)]
    # щёки на вдохе чуть приподнимаются (10.10: «щёки будто стоят»),
    # «яблочки» под глазами — вместе с ними (связка COUPLE)
    for cheek in ('cheek_l', 'cheek_r'):
        ch[(cheek, X)] = [(t, rest[cheek]['x'] + bump(t, 1.6) + 0.6 * wave(t, 18))
                          for t in range(0, DUR + 1, 2)]
    for apple in ('apple_l', 'apple_r'):
        ch[(apple, X)] = [(t, rest[apple]['x'] + 0.7 * (bump(t, 1.6) + 0.6 * wave(t, 18)))
                          for t in range(0, DUR + 1, 2)]
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


# Два рта — никогда (заказчик 27.09, трижды: «под раскрытым ртом ротик
# покоя», «рот над ртом»). Новый рот проявляется ровно настолько, насколько
# гаснет ротик покоя: у обоих один порог MOUTH_SWAP по высоте рта, сумма
# прозрачностей всегда 1. Сборку останавливает check_mouths() — если в
# каком-то кадре любого клипа оба рта видны больше чем наполовину.
MOUTH_SWAP = 0.06


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
        self.track(f'mh_{kind}', self.Y, [(p[0], p[2], ez(p)) for p in pts])
        self.ch[(E_IDS[f'{bone}_img'], self.OP)] = (
            [(0, 0.0, EI)] + [(p[0], min(1.0, max(0.0, p[2]) / MOUTH_SWAP), ez(p)) for p in pts]
            + [(self.dur - 2, 0.0, None)])
        self.mouth_h[kind] = [(p[0], p[2]) for p in pts]
        return self

    def _rest_mouth(self):
        """Ротик покоя гаснет, пока любой рот эмоции ещё щёлочка (mouth.py).
        Клип со ртом закрывает и все остальные рты: иначе улыбка петли
        настроения оставалась раскрытой под смехом щекотки, и в приложении
        побеждала она (заказчик 27.09: «щекочешь — рот не открывает»).
        Клип без рта рот петли не трогает."""
        if not self.mouth_h:
            return
        for kind in mouth.KINDS:
            if kind in self.mouth_h:
                continue
            for key in (self.SX, self.SY):
                self.track(f'mouth_{kind}', key, [(self.dur // 2, 0.0)])
            self.track(f'mh_{kind}', self.Y, [(self.dur // 2, 0.0)])
            if kind in mouth.JAW:
                self.track(f'jaw_{kind}', self.Y, [(self.dur // 2, 0.0)])
        end = self.dur - 2

        def h_at(pts, fr):
            pts = [(0, 0.0)] + pts + [(end, 0.0)]
            for (f0, v0), (f1, v1) in zip(pts, pts[1:]):
                if f0 <= fr <= f1:
                    return v0 + (v1 - v0) * (fr - f0) / max(1, f1 - f0)
            return 0.0
        frames = sorted({f for pts in self.mouth_h.values() for f, _ in pts} | {0, end})
        self.ch[(E_IDS['mouth_rest_img'], self.OP)] = [
            (fr, max(0.0, 1 - max(h_at(p, fr) for p in self.mouth_h.values()) / MOUTH_SWAP), EI if fr < end else None)
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
            # нижнее веко глаз не поднимает — бусина сплющивается к середине
            # (заказчик 10.10, увидев подъём: «это ужас»); верхнее — опускает
            shift = {'low': 0, 'top': BEAD_H, 'both': 0}[lid]
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
    """Смакует, 2,8 с (27.09: без подмен, без румянца и готовых картинок;
    заказчик: «ему кайфово — глазки должны радоваться»). Радостный прищур
    снизу: нижние веки и щёки поднимаются, пуговки видны, но прикрыты
    снизу, как у улыбающегося; брови чуть вверх. Ротик покоя переходит в
    широкую сомкнутую довольную улыбку, уголки высоко. Три «ням» — губы
    причмокивают: поджимаются и растягиваются шире, подбородок и нос
    подтягиваются, щёки поднимаются, глаза жмурятся чуть сильнее от
    удовольствия; голова блаженно покачивается из стороны в сторону."""
    e = Emo(170)
    s_ = [28, 60, 92]                          # «ням»: поджал через 10 кадров, отпустил через 26

    def nyam(base, peak, up=10, down=26):
        pts = []
        for a in s_:
            pts += [(a + up, peak), (a + down, base)]
        return pts
    # рот: широкая довольная улыбка; на «ням» губы поджимаются и
    # растягиваются, затем отпускаются
    mo = [(8, 0.1, 0.0), (26, 1.25, 1.35, EO)]
    for a in s_:
        mo += [(a + 10, 1.42, 0.85), (a + 26, 1.25, 1.35)]
    mo += [(136, 1.25, 1.35), (160, 0.1, 0.0)]
    e.mouth_open(mo, kind='content')
    e.pair('mouth', Emo.X, [(14, 4, EO), (26, 7)] + nyam(7, 8.5) + [(136, 7), (160, 0)])
    e.track('chin', Emo.X, [(12, 0)] + nyam(0.3, 1.8) + [(136, 0.3), (160, 0)])
    e.track('muzzle', Emo.X, [(12, 0)] + nyam(0.4, 1.4) + [(136, 0.4), (160, 0)])
    # глаза радуются: прищур снизу, пуговки видны; на «ням» — сильнее
    e.eyes([(6, 0.0), (26, 0.55, EO)] + nyam(0.55, 0.66, 8, 24) + [(136, 0.55), (162, 0.0)])
    e.pair('lid', Emo.X, [(26, 13, EO)] + nyam(13, 15, 8, 24) + [(136, 13), (162, 0)])
    e.pair('eye', Emo.SX, [(26, -0.07)] + nyam(-0.07, -0.09, 8, 24) + [(136, -0.07), (162, 0)])
    e.pair('cheek', Emo.X, [(26, 8, EO)] + nyam(8, 9.5) + [(136, 8), (162, 0)])
    e.pair('cheek', Emo.SY, [(26, 0.09, EO), (136, 0.085), (162, 0)])
    e.pair('brow', Emo.X, [(30, 2.5, EO), (136, 2.2), (162, 0)])
    # голова блаженно покачивается, чуть приподнята; плечи в такт «ням»
    e.track('head', Emo.R, [(26, 0.045, EO), (58, 0.02), (90, 0.05), (122, 0.025), (150, 0.03)])
    e.track('face', Emo.Y, [(26, 3), (58, 1.2), (90, 3.2), (122, 1.5), (150, 2)])
    e.track('face', Emo.X, [(26, 1.5), (150, 1.2)])
    e.track('breath', Emo.SY, [(20, 0.025)] + nyam(0.02, 0.035, 8, 24) + [(150, 0.015)])
    e.track('hood2', Emo.R, [(30, -0.05), (54, 0.03), (86, -0.03), (118, 0.02)])
    e.track('ear_r1', Emo.R, [(26, 0.06), (50, -0.02), (96, 0.04), (126, -0.01)])
    e.track('ear_l1', Emo.R, [(28, -0.04), (52, 0.02), (98, -0.03), (128, 0.01)])
    return e.build()


def emo_love():
    """Любовь, 3,6 с (ТЗ `emo_love_s45`; заказчик 27.09: «так же, костями»,
    без румянца и готовых картинок). Нежность, а не радость: всё медленно и
    мягко. Глаза мечтательно почти закрываются (прищур снизу, пуговки чуть
    видны), щёки высоко, брови мягко вверх; ротик покоя переходит в тихую
    сомкнутую улыбку. Голова медленно склоняется набок и покачивается,
    будто прижимается щекой; счастливый вздох — грудь наполняется и
    медленно опускается; уши расслабленно отходят назад, кончик капюшона
    плывёт следом. Отличие от «Смакует»: нет «ням» и причмокивания, глаза
    закрыты сильнее, движение вдвое медленнее, голова склонена глубже."""
    e = Emo(216)
    # рот: тихая довольная улыбка, уголки вверх
    e.mouth_open([(10, 0.1, 0.0), (44, 1.15, 1.2, EO), (176, 1.15, 1.2), (204, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(14, 0), (44, 6, EO), (176, 6), (204, 0)])
    # глаза: мечтательно почти закрыты снизу, медленно
    e.eyes([(6, 0.0), (50, 0.72, EO), (110, 0.68), (176, 0.72), (206, 0.0)])
    e.pair('lid', Emo.X, [(50, 15, EO), (176, 15), (206, 0)])
    e.pair('eye', Emo.SX, [(50, -0.08), (176, -0.08), (206, 0)])
    e.pair('cheek', Emo.X, [(50, 7, EO), (176, 7), (206, 0)])
    e.pair('cheek', Emo.SY, [(50, 0.07, EO), (176, 0.065), (206, 0)])
    e.pair('brow', Emo.X, [(50, 2.2, EO), (176, 2.0), (206, 0)])
    # голова медленно склоняется набок и покачивается, прижимаясь щекой
    e.track('head', Emo.R, [(10, 0), (56, 0.13, EO), (96, 0.1), (136, 0.135), (176, 0.105), (208, 0)])
    e.track('face', Emo.Y, [(56, 4.5, EO), (96, 3.2), (136, 4.8), (176, 3.6), (208, 0)])
    e.track('face', Emo.X, [(56, 1.2), (176, 1.0), (208, 0)])
    # счастливый вздох, тело мягко покачивается
    e.track('breath', Emo.SY, [(20, 0.01), (64, 0.07, EO), (120, 0.02), (176, 0.03), (208, 0)])
    e.track('chest', Emo.R, [(64, -0.012), (136, 0.006), (190, 0)])
    e.track('hips', Emo.Y, [(64, -2.5, EO), (120, -1), (176, -1.5), (208, 0)])
    e.track('hips', Emo.X, [(56, 1.5), (96, 0.5), (136, 1.8), (176, 0.8), (208, 0)])
    # уши расслабленно назад, капюшон плывёт следом
    e.track('ear_l1', Emo.R, [(60, 0.08), (136, 0.1), (176, 0.08), (208, 0)])
    e.track('ear_r1', Emo.R, [(60, -0.08), (136, -0.1), (176, -0.08), (208, 0)])
    e.track('ear_l2', Emo.R, [(66, 0.06), (142, 0.08), (208, 0)])
    e.track('ear_r2', Emo.R, [(66, -0.06), (142, -0.08), (208, 0)])
    e.track('hood2', Emo.R, [(64, -0.06), (104, -0.02), (144, -0.07), (184, -0.03), (208, 0)])
    e.track('hood1', Emo.R, [(64, -0.02), (144, -0.025), (208, 0)])
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
    # рот (заказчик 27.09: «так же зевок — нижней челюстью»): верхняя губа
    # стоит под носом, рот раскрывает нижняя челюсть — медленно вниз, на
    # вершине чуть дрожит, так же медленно вверх; подбородок идёт с ней
    _, top, bot = mouth.rows('yawn')
    H = 0.8 * (bot - top)                      # полное раскрытие — 0,8 рта с фото (≈ 40 px)
    mo = [(10, 0.1, 0.0), (40, 0.6, 0.35), (74, 1.0, 1.0, EO), (104, 0.96, 0.93),
          (120, 1.0, 0.98), (148, 0.6, 0.3), (166, 0.3, 0.0)]
    e.mouth_open(mo, kind='yawn')
    e.track('mouth_yawn', Emo.X, [(2, top - 500.0), (210, top - 500.0)])   # губа у верха ротика покоя
    e.track('jaw_yawn', Emo.Y, [(p[0], H * p[2], p[3] if len(p) > 3 else EI) for p in mo])
    # дрожь челюсти на вершине зевка
    e.track('jaw_yawn', Emo.X, [(80, 0), (86, 0.6), (92, -0.5), (98, 0.4), (104, -0.3), (110, 0)])
    # глаза зажмурились: бусины сплющены, нижние и верхние веки сходятся
    e.eyes([(6, 0.0), (44, 0.72, EO), (150, 0.7), (180, 0.0)], lid='both')
    e.pair('lid', Emo.X, [(44, 9, EO), (150, 8.5), (180, 0)])
    e.pair('ulid', Emo.X, [(44, -5, EO), (150, -4.5), (180, 0)])
    e.pair('eye', Emo.SX, [(44, -0.1), (150, -0.09), (180, 0)])
    e.pair('brow', Emo.X, [(50, 3, EO), (140, 2.5), (176, 0)])
    # челюсть вниз, мордочка тянется, щёки уже
    e.track('chin', Emo.X, [(10, 0), (40, -0.2 * H * 0.35), (74, -0.2 * H, EO), (104, -0.19 * H),
                            (120, -0.2 * H), (148, -0.2 * H * 0.3), (166, 0)])
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
        # стопа вверх (колено сгибается само, leg_ik), носок наружу, удар
        legs.setdefault((f'foot_{side}', Emo.Y), []).extend(
            [(at, 0), (at + 10, -17, EO), (at + 13, -17), (at + 20, 0.5), (at + 24, 0)])
        legs.setdefault((f'foot_{side}', Emo.R), []).extend(
            [(at, 0), (at + 10, 0.035 * out, EO), (at + 13, 0.035 * out), (at + 19, 0.0)])
        legs.setdefault((f'foot_{side}', Emo.SY), []).extend(
            [(at, 0), (at + 10, 0.05, EO), (at + 19, 0.0)])
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


# --- Поглаживание (ТЗ act_pet / act_pet_s45_b; заказчик 27.09) ----------------
# Как в Talking Tom: мишка откликается на палец, пока его гладят. Лицо
# «гладят» (`pet_face`) нарастает за 0,3 с и держится; каждый проход руки —
# `pet_pass` (голова проседает под ладонью и тянется обратно, уши
# прижимаются и пружинят с перелётом, тело подаётся к руке); наклон головы к
# пальцу приложение ставит само, живьём (кость `e_head`). Отпустили — после
# последнего прохода `pet_out`: досмаковал 0,2 с, открыл глаза, посмотрел
# вверх, дёрнул ушком, подпрыгнул. Животик — `act_pet_b`, щекотно; резкий
# мазок — `pet_startle`, вздрогнул.
PET_HOLD = 18      # кадр, где лицо «гладят» полное


def _pet_face_emo(e, at=None):
    """Лицо «гладят»: блаженный прищур снизу, улыбка, брови расслаблены.
    at — кадры ключей (по умолчанию нарастание к PET_HOLD)."""
    f = at or PET_HOLD
    e.eyes([(f, 0.8, EO)] if at is None else at_pts(at, 0.8))
    e.pair('lid', Emo.X, [(f, 16, EO)] if at is None else at_pts(at, 16))
    e.pair('eye', Emo.SX, [(f, -0.08, EO)] if at is None else at_pts(at, -0.08))
    e.pair('cheek', Emo.X, [(f, 7, EO)] if at is None else at_pts(at, 7))
    e.pair('cheek', Emo.SY, [(f, 0.07, EO)] if at is None else at_pts(at, 0.07))
    e.pair('brow', Emo.X, [(f, 2, EO)] if at is None else at_pts(at, 2))
    e.pair('mouth', Emo.X, [(f, 6, EO)] if at is None else at_pts(at, 6))


def at_pts(at, v):
    """Выход: держит значение до at[0], к at[1] — покой."""
    return [(at[0], v), (at[1], 0.0, EI)]


def _drop_end(dur, ch):
    """Без возврата в покой в конце — клип держит последнюю позу."""
    for frames in ch.values():
        if len(frames) > 2 and frames[-1][0] == dur - 2:
            frames.pop()
    return dur, ch


def pet_face():
    e = Emo(40)
    _pet_face_emo(e)
    e.mouth_open([(4, 0.1, 0.0), (PET_HOLD, 1.15, 1.2, EO)], kind='content')
    return _drop_end(*e.build())


def pet_pass():
    """Цикл «ладонь прошла по голове», 0,8 с; начинается и кончается
    покоем — приложение крутит его непрерывно со скоростью пальца и силой
    0…1 (заказчик 27.09: без рывков, мягко). Движения мягче, чем в первой
    версии: голова проседает на 2,2 %, уши прижимаются на 0,12 рад."""
    e = Emo(48)
    # голова проседает под ладонью (сжалась по высоте, чуть шире) и тянется обратно
    e.track('head', Emo.SX, [(9, -0.022), (24, 0.007), (38, 0.0)])
    e.track('head', Emo.SY, [(9, 0.008), (24, -0.003), (38, 0.0)])
    e.track('face', Emo.X, [(9, -1.3), (24, 0.35), (38, 0.0)])
    # уши прижимаются под рукой с запаздыванием и пружинят с перелётом
    e.track('ear_l1', Emo.R, [(14, 0.12), (29, -0.035), (42, 0.0)])
    e.track('ear_r1', Emo.R, [(14, -0.12), (29, 0.035), (42, 0.0)])
    e.track('ear_l2', Emo.R, [(18, 0.07), (33, -0.025), (44, 0.0)])
    e.track('ear_r2', Emo.R, [(18, -0.07), (33, 0.025), (44, 0.0)])
    # тело подаётся к руке, грудь чуть наполняется, кончик капюшона следом
    e.track('hips', Emo.Y, [(4, 0.0), (15, -1.4), (33, 0.0)])
    e.track('breath', Emo.SY, [(15, 0.015), (36, 0.0)])
    e.track('hood2', Emo.R, [(12, 0.045), (27, -0.02), (42, 0.0)])
    return e.build()


def pet_out():
    """Отпустили: держит лицо 0,2 с, открывает глаза, смотрит вверх, дёргает
    ушком, подпрыгивает; начинается ровно с лица `pet_face`."""
    e = Emo(60)
    _pet_face_emo(e, at=(12, 34))
    e.mouth_open([(12, 1.15, 1.2), (40, 0.1, 0.0)], kind='content')
    e.track('face', Emo.X, [(12, 0.0), (30, 3.0, EO), (50, 0.0)])
    e.track('ear_r1', Emo.R, [(30, 0.0), (34, -0.1), (40, 0.04), (46, 0.0)])
    e.track('ear_r2', Emo.R, [(33, 0.0), (37, -0.08), (43, 0.03), (49, 0.0)])
    e.track('hips', Emo.Y, [(30, 0.0), (38, -3.0, EO), (48, 0.5), (56, 0.0)])
    e.track('hood2', Emo.R, [(38, -0.04), (48, 0.02), (56, 0.0)])
    dur, ch = e.build()
    _, held = pet_face()
    missing = set(held) - set(ch)
    assert not missing, missing
    for k, frames in ch.items():
        if k in held:
            frames[0] = (0, held[k][-1][1], frames[0][2])
    return dur, ch


def act_pet_b():
    """Щекотно (животик), 2,5 с: зажмурился от смеха, хихикает — рот
    приоткрывается толчками; ёжится — плечи и грудь сжимаются, голова
    втягивается, тело изгибается влево-вправо; уши подпрыгивают. Руки не
    поднимает."""
    e = Emo(150)
    g = [20, 44, 68, 92]                         # «хи»: пик через 8 кадров, спад через 12
    # рот — как у утверждённого «Смеха» (заказчик 27.09: «смех со ртом уже
    # настроен в первых 10»): раскрыт широко, «хи» — толчки поверх
    mo = [(4, 0.05, 0.0), (16, 0.95, 0.85, EO)]
    for a in g:
        mo += [(a + 8, 1.0, 1.0), (a + 20, 0.95, 0.78)]
    mo += [(118, 0.9, 0.55), (132, 0.45, 0.04), (146, 0.1, 0.0)]
    e.mouth_open(mo, kind='open')
    e.eyes([(4, 0.0), (14, 0.7, EO), (128, 0.7), (146, 0.0)])
    e.pair('lid', Emo.X, [(14, 14, EO), (128, 14), (146, 0)])
    e.pair('cheek', Emo.X, [(14, 6, EO)] + [p for a in g for p in ((a + 8, 7.5), (a + 20, 6))] + [(128, 6), (146, 0)])
    e.pair('mouth', Emo.X, [(14, 6, EO), (128, 6), (146, 0)])
    e.pair('brow', Emo.X, [(14, 1.5), (128, 1.5), (146, 0)])
    # ёжится: голова втянута, грудь сжата, тело изгибается влево-вправо
    side = []
    for i, a in enumerate(g):
        k = 1 if i % 2 == 0 else -1
        side += [(a + 8, k), (a + 20, 0.3 * k)]
    e.track('face', Emo.X, [(12, -2.5, EO), (128, -2.2), (146, 0)])
    e.track('breath', Emo.SY, [(12, -0.03, EO)] + [(a + 8, -0.045) for a in g] + [(128, -0.03), (146, 0)])
    e.track('chest', Emo.R, [(f, 0.03 * k) for f, k in side] + [(140, 0)])
    e.track('hips', Emo.X, [(f, 3.0 * k) for f, k in side] + [(140, 0)])
    e.track('hips', Emo.Y, [(12, 1.5, EO), (128, 1.5), (146, 0)])
    e.track('head', Emo.R, [(f + 3, -0.03 * k) for f, k in side] + [(140, 0)])
    e.track('ear_l1', Emo.R, [p for a in g for p in ((a + 11, -0.08), (a + 22, 0.02))] + [(140, 0)])
    e.track('ear_r1', Emo.R, [p for a in g for p in ((a + 11, 0.08), (a + 22, -0.02))] + [(140, 0)])
    e.track('hood2', Emo.R, [(f + 6, -0.05 * k) for f, k in side] + [(142, 0)])
    return e.build()


def pet_startle():
    """Резкий мазок, 0,7 с: вздрогнул — глаза шире, брови и уши вверх,
    голова назад, ротик «о»; быстро (0,08 с), потом мягко в покой."""
    e = Emo(42)
    e.eyes([(5, 0.12, EO), (16, 0.07), (36, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(5, 3.0, EO), (16, 2.0), (36, 0)])
    e.track('ear_l1', Emo.R, [(5, -0.1, EO), (16, -0.06), (36, 0)])
    e.track('ear_r1', Emo.R, [(5, 0.1, EO), (16, 0.06), (36, 0)])
    e.track('face', Emo.X, [(5, 3.0, EO), (16, 2.0), (36, 0)])
    e.track('hips', Emo.Y, [(5, -3.0, EO), (14, 0.8), (26, 0)])
    e.track('breath', Emo.SY, [(5, 0.04, EO), (20, 0.01), (36, 0)])
    _, top, bot = mouth.rows('yawn')
    mo = [(3, 0.1, 0.0), (7, 0.55, 0.28, EO), (18, 0.5, 0.2), (34, 0.1, 0.0)]
    e.mouth_open(mo, kind='yawn')
    e.track('mouth_yawn', Emo.X, [(1, top - 500.0), (40, top - 500.0)])
    e.track('jaw_yawn', Emo.Y, [(p[0], 0.8 * (bot - top) * p[2], p[3] if len(p) > 3 else EI) for p in mo])
    e.track('hood2', Emo.R, [(8, 0.05), (18, -0.02), (30, 0)])
    return e.build()


# --- Покой с настроением (ТЗ idle_happy/sad/hungry/sleepy/dirty; 27.09) -----
# Слой поверх `idle_life` (дыхание, моргание, осмотр остаются): петля 12 с,
# в ней поза, лицо и 1–2 маленьких действия. Все каналы — гладкие
# периодические функции времени (ключи через 6 кадров, линейно), f(0) =
# f(конец) — петля без шва. Все петли ключуют одинаковый набор каналов (где
# канал не нужен — покой), поэтому приложение смешивает любые две петли
# без скачков. Темп дыхания — скорость `idle_life` в приложении (ТЗ §5.10).
MOOD_T = 720
MOOD_STEP = 6


def _circ(t, c):
    """Расстояние по кругу петли от кадра t до c."""
    d = (t - c) % MOOD_T
    return min(d, MOOD_T - d)


def mbump(t, c, w):
    """Плавный горб 0 → 1 → 0 шириной ±w кадров вокруг c (по кругу)."""
    d = _circ(t, c)
    return 0.5 * (1 + math.cos(math.pi * d / w)) if d < w else 0.0


def mwave(t, n=1, phase=0.0):
    return math.sin(2 * math.pi * n * t / MOOD_T + phase)


def _mood_mouth(spec, kind, w, h):
    """Рот настроения: ширина и высота — функции времени (как Emo.mouth_open)."""
    sx0, sy0 = mouth.closed(kind)
    spec[(f'mouth_{kind}', Emo.SX)] = lambda t: (sx0 + (1 - sx0) * w(t)) / sx0 - 1
    spec[(f'mouth_{kind}', Emo.SY)] = lambda t: (sy0 + (1 - sy0) * h(t)) / sy0 - 1
    spec[(f'mouth_{kind}_img', Emo.OP)] = lambda t: min(1.0, max(0.0, h(t)) / MOUTH_SWAP)
    spec[(f'mh_{kind}', Emo.Y)] = h
    spec.setdefault('_mouth_h', []).append(h)
    if kind in mouth.JAW:
        _, top, bot = mouth.rows(kind)
        k = 0.8 if kind == 'yawn' else 1.0
        spec[(f'jaw_{kind}', Emo.Y)] = lambda t: k * (bot - top) * h(t)
        spec[(f'mouth_{kind}', Emo.X)] = lambda t: top - 500.0


def _mood_eyes(spec, low, top):
    """Бусины: low — прищур улыбки, top — верхнее веко вниз. Сдвиг — как
    задуман (top − low), но вверх бусина не уходит: нижнее веко глаз не
    поднимает (заказчик 10.10: «это ужас»)."""
    for side in ('l', 'r'):
        spec[(f'bead_{side}', Emo.SY)] = lambda t: -(low(t) + top(t))
        spec[(f'bead_{side}', Emo.Y)] = lambda t: BEAD_H * max(0.0, top(t) - low(t))


def _pair(spec, name, key, fn, mirror=False):
    spec[(f'{name}_l', key)] = fn
    spec[(f'{name}_r', key)] = (lambda t: -fn(t)) if mirror else fn


def mood_happy():
    """Радость: голова выше, уши торчком, тело легче; лёгкая сомкнутая
    улыбка, чуть прищур; раз за петлю покачивается из стороны в сторону,
    раз — подпрыгивает на месте."""
    sp = {}
    sway = lambda t: mbump(t, 330, 120) * math.sin(2 * math.pi * (t - 210) / 240)
    hop = lambda t: mbump(t, 600, 20)
    prep = lambda t: mbump(t, 576, 10)
    sp[('face', Emo.X)] = lambda t: 1.5
    sp[('head', Emo.R)] = lambda t: 0.04 * sway(t - 8)
    sp[('hips', Emo.X)] = lambda t: 2.5 * sway(t)
    sp[('hips', Emo.Y)] = lambda t: -1.0 - 4.0 * hop(t) + 1.5 * prep(t)
    sp[('breath', Emo.SY)] = lambda t: 0.02 + 0.02 * hop(t - 4)
    sp[('ear_l1', Emo.R)] = lambda t: -0.06 + 0.06 * mbump(t, 614, 14)
    sp[('ear_r1', Emo.R)] = lambda t: 0.06 - 0.06 * mbump(t, 614, 14)
    sp[('ear_l2', Emo.R)] = lambda t: -0.04 + 0.05 * mbump(t, 620, 14)
    sp[('ear_r2', Emo.R)] = lambda t: 0.04 - 0.05 * mbump(t, 620, 14)
    sp[('hood2', Emo.R)] = lambda t: -0.04 * sway(t - 20) + 0.04 * mbump(t, 616, 16)
    _mood_eyes(sp, lambda t: 0.12, lambda t: 0.0)
    _pair(sp, 'lid', Emo.X, lambda t: 3.0)
    _pair(sp, 'cheek', Emo.X, lambda t: 2.0)
    _pair(sp, 'mouth', Emo.X, lambda t: 3.0)
    _mood_mouth(sp, 'content', lambda t: 0.85, lambda t: 0.75)
    return sp


def mood_sad():
    """Грусть: голова опущена и склонена, взгляд в сторону, уши поникли,
    плечи осели; тяжёлые верхние веки, брови домиком (слабее эмоции),
    маленькая грустная дуга; раз за петлю тяжёлый вздох."""
    sp = {}
    rise = lambda t: mbump(t, 380, 50)
    sink = lambda t: mbump(t, 460, 70)
    sp[('face', Emo.X)] = lambda t: -4.0 - 2.0 * sink(t)
    sp[('face', Emo.Y)] = lambda t: -1.5 - 1.0 * mbump(t, 150, 120)
    sp[('head', Emo.R)] = lambda t: 0.04 + 0.02 * sink(t)
    sp[('hips', Emo.Y)] = lambda t: 2.5 - 1.0 * rise(t)
    sp[('breath', Emo.SY)] = lambda t: -0.02 + 0.05 * rise(t) - 0.02 * sink(t)
    sp[('chest', Emo.R)] = lambda t: -0.01
    sp[('ear_l1', Emo.R)] = lambda t: 0.12 + 0.04 * sink(t - 10)
    sp[('ear_r1', Emo.R)] = lambda t: -0.12 - 0.04 * sink(t - 10)
    sp[('ear_l1', Emo.SX)] = lambda t: -0.06
    sp[('ear_r1', Emo.SX)] = lambda t: -0.06
    sp[('ear_l2', Emo.R)] = lambda t: 0.08
    sp[('ear_r2', Emo.R)] = lambda t: -0.08
    sp[('hood2', Emo.R)] = lambda t: 0.05 + 0.02 * sink(t - 14)
    _mood_eyes(sp, lambda t: 0.0, lambda t: 0.28 + 0.06 * sink(t))
    _pair(sp, 'ulid', Emo.X, lambda t: -3.0)
    sp[('brow_l', Emo.R)] = lambda t: -0.1
    sp[('brow_r', Emo.R)] = lambda t: 0.1
    _pair(sp, 'brow', Emo.X, lambda t: 1.0)
    _pair(sp, 'mouth', Emo.X, lambda t: -2.0)
    _mood_mouth(sp, 'sad', lambda t: 0.85, lambda t: 0.65)
    return sp


def mood_hungry():
    """Голод: брови с надеждой; оглядывается по сторонам (ищет еду),
    облизывается и причмокивает, животик урчит — два мелких толчка в
    корпусе, мишка смотрит вниз на животик. Без рук (заказчик 27.09)."""
    sp = {}
    look_l = lambda t: mbump(t, 120, 60)
    look_r = lambda t: mbump(t, 290, 60)
    smack = lambda t: 0.4 * mbump(t, 470, 22) + 0.3 * mbump(t, 520, 20)
    rumble = lambda t: mbump(t, 632, 6) + mbump(t, 650, 6)
    down = lambda t: mbump(t, 655, 34)
    sp[('face', Emo.Y)] = lambda t: 6.0 * (look_r(t) - look_l(t))
    sp[('face', Emo.X)] = lambda t: 1.5 * (look_l(t) + look_r(t)) - 2.0 * down(t)
    sp[('head', Emo.R)] = lambda t: 0.035 * (look_r(t - 6) - look_l(t - 6)) + 0.02 * down(t)
    sp[('hood2', Emo.R)] = lambda t: -0.04 * (look_r(t - 14) - look_l(t - 14))
    sp[('breath', Emo.SY)] = lambda t: 0.025 * rumble(t)
    sp[('hips', Emo.Y)] = lambda t: 0.8 * rumble(t)
    sp[('belly', Emo.R)] = lambda t: 0.006 * (mbump(t, 632, 6) - mbump(t, 650, 6))
    sp[('brow_l', Emo.R)] = lambda t: -0.05
    sp[('brow_r', Emo.R)] = lambda t: 0.05
    _pair(sp, 'brow', Emo.X, lambda t: 1.5 + 0.8 * down(t))
    sp[('ear_l1', Emo.R)] = lambda t: -0.03
    sp[('ear_r1', Emo.R)] = lambda t: 0.03
    sp[('chin', Emo.X)] = lambda t: -1.5 * smack(t) / 0.4
    sp[('muzzle', Emo.X)] = lambda t: 0.8 * (mbump(t, 470, 22) + mbump(t, 520, 20))
    _mood_mouth(sp, 'chew', lambda t: 0.6 * min(1.0, smack(t) / 0.1), smack)
    return sp


def mood_sleepy():
    """Сонный: веки наполовину закрыты, расслабленный рот; медленно
    покачивается, голова клюёт и поднимается; один зевок во весь рот, как
    «Зевок» (заказчик 27.09: «зевает маленьким ртом — почему?»): голова
    назад, грудь полная, глаза зажмурены, нижняя челюсть вниз."""
    sp = {}
    nod = lambda t: mbump(t, 300, 70)
    yawn = lambda t: mbump(t, 540, 72)
    # медленное сонное моргание (10.10): веки тяжело опускаются до конца,
    # чуть задерживаются и нехотя поднимаются
    slow = lambda t: mbump(t, 150, 38) + mbump(t, 440, 44)
    sway = lambda t: mwave(t, 2)
    sp[('hips', Emo.X)] = lambda t: 1.5 * sway(t)
    sp[('head', Emo.R)] = lambda t: 0.03 * mwave(t, 2, -0.3) + 0.03 * nod(t)
    sp[('face', Emo.X)] = lambda t: -1.0 - 5.0 * nod(t) + 4.0 * yawn(t)
    sp[('hood2', Emo.R)] = lambda t: 0.03 * mwave(t, 2, -0.6) + 0.04 * nod(t - 10) - 0.04 * yawn(t - 8)
    sp[('breath', Emo.SY)] = lambda t: 0.07 * yawn(t)
    sp[('chest', Emo.R)] = lambda t: -0.015 * yawn(t)
    sp[('ear_l1', Emo.R)] = lambda t: 0.06 + 0.04 * nod(t - 8)
    sp[('ear_r1', Emo.R)] = lambda t: -0.06 - 0.04 * nod(t - 8)
    _mood_eyes(sp, lambda t: 0.0, lambda t: min(1.0, 0.45 + 0.35 * nod(t) + 0.55 * yawn(t) + 0.55 * slow(t)))
    _pair(sp, 'ulid', Emo.X, lambda t: -4.0 - 3.0 * nod(t))
    _pair(sp, 'brow', Emo.X, lambda t: -0.8 + 3.0 * yawn(t))
    _mood_mouth(sp, 'sleepy', lambda t: 1.0 - yawn(t), lambda t: 1.0 - yawn(t))
    _mood_mouth(sp, 'yawn', lambda t: min(1.0, yawn(t) / 0.2), lambda t: yawn(t))
    return sp


def mood_dirty():
    """Грязнуля: морщится (нос вверх, глаза щурятся, губы поджаты); раз
    за петлю отряхивается — быстрая затухающая дрожь всем телом, уши и
    кончик капюшона хлопают; перед этим дёргает ухом. Без рук."""
    sp = {}
    shake = lambda t: mbump(t, 390, 42) * math.sin(2 * math.pi * (t - 348) / 10)
    sp[('hips', Emo.X)] = lambda t: 3.5 * shake(t)
    sp[('head', Emo.R)] = lambda t: 0.05 * shake(t - 2)
    sp[('breath', Emo.SX)] = lambda t: 0.015 * abs(shake(t))
    sp[('ear_l1', Emo.R)] = lambda t: 0.12 * shake(t - 3) + 0.1 * mbump(t, 150, 8)
    sp[('ear_r1', Emo.R)] = lambda t: -0.12 * shake(t - 3)
    sp[('hood2', Emo.R)] = lambda t: 0.08 * shake(t - 5)
    sp[('muzzle', Emo.X)] = lambda t: 1.0
    _mood_eyes(sp, lambda t: 0.15, lambda t: 0.15 + 0.2 * mbump(t, 390, 40))
    _pair(sp, 'brow', Emo.X, lambda t: -1.0)
    _mood_mouth(sp, 'pout', lambda t: 0.6, lambda t: 0.5)
    return sp


MOODS = {'mood_happy': mood_happy, 'mood_sad': mood_sad, 'mood_hungry': mood_hungry,
         'mood_sleepy': mood_sleepy, 'mood_dirty': mood_dirty}


# --- Характер (ТЗ idle_trait_*; заказчик 27.09: «делай всё сразу») --------
# Покой характера — такая же петля 12 с, как настроения (тот же набор
# каналов, смешивается с любой). Приложение играет её, когда настроение
# обычное; при особом настроении играет настроение, а характер остаётся
# в темпе дыхания и в разбивках покоя. Различие — поза, темп, лицо, без
# подписей (ТЗ аниматора 7.5).

def mhold(t, a, b, e):
    """Плато 0 → 1 (от a за e кадров) … 1 → 0 (от b за e кадров)."""
    def sm(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3 - 2 * x)
    return sm((t - a) / e) * (1 - sm((t - b) / e))


def _wide_eyes(spec, w):
    for side in ('l', 'r'):
        spec[(f'bead_{side}', Emo.SX)] = w
        spec[(f'bead_{side}', Emo.SY)] = w


def idle_trait_active():
    """Активный: бодрый, голова высоко, уши торчком; всё время пружинит на
    носочках (раз в секунду), часто зыркает по сторонам, раз за петлю
    подпрыгивает; уголки рта вверх. Дыхание ×1,2 — в приложении."""
    sp = {}
    bob = lambda t: sum(mbump(t, c, 12) for c in range(30, 700, 60))
    hop = lambda t: mbump(t, 612, 16)
    prep = lambda t: mbump(t, 590, 9)
    look = lambda t: (mhold(t, 130, 175, 10) - mhold(t, 230, 275, 10)
                      + mhold(t, 400, 440, 10) - mhold(t, 480, 520, 10))
    sp[('face', Emo.X)] = lambda t: 2.5
    sp[('face', Emo.Y)] = lambda t: 6.0 * look(t)
    sp[('head', Emo.R)] = lambda t: 0.035 * look(t - 4)
    sp[('hips', Emo.Y)] = lambda t: -1.4 * bob(t) - 5.0 * hop(t) + 1.8 * prep(t)
    sp[('breath', Emo.SY)] = lambda t: 0.012 * bob(t) + 0.02 * hop(t - 4)
    sp[('ear_l1', Emo.R)] = lambda t: -0.12 + 0.04 * bob(t - 5) + 0.08 * mbump(t, 626, 12)
    sp[('ear_r1', Emo.R)] = lambda t: 0.12 - 0.04 * bob(t - 5) - 0.08 * mbump(t, 626, 12)
    sp[('ear_l2', Emo.R)] = lambda t: -0.05 + 0.05 * mbump(t, 632, 12)
    sp[('ear_r2', Emo.R)] = lambda t: 0.05 - 0.05 * mbump(t, 632, 12)
    sp[('hood2', Emo.R)] = lambda t: -0.04 * look(t - 12) + 0.05 * mbump(t, 628, 14) + 0.02 * bob(t - 6)
    sp[('arm_l1', Emo.R)] = lambda t: 0.012 * bob(t) + 0.025 * hop(t)
    sp[('arm_r1', Emo.R)] = lambda t: -0.012 * bob(t) - 0.025 * hop(t)
    _mood_eyes(sp, lambda t: 0.06, lambda t: 0.0)
    _pair(sp, 'mouth', Emo.X, lambda t: 3.0)
    _pair(sp, 'brow', Emo.X, lambda t: 1.5)
    return sp


def idle_trait_curious():
    """Любознательный: глаза широко, брови вверх; голова почти всё время
    набок — то в одну сторону, то в другую (раз в 3 с), корпус следом, ухо
    с той стороны торчком и подрагивает; раз за петлю смотрит вверх."""
    sp = {}
    tilt = lambda t: (mhold(t, 20, 160, 20) - mhold(t, 200, 330, 20)
                      + mhold(t, 440, 560, 20) - mhold(t, 590, 690, 20))
    up = lambda t: mbump(t, 385, 45)
    tw = lambda t: mbump(t, 100, 5) + mbump(t, 112, 5) + mbump(t, 500, 5) + mbump(t, 512, 5)
    sp[('head', Emo.R)] = lambda t: 0.06 * tilt(t)
    sp[('chest', Emo.R)] = lambda t: 0.015 * tilt(t - 6)
    sp[('face', Emo.Y)] = lambda t: 5.0 * tilt(t)
    sp[('face', Emo.X)] = lambda t: 1.5 + 4.0 * up(t)
    sp[('hips', Emo.X)] = lambda t: 2.0 * tilt(t - 8)
    sp[('ear_r1', Emo.R)] = lambda t: 0.04 + 0.1 * max(0.0, tilt(t - 6)) + 0.05 * tw(t) + 0.05 * up(t)
    sp[('ear_l1', Emo.R)] = lambda t: -0.04 - 0.1 * max(0.0, -tilt(t - 6)) - 0.05 * tw(t - 200) - 0.05 * up(t)
    sp[('ear_l2', Emo.R)] = lambda t: -0.04 * max(0.0, -tilt(t - 12))
    sp[('ear_r2', Emo.R)] = lambda t: 0.04 * max(0.0, tilt(t - 12))
    sp[('hood2', Emo.R)] = lambda t: -0.05 * tilt(t - 16) - 0.03 * up(t - 10)
    _wide_eyes(sp, lambda t: 0.1 + 0.04 * up(t))
    _pair(sp, 'brow', Emo.X, lambda t: 3.0 + 1.5 * up(t))
    return sp


def idle_trait_affectionate():
    """Ласковый: голова набок, баюкающее покачивание всем телом, тёплый
    прищур, сомкнутая улыбка, уши мягко опущены; дважды за петлю —
    счастливый вздох."""
    sp = {}
    rock = lambda t: mwave(t, 2)
    sigh = lambda t: mbump(t, 200, 55) + mbump(t, 560, 55)
    sp[('head', Emo.R)] = lambda t: 0.06 + 0.025 * mwave(t, 2, -0.4)
    sp[('chest', Emo.R)] = lambda t: 0.015 * rock(t - 10) - 0.01 * sigh(t)
    sp[('face', Emo.Y)] = lambda t: 3.0 + 2.0 * mwave(t, 2, -0.4)
    sp[('face', Emo.X)] = lambda t: 0.5 + 1.5 * sigh(t)
    sp[('hips', Emo.X)] = lambda t: 3.0 * rock(t)
    sp[('breath', Emo.SY)] = lambda t: 0.05 * sigh(t)
    sp[('ear_l1', Emo.R)] = lambda t: 0.08 + 0.02 * mwave(t, 2, -1.0)
    sp[('ear_r1', Emo.R)] = lambda t: -0.08 - 0.02 * mwave(t, 2, -1.0)
    sp[('hood2', Emo.R)] = lambda t: -0.04 * mwave(t, 2, -0.9)
    sp[('arm_l1', Emo.R)] = lambda t: 0.012 * rock(t)
    sp[('arm_r1', Emo.R)] = lambda t: 0.012 * rock(t)
    _mood_eyes(sp, lambda t: 0.32 + 0.12 * sigh(t), lambda t: 0.0)
    _pair(sp, 'lid', Emo.X, lambda t: 7.0 + 3.0 * sigh(t))
    _pair(sp, 'cheek', Emo.X, lambda t: 4.0)
    _pair(sp, 'mouth', Emo.X, lambda t: 5.0)
    _mood_mouth(sp, 'content', lambda t: 1.0, lambda t: 0.95)
    return sp


def idle_trait_calm():
    """Спокойный: почти неподвижен, веки наполовину прикрыты, безмятежная
    полуулыбка, уши расслаблены; дважды за петлю медленно кивает.
    Дыхание ×0,85 — в приложении."""
    sp = {}
    nod = lambda t: mbump(t, 200, 90) + mbump(t, 540, 90)
    sp[('face', Emo.X)] = lambda t: -1.0 - 4.0 * nod(t)
    sp[('head', Emo.R)] = lambda t: 0.012 * nod(t)
    sp[('hood2', Emo.R)] = lambda t: 0.03 * nod(t - 20)
    sp[('ear_l1', Emo.R)] = lambda t: 0.05
    sp[('ear_r1', Emo.R)] = lambda t: -0.05
    _mood_eyes(sp, lambda t: 0.0, lambda t: 0.32 + 0.1 * nod(t))
    _pair(sp, 'ulid', Emo.X, lambda t: -3.0 - 1.0 * nod(t))
    _pair(sp, 'mouth', Emo.X, lambda t: 1.5)
    _mood_mouth(sp, 'content', lambda t: 0.6, lambda t: 0.35)
    return sp


def idle_trait_independent():
    """Самостоятельный: подбородок вверх, взгляд из-под полуопущенных век,
    брови ровно-строго; почти всё время смотрит в сторону, а не на
    зрителя, — короткие чёткие повороты головы, мельком глянул в другую
    сторону; дважды дёрнул ухом. Без улыбки."""
    sp = {}
    away = lambda t: -mhold(t, 30, 340, 12) + 0.8 * mhold(t, 430, 640, 12)
    sp[('face', Emo.X)] = lambda t: 3.0
    sp[('face', Emo.Y)] = lambda t: 6.5 * away(t)
    sp[('head', Emo.R)] = lambda t: 0.045 * away(t - 3)
    sp[('hood2', Emo.R)] = lambda t: -0.04 * away(t - 10)
    sp[('ear_r1', Emo.R)] = lambda t: 0.15 * mbump(t, 360, 6) + 0.15 * mbump(t, 660, 6)
    sp[('ear_r2', Emo.R)] = lambda t: 0.09 * mbump(t, 364, 7) + 0.09 * mbump(t, 664, 7)
    _mood_eyes(sp, lambda t: 0.0, lambda t: 0.16)
    _pair(sp, 'brow', Emo.X, lambda t: -1.2)
    _pair(sp, 'mouth', Emo.X, lambda t: -1.0)
    return sp


def idle_trait_reserved():
    """Замкнутый: сжался (плечи вниз, грудь меньше), голова низко опущена и
    отвёрнута, веки тяжёлые, брови чуть домиком, уши прижаты назад; дважды
    робко поднимает глаза на зрителя — и снова прячет."""
    sp = {}
    peek = lambda t: mhold(t, 240, 300, 22) + mhold(t, 560, 595, 18)
    sp[('face', Emo.X)] = lambda t: -6.5 + 5.0 * peek(t)
    sp[('face', Emo.Y)] = lambda t: -4.5 + 3.5 * peek(t)
    sp[('head', Emo.R)] = lambda t: -0.06 + 0.04 * peek(t)
    sp[('chest', Emo.R)] = lambda t: -0.012
    sp[('hips', Emo.Y)] = lambda t: 3.0
    sp[('breath', Emo.SY)] = lambda t: -0.035
    sp[('breath', Emo.SX)] = lambda t: -0.01
    sp[('ear_l1', Emo.R)] = lambda t: 0.14 - 0.03 * peek(t)
    sp[('ear_r1', Emo.R)] = lambda t: -0.14 + 0.03 * peek(t)
    sp[('ear_l2', Emo.R)] = lambda t: 0.06
    sp[('ear_r2', Emo.R)] = lambda t: -0.06
    sp[('hood2', Emo.R)] = lambda t: 0.04 - 0.03 * peek(t - 10)
    sp[('brow_l', Emo.R)] = lambda t: -0.05
    sp[('brow_r', Emo.R)] = lambda t: 0.05
    _mood_eyes(sp, lambda t: 0.0, lambda t: 0.3 - 0.22 * peek(t))
    return sp


MOODS.update({'idle_trait_active': idle_trait_active, 'idle_trait_curious': idle_trait_curious,
              'idle_trait_affectionate': idle_trait_affectionate, 'idle_trait_calm': idle_trait_calm,
              'idle_trait_independent': idle_trait_independent, 'idle_trait_reserved': idle_trait_reserved})


def _mood_base(name, key):
    if name.startswith('mouth_') and name.endswith('_img'):
        return 0.0
    r = E_REST[name]
    return {Emo.R: r.get('rotation', 0.0), Emo.X: r.get('x', 0.0), Emo.Y: r.get('y', 0.0)}.get(key, 1.0)


def build_moods():
    """{имя клипа: (длина, каналы)} — все петли с одним набором каналов;
    `mood_normal` — покой по всем этим каналам."""
    specs = {n: fn() for n, fn in MOODS.items()}
    for sp in specs.values():                  # ротик покоя гаснет под ртом настроения
        hs = sp.pop('_mouth_h', [])
        sp[('mouth_rest_img', Emo.OP)] = (lambda hs: lambda t: -min(1.0, max([0.0] + [h(t) for h in hs]) / MOUTH_SWAP))(hs)
    keys = sorted({k for sp in specs.values() for k in sp})
    specs['mood_normal'] = {}
    out = {}
    frames = list(range(0, MOOD_T + 1, MOOD_STEP))
    for n, sp in specs.items():
        ch = {}
        for name, key in keys:
            base = 1.0 if name == 'mouth_rest_img' else _mood_base(name, key)
            fn = sp.get((name, key))
            if fn is None:
                ch[(E_IDS[name], key)] = [(0, base, LIN), (MOOD_T, base, LIN)]
            else:
                ch[(E_IDS[name], key)] = [(f, base + fn(f % MOOD_T), LIN) for f in frames]
        out[n] = (MOOD_T, ch)
    return out


# --- Разнообразие покоя (ТЗ idle_bonus_1…6; заказчик 27.09) ------------------
# Короткие «разбивки» покоя: приложение запускает одну раз в 15–30 с, когда
# мишку не трогают, с учётом настроения. Каждая начинается и кончается
# покоем. Руки — только чуть-чуть, до 3° (заказчик: «если позволяет, руки
# минимально, не глобально»).

def idle_bonus_1():
    """Потянулся, 2,4 с: чуть присел — вытянулся вверх (грудь полная, спина
    прогнута, голова назад, глаза зажмурены, «м-м»), держит с лёгкой
    дрожью — выдох, осел, уши дёрнулись. Руки чуть в стороны (3°)."""
    e = Emo(144)
    e.track('hips', Emo.Y, [(10, 2.0, EO), (40, -5.0, EO), (80, -5.3), (100, -4.8), (122, 1.0), (136, 0.0)])
    e.track('breath', Emo.SY, [(10, -0.01), (40, 0.08, EO), (100, 0.075), (122, -0.02), (136, 0.0)])
    e.track('chest', Emo.R, [(40, -0.03, EO), (100, -0.028), (124, 0.005), (136, 0.0)])
    e.track('face', Emo.X, [(40, 3.5, EO), (100, 3.2), (124, -0.5), (136, 0.0)])
    e.track('head', Emo.R, [(40, 0.0), (48, 0.01), (58, -0.008), (68, 0.01), (80, -0.006), (92, 0.008), (108, 0.0)])
    e.eyes([(14, 0.0), (40, 0.6, EO), (100, 0.6), (124, 0.0)], lid='both')
    e.pair('brow', Emo.X, [(40, 2.0), (100, 2.0), (124, 0.0)])
    e.mouth_open([(16, 0.1, 0.0), (40, 0.9, 0.8, EO), (100, 0.9, 0.8), (120, 0.1, 0.0)], kind='content')
    e.track('ear_l1', Emo.R, [(40, 0.08), (100, 0.08), (120, -0.05), (130, 0.02), (138, 0.0)])
    e.track('ear_r1', Emo.R, [(40, -0.08), (100, -0.08), (120, 0.05), (130, -0.02), (138, 0.0)])
    e.track('hood2', Emo.R, [(44, -0.05), (104, -0.04), (126, 0.03), (138, 0.0)])
    e.track('arm_l1', Emo.R, [(40, 0.05, EO), (100, 0.05), (124, 0.0)])
    e.track('arm_r1', Emo.R, [(40, -0.05, EO), (100, -0.05), (124, 0.0)])
    return e.build()


def idle_bonus_2():
    """Почесал ушко о плечо, 2,2 с: голова набок (5°) вместе с корпусом
    (2°) — так капюшон не тянется (заказчик 27.09: «искажение капюшона»),
    два раза потёрся, довольный прищур и улыбка — голова возвращается, ухо
    распрямляется с перелётом."""
    e = Emo(132)
    e.track('chest', Emo.R, [(20, -0.03, EO), (92, -0.03), (116, 0.0)])
    e.track('head', Emo.R, [(20, -0.085, EO), (38, -0.065), (56, -0.09), (74, -0.065), (92, -0.085),
                            (114, 0.006), (126, 0.0)])
    e.track('face', Emo.Y, [(20, -4.0, EO), (38, -3.2), (56, -4.2), (74, -3.2), (92, -4.0), (114, 0.0)])
    e.track('face', Emo.X, [(20, -1.0), (92, -1.0), (114, 0.0)])
    e.track('ear_l1', Emo.SX, [(20, -0.06, EO), (92, -0.06), (110, 0.02), (122, 0.0)])
    e.track('ear_l1', Emo.R, [(20, 0.08, EO), (38, 0.05), (56, 0.08), (74, 0.05), (92, 0.08), (112, -0.05), (124, 0.0)])
    e.track('ear_r1', Emo.R, [(24, -0.04), (96, -0.04), (116, 0.03), (128, 0.0)])
    e.track('hips', Emo.X, [(20, -2.5), (92, -2.5), (116, 0.0)])
    e.track('hood2', Emo.R, [(24, -0.06), (96, -0.05), (118, 0.03), (130, 0.0)])
    e.eyes([(10, 0.0), (26, 0.45, EO), (92, 0.45), (114, 0.0)])
    e.pair('lid', Emo.X, [(26, 9, EO), (92, 9), (114, 0)])
    e.pair('cheek', Emo.X, [(26, 4, EO), (92, 4), (114, 0)])
    e.pair('mouth', Emo.X, [(26, 4), (92, 4), (114, 0)])
    e.mouth_open([(14, 0.1, 0.0), (30, 0.85, 0.7, EO), (90, 0.85, 0.7), (108, 0.1, 0.0)], kind='content')
    return e.build()


def idle_bonus_3():
    """Прислушался, 2,5 с: замер (дыхание тише), голова набок к звуку,
    ухо с той стороны торчком и дважды дёргается, глаза шире, брови вверх,
    ротик приоткрыт — голова в другую сторону, там дёргается другое ухо —
    расслабился."""
    e = Emo(150)
    e.track('breath', Emo.SY, [(10, -0.015), (100, -0.012), (120, 0.02), (140, 0.0)])
    e.track('chest', Emo.R, [(18, 0.02, EO), (70, 0.02), (84, -0.02, EO), (116, -0.02), (140, 0.0)])
    e.track('head', Emo.R, [(18, 0.06, EO), (70, 0.06), (84, -0.055, EO), (116, -0.055), (140, 0.0)])
    e.track('face', Emo.Y, [(18, 4.5, EO), (70, 4.5), (84, -4.5, EO), (116, -4.5), (140, 0.0)])
    e.track('face', Emo.X, [(18, 1.5), (116, 1.5), (140, 0.0)])
    e.track('ear_r1', Emo.R, [(14, 0.16, EO), (36, 0.12), (42, 0.19), (48, 0.13), (56, 0.19), (62, 0.14),
                              (74, 0.14), (86, 0.05), (116, 0.05), (140, 0.0)])
    e.track('ear_l1', Emo.R, [(14, -0.05), (74, -0.05), (86, -0.16, EO), (96, -0.12), (102, -0.19),
                              (108, -0.13), (116, -0.16), (140, 0.0)])
    e.track('ear_l2', Emo.R, [(90, -0.06), (118, -0.06), (142, 0.0)])
    e.track('ear_r2', Emo.R, [(18, 0.06), (76, 0.06), (100, 0.0)])
    e.eyes([(16, 0.1, EO), (116, 0.09), (140, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(16, 3.5, EO), (116, 3.2), (140, 0.0)])
    e.mouth_open([(24, 0.1, 0.0), (36, 0.28, 0.22, EO), (112, 0.26, 0.2), (126, 0.1, 0.0)], kind='open')
    e.track('hood2', Emo.R, [(22, 0.06), (88, -0.05), (120, -0.03), (142, 0.0)])
    return e.build()


def idle_bonus_4():
    """Переступил с ноги на ногу, 2 с: вес на левую (таз в сторону, корпус
    наклонился для равновесия) — правая стопа поднялась на 22 px и
    опустилась — вес на правую — левая — выровнялся; без удара. Руки чуть
    покачиваются (2°), уши подпрыгивают на каждом шаге."""
    e = Emo(120)
    e.track('hips', Emo.X, [(10, -5.5, EO), (46, -5.5), (58, 5.5, EI), (92, 5.5), (110, 0.0)])
    e.track('hips', Emo.Y, [(16, -1.5), (26, -2.0), (36, 0.0), (64, -1.5), (74, -2.0), (84, 0.0)])
    e.track('chest', Emo.R, [(10, 0.025, EO), (46, 0.025), (58, -0.025, EI), (92, -0.025), (110, 0.0)])
    e.track('head', Emo.R, [(12, -0.02), (46, -0.02), (60, 0.02), (92, 0.02), (112, 0.0)])
    e.track('foot_r', Emo.Y, [(14, 0.0), (24, -22.0, EO), (30, -22.0), (40, 0.0, EI)])
    e.track('foot_l', Emo.Y, [(62, 0.0), (72, -22.0, EO), (78, -22.0), (88, 0.0, EI)])
    e.track('face', Emo.Y, [(16, 1.5), (60, -1.5), (100, 0.0)])
    e.track('hood2', Emo.R, [(20, -0.05), (32, 0.02), (64, 0.05), (80, -0.02), (104, 0.0)])
    e.track('ear_l1', Emo.R, [(24, -0.06), (36, 0.03), (72, -0.06), (84, 0.03), (100, 0.0)])
    e.track('ear_r1', Emo.R, [(24, 0.06), (36, -0.03), (72, 0.06), (84, -0.03), (100, 0.0)])
    e.track('arm_l1', Emo.R, [(22, 0.03), (70, -0.025), (100, 0.0)])
    e.track('arm_r1', Emo.R, [(22, -0.025), (70, 0.03), (100, 0.0)])
    return e.build()


def idle_bonus_5():
    """Встряхнулся, 1,4 с: зажмурился, сморщил нос — голова и всё тело
    быстро качаются влево-вправо с затуханием, уши и кончик капюшона
    хлопают с запаздыванием — открыл глаза."""
    e = Emo(84)
    e.track('face', Emo.X, [(8, -2.0), (20, -1.5), (66, 0.0)])
    e.eyes([(4, 0.0), (12, 0.85, EO), (50, 0.85), (64, 0.0)], lid='both')
    e.track('muzzle', Emo.X, [(8, 1.5), (50, 1.5), (62, 0.0)])
    sw = [(14, 0.0), (19, 1.0), (25, -0.9), (31, 0.7), (37, -0.45), (43, 0.2), (50, 0.0)]
    e.track('head', Emo.R, [(f, 0.075 * v) for f, v in sw])
    e.track('chest', Emo.R, [(f + 1, 0.02 * v) for f, v in sw])
    e.track('face', Emo.Y, [(f, 3.5 * v) for f, v in sw])
    e.track('hips', Emo.X, [(f + 1, 2.0 * v) for f, v in sw])
    flap = [(22, -0.24), (28, 0.22), (34, -0.16), (40, 0.1), (46, -0.04), (54, 0.0)]
    e.track('ear_l1', Emo.R, flap)
    e.track('ear_r1', Emo.R, flap)
    e.track('ear_l2', Emo.R, [(f + 3, v * 0.7) for f, v in flap])
    e.track('ear_r2', Emo.R, [(f + 3, v * 0.7) for f, v in flap])
    e.track('hood2', Emo.R, [(24, -0.18), (30, 0.16), (36, -0.12), (42, 0.07), (50, 0.0)])
    return e.build()


def idle_bonus_6():
    """Вздохнул и улыбнулся сам себе, 2,8 с: глубокий вдох — плечи и
    голова поднимаются, грудь полная — долгий выдох, осел, глаза на миг
    закрылись — тихая улыбка, радостный прищур, голова набок — улыбка
    гаснет. Руки чуть опускаются на выдохе (1°)."""
    e = Emo(168)
    e.track('breath', Emo.SY, [(6, 0.0), (48, 0.11, EO), (86, -0.03), (120, -0.01), (150, 0.0)])
    e.track('hips', Emo.Y, [(48, -3.5, EO), (86, 2.0), (150, 0.0)])
    e.track('chest', Emo.R, [(48, -0.02), (86, 0.01), (140, 0.0)])
    e.track('face', Emo.X, [(48, 3.0, EO), (86, -2.5), (110, 0.5), (150, 0.0)])
    e.eyes([(60, 0.0), (74, 0.6), (84, 0.6), (96, 0.4, EO), (132, 0.38), (154, 0.0)], lid='both')
    e.mouth_open([(80, 0.1, 0.0), (98, 1.1, 1.1, EO), (132, 1.1, 1.1), (152, 0.1, 0.0)], kind='content')
    e.pair('lid', Emo.X, [(84, 0), (98, 9, EO), (132, 9), (154, 0)])
    e.pair('cheek', Emo.X, [(84, 0), (98, 5, EO), (132, 5), (154, 0)])
    e.pair('mouth', Emo.X, [(84, 0), (98, 6, EO), (132, 6), (154, 0)])
    e.track('head', Emo.R, [(84, 0.0), (104, 0.06, EO), (134, 0.055), (156, 0.0)])
    e.track('face', Emo.Y, [(84, 0.0), (104, 3.0), (134, 2.8), (156, 0.0)])
    e.track('arm_l1', Emo.R, [(86, -0.02), (120, 0.0)])
    e.track('arm_r1', Emo.R, [(86, 0.02), (120, 0.0)])
    _ears(e, [(48, -0.05), (86, 0.06), (140, 0.04), (160, 0.0)])
    return e.build()



# --- Реакции характера (ТЗ reaction_trait_*_touch / *_treat; 27.09) --------
# По две на характер: на касание (тап по мишке) и на угощение. Угощение
# повторяет уже утверждённые реакции кухни (`kitchen_scene.dart`, `_treat`),
# чтобы характер на кухне и в игровой был один. Руки — до 2°.

def _ears(e, pts):
    """Оба уха зеркально: минус — торчком, плюс — вниз-назад."""
    e.track('ear_l1', Emo.R, pts)
    e.track('ear_r1', Emo.R, [(p[0], -p[1], *p[2:]) for p in pts])

def reaction_trait_active_touch():
    """Активный, касание, 1,6 с: присел — радостный подскок, второй
    поменьше, уши вверх, глаза-улыбки, широкая сомкнутая улыбка."""
    e = Emo(96)
    e.track('hips', Emo.Y, [(6, 2.0), (12, 2.5), (24, -7.0, EO), (36, 1.5, EI), (44, 0.5), (54, -3.0, EO), (64, 0.5, EI), (74, 0.0)])
    e.track('breath', Emo.SY, [(12, -0.02), (24, 0.04, EO), (38, -0.01), (56, 0.02), (74, 0.0)])
    e.track('face', Emo.X, [(12, -1.0), (26, 2.5, EO), (70, 1.5), (90, 0.0)])
    _ears(e, [(10, 0.0), (26, -0.08, EO), (40, 0.04), (56, -0.05), (66, 0.02), (80, 0.0)])
    e.track('hood2', Emo.R, [(24, -0.06), (38, 0.05), (56, -0.03), (66, 0.02), (80, 0.0)])
    e.eyes([(8, 0.0), (22, 0.45, EO), (70, 0.4), (88, 0.0)])
    e.pair('lid', Emo.X, [(22, 8, EO), (70, 8), (88, 0)])
    e.pair('cheek', Emo.X, [(22, 4, EO), (70, 4), (88, 0)])
    # улыбка с открытым ртом — ртом утверждённой «Улыбки», чуть шире от
    # радости подскока (заказчик 27.09: «эмоция просит улыбку, а рот закрыт»)
    e.mouth_open([(6, 0.05, 0.0), (22, 1.0, 0.6, EO), (68, 0.97, 0.55), (86, 0.25, 0.0)])
    e.pair('mouth', Emo.X, [(10, 0), (22, 9, EO), (68, 8.5), (88, 0.5)])
    e.pair('mouth', Emo.Y, [(22, -2), (68, -1.8), (88, 0)], mirror=True)
    e.track('arm_l1', Emo.R, [(12, 0.0), (24, 0.035, EO), (40, 0.0), (56, 0.02), (70, 0.0)])
    e.track('arm_r1', Emo.R, [(12, 0.0), (24, -0.035, EO), (40, 0.0), (56, -0.02), (70, 0.0)])
    return e.build()


def reaction_trait_curious_touch():
    """Любознательный, касание, 1,8 с: голова к пальцу набок, глаза шире,
    брови вверх, маленькое «м?» ртом, уши торчком по очереди."""
    e = Emo(108)
    e.track('head', Emo.R, [(6, 0.0), (22, 0.09, EO), (74, 0.08), (96, 0.0)])
    e.track('face', Emo.Y, [(22, 3.5, EO), (74, 3.0), (96, 0.0)])
    e.track('face', Emo.X, [(22, 1.5, EO), (74, 1.5), (96, 0.0)])
    e.track('hips', Emo.X, [(26, 1.5), (74, 1.5), (98, 0.0)])
    e.eyes([(8, 0.0), (22, 0.1, EO), (76, 0.09), (96, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(20, 3.0, EO), (76, 2.6), (96, 0.0)])
    e.track('ear_r1', Emo.R, [(12, 0.0), (22, 0.1, EO), (76, 0.08), (96, 0.0)])
    e.track('ear_l1', Emo.R, [(20, 0.0), (32, -0.09, EO), (76, -0.07), (98, 0.0)])
    e.track('hood2', Emo.R, [(26, -0.05), (50, -0.03), (80, -0.04), (100, 0.0)])
    e.mouth_open([(28, 0.1, 0.0), (40, 0.32, 0.3, EO), (62, 0.3, 0.28), (74, 0.1, 0.0)], kind='open')
    return e.build()


def reaction_trait_affectionate_touch():
    """Ласковый, касание, 2,2 с: тянется головой к пальцу, глаза
    блаженно прищурены, тихая улыбка, счастливый вздох."""
    e = Emo(132)
    e.track('head', Emo.R, [(8, 0.0), (34, 0.11, EO), (70, 0.09), (96, 0.11), (122, 0.0)])
    e.track('face', Emo.Y, [(34, 3.5, EO), (70, 2.8), (96, 3.6), (122, 0.0)])
    e.track('face', Emo.X, [(34, 1.0), (96, 1.0), (122, 0.0)])
    e.track('hips', Emo.X, [(34, 1.5), (96, 1.5), (122, 0.0)])
    e.track('breath', Emo.SY, [(20, 0.0), (52, 0.05, EO), (96, 0.01), (122, 0.0)])
    e.eyes([(6, 0.0), (32, 0.6, EO), (100, 0.58), (124, 0.0)])
    e.pair('lid', Emo.X, [(32, 12, EO), (100, 12), (124, 0)])
    e.pair('cheek', Emo.X, [(32, 5, EO), (100, 5), (124, 0)])
    e.mouth_open([(10, 0.1, 0.0), (32, 1.1, 1.15, EO), (100, 1.1, 1.15), (120, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(12, 0), (32, 5, EO), (100, 5), (120, 0)])
    _ears(e, [(36, 0.07), (100, 0.07), (124, 0.0)])
    e.track('hood2', Emo.R, [(40, -0.05), (100, -0.04), (126, 0.0)])
    e.track('arm_l1', Emo.R, [(40, 0.01), (100, 0.01), (122, 0.0)])
    e.track('arm_r1', Emo.R, [(40, -0.01), (100, -0.01), (122, 0.0)])
    return e.build()


def reaction_trait_calm_touch():
    """Спокойный, касание, 1,8 с: медленно моргнул, мягко улыбнулся и
    неторопливо кивнул."""
    e = Emo(108)
    e.eyes([(10, 0.0), (26, 0.95), (36, 0.95), (54, 0.25, EO), (86, 0.22), (102, 0.0)], lid='both')
    e.mouth_open([(34, 0.1, 0.0), (54, 0.85, 0.75, EO), (86, 0.85, 0.75), (100, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(36, 0), (54, 3, EO), (86, 3), (100, 0)])
    e.track('face', Emo.X, [(40, 0.0), (62, -3.0), (84, 0.0)])
    e.track('head', Emo.R, [(40, 0.0), (62, 0.01), (84, 0.0)])
    e.track('hood2', Emo.R, [(48, 0.0), (70, 0.02), (92, 0.0)])
    return e.build()


def reaction_trait_independent_touch():
    """Самостоятельный, касание, 1,4 с: коротко глянул на палец, кивнул
    «угу» — и отвернулся. Без улыбки."""
    e = Emo(84)
    e.track('face', Emo.Y, [(4, 0.0), (12, 3.0, EO), (36, 3.0), (48, -4.5, EO), (70, -4.5), (84, 0.0)])
    e.track('head', Emo.R, [(14, 0.025), (36, 0.025), (50, -0.035), (70, -0.035), (84, 0.0)])
    e.track('face', Emo.X, [(18, 0.0), (24, -3.0), (30, 0.0), (48, 1.5), (70, 1.5), (84, 0.0)])
    e.track('ear_r1', Emo.R, [(48, 0.0), (52, 0.12), (58, 0.0)])
    e.track('hood2', Emo.R, [(16, -0.02), (40, -0.02), (54, 0.03), (72, 0.03), (84, 0.0)])
    e.pair('brow', Emo.X, [(10, -0.8), (70, -0.8), (84, 0.0)])
    return e.build()


def reaction_trait_reserved_touch():
    """Замкнутый, касание, 2,2 с: чуть съёжился, зажмурился — потом робкая
    улыбка, взгляд вниз, уши назад."""
    e = Emo(132)
    e.track('hips', Emo.Y, [(3, 0.0), (10, 2.5, EO), (40, 2.0), (110, 1.0), (126, 0.0)])
    e.track('breath', Emo.SY, [(3, 0.0), (10, -0.035, EO), (40, -0.02), (110, -0.01), (126, 0.0)])
    e.track('face', Emo.X, [(3, 0.0), (10, -2.5, EO), (40, -2.0), (60, -3.5), (104, -3.5), (126, 0.0)])
    e.track('face', Emo.Y, [(10, -1.5), (60, -2.5), (104, -2.5), (126, 0.0)])
    e.track('head', Emo.R, [(10, -0.03), (104, -0.035), (126, 0.0)])
    e.eyes([(3, 0.0), (9, 0.5, EO), (22, 0.5), (34, 0.0)], lid='both')
    _ears(e, [(10, 0.1, EO), (104, 0.08), (126, 0.0)])
    e.track('hood2', Emo.R, [(14, 0.04), (104, 0.03), (128, 0.0)])
    e.mouth_open([(44, 0.1, 0.0), (62, 0.7, 0.55, EO), (98, 0.7, 0.55), (114, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(46, 0), (62, 2, EO), (98, 2), (114, 0)])
    return e.build()


def reaction_trait_active_treat():
    """Активный, угощение, 3 с: три подскока с затуханием, уши вверх,
    глаза-улыбки, широкая улыбка до 2,4 с; руки чуть похлопывают."""
    e = Emo(180)
    hops = []
    for i, (c, h) in enumerate([(22, 6.0), (48, 4.0), (72, 2.2)]):
        hops += [(c - 8, 1.2), (c, -h, EO), (c + 10, 0.8, EI)]
    e.track('hips', Emo.Y, hops + [(96, 0.0)])
    e.track('breath', Emo.SY, [(14, -0.01), (22, 0.03), (48, 0.02), (72, 0.01), (96, 0.0)])
    e.track('face', Emo.X, [(10, 0.0), (22, 2.5, EO), (140, 1.5), (164, 0.0)])
    _ears(e, [(8, 0.0), (22, -0.08, EO), (32, 0.03), (48, -0.06), (58, 0.02), (72, -0.04),
                          (82, 0.0), (140, -0.04), (166, 0.0)])
    e.track('hood2', Emo.R, [(22, -0.05), (32, 0.04), (48, -0.03), (58, 0.03), (72, -0.02), (86, 0.0)])
    e.eyes([(6, 0.0), (20, 0.45, EO), (140, 0.42), (162, 0.0)])
    e.pair('lid', Emo.X, [(20, 8, EO), (140, 8), (162, 0)])
    e.pair('cheek', Emo.X, [(20, 4, EO), (140, 4), (162, 0)])
    e.mouth_open([(6, 0.1, 0.0), (20, 1.2, 1.3, EO), (140, 1.15, 1.25), (158, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(8, 0), (20, 5, EO), (140, 5), (158, 0)])
    pat = [(14, 0.0), (24, 0.02), (34, 0.0), (48, 0.02), (58, 0.0), (72, 0.015), (84, 0.0)]
    e.track('arm_l1', Emo.R, pat)
    e.track('arm_r1', Emo.R, [(f, -v) for f, v in pat])
    return e.build()


def reaction_trait_curious_treat():
    """Любознательный, угощение, 3,4 с: заглянул вниз на еду с наклоном
    набок, уши торчком — поднял глаза на зрителя, глаза шире, маленькое
    «о» — и обратно."""
    e = Emo(204)
    e.track('face', Emo.X, [(6, 0.0), (30, -4.0, EO), (72, -4.0), (96, 1.5, EO), (138, 1.5), (180, 0.0)])
    e.track('face', Emo.Y, [(6, 0.0), (40, 3.0, EO), (72, 3.0), (100, 0.0)])
    e.track('head', Emo.R, [(6, 0.0), (40, 0.08, EO), (72, 0.08), (104, 0.0)])
    _ears(e, [(14, 0.0), (36, -0.06, EO), (160, -0.05), (190, 0.0)])
    e.track('ear_l2', Emo.R, [(40, -0.04), (160, -0.03), (190, 0.0)])
    e.track('hood2', Emo.R, [(40, -0.05), (80, 0.0), (100, 0.03), (140, 0.02), (184, 0.0)])
    e.eyes([(80, 0.0), (94, 0.1, EO), (138, 0.09), (160, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(20, 1.0), (80, 1.0), (94, 3.0, EO), (138, 2.6), (170, 0.0)])
    e.mouth_open([(88, 0.1, 0.0), (100, 0.33, 0.33, EO), (132, 0.3, 0.3), (146, 0.1, 0.0)], kind='open')
    return e.build()


def reaction_trait_affectionate_treat():
    """Ласковый, угощение, 3,6 с: голова медленно набок, уши мягко вниз,
    два благодарных кивка к зрителю, тёплый прищур, улыбка до 3 с."""
    e = Emo(216)
    e.track('head', Emo.R, [(6, 0.0), (66, 0.1, EO), (156, 0.1), (206, 0.0)])
    e.track('face', Emo.Y, [(66, 3.0, EO), (156, 3.0), (206, 0.0)])
    e.track('face', Emo.X, [(54, 0.0), (66, -3.0), (80, 0.0), (114, 0.0), (126, -3.0), (140, 0.0)])
    _ears(e, [(8, 0.0), (60, 0.07, EO), (156, 0.07), (204, 0.0)])
    e.track('hood2', Emo.R, [(66, -0.04), (156, -0.04), (206, 0.0)])
    e.eyes([(6, 0.0), (40, 0.5, EO), (180, 0.48), (200, 0.0)])
    e.pair('lid', Emo.X, [(40, 10, EO), (180, 10), (200, 0)])
    e.pair('cheek', Emo.X, [(40, 5, EO), (180, 5), (200, 0)])
    e.mouth_open([(8, 0.1, 0.0), (36, 1.05, 1.1, EO), (180, 1.05, 1.1), (198, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(10, 0), (36, 5, EO), (180, 5), (198, 0)])
    e.track('breath', Emo.SY, [(30, 0.0), (70, 0.04), (130, 0.01), (200, 0.0)])
    return e.build()


def reaction_trait_calm_treat():
    """Спокойный, угощение, 3,6 с: один глубокий медленный кивок, уши чуть
    опускаются, мягкая улыбка."""
    e = Emo(216)
    e.track('face', Emo.X, [(12, 0.0), (84, -5.0, EO), (108, -5.0), (192, 0.0)])
    e.track('head', Emo.R, [(12, 0.0), (84, 0.015), (108, 0.015), (192, 0.0)])
    _ears(e, [(18, 0.0), (84, 0.05), (120, 0.05), (198, 0.0)])
    e.track('hood2', Emo.R, [(30, 0.0), (96, 0.04), (120, 0.04), (200, 0.0)])
    e.eyes([(14, 0.0), (60, 0.35, EO), (170, 0.32), (196, 0.0)])
    e.pair('lid', Emo.X, [(60, 6, EO), (170, 6), (196, 0)])
    e.mouth_open([(18, 0.1, 0.0), (54, 0.9, 0.8, EO), (170, 0.9, 0.8), (190, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(20, 0), (54, 3, EO), (170, 3), (190, 0)])
    return e.build()


def reaction_trait_independent_treat():
    """Самостоятельный, угощение, 2,4 с: короткий деловой кивок, взгляд в
    сторону и обратно, оба уха один раз дёрнулись. Без улыбки."""
    e = Emo(144)
    e.track('face', Emo.X, [(6, 0.0), (18, -2.5, EO), (30, 0.0), (54, 1.0), (102, 1.0), (126, 0.0)])
    e.track('face', Emo.Y, [(50, 0.0), (64, -4.0, EO), (102, -4.0), (124, 0.0)])
    e.track('head', Emo.R, [(52, 0.0), (66, -0.03), (102, -0.03), (124, 0.0)])
    _ears(e, [(54, 0.0), (58, -0.1), (66, 0.03), (74, 0.0)])
    e.track('hood2', Emo.R, [(56, 0.0), (70, 0.03), (104, 0.03), (128, 0.0)])
    e.pair('brow', Emo.X, [(10, -0.8), (110, -0.8), (130, 0.0)])
    return e.build()


def reaction_trait_reserved_treat():
    """Замкнутый, угощение, 3,2 с: отвёл взгляд вниз и в сторону с лёгким
    поворотом головы, уши назад, короткая робкая улыбка — и снова обычное
    лицо."""
    e = Emo(192)
    e.track('face', Emo.X, [(6, 0.0), (48, -3.0, EO), (138, -3.0), (180, 0.0)])
    e.track('face', Emo.Y, [(6, 0.0), (48, -4.0, EO), (138, -4.0), (180, 0.0)])
    e.track('head', Emo.R, [(6, 0.0), (48, -0.05, EO), (138, -0.05), (180, 0.0)])
    _ears(e, [(10, 0.0), (48, 0.08), (138, 0.08), (180, 0.0)])
    e.track('hood2', Emo.R, [(20, 0.0), (56, 0.03), (140, 0.03), (184, 0.0)])
    e.eyes([(40, 0.0), (60, 0.18), (96, 0.18), (114, 0.0)])
    e.mouth_open([(46, 0.1, 0.0), (62, 0.7, 0.55, EO), (96, 0.7, 0.55), (112, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(48, 0), (62, 2, EO), (96, 2), (112, 0)])
    return e.build()


TRAIT_REACTIONS = {f'reaction_trait_{t}_{k}': globals()[f'reaction_trait_{t}_{k}']
                   for t in ('active', 'curious', 'affectionate', 'calm', 'independent', 'reserved')
                   for k in ('touch', 'treat')}


EMOTION_ANIMS = {
    'emo_smile': emo_smile, 'emo_laugh': emo_laugh, 'emo_surprised': emo_surprised,
    'emo_sad': emo_sad, 'emo_chew': emo_chew, 'emo_lick': emo_lick,
    'emo_yawn': emo_yawn, 'emo_sleepy': emo_sleepy, 'emo_upset': emo_upset,
    'emo_love': emo_love,
    'pet_face': pet_face, 'pet_pass': pet_pass, 'pet_out': pet_out,
    'act_pet_b': act_pet_b, 'pet_startle': pet_startle,
    'idle_bonus_1': idle_bonus_1,
    'idle_bonus_2': idle_bonus_2,
    'idle_bonus_3': idle_bonus_3,
    'idle_bonus_4': idle_bonus_4,
    'idle_bonus_5': idle_bonus_5,
    'idle_bonus_6': idle_bonus_6,
    **TRAIT_REACTIONS,
}


def assets_by_id(root):
    return {a.attrib['id']: a for a in root.iter('ImageAsset')}


# --- Живое лицо: связки мимики (заказчик 10.10) ------------------------------
# «Двигается только кусочек лица, а лоб, щёки, подбородок будто стоят».
# Каждая эмоция, которая трогает бровь, щёку, подбородок, мордочку или
# сдвигает лицо, сама тянет за собой соседние зоны: брови — лоб (внутренние
# концы бровей вверх — лоб «домиком»), щёки и нижние веки — «яблочки» и
# скулы, подбородок — челюсть, мордочка — нос; сдвиг лица — объёмный
# поворот (TURN). Так все прежние эмоции, настроения и реакции оживают
# разом, без переписывания каждой.
# (цель, ключ, [(источник, ключ, доля)]): смещение цели от покоя — сумма
# долей смещений источников.
_R, _SX, _SY, _X, _Y = 15, 16, 17, 90, 91
COUPLE = [
    # брови чуть заметнее, лоб — целиком за ними, середина лба — «домиком»,
    # когда внутренние концы бровей поднимаются
    ('brow_l', _X, [('brow_l', _X, 0.25)]),
    ('brow_r', _X, [('brow_r', _X, 0.25)]),
    ('fore_l', _X, [('brow_l', _X, 1.0)]),
    ('fore_r', _X, [('brow_r', _X, 1.0)]),
    ('fore_c', _X, [('brow_l', _X, 0.5), ('brow_r', _X, 0.5),
                    ('brow_l', _R, -14.0), ('brow_r', _R, 14.0)]),
    ('apple_l', _X, [('cheek_l', _X, 0.7), ('lid_l', _X, 0.25)]),
    ('apple_r', _X, [('cheek_r', _X, 0.7), ('lid_r', _X, 0.25)]),
    ('apple_l', _SY, [('cheek_l', _SY, 0.6)]),
    ('apple_r', _SY, [('cheek_r', _SY, 0.6)]),
    ('zyg_l', _X, [('cheek_l', _X, 0.45)]),
    ('zyg_r', _X, [('cheek_r', _X, 0.45)]),
    ('jaw', _X, [('chin', _X, 0.7)]),
    ('jaw', _Y, [('chin', _Y, 0.7)]),
    ('jaw', _SX, [('chin', _SX, 0.8)]),
    ('nose', _X, [('muzzle', _X, 1.0), ('cheek_l', _X, 0.08), ('cheek_r', _X, 0.08)]),
    ('nose', _SX, [('muzzle', _SX, 0.6)]),
    ('ear_l1', _R, [('face', _Y, EAR_TURN)]),
    ('ear_r1', _R, [('face', _Y, EAR_TURN)]),
    # плечи поднимаются на глубоком вдохе (зевок, вздох, смех) — ключицы
    ('clav_l', _R, [('breath', _SY, 0.5)]),
    ('clav_r', _R, [('breath', _SY, -0.5)]),
] + [(name, key, [('face', _Y if src == 'y' else _X, k)]) for name, key, src, k in TURN]


def _merged_couple():
    """Связки по цели: у одной цели может быть несколько строк (нос — от
    мордочки и от поворота лица), их источники складываются."""
    by = {}
    for name, key, sources in COUPLE:
        by.setdefault((name, key), []).extend(sources)
    return [(name, key, sources) for (name, key), sources in by.items()]

# Точность упрощения выведенных дорожек: точка, которую соседи и так дают с
# такой погрешностью, не нужна.
_TOL = {_R: 0.0005, _X: 0.05, _Y: 0.05, _SX: 0.0005, _SY: 0.0005}


def _bezier_y(ease, u):
    """CSS cubic-bezier(x1 y1 x2 y2): y при x = u."""
    x1, y1, x2, y2 = (float(v) for v in ease.split())
    lo, hi = 0.0, 1.0
    for _ in range(40):
        t = (lo + hi) / 2
        x = 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t * t * x2 + t ** 3
        lo, hi = (t, hi) if x < u else (lo, t)
    t = (lo + hi) / 2
    return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t * t * y2 + t ** 3


def track_at(frames, fr):
    """Значение дорожки [(кадр, значение, кривая)] в кадре fr — как в Rive:
    кривая ключа ведёт отрезок до следующего, None — держит значение."""
    if fr <= frames[0][0]:
        return frames[0][1]
    for (f0, v0, e0), (f1, v1, _) in zip(frames, frames[1:]):
        if f0 <= fr <= f1:
            if fr == f1:
                return v1
            if e0 is None:
                return v0
            return v0 + (v1 - v0) * _bezier_y(e0, (fr - f0) / (f1 - f0))
    return frames[-1][1]


def _rest_of(name, key):
    r = E_REST[name]
    return {_R: r.get('rotation', 0.0), _X: r.get('x', 0.0), _Y: r.get('y', 0.0)}.get(key, 1.0)


def _simplify(pts, tol):
    """Убрать точки, которые линейная интерполяция соседей даёт и так."""
    keep = list(pts)
    changed = True
    while changed and len(keep) > 2:
        changed = False
        out = [keep[0]]
        i = 1
        while i < len(keep) - 1:
            (f0, v0), (f1, v1), (f2, v2) = out[-1], keep[i], keep[i + 1]
            lin = v0 + (v2 - v0) * (f1 - f0) / (f2 - f0)
            if abs(lin - v1) < tol:
                changed = True
            else:
                out.append(keep[i])
            i += 1
        out.append(keep[-1])
        keep = out
    return keep


def couple(dur, ch):
    """Добавить к клипу дорожки связок COUPLE (см. выше). Своя дорожка у
    цели, если есть, складывается со связкой."""
    names = {v: k for k, v in E_IDS.items()}
    src = {}
    for (oid, key), frames in ch.items():
        n = names.get(oid)
        if n is not None and frames:
            src[(n, key)] = frames
    out = dict(ch)
    for tname, tkey, sources in _merged_couple():
        live = [(src[(sn, sk)], _rest_of(sn, sk), k) for sn, sk, k in sources if (sn, sk) in src]
        if not live or tname not in E_IDS:
            continue
        tid = E_IDS[tname]
        base = _rest_of(tname, tkey)
        own = src.get((tname, tkey))
        frs = set(range(0, dur + 1, 2))
        for frames, _, _ in live:
            frs |= {fr for fr, *_ in frames if 0 <= fr <= dur}
        pts = []
        for fr in sorted(frs):
            v = base if own is None else track_at(own, fr)
            for frames, b, k in live:
                v += k * (track_at(frames, fr) - b)
            pts.append((fr, v))
        if own is None and max(abs(v - base) for _, v in pts) < _TOL.get(tkey, 1e-3):
            continue
        pts = _simplify(pts, _TOL.get(tkey, 1e-3) / 2)
        out[(tid, tkey)] = [(fr, v, LIN) for fr, v in pts]
    legs_ik(dur, out, src)
    return out


# --- Колени (заказчик 10.10: «сгиб в коленях») ------------------------------
# Бедро держится за таз, стопа стоит на полу; таз опустился — колено само
# сгибается наружу, как у плюшевого мишки спереди, поднялась стопа (притоп,
# шаг) — сгибается сильнее. Изгиб считается здесь, при сборке, по законам
# двухзвенного IK и ложится обычными ключами: в самом Rive решатель IK у
# прямой ноги разводил бы колени «лягушкой» от каждого вдоха. Укорочение
# ноги делят колено (доля bend) и мягкое сжатие плюша; таз выше покоя —
# нога просто вытягивается, изгиб не меняется (рисунок ног прямой).
KNEE_BEND = 0.5        # эмоции: таз опустился — присел
KNEE_BEND_LIFT = 0.15  # стопа поднялась (притоп, шаг): спереди нога в основном
#                        укорачивается — колено идёт к зрителю, а не вбок
KNEE_BEND_BREATH = 0.2  # дыхание: колено едва-едва


def _leg_geom(side):
    by = {n: (p, st, en) for n, p, st, en in CHAIN if n in (f'leg_{side}', f'shin_{side}')}
    hip, knee = by[f'leg_{side}'][1], by[f'leg_{side}'][2]
    ankle = by[f'shin_{side}'][2]
    return hip, knee, ankle


def leg_ik(side, dx=0.0, dy=0.0, fx=0.0, fy=0.0, bend=KNEE_BEND):
    """Сдвиг таза (dx, dy) и стопы (fx, fy), px мира → смещения от покоя:
    поворот бедра, поворот голени относительно бедра, масштаб бедра."""
    hip, knee, ankle = _leg_geom(side)
    L1 = math.hypot(knee[0] - hip[0], knee[1] - hip[1])
    L2 = math.hypot(ankle[0] - knee[0], ankle[1] - knee[1])
    th0 = math.atan2(knee[1] - hip[1], knee[0] - hip[0])
    sh0 = math.atan2(ankle[1] - knee[1], ankle[0] - knee[0])
    D0 = math.hypot(ankle[0] - hip[0], ankle[1] - hip[1])
    hx, hy = hip[0] + dx, hip[1] + dy
    ax, ay = ankle[0] + fx, ankle[1] + fy
    D = math.hypot(ax - hx, ay - hy)
    if D >= D0:
        sc = D / D0                               # выше покоя — только вытянуться
    else:
        sc = 1 - (1 - bend) * (D0 - D) / D0
    l1, l2 = sc * L1, sc * L2
    cos_a = max(-1.0, min(1.0, (l1 * l1 + D * D - l2 * l2) / (2 * l1 * D)))
    a = math.acos(cos_a)
    base = math.atan2(ay - hy, ax - hx)
    out = -1 if knee[0] < hip[0] else 1           # колено наружу: левое — влево
    th = base + (a if out < 0 else -a)
    kx, ky = hx + l1 * math.cos(th), hy + l1 * math.sin(th)
    sh = math.atan2(ay - ky, ax - kx)
    return th - th0, (sh - th) - (sh0 - th0), sc


def legs_ik(dur, out, src):
    """Колени для клипа: по сдвигам таза и стоп — ключи бедра и голени."""
    hx = src.get(('hips', _X))
    hy = src.get(('hips', _Y))
    for side in ('l', 'r'):
        fx = src.get((f'foot_{side}', _X))
        fy = src.get((f'foot_{side}', _Y))
        tracks = [t for t in (hx, hy, fx, fy) if t]
        if not tracks:
            continue
        frs = set(range(0, dur + 1, 2))
        for t in tracks:
            frs |= {fr for fr, *_ in t if 0 <= fr <= dur}
        th, sh, sc = [], [], []
        for fr in sorted(frs):
            def off(t, name, key):
                return 0.0 if t is None else track_at(t, fr) - _rest_of(name, key)
            dyh, dyf = off(hy, 'hips', _Y), off(fy, f'foot_{side}', _Y)
            drop, lift = max(0.0, dyh), max(0.0, -dyf)
            bend = ((KNEE_BEND * drop + KNEE_BEND_LIFT * lift) / (drop + lift)
                    if drop + lift > 1e-6 else KNEE_BEND)
            r1, r2, k = leg_ik(side, off(hx, 'hips', _X), dyh,
                               off(fx, f'foot_{side}', _X), dyf, bend=bend)
            th.append((fr, _rest_of(f'leg_{side}', _R) + r1))
            sh.append((fr, _rest_of(f'shin_{side}', _R) + r2))
            sc.append((fr, k))
        for name, key, pts in ((f'leg_{side}', _R, th), (f'shin_{side}', _R, sh), (f'leg_{side}', _SX, sc)):
            base = _rest_of(name, key)
            if max(abs(v - base) for _, v in pts) < _TOL[key]:
                continue
            out[(E_IDS[name], key)] = [(fr, v, LIN) for fr, v in _simplify(pts, _TOL[key] / 2)]


def couple_moods(moods):
    """Связки для петель настроения: у всех петель — один набор каналов
    (приложение смешивает их между собой, и канал, которого нет в одной из
    петель, при переходе застрял бы в прошлой позе)."""
    out = {n: (d, couple(d, ch)) for n, (d, ch) in moods.items()}
    keys = set().union(*(ch.keys() for _, ch in out.values()))
    names = {v: k for k, v in E_IDS.items()}
    for n, (d, ch) in out.items():
        for oid, key in keys - ch.keys():
            name = names[oid]
            base = 1.0 if name == 'mouth_rest_img' else _mood_base(name, key)
            ch[(oid, key)] = [(0, base, LIN), (d, base, LIN)]
    return out


def check_keys(root):
    """Сдвиг x/y у Node и картинок — ключи 13/14, у корневой кости — 90/91.
    Чужой ключ рантайм молча пропускает — движение просто не происходит
    (так до 10.10 стояли глаза в улыбке, NODE_XY). Иначе — ошибка сборки."""
    ab = root.find('Artboard')
    tag = {e.get('id'): e.tag for e in ab.iter() if e.get('id')}
    bad = set()
    for an in ab.iter('LinearAnimation'):
        for ko in an.iter('KeyedObject'):
            t = tag.get(ko.get('objectId'))
            for kp in ko.iter('KeyedProperty'):
                k = int(kp.get('propertyKey'))
                if (k in (90, 91) and t != 'RootBone') or (k in (13, 14) and t in ('Bone', 'RootBone')):
                    bad.add((an.get('name'), t, ko.get('objectId'), k))
    if bad:
        raise SystemExit('ключ сдвига не того типа (клип, тип, id, ключ): '
                         + ', '.join(map(str, sorted(bad)[:12])) + f' — всего {len(bad)}')


def check_eyes(root):
    """Бусины глаз в клипах вверх не уходят — нижнее веко не поднимается
    (заказчик 10.10: «это ужас»). Иначе — ошибка сборки."""
    ab = root.find('Artboard')
    rest = {WRAP_IDS[k]: E_REST[k]['y'] for k in ('bead_l', 'bead_r')}
    bad = set()
    for an in ab.iter('LinearAnimation'):
        for ko in an.iter('KeyedObject'):
            if ko.get('objectId') not in rest:
                continue
            for kp in ko.iter('KeyedProperty'):
                if kp.get('propertyKey') != '14':
                    continue
                if any(float(k.get('value')) < rest[ko.get('objectId')] - 0.05
                       for k in kp.iter('KeyFrameDouble')):
                    bad.add(an.get('name'))
    if bad:
        raise SystemExit('глаза уходят вверх (нижнее веко): ' + ', '.join(sorted(bad)))


def check_mouths(root):
    """Два рта — никогда: в каждом кадре каждого клипа ротик покоя и любой
    другой рот не видны оба больше чем наполовину. Иначе — ошибка сборки."""
    rest_id = E_IDS['mouth_rest_img']
    mouth_ids = {v for k, v in E_IDS.items() if k.startswith('mouth_') and k.endswith('_img')
                 and k != 'mouth_rest_img'}

    def curve(kp):
        ks = [(int(k.get('frame', '0')), float(k.get('value')), k.get('interpolationType')) for k in kp]
        return sorted(ks)

    def at(ks, fr, default):
        if not ks:
            return default
        if fr <= ks[0][0]:
            return ks[0][1]
        for (f0, v0, it), (f1, v1, _) in zip(ks, ks[1:]):
            if f0 <= fr <= f1:
                return v0 if it == 'hold' else v0 + (v1 - v0) * (fr - f0) / max(1, f1 - f0)
        return ks[-1][1]
    bad = []
    for an in root.iter('LinearAnimation'):
        if an.get('name', '').startswith('mop_'):     # служебные: прозрачности для приложения
            continue
        rest, mouths = [], []
        for ko in an.findall('KeyedObject'):
            oid = ko.get('objectId')
            for kp in ko.findall('KeyedProperty'):
                if kp.get('propertyKey') != '18':
                    continue
                if oid == rest_id:
                    rest = curve(kp)
                elif oid in mouth_ids:
                    mouths.append(curve(kp))
        if not mouths:
            continue
        for fr in range(int(an.get('duration', '0')) + 1):
            r = at(rest, fr, 1.0)
            m = max(at(ks, fr, 0.0) for ks in mouths)
            if min(r, m) > 0.5:
                bad.append((an.get('name'), fr, round(r, 2), round(m, 2)))
                break
    if bad:
        raise RuntimeError('два рта (клип, кадр, ротик покоя, другой рот): %s' % bad)


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
        'leg_left': 'foot_l', 'leg_right': 'foot_r',
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
        if name.startswith('jaw_'):   # в покое челюсть поднята к губе — полость сомкнута
            _, top, bot = mouth.rows(name[4:])
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
    # 4в''. Датчики ртов `mh_<вид>` (27.09): невидимые узлы, их y — насколько
    #      раскрыт рот (та же высота, что в mouth_open). Приложение после всех
    #      смешиваний читает их и само ставит прозрачности ртов (клипы mop_*):
    #      смесь двух петель или петли с эмоцией иначе давала полупрозрачную
    #      улыбку поверх полупрозрачного ротика покоя.
    for k in mouth.KINDS:
        nid = ident(next(ids))
        # RootBone, а не Node: у костей x/y — ключи 90/91, как у всех Emo.track
        ab.insert(0, ET.Element('RootBone', {'x': '0', 'y': '0', 'length': '0',
                                             'name': f'mh_{k}', 'id': nid}))
        E_IDS[f'mh_{k}'] = nid
        E_REST[f'mh_{k}'] = dict(x=0.0, y=0.0)
    # 4в'''. Ткань кофты и рукавов под капюшоном — с запасом (underpaint.py):
    #       при движении головы из-под края капюшона видна кофта, а не срез.
    print('underpaint', underpaint.build(project, root, byname), 'px')
    # 4г. Расправленная кофта у подмышек поверх кофты (crease.py).
    for side, cid in crease.build(project, root, ab, byname, lambda: ident(next(ids))).items():
        E_IDS[f'flat_{side}'] = cid

    # 5. Сетки: новые сухожилия и веса.
    #    Карта расстояний до контура мордочки — для кромки капюшона.
    import cv2
    global FACE_DIST
    fa = np.asarray(Image.open(os.path.join(project, assets_by_id(root)[byname['face_img'].attrib['assetId']]
                                            .attrib['file'])).convert('RGBA'))[..., 3]
    FACE_DIST = cv2.distanceTransform((fa < 128).astype(np.uint8), cv2.DIST_L2, 5)
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
    double_blink(idle)
    for wrap, frames in saccades().items():
        ko = ET.SubElement(idle, 'KeyedObject', {'objectId': WRAP_IDS[wrap]})
        kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': '13'})
        for fr, val in frames:
            ET.SubElement(kp, 'KeyFrameDouble', {'value': fmt(val), 'frame': str(fr),
                                                 'interpolationType': 'linear'})
    rest = {name: dict(b['local']) for name, b in B.items()}
    for (bname, key), frames in {**breathing(B, rest), **blink_face(rest)}.items():
        ko = ET.SubElement(idle, 'KeyedObject', {'objectId': B[bname]['id']})
        kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
        for fr, val in frames:
            ET.SubElement(kp, 'KeyFrameDouble', {'value': fmt(val), 'frame': str(fr),
                                                 'interpolationType': 'linear'})

    # 8. Эмоции на новых костях: emo_smile заново, остальные — новые.
    anims = {a.attrib.get('name'): a for a in root.iter('LinearAnimation')}
    # Живое лицо (10.10): связки мимики ко всем эмоциям, реакциям и петлям.
    builders = {n: (lambda fn: lambda: (lambda d, c: (d, couple(d, c)))(*fn()))(fn)
                for n, fn in EMOTION_ANIMS.items()}
    for n, dc in couple_moods(build_moods()).items():       # петли настроения (loop)
        builders[n] = (lambda dc: lambda: dc)(dc)
    # прозрачности ртов для приложения: mop_zero гасит все, mop_<вид> — один на 1
    layers = ['rest'] + list(mouth.KINDS)
    builders['mop_zero'] = lambda: (1, {(E_IDS[f'mouth_{k}_img'], Emo.OP): [(0, 0.0, None)] for k in layers})
    for k in layers:
        builders[f'mop_{k}'] = (lambda k: lambda: (1, {(E_IDS[f'mouth_{k}_img'], Emo.OP): [(0, 1.0, None)]}))(k)
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
            if oid in WRAP_IDS.values():
                key = NODE_XY.get(key, key)
            ko = ET.SubElement(emo, 'KeyedObject', {'objectId': oid})
            kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': str(key)})
            for fr, val, ease in frames:
                cubic_key(kp, fr, val, ease)

    check_mouths(root)
    check_keys(root)
    check_eyes(root)
    ET.indent(tree, space='    ')
    tree.write(path, encoding='unicode')
    print('bones', len(B), 'followers', len(followers))


if __name__ == '__main__':
    main(sys.argv[1])
