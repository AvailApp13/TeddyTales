"""Мимика v2 — лицо как в видео Ирины, у мальчика и у девочки.

    PYTHONHASHSEED=0 python3 tool/rive/face_v2.py        # мальчик → assets/rive/bear_boy_v3.riv
    PYTHONHASHSEED=0 python3 tool/rive/face_v2_girl.py   # девочка → assets/rive/bear_girl_v2.riv

Заказчик 26.10: «всё, что я прислал, нужно полностью один в один
реализовать на нашего мишку… глазки, всё», затем: «делаем ровно всё так,
как в видео… и у мальчика, и у девочки, все эмоции». Разбор листов —
`docs/mimika-v2.md`, задания по эмоциям — `docs/mimika-v2-spec.md`.

Риг тот же (`build_bear.py`, `rebuild_rig.py`); здесь — части лица своим
рисунком на костях (`vec.py`) и набор выражений:
- рот — вышитый шов: стежок от носа и «домик» ∧; улыбка, грусть, обида —
  позы того же шва (`POSES`), без смены картинки; раскрытые рты — полости
  (`mouth.py`) и свои «о» и губки «3» (`VMOUTHS`) растут из шва, правило
  «два рта — никогда» то же (`MOUTH_SWAP`, `check_mouths`);
- нос — выше, тёмный шоколад, «щиток»; глаза — глянцевые бусины с бликом,
  глаз сидит прямо в меху; закрытые глаза — дужки ◠/◡ (кости `arc_*`) или
  вышитая черта ◡ (`fx_eyes_closed`: моргание, сон); мокрые глаза, слёзы;
- бровки — штрихи на трёх костях (`bw_*`): дуга, «домиком», сердитые;
- румянец, покраснение лица, сердце на груди — слои на сетках лица и кофты;
- выражения (`EXPR`) — числа по каналам; `face(e, keys)` строит из ключей
  «выражение@кадр» все каналы лица клипа, `reface` меняет лицо готового
  клипа, не трогая тело, `reface_mood` — то же для петель.

Геометрия героя — словарь (`BOY` здесь, девочка — `face_v2_girl.py`),
`install(geom)` ставит всё в риг до сборки.
"""
import copy
import math
import os
import sys
import xml.etree.ElementTree as ET

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_bear  # noqa: E402
import mouth  # noqa: E402
import rebuild_rig as rr  # noqa: E402
import vec  # noqa: E402
from mesh_refine import _read_indices, _write_indices, VERT_TAGS  # noqa: E402
from xf import M, world_map  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
X, Y, SX, SY, R, OP = rr.Emo.X, rr.Emo.Y, rr.Emo.SX, rr.Emo.SY, rr.Emo.R, rr.Emo.OP

# Геометрия героя (px мира в покое). Мальчик; девочка — face_v2_girl.py.
BOY = dict(
    out=os.path.join(ROOT, 'assets/rive/bear_boy_v3.riv'),
    # нос видео: верх 438, кончик 479, середина 458,5 (прежний — 468)
    nose_bone=((513, 458.5), (513, 448.5)), nose_zone=(513, 458.5, 27, 21),
    nose_tip=(513.5, 477.0),          # стежок начинается внутри низа носа
    junction=(513.5, 498.0),          # развилка «домика»: стежок 19 px («Спокойствие 1–4»)
    beads={'l': (457.0, 415.3), 'r': (567.2, 414.9)},
    brow_y=380.0,
    blush={'l': (431.0, 457.0), 'r': (593.0, 457.0)},
    heart=(540.0, 648.0), heart_w=140.0, heart_hole=(539.0, 598.0, 17.0),   # сердце на груди («Любовь 1–3»)
    seam_rgb='#4a2610', brow_rgb='#4a2a18', arc_rgb='#250806',
    blush_rgb=(236, 128, 128), red_rgb=(232, 96, 86),
    shirt='shirt_img',
)
G = {}

# --- Картинки мальчика до сборки рига ----------------------------------------
# Текстура лица → мир (сетка лица в покое): x = 505,70 + (px − 666,5) · 0,6298,
# y = 480,52 + (py − 1000) · 0,6298.
# Нос видео («Спокойствие 1–6»): выше прежнего, тёмный шоколад, «щиток»
# шире своей высоты (1,2 : 1). Мир: верх 438, кончик 479, ширина 50.
NOSE_BOX = (638.0, 932.0, 718.0, 998.0)       # то же в пикселях текстуры
NOSE_RGB = (82.0, 42.0, 23.0)                  # середина носа в кадрах
NOSE_ROI = (625, 935, 735, 1020)               # где искать прежний нос
# Бусины видео: глянцевые, почти чёрные с тёплым низом, чёткий край, белый
# блик справа выше середины, вторая точка у края, светлый серп отражения
# по нижнему краю. Пиксели картинки бусины; масштаб картинки 0,63.
BEAD_R_PX = 26.5                               # 16,7 px мира, глаз 33 px
BEAD_SHADE = 30.0                              # мягкая тень до кольца век
BEAD_RGB = ((12.0, 8.0, 7.0), (22.0, 15.0, 12.0), (44.0, 27.0, 19.0))   # верх, середина, низ
GLINT = ((4.8, -5.0, 2.5, 0.95), (13.5, 4.0, 1.5, 0.75))   # (dx, dy, радиус, сила)
OLD_EYES = ((589, 896), (764, 896))            # прежние глаза в текстуре лица
EYE_HOLE = 36                                  # их радиус с ворсинками, px текстуры


def _inpaint(rgb, hole, shift=110, axis=1):
    """Закрасить hole мехом: гладкая заливка по краям + ворс, взятый на
    `shift` пикселей правее (axis=1, щека) или ниже (axis=0; отрицательный —
    выше, лоб): там чистый мех, без глаз, носа и края текстуры — сдвиг вниз
    от носа приносил край картинки полосами."""
    bgr = np.ascontiguousarray(rgb[..., ::-1].clip(0, 255).astype(np.uint8))
    base = cv2.inpaint(bgr, (hole * 255).astype(np.uint8), 9, cv2.INPAINT_TELEA)[..., ::-1].astype(np.float64)
    src = np.roll(rgb, -shift, axis=axis)
    det = src - np.dstack([ndimage.gaussian_filter(src[..., i], 3) for i in range(3)])
    f = ndimage.gaussian_filter(hole.astype(np.float64), 2.0)[..., None]
    return rgb * (1 - f) + (base + det * 0.9) * f


def fill_eyes(rgb, alpha, eyes, radius, shift=-80):
    """Прежние глаза в текстуре лица — мехом: глазница-заплатка над ними
    была светлее и серее меха, и сплющенная бусина (смех, моргание)
    открывала бледный овал. В видео глаз сидит прямо в меху."""
    H, W = rgb.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    lum = rgb.mean(2)
    for cx, cy in eyes:
        d = np.hypot(xx - cx, yy - cy)
        hole = ndimage.binary_dilation((d < radius) | ((d < radius + 18) & (lum < 175)), iterations=3)
        rgb = _inpaint(rgb, hole, shift, axis=0)
        # цвет заплатки — как у меха вокруг (по краю глаза был серый ворс)
        ring = (d > radius + 22) & (d < radius + 40) & (alpha > 250)
        f = ndimage.gaussian_filter(hole.astype(np.float64), 4.0)[..., None]
        rgb = rgb + (rgb[ring].mean(0) - rgb[hole].mean(0)) * f
    return rgb


def _face(path):
    """Лицо мальчика: прежние глаза — мехом, нос — шоколадный «щиток»."""
    nose_edit(path, NOSE_ROI, NOSE_BOX, NOSE_RGB, eyes=(OLD_EYES, EYE_HOLE))


def nose_edit(path, roi_box, box, color, eyes=None, egg=None):
    """Нос лица — контур прежнего, симметричный, перенесён в box (пиксели
    текстуры) и перекрашен в color — шоколад видео; фактура ткани
    остаётся. egg — (доля высоты самого широкого места, ширина низа): нос
    «яйцом» (девочка). Прежний ротик ∧ стирает с лица `mouth.build` (его
    слой заменяет шов, `seam`)."""
    face = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64)
    rgb, alpha = face[..., :3], face[..., 3]
    H, W = rgb.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    lum = rgb.mean(2)
    r, b = rgb[..., 0], rgb[..., 2]
    if eyes:
        rgb = fill_eyes(rgb, alpha, *eyes)
    lum = rgb.mean(2)

    x0, y0, x1, y1 = roi_box
    roi = (xx > x0) & (xx < x1) & (yy > y0) & (yy < y1)
    core = roi & (lum < 135) & (r - b > 30)
    core = ndimage.binary_opening(core, iterations=1)
    core = ndimage.binary_closing(core, iterations=4)
    core = ndimage.binary_fill_holes(core)
    lab, n = ndimage.label(core)
    core = lab == (np.argmax(ndimage.sum(core, lab, range(1, n + 1))) + 1)
    core = ndimage.gaussian_filter(core.astype(np.float64), 2.5) > 0.5
    xs = np.nonzero(core)[1]
    mid = int(round((xs.min() + xs.max()) / 2))
    win = core[:, mid - 60:mid + 61].astype(np.float64)
    sym = np.zeros(core.shape)
    sym[:, mid - 60:mid + 61] = (win + win[:, ::-1]) / 2
    core = ndimage.gaussian_filter(sym, 3.0) > 0.4
    ys, xs = np.nonzero(core)
    cx0, cx1, cy0, cy1 = xs.min(), xs.max(), ys.min(), ys.max()
    tx0, ty0, tx1, ty1 = box
    sx, sy = (tx1 - tx0) / (cx1 - cx0), (ty1 - ty0) / (cy1 - cy0)
    F = np.array([[sx, 0, tx0 - cx0 * sx], [0, sy, ty0 - cy0 * sy]], np.float32)
    mask = cv2.warpAffine(core.astype(np.float32), F, (W, H), flags=cv2.INTER_LINEAR) > 0.5
    moved = cv2.warpAffine(rgb.astype(np.float32), F, (W, H), flags=cv2.INTER_LINEAR,
                           borderMode=cv2.BORDER_REPLICATE).astype(np.float64)
    if egg:
        # «яйцо»: ниже самого широкого места строки сужаются к низу до egg[1]
        top_k, low_w = egg
        mx = (tx0 + tx1) / 2
        v = ((yy - ty0) / (ty1 - ty0)).astype(np.float32)
        k = (1.0 - (1.0 - low_w) * np.clip((v - top_k) / (1 - top_k), 0, 1) ** 1.3).clip(low_w, 1)
        mapx = (mx + (xx - mx) / k).astype(np.float32)
        mapy = yy.astype(np.float32)
        mask = cv2.remap(mask.astype(np.float32), mapx, mapy, cv2.INTER_LINEAR) > 0.5
        moved = cv2.remap(moved.astype(np.float32), mapx, mapy, cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_REPLICATE).astype(np.float64)

    shade = roi & (lum < 175) & (r - b > 22)
    hole = (ndimage.binary_dilation(core | shade, iterations=6)
            | (ndimage.binary_dilation(core, iterations=12) & (yy > 990)))
    rgb = _inpaint(rgb, hole)

    detail = moved.mean(2, keepdims=True) - moved[mask].mean()
    nose = np.array(color) + detail * 0.75
    ys = np.nonzero(mask)[0]
    v = ((yy - ys.min()) / (ys.max() - ys.min())).clip(0, 1)[..., None]
    hl = np.exp(-(((xx - (tx0 + tx1) / 2) / 17.0) ** 2
                  + ((yy - (ys.min() + 0.25 * (ys.max() - ys.min()))) / 7.0) ** 2))[..., None] * 0.20
    nose = nose * (1 - 0.18 * v) * (1 - hl) + np.array([160.0, 120.0, 100.0]) * hl
    edge = ndimage.gaussian_filter(mask.astype(np.float64), 1.0)[..., None]
    rgb = rgb * (1 - edge) + nose * edge
    Image.fromarray(np.dstack([rgb.clip(0, 255), alpha]).astype(np.uint8), 'RGBA').save(path)


def bead(path):
    """Бусина видео на месте прежней: тот же размер картинки, центр диска —
    там же (центр тёмного в прежней картинке)."""
    old = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64)
    H, W = old.shape[:2]
    dark = (old[..., 3] > 200) & (old[..., :3].mean(2) < 100)
    ys, xs = np.nonzero(dark)
    cx, cy = xs.mean() + 0.5, ys.mean() + 0.5
    yy, xx = np.mgrid[0:H, 0:W] + 0.5
    dx, dy = xx - cx, yy - cy
    d = np.hypot(dx, dy)
    disc = np.clip(BEAD_R_PX + 0.5 - d, 0, 1)
    top, midc, bot = (np.array(c) for c in BEAD_RGB)
    v = (dy / BEAD_R_PX).clip(-1, 1)[..., None]
    col = np.where(v < 0, midc + (top - midc) * -v, midc + (bot - midc) * v ** 2)
    # светлый серп по нижнему краю (отражение в стекле)
    ang = np.arctan2(dy, dx)
    rim = (np.clip(1 - np.abs(d - (BEAD_R_PX - 2.2)) / 1.3, 0, 1)
           * np.clip(np.cos(ang - math.radians(125)) * 1.6 - 0.35, 0, 1) * 0.30)[..., None]
    col = col * (1 - rim) + np.array([215.0, 205.0, 200.0]) * rim
    for gx, gy, gr, k in GLINT:
        g = (np.clip(gr + 0.5 - np.hypot(dx - gx, dy - gy), 0, 1) * k)[..., None]
        col = col * (1 - g) + 255.0 * g
    shade = np.clip((BEAD_SHADE - d) / (BEAD_SHADE - BEAD_R_PX), 0, 1) ** 1.5 * 0.45
    a = np.maximum(disc, shade * (d > BEAD_R_PX))
    col = np.where((disc > 0)[..., None], col, np.array([40.0, 26.0, 20.0]))
    Image.fromarray(np.dstack([col.clip(0, 255), a * 255]).round().astype(np.uint8), 'RGBA').save(path)


def clear(path):
    """Картинка остаётся своего размера, но прозрачная: глазницу-заплатку
    `lids.py` впекает в лицо — теперь там мех самого лица."""
    im = Image.open(path).convert('RGBA')
    Image.new('RGBA', im.size, (0, 0, 0, 0)).save(path)


def closed_eye(path):
    """Закрытый глаз (моргание, сон, `fx_eyes_closed`): от прежней картинки
    остаётся только вышитая черта ◡ — без бледного диска меха вокруг."""
    im = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64)
    lum = im[..., :3].mean(2)
    line = (lum < 140) & (im[..., 3] > 200)
    lab, n = ndimage.label(ndimage.binary_closing(line, iterations=2))
    line = lab == (np.argmax(ndimage.sum(line, lab, range(1, n + 1))) + 1)
    a = np.clip((170 - lum) / 40, 0, 1) * ndimage.binary_dilation(line, iterations=3)
    a = np.maximum(a, line) * ndimage.gaussian_filter(line.astype(np.float64), 1.2).clip(0, 1) ** 0.3
    rgb = im[..., :3] * 0.85
    Image.fromarray(np.dstack([rgb, a * 255]).clip(0, 255).round().astype(np.uint8), 'RGBA').save(path)


def prepare(project):
    """Картинки мальчика до сборки рига: веки (`lids.py`) и сетки строятся
    уже по новому лицу."""
    _face(os.path.join(project, 'bear_face.png'))
    for side in 'lr':
        bead(os.path.join(project, f'face_gaze_bead_{side}.png'))
        clear(os.path.join(project, f'face_gaze_socket_{side}.png'))
        closed_eye(os.path.join(project, f'face_eyes_closed_eye_{side}.png'))


# --- Рот-шов -------------------------------------------------------------------
SEAM_W = 2.2                # толщина стежка, px мира (кадры: #3e2111–#58300d)
LEG = 17.0                  # длина ножки «домика»
LEG_ANGLE = 32              # градусов вниз от горизонтали (видео: ширина 28,4, провис 9,5)
LEG_T = tuple(round(0.1 * i, 1) for i in range(1, 11))   # кости ножки — доли её длины
LEG_STEPS = 30                          # точек на ножку (дуги улыбки гладкие)


def _rest_leg(s, t):
    """Ножка «домика» в покое, от развилки: s = −1 левая, +1 правая; конец
    чуть загибается вниз (кадры «Спокойствие 1–6»)."""
    a, leg = math.radians(G.get('leg_angle', LEG_ANGLE)), G.get('leg', LEG)
    return s * leg * t * math.cos(a), leg * t * math.sin(a) + 1.0 * t * t


# Позы шва (замеры кадров; межглазье 110 px): сдвиг развилки и ножка от
# развилки как функция доли длины t.
POSES = {
    # «Спокойствие 1–4»: домик ∧
    'rest': ((0.0, 0.0), _rest_leg),
    # «Улыбка 1, 3»: мягкая «ω» 54 px — дно на 2 px ниже развилки, уголки
    # мягко вверх; стежок 23 px (развилка ниже покоя на 4)
    'smile': ((0.0, 4.0), lambda s, t: (s * 27.0 * t, 2.8 * math.sin(math.pi * t) - 2.5 * t * t)),
    # «Улыбка 2, 4», «Радость 3»: широкая «ω» 86 px с острым пиком на
    # развилке, дно +6,5 на ±17, уголки −9,5 (таблица кадра 4)
    'smile_wide': ((0.0, 2.0), lambda s, t: (s * 43.0 * t, _table(G.get('wide_y', WIDE_Y), t))),
    # «Грусть 2–3»: ∩ — ножка выпуклая, конец круто вниз; стежок 18
    'sad': ((0.0, -1.0), lambda s, t: (s * 13.5 * t, 6.0 * t + 4.5 * t * t)),
    # «Грусть 6»: широкий ∩ — дуга по всей длине, развилка ниже
    'sad_wide': ((0.0, 5.0), lambda s, t: (s * 21.0 * t, 5.0 * t + 6.0 * t * t)),
    # «Обида 2–3»: надутые губы ∩ — концы загнуты вниз, развилка на месте
    'pout': ((0.0, 0.5), lambda s, t: (s * 13.0 * t, 5.0 * t + 6.5 * t * t)),
    # «Обида 1»: губа надута вбок — левая ножка крючком вниз
    'pout_side': ((0.0, 0.0), lambda s, t: (s * (12.0 if s < 0 else 11.0) * t,
                                            (5.0 * t + 10.0 * t * t) if s < 0 else (4.5 * t + 5.0 * t * t))),
    # «Сонливость 2»: маленький ∧ под тяжёлыми веками
    'sleepy': ((0.0, 2.5), lambda s, t: (s * 12.5 * t, 7.0 * t + 1.0 * t * t)),
    # «Сон 1–3»: спокойный ∧ с мягкой вершиной
    'sleep': ((0.0, 4.5), lambda s, t: (s * 13.5 * t, 7.5 * t + 4.0 * t * t)),
    # «Огорчение 2», «Грусть 5»: дуга-хмурость ⌒ (верх рта «frown»)
    'frown': ((0.0, 2.5), lambda s, t: (s * 20.5 * t, 3.5 * t + 6.5 * t * t)),
    # «Плач 2»: всхлип — верх тёмной дуги ⌒ (рот «sob»)
    'sob': ((0.0, -4.5), lambda s, t: (s * 30.0 * t, 6.0 * t + 4.0 * t * t)),
    # «Плач 3–4»: широкий ∧ и он же с дрожью губы
    'cry_wide': ((0.0, -1.5), lambda s, t: (s * 23.5 * t, 10.5 * t + 1.0 * t * t)),
    'cry_wave': ((0.0, -1.5), lambda s, t: (s * 23.5 * t, 10.5 * t + 1.0 * t * t + 1.3 * math.sin(2 * math.pi * t))),
    # «Злость 1–4»: ∧ уголками вниз, правый ниже — чуть кривой
    'anger': ((0.0, -1.0), lambda s, t: (s * 14.0 * t, (10.0 * t + 4.0 * t * t) if s < 0 else (13.0 * t + 3.5 * t * t))),
    # «Сомнение 3»: шов подтянут к носу дугой ∩
    'doubt': ((0.0, -5.5), lambda s, t: (s * 14.0 * t, 5.5 * t + 6.5 * t * t)),
    # «Растерянность 1–2»: поджатый кривой домик — ближняя ножка длиннее
    'hmm': ((0.0, -5.0), lambda s, t: ((0.85 if s > 0 else 0.6) * _rest_leg(s, t)[0], 1.05 * _rest_leg(s, t)[1])),
    # «Смущение 2»: крошечный сомкнутый ∧
    'shy': ((0.0, -0.8), lambda s, t: (s * 11.0 * t, 5.8 * t + 0.55 * t * t)),
    # «Подмигивание 2, 4»: «‿» с плоским дном и задорными уголками, 66 px
    'wink': ((0.0, -3.0), lambda s, t: (s * 33.0 * t, _table(WINK_Y, t))),
    # «Еда 2»: сомкнутые губы при жевании «‿», уголки загнуты вверх (рот «munch»)
    'munch': ((0.0, 2.0), lambda s, t: (s * 23.0 * t, 11.0 * math.sin(0.75 * math.pi * t))),
    # «Зевок 3»: линия губы большого «U» (рот «gape»)
    'yawnlip': ((0.0, 0.0), lambda s, t: (s * 32.0 * t, _table(GAPE_Y, t))),
    # «Огорчение», «Плач»: дрожащий узкий ∧ — уголки чуть волной
    'wobble': ((0.0, 6.5), lambda s, t: (s * 12.5 * t, 8.0 * t + 4.0 * t * t - 1.6 * math.sin(math.pi * t))),
    # «Сомнение»: уголок одной стороны вверх, другой — домиком
    'smirk': ((0.0, 4.5), lambda s, t: (s * (16.0 if s > 0 else 13.0) * t,
                                        (-3.0 * math.sin(math.pi * t) - 2.5 * t * t) if s > 0 else (6.0 * t + 1.5 * t * t))),
    # «Растерянность»: неровная волна — одна ножка выше
    'wavy': ((0.0, 5.5), lambda s, t: (s * 14.0 * t, (5.0 * t + 1.5 * math.sin(2 * math.pi * t)) if s > 0
                                       else (7.0 * t - 1.5 * math.sin(2 * math.pi * t)))),
    # «Испуг»: узкий высокий ∧, стежок короче
    'fear': ((0.0, -2.0), lambda s, t: (s * 13.0 * t, 11.5 * t + 1.0 * t * t)),
    # губки сомкнуты в точку перед «чмок»: ножки сходятся
    'purse': ((0.0, 8.0), lambda s, t: (s * 4.0 * t, 3.0 * t)),
    # шов — линия губы «D» смеха и радости: «домик» перетекает в неё до
    # того, как раскроется полость, и гаснет ровно на её месте
    'lip': ((0.0, 0.0), lambda s, t: (s * 38.5 * t, _table(LIP_Y, t))),
    'joylip': ((0.0, 0.0), lambda s, t: (s * 46.0 * t, _table(JOYLIP_Y, t))),
    # «Восторг 1–3»: линия губы «D» 100 px — середина плоско провисает на
    # 6,5 ниже конца стежка (стежок дотягивается до неё), концы острые
    'dlip': ((0.0, 6.5), lambda s, t: (s * 50.0 * t, _table(DLIP_Y, t))),
    # «Нежность 1»: «лодочка» 62 px — донце мелкое, уголки крючком вверх
    'tender': ((0.0, 5.0), lambda s, t: (s * 31.0 * t, _table(TENDER_Y, t))),
}
LIP_Y = (0.0, -0.1, -0.3, -0.5, -0.9, -1.4, -1.9, -2.4, -3.0, -4.4, -9.0)
JOYLIP_Y = (0.0, 1.1, 2.3, 3.2, 3.9, 4.0, 3.7, 3.3, 2.7, -0.3, -4.0)
DLIP_Y = (0.0, 0.1, 0.3, 0.4, 0.3, -0.5, -1.8, -3.6, -5.8, -8.2, -11.5)
TENDER_Y = (0.0, 0.5, 1.1, 1.5, 1.6, 1.2, 0.2, -1.8, -4.6, -8.0, -12.0)
WINK_Y = (0.0, 1.2, 1.9, 1.9, 1.3, 0.3, -0.9, -2.6, -5.0, -8.0, -11.0)
GAPE_Y = (0.0, 1.8, 3.6, 5.2, 6.6, 7.8, 8.6, 9.0, 8.6, 7.2, 5.0)
# широкая «ω»: высота ножки от развилки (вниз +) по долям 0, 0,1 … 1,0
WIDE_Y = (0.0, 2.7, 4.8, 6.2, 6.5, 6.0, 4.5, 2.0, -1.0, -6.5, -9.5)


def _table(ys, t):
    """Значение таблицы ys (равные шаги по t от 0 до 1) — гладко (Катмулл — Ром)."""
    n = len(ys) - 1
    x = min(max(t, 0.0), 1.0) * n
    i = min(int(x), n - 1)
    u = x - i
    p0, p1, p2, p3 = ys[max(i - 1, 0)], ys[i], ys[i + 1], ys[min(i + 2, n)]
    return 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                  + (3 * p1 - p0 - 3 * p2 + p3) * u ** 3)


# ротик-линия прежних клипов → поза шва
SEAM_KINDS = {'content': 'smile', 'sad': 'sad', 'pout': 'pout', 'sleepy': 'sleepy'}
SEAM_BONES = ['seam_c'] + [f'seam_{side}{i}' for side in 'lr' for i in range(1, len(LEG_T) + 1)]


def _seam_bone_world(name):
    jx, jy = G['junction']
    if name == 'seam_c':
        return jx, jy
    s = -1 if name[5] == 'l' else 1
    dx, dy = _rest_leg(s, LEG_T[int(name[6:]) - 1])
    return jx + dx, jy + dy


def pose_offsets(pose, k=1.0):
    """{кость: (dx, dy) мира} — сдвиг костей шва от покоя к позе, доля k."""
    (jx, jy), leg = POSES[pose]
    out = {'seam_c': (jx * k, jy * k)}
    for side, s in (('l', -1), ('r', 1)):
        for i, t in enumerate(LEG_T, 1):
            px, py = leg(s, t)
            rx, ry = _rest_leg(s, t)
            out[f'seam_{side}{i}'] = ((jx + px - rx) * k, (jy + py - ry) * k)
    return out


def to_local(dx, dy):
    """Сдвиг мира → ключи x/y кости эмоции под лицом (лицо смотрит вверх:
    локальный x — вверх, y — вправо)."""
    return -dy, dx


def _leg_weights(side, t):
    knots = [0.0] + list(LEG_T)
    names = ['seam_c'] + [f'seam_{side}{i}' for i in range(1, len(LEG_T) + 1)]
    for (t0, a), (t1, b) in zip(zip(knots, names), zip(knots[1:], names[1:])):
        if t <= t1 + 1e-9:
            u = (t - t0) / (t1 - t0)
            return {n: v for n, v in ((a, 1 - u), (b, u)) if v > 1e-4}
    return {names[-1]: 1.0}


def seam(ctx):
    """Шов вместо картинки ротика покоя: та же роль в клипах и приложении
    (ключи прозрачности `mouth_rest_img`, клип `mop_rest`); картинки
    ртов-линий убраны, их прозрачность — прозрачность шва."""
    ab, B = ctx['ab'], ctx['B']
    rest = ctx['byname'].get('face_mouth_rest_img') or next(
        e for e in ab.iter('Image') if e.get('name') == 'face_mouth_rest_img')
    holder = next(p for p in ab.iter() if rest in list(p))
    hw = ctx['W'][holder]
    common = dict(bones=B, pack=rr.pack, next_id=ctx['next_id'], holder_world=hw, stroke=(SEAM_W, G['seam_rgb']))
    (nx, ny), (jx, jy) = G['nose_tip'], G['junction']

    # стежок от носа: верх — за мехом носа, низ — за развилкой
    nose_pts = [(nx, ny + (jy - ny) * i / 6) for i in range(7)]

    def nose_w(x, y):
        u = (y - ny) / (jy - ny)
        fur = rr.weights_for('face_seam', x, y, B)
        w = {b: v * (1 - u) for b, v in fur.items()}
        w['seam_c'] = w.get('seam_c', 0) + u
        return {b: v for b, v in w.items() if v > 1e-4}
    nose = vec.shape('face_seam_nose', nose_pts, weights=nose_w, **common)

    leg_pts, leg_ws = [], []
    for side, s in (('l', -1), ('r', 1)):
        part = []
        for i in range(LEG_STEPS + 1):
            t = i / LEG_STEPS
            dx, dy = _rest_leg(s, t)
            part.append(((jx + dx, jy + dy), _leg_weights(side, t)))
        part = part[::-1] if side == 'l' else part[1:]
        for p, w in part:
            leg_pts.append(p)
            leg_ws.append(w)
    lookup = dict(zip(leg_pts, leg_ws))
    legs = vec.shape('face_seam_legs', leg_pts, weights=lambda x, y: lookup[(x, y)], **common)

    at = list(holder).index(rest)
    holder.insert(at, legs)
    holder.insert(at, nose)
    holder.remove(rest)
    rr.E_IDS['mouth_rest_img'] = legs.get('id')
    for kind in SEAM_KINDS:                    # картинки ртов-линий не нужны
        img = next(e for e in ab.iter('Image') if e.get('id') == rr.E_IDS[f'mouth_{kind}_img'])
        next(p for p in ab.iter() if img in list(p)).remove(img)
        rr.E_IDS[f'mouth_{kind}_img'] = legs.get('id')


# --- Свои рты: «о» и губки «3» ---------------------------------------------------
# Растут из развилки шва костью `mouth_<вид>` (как полости `mouth.py`):
# в покое сжаты (`VMOUTHS` — масштаб ширины и высоты), раскрываются
# `Emo.mouth_open`; в приложении — свои датчики `mh_<вид>` и `mop_<вид>`.
VMOUTHS = {'o': (0.35, 0.08), 'kiss': (0.3, 0.25), 'd': (0.45, 0.06), 'laugh': (0.5, 0.05),
           'delight': (0.5, 0.05), 'frown': (1.0, 0.1), 'sob': (1.0, 0.1), 'munch': (1.0, 0.15),
           'gape': (0.5, 0.04)}
# где кость рта сжимает его (сдвиг от развилки): «D» восторга растёт из
# середины линии губы, а не из конца стежка
VPIVOT = {'delight': (0.0, 6.5)}
MOUTH_DARK, MOUTH_LINE, TONGUE = '#3c1b10', '#2a1208', '#e58f97'


# Рты-линзы («Грусть 5», «Огорчение 2» — хмурость ⌒, «Плач 2» — всхлип,
# «Еда 2» — жевание, «Зевок 3» — большое «U»): верх — линия шва в своей
# позе (на костях шва), низ — на «костях глубины» `sd_*`, детях костей шва.
# В покое кости глубины на месте: низ лежит на верхе, рот сомкнут ровно по
# шву; раскрываясь, рот уходит вниз от шва на глубину depth(t)·h (t — доля
# ножки). Рот растёт из шва и в него же смыкается — подмены нет.
def _gape_depth(t):
    """Глубина «U» зевка под линией губы (кадр 3): низ (x; y) от развилки."""
    bot = ((0, 62.0), (8, 60.0), (16, 55.0), (22, 48.0), (26.5, 37.0), (28.5, 25.0), (30, 13.0), (32, 5.0))
    x = 32.0 * t
    for (x0, y0), (x1, y1) in zip(bot, bot[1:]):
        if x <= x1:
            yb = y0 + (y1 - y0) * (x - x0) / (x1 - x0)
            break
    else:
        yb = bot[-1][1]
    return max(0.0, yb - _table(GAPE_Y, t))


GROWN = {
    # «Грусть 5», «Огорчение»: приоткрытый серп ⌒, концы острые
    'frown': ('frown', lambda t: 7.0 * (1 - t * t)),
    # «Плач 2»: тёмная дуга всхлипа, концы скруглены
    'sob': ('sob', lambda t: (8.0 - 2.0 * t * t) * math.sqrt(min(1.0, max(0.0, (1 - t) / 0.15)))),
    # «Еда 2»: щёлочка жевания — у развилки линза, к уголкам на нет
    'munch': ('munch', lambda t: max(10.0 * (1 - t / 0.3) ** 2 if t < 0.3 else 0.0, 4.0 * math.sin(math.pi * t))),
    # «Зевок 3»: большое «U» 64 × 62 с языком-куполом
    'gape': ('yawnlip', _gape_depth),
}
LENS_RGB = {'frown': ('#3c1b10', '#2a1208', 1.6), 'sob': ('#3c1b10', '#2a1208', 1.6),
            'munch': ('#2a0402', '#3a1208', 1.4), 'gape': ('#140202', '#945543', 1.6)}
SD_BONES = ['sd' + n[4:] for n in SEAM_BONES]


def _sd_t(name):
    """Доля ножки кости глубины (или шва)."""
    tail = name.split('_', 1)[1]
    return 0.0 if tail == 'c' else LEG_T[int(tail[1:]) - 1]


def lens_depth(kind, h):
    """{кость глубины: сдвиг X (вверх +)} рта kind при раскрытии h."""
    depth = GROWN[kind][1]
    return {b: -depth(_sd_t(b)) * h for b in SD_BONES}


def _lens_shapes(kind, common):
    """Фигуры рта-линзы kind: губа (шов), обвод низа, язык (у зевка), полость."""
    jx, jy = G['junction']
    look = {}
    top, bot = [], []
    n = 30
    for i in range(-n, n + 1):
        sg, t = (1 if i >= 0 else -1), abs(i) / n
        side = 'r' if sg > 0 else 'l'
        rx, ry = _rest_leg(sg, t)
        p = (jx + rx, jy + ry)
        w = _leg_weights(side, t)
        look[p] = w
        top.append(p)
        if 0 < abs(i) < n or i == 0:
            q = (p[0], p[1] + 1e-3)
            look[q] = {'sd' + b[4:]: v for b, v in w.items()}
            bot.append(q)
    wt = lambda x, y: look[(x, y)]
    cav, rim, rim_w = LENS_RGB[kind]
    cavity = vec.shape(f'{kind}_cavity', top + bot[::-1], weights=wt, closed=True, fill=(cav,), **common)
    out = [vec.shape(f'{kind}_lip', top, weights=wt, stroke=(SEAM_W, G['seam_rgb']), **common),
           vec.shape(f'{kind}_rim', [top[0]] + bot + [top[-1]], weights=wt, stroke=(rim_w, rim), **common)]
    if kind == 'gape':
        # язык-купол на кости глубины у развилки: нарисован на полную глубину
        # выше, опускается вместе с дном; виден только внутри полости
        d0 = _gape_depth(0.0)
        dome = [(-17, 46.0), (-14, 40.0), (-8, 36.0), (0, 34.0), (8, 36.0), (14, 40.0), (17, 46.0)]
        tg = _spline(dome, 3) + [(x, 60.5 - 0.03 * x * x) for x in [17 - 34 * i / 8 for i in range(1, 8)]]
        tongue = vec.shape('gape_tongue', [(jx + x, jy + y - d0) for x, y in tg], weights=lambda x, y: {'sd_c': 1.0},
                           closed=True, fill=('#8a3536',), stroke=(1.0, '#5b1619'), **common)
        ET.SubElement(tongue, 'ClippingShape', {'sourceId': cavity.get('id'), 'name': 'clip',
                                                'id': common['next_id']()})
        out.append(tongue)
    return out + [cavity]


def _spline(pts, n=4):
    """Гладкая ломаная через точки (Катмулл — Ром), n отрезков на звено."""
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2 = pts[max(i - 1, 0)], pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        for k in range(n):
            u = k / n
            out.append(tuple(0.5 * (2 * b + (c - a) * u + (2 * a - 5 * b + 4 * c - d) * u * u
                                    + (3 * b - a - 3 * c + d) * u ** 3) for a, b, c, d in zip(p0, p1, p2, p3)))
    return out + [pts[-1]]


def _grown_d(kind, pose, common, bottom, tongue, colors, t_end=1.0):
    """Рот «D», выросший из шва: верх полости и линия губы лежат на костях
    шва (нарисованы на «домике» покоя — в позе pose встают ровно на её
    линию), низ — на кости рта (сжимается к `VPIVOT`), у концов — снова на
    шве. Шов гаснет под линией губы на том же месте, скачка нет.
    bottom — низ полости от правого конца до левого (сдвиги от развилки),
    tongue — язык (на кости рта); colors — (полость, обвод низа, язык,
    свет языка, край языка)."""
    jx, jy = G['junction']
    off = pose_offsets(pose)
    bone = f'mouth_{kind}'

    def delta(side, t):
        dx = dy = 0.0
        for b, w in _leg_weights(side, t).items():
            dx += w * off[b][0]
            dy += w * off[b][1]
        return dx, dy

    def rest(s, t):
        rx, ry = _rest_leg(s, t)
        return jx + rx, jy + ry

    look = {}
    top = []
    n = 24
    for i in range(-n, n + 1):
        s, t = (1 if i >= 0 else -1), abs(i) / n * t_end
        p = rest(s, t)
        look[p] = _leg_weights('r' if s > 0 else 'l', t)
        top.append(p)
    x_end = abs(POSES[pose][1](1, t_end)[0])
    bot = []
    for x, y in bottom[1:-1]:
        side = 'r' if x >= 0 else 'l'
        t = t_end * min(1.0, abs(x) / x_end)
        a = min(1.0, max(0.0, 1 - (abs(x) / x_end) ** 3))
        dx, dy = delta(side, t)
        p = (jx + x - (1 - a) * dx, jy + y - (1 - a) * dy)
        w = {b: v * (1 - a) for b, v in _leg_weights(side, t).items()}
        w[bone] = w.get(bone, 0.0) + a
        look[p] = {b: v for b, v in w.items() if v > 1e-4}
        bot.append(p)
    one = {bone: 1.0}
    at = lambda pts: [(jx + x, jy + y) for x, y in pts]
    wt = lambda x, y: look.get((x, y), one)
    cav, rim, tg, light, edge = colors
    dome = [p for p in tongue if p[1] <= min(q[1] for q in tongue) + 6]
    band = dome + [(x, y + 3.0 * (1 - (x / max(abs(q[0]) for q in dome)) ** 2)) for x, y in dome[::-1]]
    return [vec.shape(f'{kind}_lip', top, weights=wt, stroke=(2.0, G['seam_rgb']), **common),
            vec.shape(f'{kind}_tongue_light', at(band), weights=wt, closed=True, fill=(light,), **common),
            vec.shape(f'{kind}_tongue', at(tongue), weights=wt, closed=True, fill=(tg,), stroke=(0.8, edge), **common),
            vec.shape(f'{kind}_rim', [top[-1]] + bot + [top[0]], weights=wt, stroke=(1.4, rim), **common),
            vec.shape(f'{kind}_cavity', top + bot, weights=wt, closed=True, fill=(cav,), **common)]


def _ellipse(cx, cy, rx, ry, n=28):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _vmouth_shapes(kind, common):
    """Фигуры рта kind в мире (покой — раскрыт целиком; кость сжимает)."""
    jx, jy = G['junction']
    one = {f'mouth_{kind}': 1.0}
    if kind == 'o':
        # «Удивление 1–2»: «о» — капля острым концом вверх: острый верх —
        # конец стежка (ножки «домика» стали её краями), низ круглый;
        # 25 × 37,5, язык — пологий купол внизу
        right = [(0, 0), (4.5, 2), (6.2, 4), (8.2, 6), (10, 9), (11.2, 12), (12, 15), (12.5, 18), (12.7, 22),
                 (12.2, 26), (11.7, 28), (10.5, 30), (9.7, 32), (8.2, 34), (5.5, 36), (0, 37.5)]
        cav = right + [(-x, y) for x, y in right[::-1][1:-1]]
        tongue = ([(x, 19.5 + 2 * (x / 11) ** 2) for x in [-11 + 22 * i / 10 for i in range(11)]]
                  + [(x, y) for x, y in [(10.3, 30), (9.4, 32), (7.6, 34), (5.0, 35.6), (0, 36.6),
                                         (-5.0, 35.6), (-7.6, 34), (-9.4, 32), (-10.3, 30)]])
        at = lambda pts: [(jx + x, jy + y) for x, y in pts]
        w = lambda x, y: one
        band = [(x, 19.5 + 2 * (x / 11) ** 2) for x in [-10 + 20 * i / 10 for i in range(11)]]
        band += [(x, y + 3.0 * (1 - (x / 10) ** 2)) for x, y in band[::-1]]
        # язык приглушённо-розовый, верх светлее (кадры: #8f524b, верх #b0706a)
        return [vec.shape('o_tongue_light', at(band), weights=w, closed=True, fill=('#b0706a',), **common),
                vec.shape('o_tongue', at(tongue), weights=w, closed=True, fill=('#9a5550',),
                          stroke=(0.8, '#6e302c'), **common),
                vec.shape('o_cavity', at(cav), weights=w, closed=True, fill=('#360b04',),
                          stroke=(1.4, '#2a0802'), **common)]
    if kind in GROWN:
        return _lens_shapes(kind, common)
    if kind == 'delight':
        # «Восторг 1–3»: «D» 100 × 38,5 — верх плоско провисает (поза
        # 'dlip'), низ — полная U, язык-купол 26 × 12, приглушённый
        right = [(50, -5.0), (48.5, 1.5), (46, 7.5), (42, 13.5), (36, 20.0), (29, 26.5), (20, 33.0), (10, 37.3),
                 (0, 38.5)]
        bottom = _spline(right + [(-x, y) for x, y in right[::-1][1:]], 3)
        dome = [(-13, 36.0), (-11, 29.0), (-7, 26.3), (0, 25.5), (7, 26.3), (11, 29.0), (13, 36.0)]
        tongue = _spline(dome, 3) + [(x, 37.5 - 0.0128 * x * x) for x in [13 - 26 * i / 8 for i in range(1, 8)]]
        return _grown_d('delight', 'dlip', common, bottom, tongue,
                        ('#290b07', '#3a1208', '#a06e62', '#ba9085', '#7a4a40'))
    if kind == 'd':
        # «Радость 1»: маленькое «D» плашмя — под «ω» шва раскрылась полость:
        # верх — выемка у стежка, на ±20 ниже на 4; низ — парабола
        # y = 24 − 0,0163·x²; уголки — крючки вверх-наружу до (±46; −4)
        top_ = [(-38, 2.5), (-30, 3.5), (-20, 4.0), (-10, 2.5), (-4, 1.0), (0, 0.0),
                (4, 1.0), (10, 2.5), (20, 4.0), (30, 3.5), (38, 2.5)]
        bot = [(x, 24 - 0.0163 * x * x) for x in [38 - 76 * i / 12 for i in range(13)]]
        lip = [(-46, -4.0)] + top_ + [(46, -4.0)]
        tongue = ([(x, 19 - 5.5 * (1 - (x / 15) ** 2)) for x in [-15 + 30 * i / 10 for i in range(11)]]
                  + [(x, 24 - 0.0163 * x * x) for x in [15 - 30 * i / 8 for i in range(9)]])
        return _mouth_parts(jx, jy, one, common, top_ + bot, bot, lip, tongue, '#2a0402', '#3a1208', 'd_tongue')
    if kind == 'laugh':
        # «Смех 3–4»: большое «D» — линия губы с крючками уголков вверх
        # (середина у стежка), проём вниз до 43, язык-купол в нижней половине
        lip_l = [(-38.5, -9.0), (-37.5, -6.5), (-35, -4.5), (-31, -3.0), (-20, -1.5), (-10, -0.4)]
        lip = lip_l + [(0, 0.0)] + [(-x, y) for x, y in lip_l[::-1]]
        side = [(-31, -3.0), (-30.5, 3.0), (-27, 21.0), (-21, 34.0), (-11, 41.0), (0, 43.0)]
        bot = side + [(-x, y) for x, y in side[::-1][1:]]
        cav = lip[3:-3] + bot[::-1][1:-1]          # верх слева направо, низ — обратно
        dome = [(19 * math.cos(math.pi * (1 - i / 12)), 35 - 13 * math.sin(math.pi * (1 - i / 12))) for i in range(13)]
        tongue = dome + [(x, y) for x, y in bot[::-1] if abs(x) < 19]
        return _mouth_parts(jx, jy, one, common, cav, bot, lip, tongue, '#4a1a0c', '#2e1008')
    # «Поцелуй 1–2»: губки «ε» 18,4 × 43,5 во весь рот под носом —
    # маленькая верхняя дужка и большая «C» снизу, острый уголок на развилке,
    # конец загнут вверх; нитка цветом шва
    mid = [(-9.3, -15), (-11.6, -12), (-13.2, -9), (-14, -6), (-13.4, -3), (-8, -0.6), (0, 0)]
    low = [(0, 0), (-9.8, 3), (-11.9, 5.2), (-15, 8.5), (-16.4, 13), (-16.2, 17.5), (-15.2, 21.5), (-11, 25.6),
           (-5.5, 28.5), (-1, 27.3), (2, 23)]
    pts = [(jx + x, jy + y) for x, y in _spline(mid, 8)[:-1] + _spline(low, 8)]
    return [vec.shape('kiss_line', pts, weights=lambda x, y: one, stroke=(3.0, G['seam_rgb']), **common)]


def _mouth_parts(jx, jy, one, common, cavity, bottom, lip, tongue, dark, rim, tongue_bone=None):
    """Фигуры рта «D» (сверху вниз): линия губы цветом шва, язык, обвод низа,
    полость. Точки — сдвиги от развилки шва. tongue_bone — своя кость языка
    (большой язык «вкусно!»); язык виден только внутри полости."""
    at = lambda pts: [(jx + x, jy + y) for x, y in pts]
    w = lambda x, y: one
    cav = vec.shape('d_cavity', at(cavity), weights=w, closed=True, fill=(dark,), **common)
    tg = vec.shape('d_tongue', at(tongue), weights=(lambda x, y: {tongue_bone: 1.0}) if tongue_bone else w,
                   closed=True, fill=('#d47a7c',), stroke=(0.8, '#a5524c'), **common)
    ET.SubElement(tg, 'ClippingShape', {'sourceId': cav.get('id'), 'name': 'clip', 'id': common['next_id']()})
    return [vec.shape('d_lip', at(lip), weights=w, stroke=(2.2, G['seam_rgb']), **common), tg,
            vec.shape('d_rim', at(bottom), weights=w, stroke=(1.5, rim), **common), cav]


# --- Дужки, бровки, слёзы, мокрые глаза ---------------------------------------
# «Смех 3–4», «Подмигивание»: глазки закрыты тёмным серпом ◠ в нижней
# половине глаза (ширина 34, в середине 8, на концах 3; гребень на 9 выше
# концов; концы на cy+14). Глаз закрывается сверху вниз: верхнее веко
# опускает бусину к линии серпа и сплющивает в черту (вверх она не уходит),
# на её месте проявляется полоска серпа, середина поднимается костью
# `arc_<сторона>`. Без подмены картинки.
ARC_HALF, ARC_T, ARC_DY = 17.0, 3.2, 14.0
# Бровки: три кости на бровь (`bw_<сторона>o/m/i` — внешний конец,
# середина, внутренний у переносицы), дети костей зон бровей: поднимаются
# вместе с мехом лба, а форму задают сами. В покое — пологая дужка.
BROW_HALF, BROW_ARCH, BROW_W = 12.0, 3.0, 2.8
# формы бровок: сдвиг (к переносице, вниз) px мира концов и середины
BROW_SHAPES = {
    'arch': {'o': (0.0, 1.5), 'm': (0.0, -3.5), 'i': (0.0, 1.5)},     # высокая дуга: удивление
    # смех и радость: штрих 25° внутренним концом вверх, чуть выгнут вверх
    'laugh': {'o': (-2.0, 3.5), 'm': (-1.0, -1.5), 'i': (-1.0, -7.5)},
    # «Удивление 1–2»: штрих высоко на лбу (центр y≈340), наклон 29°
    # внутренним концом вверх, сдвинут наружу; мех лба не тянется
    'surprise': {'o': (-7.5, -28.0), 'm': (-10.0, -34.0), 'i': (-9.5, -40.5)},
    # «Испуг»: «тревожный домик» — наружная половина почти ровная,
    # внутренний конец круто вверх, середина прогнута вниз
    'fear': {'o': (2.0, 4.5), 'm': (5.0, 2.5), 'i': (8.0, -10.5)},
    'sad': {'o': (-1.0, 4.0), 'm': (0.0, -1.0), 'i': (0.0, -7.0)},    # «домиком»: грусть, плач
    'angry': {'o': (0.0, -3.5), 'm': (0.0, 0.0), 'i': (1.0, 5.0)},    # к переносице: злость
    'flat': {'o': (0.0, 0.0), 'm': (0.0, 2.5), 'i': (0.0, 0.0)},      # прямые: сомнение
    'knit': {'o': (6.0, 0.0), 'm': (6.0, 0.0), 'i': (6.0, 0.0)},      # «Поцелуй 2»: к переносице
    # «Огорчение 2»: «клюшка» — внутренний конец круто вверх, середина прогнута
    'sorry': {'o': (2.0, 5.3), 'm': (6.0, 5.8), 'i': (10.0, -9.5)},
    # «Огорчение 3»: «ну прости» — почти прямая, 36°, высоко
    'plead': {'o': (0.0, -1.6), 'm': (0.0, -5.0), 'i': (0.6, -19.4)},
    # «Плач 1, 3»: длинная мягкая «клюшка», ~50 px под 29°
    'cry': {'o': (-12.0, 10.0), 'm': (0.5, 5.0), 'i': (8.0, -14.5)},
    # «Злость»: бровь-складка опущена на глаз, внутренний конец ниже, у переносицы
    'anger': {'o': (-7.0, 7.0), 'm': (3.0, 14.0), 'i': (15.0, 16.0)},
}
TEAR_RGB, TEAR_EDGE, STREAK_RGB = '#d4efff', '#86bfe3', '#e3f5ff'


def _brow_bind(s):
    """Кости бровки s в покое: внешний конец, середина, внутренний."""
    cx, _ = G['beads'][s]
    toward = 1 if s == 'l' else -1                 # к переносице
    y, half = G['brow_y'], G.get('brow_half', BROW_HALF)
    return {'o': (cx - toward * half, y), 'm': (cx, y - G.get('brow_arch', BROW_ARCH)), 'i': (cx + toward * half, y)}


def brow_offsets(shape, s, k=1.0):
    """{кость: (dx, dy) мира} формы бровки."""
    toward = 1 if s == 'l' else -1
    return {f'bw_{s}{p}': (toward * dx * k, dy * k) for p, (dx, dy) in BROW_SHAPES[shape].items()}


def _tear_bind(s, i):
    """Начало дорожки слезы: нижне-наружный угол глаза («Плач 1, 3»)."""
    cx, cy = G['beads'][s]
    toward = 1 if s == 'l' else -1
    return (cx - toward * 15.0, cy + 13.0) if i == 1 else (cx - toward * 9.0, cy + 15.0)


TEAR_FALL = 88.0            # на сколько px стекает капля (по дорожке)
TEAR_PERIOD = 60            # кадров на каплю
TEAR_TILT = 15.0            # дорожка уходит наружу от вертикали, °


def _drop(x, y, w=5.6, h=8.5):
    """Капля острым концом вверх: верх в (x, y)."""
    pts = []
    for i in range(24):
        a = 2 * math.pi * i / 24
        r = 1 - 0.55 * max(0.0, -math.sin(a)) ** 1.5      # вверху уже
        pts.append((x + w / 2 * math.cos(a) * r, y + h * 0.62 + h * 0.5 * math.sin(a)))
    return pts


def _streak(s):
    """Мокрая дорожка по щеке: от угла глаза вниз на 86 и наружу на 22, у
    морды круче вниз; лента 5,5 вверху → 3,5 внизу (точки мира, кольцом)."""
    x0, y0 = _tear_bind(s, 1)
    away = -1 if s == 'l' else 1
    mid = [(x0 + away * 22.0 * (1 - (1 - u) ** 2), y0 + 4 + 86.0 * u) for u in [i / 13 for i in range(14)]]
    left, right = [], []
    for i, (x, y) in enumerate(mid):
        a, b = mid[max(i - 1, 0)], mid[min(i + 1, 13)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln, dx / ln
        w = (5.5 - 2.0 * i / 13) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1], mid


def _shirt_map(img):
    """(пиксель → мир, мир → пиксель) картинки на сетке по её Skin."""
    skin = img.find('Mesh').find('Skin')
    m = M(*[float(skin.get(k)) for k in ('xx', 'xy', 'yx', 'yy', 'tx', 'ty')])
    return m


def mesh_layer(src_img, W, H, tile, origin, name, asset_id, next_id):
    """Копия сетки картинки src_img со своей плиткой tile, лежащей в её
    текстуре с пикселя origin; остаются треугольники целиком внутри плитки
    (так же румянец, сердце, покраснение — ходят с мехом и тканью)."""
    th, tw = tile.shape[:2]
    px0, py0 = origin
    img = copy.deepcopy(src_img)
    for el in img.iter():
        if 'id' in el.attrib:
            el.set('id', next_id())
    img.set('assetId', asset_id)
    img.set('name', name)
    mesh = img.find('Mesh')
    uv = []
    for v in (v for v in mesh if v.tag in VERT_TAGS):
        u, vv = float(v.get('u')) * W, float(v.get('v')) * H
        uv.append((u, vv))
        v.set('u', repr((u - px0) / tw))
        v.set('v', repr((vv - py0) / th))
    tris = _read_indices(mesh.get('triangleIndexBytes'))
    keep = []
    for j in range(0, len(tris), 3):
        t = tris[j:j + 3]
        xs, ys = [uv[k][0] for k in t], [uv[k][1] for k in t]
        if min(xs) >= px0 and max(xs) <= px0 + tw and min(ys) >= py0 and max(ys) <= py0 + th:
            keep += t
    mesh.set('triangleIndexBytes', _write_indices(keep))
    return img


def _to_tex(img, W, H):
    """Мир → пиксель текстуры картинки на сетке (через Skin)."""
    inv = _shirt_map(img).inv()
    return lambda x, y: tuple(v + s / 2 for v, s in zip(inv.apply(x, y), (W, H)))


def _gauss_tile(to_tex, blobs, rgb, peak, pad=3.2):
    """Плитка мягких пятен: blobs [(x, y, σx, σy)] в мире."""
    cs = [(*to_tex(b[0], b[1]), b[2], b[3]) for b in blobs]
    k = abs(to_tex(1, 0)[0] - to_tex(0, 0)[0])            # px текстуры на px мира
    x0 = int(min(cx - pad * sx * k for cx, _, sx, _ in cs))
    x1 = int(max(cx + pad * sx * k for cx, _, sx, _ in cs)) + 1
    y0 = int(min(cy - pad * sy * k for _, cy, _, sy in cs))
    y1 = int(max(cy + pad * sy * k for _, cy, _, sy in cs)) + 1
    yy, xx = np.mgrid[y0:y1, x0:x1] + 0.5
    a = np.zeros(xx.shape)
    for (cx, cy, sx, sy), b in zip(cs, blobs):
        g = b[4] if len(b) > 4 else 1.0
        a = np.maximum(a, g * np.exp(-0.5 * (((xx - cx) / (sx * k)) ** 2 + ((yy - cy) / (sy * k)) ** 2)))
    tile = np.zeros(xx.shape + (4,), np.uint8)
    tile[..., :3] = rgb
    tile[..., 3] = (a * peak * 255).round().astype(np.uint8)
    return tile, (x0, y0)


def _heart_poly(n=200):
    """Контур сердца (ед.: ширина 32, y вверх): классическая кривая, выемка
    приподнята до 0,13 ширины («Любовь 1–3»: подвеска)."""
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        if y > 0:
            y += 2.74 * math.exp(-(x / 4.0) ** 2) * min(1.0, y / 5.0)
        out.append((x, y))
    return out


def _heart_tiles(to_tex):
    """Сердце-подвеска на груди и его ореол («Любовь — сердце светится»):
    ширина heart_w, высота 0,9 ширины, выемка под кнопкой; край
    (242; 186; 219), к середине светлее (254; 210; 233) на глубине 30 px;
    ореол (255; 165; 210) коротким спадом 0,15 ширины. Кнопка кофты лежит
    поверх сердца и ореола (`heart_hole`)."""
    hx, hy = G['heart']
    k = abs(to_tex(1, 0)[0] - to_tex(0, 0)[0])            # px текстуры на px мира
    unit = G['heart_w'] / 32.0                              # px мира на ед. кривой
    cx, cy = to_tex(hx, hy)
    pts = [(cx + x * unit * k, cy - (y + 2.55) * unit * k) for x, y in _heart_poly()]
    w = G['heart_w'] * k
    size = int(w * 1.7)
    x0, y0 = int(cx - size / 2), int(cy - size / 2)
    mask = Image.new('L', (size, size), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).polygon([(x - x0, y - y0) for x, y in pts], fill=255)
    f = np.asarray(mask, np.float64) / 255
    inside = ndimage.gaussian_filter(f, 1.2)
    depth = ndimage.distance_transform_edt(f > 0.5)
    core = np.clip(depth / (30.0 * k), 0, 1)
    rgb = np.dstack([242 + 12 * core, 186 + 24 * core, 219 + 14 * core])
    d = ndimage.distance_transform_edt(f <= 0.5)
    glow = 0.6 * np.exp(-(d / (0.15 * w)) ** 2) * (f <= 0.5)
    hole = np.ones(f.shape)
    holes = G.get('heart_hole') or ()
    for bx, by, br in ([holes] if isinstance(holes[0], (int, float)) else holes) if holes else ():
        px, py = to_tex(bx, by)
        yy, xx = np.mgrid[0:size, 0:size] + 0.5
        r = np.hypot(xx + x0 - px, yy + y0 - py) / k
        hole = np.minimum(hole, np.clip((r - br) / 2.0, 0, 1))
    heart = np.dstack([rgb, inside * hole * 255]).clip(0, 255).astype(np.uint8)
    halo = np.dstack([np.full(f.shape, 255.0), np.full(f.shape, 165.0), np.full(f.shape, 210.0),
                      glow * hole * 255]).clip(0, 255).astype(np.uint8)
    return heart, halo, (x0, y0)


# черта сна «тип Б» (лист «Сон»): почти прямая, прогиб ◡ 1,5, наружный конец
# ниже на 1,5; середина на cy + SHUT_DY
SHUT_DY, SHUT_HALF = 4.5, 20.0
# срез бусины веком («Грусть», «Огорчение», «Плач», «Злость»): край — прямая
# через кости lc_<s>o/i на ±CUT_HALF; в покое на CUT_REST над серединой глаза
CUT_HALF, CUT_REST = 30.0, 22.0
# реснички-бахрома от нижнего края черты: (сдвиг от середины наружу, длина,
# наклон наружу, °); мальчик — шесть по всей черте, девочка — три снаружи
LASHES = ((-14, 2.5, 5), (-8, 3.0, 10), (-2, 3.5, 15), (4, 4.0, 20), (10, 4.5, 25), (16, 4.0, 30))


def _shut_line(s, B):
    """Черта сна глаза s и её реснички: (кольцо точек, веса, реснички).
    Черта — на трёх костях shut_<s>o/m/i (наружный конец, середина,
    внутренний): прогиб, наклон, толщина — их ключами."""
    cx, cy = G['beads'][s]
    out = -1 if s == 'l' else 1                     # наружу по x
    half = SHUT_HALF

    def centre(u):                                  # u: −1 … 1 по x
        return cy + SHUT_DY - 1.5 * u * u + 0.75 * out * u

    def w_at(x, y):
        v = max(-1.0, min(1.0, (x - cx) / half)) * out      # +1 — наружный конец
        w = {f'shut_{s}m': 1 - abs(v)}
        w[f'shut_{s}o' if v > 0 else f'shut_{s}i'] = abs(v)
        return {b: x_ for b, x_ in w.items() if x_ > 1e-4}

    th = lambda u: 1.2 + 1.4 * (1 - u * u)
    us = [-1 + 2 * i / 24 for i in range(25)]
    upper = [(cx + half * u, centre(u) - th(u) / 2) for u in us]
    lower = [(cx + half * u, centre(u) + th(u) / 2) for u in us[::-1]]
    cap = lambda u, sg: [(cx + half * u + sg * 0.6 * math.sin(math.pi * k / 4), centre(u) - sg * 0.6 * math.cos(math.pi * k / 4))
                         for k in range(1, 4)]
    ring = upper + cap(1, 1) + lower + cap(-1, -1)
    lashes = []
    for dx, ln, tilt in G.get('lashes', LASHES):
        bx = cx + out * dx
        u = (bx - cx) / half
        by = centre(u) + th(u) / 2 - 0.3
        a = math.radians(tilt)
        ex, ey = bx + out * ln * math.sin(a), by + ln * math.cos(a)
        nx, ny = math.cos(a), -out * math.sin(a)        # поперёк реснички
        pts = [(bx - 0.7 * nx, by - 0.7 * ny), (ex - 0.25 * nx, ey - 0.25 * ny), (ex + 0.25 * nx, ey + 0.25 * ny),
               (bx + 0.7 * nx, by + 0.7 * ny)]
        lashes.append((pts, w_at(bx, by)))
    return ring, w_at, lashes


def _flush_tile(face_png, to_tex):
    """Краска на всё лицо («Обида 1–2»): мех лица ровной заливкой, мягкий
    край 12 px у капюшона; нос не краснеет."""
    a = np.asarray(Image.open(face_png).convert('RGBA'), np.float64)[..., 3] / 255
    k = abs(to_tex(1, 0)[0] - to_tex(0, 0)[0])
    inner = ndimage.distance_transform_edt(a > 0.5)
    m = np.clip(inner / (12.0 * k), 0, 1)
    x0, y0, x1, y1 = NOSE_BOX_TEX[0]
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]] + 0.5
    cxn, cyn = (x0 + x1) / 2, (y0 + y1) / 2
    rn = np.hypot((xx - cxn) / ((x1 - x0) / 2 + 6 * k), (yy - cyn) / ((y1 - y0) / 2 + 6 * k))
    m *= np.clip((rn - 1.0) / 0.25, 0, 1)
    ys, xs = np.nonzero(m > 0.003)
    bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    tile = np.zeros((by1 - by0, bx1 - bx0, 4), np.uint8)
    tile[..., :3] = G.get('flush_rgb', G['red_rgb'])
    tile[..., 3] = (m[by0:by1, bx0:bx1] * G.get('flush_peak', 0.8) * 255).round().astype(np.uint8)
    return tile, (int(bx0), int(by0))


NOSE_BOX_TEX = [None]          # NOSE_BOX героя (пиксели текстуры лица) — для краски


def _ring(cx, cy, r, n=28):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _local_shape(name, pts, fill=None, stroke=None, nid=None, closed=True):
    """Фигура в локальных координатах узла (без костей) — в обёртке бусины."""
    sh = ET.Element('Shape', {'x': '0', 'y': '0', 'name': name, 'id': nid()})
    path = ET.SubElement(sh, 'PointsPath', {'isClosed': 'true' if closed else 'false', 'name': 'p', 'id': nid()})
    for x, y in pts:
        ET.SubElement(path, 'StraightVertex', {'x': f'{x:.4g}', 'y': f'{y:.4g}', 'name': 'v', 'id': nid()})
    if fill:
        fl = ET.SubElement(sh, 'Fill', {'name': 'F', 'id': nid()})
        ET.SubElement(fl, 'SolidColor', {'colorValue': vec.argb(*fill), 'name': 'C', 'id': nid()})
    if stroke:
        w, *c = stroke
        st = ET.SubElement(sh, 'Stroke', {'thickness': f'{w}', 'cap': 'round', 'join': 'round', 'name': 'S', 'id': nid()})
        ET.SubElement(st, 'SolidColor', {'colorValue': vec.argb(*c), 'name': 'C', 'id': nid()})
    return sh


def parts(ctx):
    """Слои v2. Над веками (сверху вниз): дужки, бровки (с тенью складки и
    толстой копией), складки между бровями, реснички открытого глаза, слёзы,
    свои рты. Накладки на мех лица (румянец, подушечки, покраснение, краска,
    отсвет сердца) — сразу над мехом: под швом, носом и глазами. Сердце — на
    кофте. В обёртке бусины: мокрые блики, ободок, лужица слёз, тусклая
    бусина и клип-путь среза веком; под бусиной — белок и тяжёлое веко.
    Закрытые глаза — векторная черта `face_shut`."""
    ab, B, byname, root = ctx['ab'], ctx['B'], ctx['byname'], ctx['root']
    Wm = world_map(ab)
    lid = byname['lid_patch_img']
    holder = next(p for p in ab.iter() if lid in list(p))
    hw = Wm[holder]
    nid = ctx['next_id']
    assets = {a.get('id'): a for a in root.iter('ImageAsset')}

    def add_asset(fn, tile, aid):
        Image.fromarray(tile, 'RGBA').save(os.path.join(ctx['project'], fn))
        asset = nid()
        ET.SubElement(root, 'ImageAsset', {'file': fn, 'height': str(tile.shape[0]), 'width': str(tile.shape[1]),
                                           'assetId': aid, 'name': fn[:-4], 'id': asset})
        return asset

    def layer(src, tile, origin, name, fn, aid, at_holder, at):
        fa = assets[src.get('assetId')]
        el = mesh_layer(src, int(fa.get('width')), int(fa.get('height')), tile, origin, name,
                        add_asset(fn, tile, aid), nid)
        el.set('opacity', '0')
        at_holder.insert(list(at_holder).index(at), el)
        rr.E_IDS[name[:-4]] = el.get('id')
        return el

    # накладки на мех лица — сразу над мехом (вставляются над face_img)
    face_img = byname['face_img']
    fh = next(p for p in ab.iter() if face_img in list(p))
    fa = assets[face_img.get('assetId')]
    to_tex = _to_tex(face_img, int(fa.get('width')), int(fa.get('height')))
    jx, jy = G['junction']
    tile, origin = _flush_tile(os.path.join(ctx['project'], fa.get('file')), to_tex)
    layer(face_img, tile, origin, 'face_flush_img', 'bear_flush.png', '9900306', fh, face_img)
    tile, origin = _gauss_tile(to_tex, [(jx, jy - 40, 70.0, 48.0)] + [(x, y, 22.0, 16.0) for x, y in G['blush'].values()],
                               G['red_rgb'], G.get('red_peak', 0.42))
    layer(face_img, tile, origin, 'face_red_img', 'bear_red.png', '9900301', fh, face_img)
    bx, by = G.get('bounce', (jx - 1.5, jy + 55.0))
    tile, origin = _gauss_tile(to_tex, [(bx, by, 38.0, 12.0), (bx - 38, by - 8, 16.0, 10.0, 0.6),
                                        (bx + 38, by - 8, 16.0, 10.0, 0.6)], (250, 140, 175), 0.38)
    layer(face_img, tile, origin, 'face_heart_bounce_img', 'bear_heart_bounce.png', '9900305', fh, face_img)
    # подушечки щёк под серпами смеха («Смех 3–4»): светлые пятна
    tile, origin = _gauss_tile(to_tex, [(x - 2 if x < 512 else x + 2, y + 25, 17.0, 9.0)
                                        for x, y in G['beads'].values()], (252, 232, 212), 0.55)
    layer(face_img, tile, origin, 'face_pad_img', 'bear_pad.png', '9900304', fh, face_img)
    bx_, by_ = G.get('blush_r', (15.0, 12.0))
    tile, origin = _gauss_tile(to_tex, [(x, y, bx_, by_) for x, y in G['blush'].values()], G['blush_rgb'],
                               G.get('blush_peak', 0.55))
    layer(face_img, tile, origin, 'face_blush_img', 'bear_blush.png', '9900300', fh, face_img)

    # сердце — на кофте, под руками и лицом (слой сразу над кофтой)
    shirt = byname[G['shirt']]
    sa = assets[shirt.get('assetId')]
    sh_holder = next(p for p in ab.iter() if shirt in list(p))
    heart, halo, origin = _heart_tiles(_to_tex(shirt, int(sa.get('width')), int(sa.get('height'))))
    hl = layer(shirt, heart, origin, 'face_heart_img', 'bear_heart.png', '9900302', sh_holder, shirt)
    layer(shirt, halo, origin, 'face_heart_glow_img', 'bear_heart_glow.png', '9900303', sh_holder, hl)

    common = dict(bones=B, pack=rr.pack, next_id=nid, holder_world=hw, opacity=0.0)
    top = []                                   # сверху вниз
    for s, (cx, cy) in G['beads'].items():
        toward = 1 if s == 'l' else -1
        # серп: в покое — полоска толщиной ARC_T со скруглёнными концами на
        # cy+ARC_DY; верхний край идёт за костью долей a(x), нижний — a(x)/2
        y0 = cy + ARC_DY
        n = 21
        half, thick = G.get('arc_half', ARC_HALF), G.get('arc_t', ARC_T)
        upper = [(cx - half + 2 * half * i / (n - 1), y0 - thick / 2) for i in range(n)]
        cap_r = [(cx + half + thick / 2 * math.sin(math.pi * k / 6), y0 - thick / 2 * math.cos(math.pi * k / 6))
                 for k in range(1, 6)]
        lower = [(x, y0 + thick / 2) for x, _ in upper[::-1]]
        cap_l = [(cx - half - thick / 2 * math.sin(math.pi * k / 6), y0 + thick / 2 * math.cos(math.pi * k / 6))
                 for k in range(1, 6)]
        pts = upper + cap_r + lower + cap_l
        lookup = {}
        for x, y in pts:
            a = max(0.0, 1 - ((x - cx) / half) ** 2) * (1.0 if y < y0 else 0.5)
            fur = rr.weights_for('face_arc', x, y, B)
            w = {b: v * (1 - a) for b, v in fur.items()}
            w[f'arc_{s}'] = w.get(f'arc_{s}', 0) + a
            lookup[(x, y)] = {b: v for b, v in w.items() if v > 1e-4}
        top.append(vec.shape(f'face_arc_{s}', pts, weights=lambda x, y, lk=lookup: lk[(x, y)], closed=True,
                             fill=(G['arc_rgb'],), **common))

        # реснички открытого глаза («Огорчение 3», «Плач»): два штриха у
        # наружного верхнего края, на кости глаза (со взглядом не ездят)
        grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_olash_{s}', 'id': nid()})
        for ang, ln in ((205, 4.2), (222, 3.2)):
            a = math.radians(ang if s == 'l' else 180 - ang)
            bx0, by0 = cx + 17 * math.cos(a), cy + 17 * math.sin(a)
            d = a - math.radians(15) * (1 if s == 'r' else -1)
            ex, ey = bx0 + ln * math.cos(d), by0 + ln * math.sin(d)
            nx, ny = -math.sin(d), math.cos(d)
            pts = [(bx0 - 0.65 * nx, by0 - 0.65 * ny), (ex - 0.25 * nx, ey - 0.25 * ny),
                   (ex + 0.25 * nx, ey + 0.25 * ny), (bx0 + 0.65 * nx, by0 + 0.65 * ny)]
            grp.append(vec.shape(f'olash_{s}', pts, weights=lambda x, y, b=f'eye_{s}': {b: 1.0}, closed=True,
                                 fill=(G['seam_rgb'], 0.9), bones=B, pack=rr.pack, next_id=nid, holder_world=hw))
        top.append(grp)

        bind = _brow_bind(s)
        (ox, oy), (mx, my), (ix, iy) = bind['o'], bind['m'], bind['i']
        # бровка — залитый штрих: в середине 3,3, к концам 1,5 («Удивление»,
        # «Смех 3»); верхний и нижний края — на весах средней линии; под ней
        # толстая копия (мягкая складка «Плача») и тень складки («Злость»)
        mid = []
        for i in range(17):
            t = i / 16                        # 0 — внешний конец, 1 — внутренний
            x = ox + (ix - ox) * t
            y = oy + (iy - oy) * t - G.get('brow_arch', BROW_ARCH) * (1 - (2 * t - 1) ** 2)
            if t <= 0.5:
                w = {f'bw_{s}o': 1 - 2 * t, f'bw_{s}m': 2 * t}
            else:
                w = {f'bw_{s}m': 2 - 2 * t, f'bw_{s}i': 2 * t - 1}
            mid.append(((x, y), {b: v for b, v in w.items() if v > 1e-4}, t))

        def stroke_ring(k):
            up, lo = [], []
            for (x, y), w, t in mid:
                th = (1.5 + 1.8 * math.sin(math.pi * t)) * G.get('brow_w', BROW_W) / 2.8 * k
                up.append(((x, y - th / 2), w))
                lo.append(((x, y + th / 2), w))
            ring = up + lo[::-1]
            return [p for p, _ in ring], {p: w for p, w in ring}
        pts, lookup = stroke_ring(1.0)
        top.append(vec.shape(f'face_brow_{s}', pts, weights=lambda x, y, lk=lookup: lk[(x, y)],
                             closed=True, fill=(G['brow_rgb'], 0.95), **common))
        pts, lookup = stroke_ring(1.8)
        top.append(vec.shape(f'face_browk_{s}', pts, weights=lambda x, y, lk=lookup: lk[(x, y)],
                             closed=True, fill=(G['brow_rgb'], 0.9), **common))
        sh_pts = [(x, y + 2.5) for (x, y), _, _ in mid]
        sh_look = {(x, y + 2.5): w for (x, y), w, _ in mid}
        top.append(vec.shape(f'face_bshade_{s}', sh_pts, weights=lambda x, y, lk=sh_look: lk[(x, y)],
                             stroke=(6.0, G.get('bshade_rgb', '#a8784f')), **common))

        # слёзы: мокрая дорожка-лента по щеке с бликами и две капли
        ring, line = _streak(s)
        fw_ = lambda x, y: rr.weights_for('face_x', x, y, B)
        grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_streak_{s}', 'id': nid()})
        for u in (0.3, 0.6):
            x, y = line[int(u * 13)]
            grp.append(vec.shape('streak_glint', _ring(x, y, 1.0, 10), weights=fw_, closed=True, fill=('#ffffff', 0.9),
                                 bones=B, pack=rr.pack, next_id=nid, holder_world=hw))
        grp.append(vec.shape('streak', ring, weights=fw_, closed=True, fill=(STREAK_RGB,),
                             bones=B, pack=rr.pack, next_id=nid, holder_world=hw))
        top.append(grp)
        for i in (1, 2):
            tx, ty = _tear_bind(s, i)
            top.append(vec.shape(f'face_tear_{s}{i}', _drop(tx, ty), weights=lambda x, y, b=f'tear_{s}{i}': {b: 1.0},
                                 closed=True, fill=(TEAR_RGB, 0.92), stroke=(0.9, TEAR_EDGE, 0.9), **common))

    # складки между бровями («Злость 2–3»): два коротких штриха на зонах бровей
    grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': 'face_crease', 'id': nid()})
    for s, sg in (('l', -1), ('r', 1)):
        pts = []
        for i in range(9):
            u = i / 8
            pts.append((jx + sg * (23.5 - 6.0 * u) + sg * (-1.5) * math.sin(math.pi * u), 397.0 - 16.0 * u))
        grp.append(vec.shape(f'crease_{s}', pts, weights=lambda x, y, b=f'brow_{s}': {b: 1.0},
                             stroke=(1.8, '#7a4a2c', 0.55), bones=B, pack=rr.pack, next_id=nid, holder_world=hw))
    top.append(grp)

    # свои рты — над полостями: группа на вид, её прозрачность — прозрачность рта
    for kind in VMOUTHS:
        grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_mouth_{kind}', 'id': nid()})
        for sh in _vmouth_shapes(kind, dict(bones=B, pack=rr.pack, next_id=nid, holder_world=hw)):
            grp.append(sh)
        top.append(grp)
        rr.E_IDS[f'mouth_{kind}_img'] = grp.get('id')

    for el in top[::-1]:
        holder.insert(list(holder).index(lid), el)
    for el in top:
        name = el.get('name')
        if name.startswith('face_') and not name.startswith('face_mouth_'):
            rr.E_IDS[name] = el.get('id')

    for s in 'lr':
        cx, cy = G['beads'][s]
        toward = 1 if s == 'l' else -1
        wrap = next(e for e in ab.iter('Node') if e.get('id') == rr.WRAP_IDS[f'bead_{s}'])
        gaze = next(p for p in ab.iter() if wrap in list(p))
        gw = Wm[gaze]
        # мокрые глаза: свет на нижнем крае и второй большой блик — в обёртке
        # бусины (ходят и сплющиваются вместе с ней)
        grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_wet_{s}', 'id': nid()})
        grp.append(_local_shape('wet_rim', [(13.2 * math.cos(math.radians(a)), 13.2 * math.sin(math.radians(a)))
                                            for a in range(30, 151, 10)], stroke=(2.4, '#cfeaff', 0.75), nid=nid,
                                closed=False))
        for gx, gy, gw_ in ((-5.0, -5.5, 5.5), (5.5, 5.0, 2.6), (-1.0, 7.5, 3.2)):
            g = ET.SubElement(grp, 'Shape', {'x': f'{gx}', 'y': f'{gy}', 'name': 'wet_glint', 'id': nid()})
            ET.SubElement(g, 'Ellipse', {'width': f'{gw_}', 'height': f'{gw_ * 0.8:.3g}', 'name': 'e', 'id': nid()})
            fl = ET.SubElement(g, 'Fill', {'name': 'F', 'id': nid()})
            ET.SubElement(fl, 'SolidColor', {'colorValue': vec.argb('#ffffff', 0.9), 'name': 'C', 'id': nid()})
        wrap.insert(0, grp)
        rr.E_IDS[f'face_wet_{s}'] = grp.get('id')
        # ободок «распахнутого» взгляда («Удивление 1–2»): светлая дуга 120°
        # внутри края бусины с наружной стороны, чуть ниже середины
        rim_g = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_rim_{s}', 'id': nid()})
        c0 = 190 if s == 'l' else -10
        rim_g.append(_local_shape('rim', [(14.3 * math.cos(math.radians(a)), 14.3 * math.sin(math.radians(a)))
                                          for a in range(c0 - 60, c0 + 61, 10)], stroke=(2.4, '#e9ddd0', 0.85),
                                  nid=nid, closed=False))
        wrap.insert(0, rim_g)
        rr.E_IDS[f'face_rim_{s}'] = rim_g.get('id')
        # лужица слёз у нижнего края бусины («Плач 1, 3»): линза, толще к
        # наружному углу, где начинается дорожка
        a0, a1 = (70, 165) if s == 'l' else (110, 15)
        outer, inner = [], []
        for i in range(17):
            u = i / 16
            a = math.radians(a0 + (a1 - a0) * u)
            th = 4.5 * u ** 0.8
            outer.append((14.5 * math.cos(a), 14.5 * math.sin(a)))
            inner.append(((14.5 - th) * math.cos(a), (14.5 - th) * math.sin(a)))
        pool = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_pool_{s}', 'id': nid()})
        mx, my = outer[10]
        for (gx, gy, r_) in ((mx * 0.88, my * 0.88, 1.1), (outer[13][0] * 0.85, outer[13][1] * 0.85, 0.7)):
            pool.append(_local_shape('pool_glint', _ring(gx, gy, r_, 10), fill=('#ffffff', 0.95), nid=nid))
        pool.append(_local_shape('pool', outer + inner[::-1], fill=('#cfeaff', 0.8), stroke=(0.6, TEAR_EDGE, 0.9),
                                 nid=nid))
        wrap.insert(0, pool)
        rr.E_IDS[f'face_pool_{s}'] = pool.get('id')
        # тусклая бусина «зажмурился» («Смущение 2»): тёмный диск без блика
        dull = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_dull_{s}', 'id': nid()})
        dull.append(_local_shape('dull', _ring(0, 0, 16.8, 32), fill=('#160f0c',), nid=nid))
        wrap.insert(0, dull)
        rr.E_IDS[f'face_dull_{s}'] = dull.get('id')

        gcommon = dict(bones=B, pack=rr.pack, next_id=nid, holder_world=gw)
        # срез бусины веком: клип-путь обёртки — прямая через кости lc_<s>o/i
        # сверху, ниже — до щеки; в покое край на CUT_REST над серединой глаза
        o_x, i_x = cx - toward * CUT_HALF, cx + toward * CUT_HALF
        clip_pts = [(o_x, cy - CUT_REST), (i_x, cy - CUT_REST), (i_x, cy + 45.0), (o_x, cy + 45.0)]
        clip_w = {clip_pts[0]: {f'lc_{s}o': 1.0}, clip_pts[1]: {f'lc_{s}i': 1.0},
                  clip_pts[2]: {'face': 1.0}, clip_pts[3]: {'face': 1.0}}
        clipper = vec.shape(f'cut_{s}', clip_pts, weights=lambda x, y, lk=clip_w: lk[(x, y)], closed=True, **gcommon)
        gaze.append(clipper)
        ET.SubElement(wrap, 'ClippingShape', {'sourceId': clipper.get('id'), 'name': 'cut', 'id': nid()})
        # под бусиной: тяжёлое светлое веко («Сонливость 2») и белок («Сомнение 1»)
        at = list(gaze).index(wrap) + 1
        arc = [(cx + 20 * math.cos(f), cy + 12 - 24 * math.sin(f)) for f in [math.pi * (1 - i / 20) for i in range(21)]]
        fur = lambda x, y: rr.weights_for('face_arc', x, y, B)
        cap = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': '0', 'name': f'face_lidcap_{s}', 'id': nid()})
        cap.append(vec.shape('lidcap_edge', arc, weights=fur, stroke=(1.2, G.get('lidcap_edge', '#7a4e33'), 0.55),
                             **gcommon))
        cap.append(vec.shape('lidcap', arc, weights=fur, closed=True, fill=(G.get('lidcap_rgb', '#b47d58'),),
                             **gcommon))
        gaze.insert(at, cap)
        rr.E_IDS[f'face_lidcap_{s}'] = cap.get('id')
        white = vec.shape(f'face_white_{s}', _ring(cx, cy, 16.7, 32), weights=lambda x, y, b=f'eye_{s}': {b: 1.0},
                          closed=True, fill=(G.get('white_rgb', '#d8c8c3'),), opacity=0.0, **gcommon)
        gaze.insert(at + 1, white)
        rr.E_IDS[f'face_white_{s}'] = white.get('id')

    # закрытые глаза (моргание покоя, клипы, сон): векторная черта сна «тип Б»
    # с ресничками вместо прежних картинок — в том же узле `fx_eyes_closed`,
    # который ключуют моргание `idle_life` и поза `pose_eyes_shut`
    fx = next(e for e in ab.iter() if e.get('name') == 'fx_eyes_closed')
    for img in [c for c in fx if c.tag == 'Image']:
        fx.remove(img)
    common = dict(bones=B, pack=rr.pack, next_id=nid, holder_world=Wm[fx])
    for s in 'lr':
        ring, w_at, lashes = _shut_line(s, B)
        grp = ET.Element('Node', {'x': '0', 'y': '0', 'opacity': f"{G.get('lash_rest', 0.0):g}",
                                  'name': f'face_lash_{s}', 'id': nid()})
        for i, (pts, w) in enumerate(lashes):
            grp.append(vec.shape(f'lash_{s}{i}', pts, weights=lambda x, y, w=w: w, closed=True,
                                 fill=(G['arc_rgb'],), **common))
        fx.append(grp)
        fx.append(vec.shape(f'shut_line_{s}', ring, weights=w_at, closed=True, fill=(G['arc_rgb'],), **common))
        rr.E_IDS[f'face_lash_{s}'] = grp.get('id')
    rr.E_IDS['face_shut'] = fx.get('id')


def prune(img):
    """Вершины сетки, которых нет ни в одном треугольнике, — долой (копия
    сетки лица под маленькую плитку несла все ~1500 вершин лица, по 0,7 МБ
    на накладку; .riv перерастал 15 МБ артефакта). Вид не меняется."""
    mesh = img.find('Mesh')
    verts = [v for v in mesh if v.tag in VERT_TAGS]
    tris = _read_indices(mesh.get('triangleIndexBytes'))
    used = sorted(set(tris))
    if len(used) == len(verts):
        return 0
    remap = {o: n for n, o in enumerate(used)}
    keep = set(used)
    for i, v in enumerate(verts):
        if i not in keep:
            mesh.remove(v)
    mesh.set('triangleIndexBytes', _write_indices([remap[i] for i in tris]))
    return len(verts) - len(used)


def prune_layers(ctx):
    """Накладки на копиях сеток (v2 и прежние: моргание, удивление, полости
    рта) — только их вершины."""
    n = 0
    for img in ctx['ab'].iter('Image'):
        if img.find('Mesh') is not None and img.get('name') not in ('face_img', 'lid_patch_img'):
            n += prune(img)
    print('убрано лишних вершин накладок:', n)
    # картинки, которых нет ни на одном слое: снимок экрана из исходника
    # заказчика, вторая копия изнанки капюшона, ротик покоя и рты-линии
    # (их заменил шов) — в .riv они всё равно ложились
    root = ctx['root']
    used = {e.get('assetId') for e in root.iter('Image')}
    for parent in list(root.iter()):
        for a in [c for c in parent if c.tag == 'ImageAsset' and c.get('id') not in used]:
            parent.remove(a)
            print('картинка не нужна:', a.get('file'))


# --- Установка в риг ---------------------------------------------------------------
_installed = []


def install(geom):
    """Всё v2 — в риг до сборки: кости, слои, позы шва, свои рты, выражения."""
    assert not _installed, 'install — один раз'
    _installed.append(True)
    G.clear()
    G.update(geom)
    NOSE_BOX_TEX[0] = G.get('nose_box', NOSE_BOX)
    if 'nose_bone' in G:
        (sx_, sy_), (ex, ey) = G['nose_bone']
        rr.CHAIN[:] = [('nose', 'face', (sx_, sy_), (ex, ey)) if c[0] == 'nose' else c for c in rr.CHAIN]
        rr.FACE_ZONES[:] = [('nose', *G['nose_zone']) if z[0] == 'nose' else z for z in rr.FACE_ZONES]
    # кости — в конце списка: номера прежних костей не меняются
    for n in SEAM_BONES:
        x, y = _seam_bone_world(n)
        rr.CHAIN.append((n, 'face', (round(x, 3), round(y, 3)), (round(x, 3), round(y, 3) - 10)))
    for s, (x, y) in G['beads'].items():
        rr.CHAIN.append((f'arc_{s}', 'face', (x, y + ARC_DY), (x, y + ARC_DY - 10)))
    for s in 'lr':
        for p, (x, y) in _brow_bind(s).items():
            rr.CHAIN.append((f'bw_{s}{p}', f'brow_{s}', (x, y), (x, y - 10)))
        for i in (1, 2):
            x, y = _tear_bind(s, i)
            away = -1 if s == 'l' else 1
            a = math.radians(TEAR_TILT)
            rr.CHAIN.append((f'tear_{s}{i}', 'face', (x, y), (x - away * 10 * math.sin(a), y - 10 * math.cos(a))))
    jx, jy = G['junction']
    for k in VMOUTHS:
        px, py = VPIVOT.get(k, (0.0, 0.0))
        rr.CHAIN.append((f'mouth_{k}', 'face', (jx + px, jy + py), (jx + px + 20, jy + py)))
        mouth.KINDS.append(k)
    for n in SEAM_BONES:                       # кости глубины ртов-линз
        x, y = _seam_bone_world(n)
        rr.CHAIN.append(('sd' + n[4:], n, (round(x, 3), round(y, 3)), (round(x, 3), round(y, 3) - 10)))
    for s, (x, y) in G['beads'].items():
        toward = 1 if s == 'l' else -1
        # черта сна: наружный конец, середина, внутренний
        for p, dx in (('o', -toward * SHUT_HALF), ('m', 0.0), ('i', toward * SHUT_HALF)):
            rr.CHAIN.append((f'shut_{s}{p}', 'face', (x + dx, y + SHUT_DY), (x + dx, y + SHUT_DY - 10)))
        # срез бусины веком: прямая через две кости над глазом
        for p, dx in (('o', -toward * CUT_HALF), ('i', toward * CUT_HALF)):
            rr.CHAIN.append((f'lc_{s}{p}', 'face', (x + dx, y - CUT_REST), (x + dx, y - CUT_REST - 10)))
    rr.CHAIN.append(('d_tongue', 'mouth_d', (jx, jy + 19.0), (jx + 20, jy + 19.0)))
    rr.HOOKS.extend([seam, parts, prune_layers])
    # сердце и его отсвет — с телом: на кухне и в кровати гаснут вместе
    rr.BODY_IMAGES = rr.BODY_IMAGES + ('face_heart_img', 'face_heart_glow_img', 'face_heart_bounce_img')
    sleep0 = rr.sleep_clips

    def sleep_clips(ab, idle, B):
        """Позы сна: глаза закрыты чертой с ресничками (лист «Сон»). В
        моргании покоя бусина, сплющиваясь, опускается к черте сна (она на
        SHUT_DY ниже середины глаза): на переходе одна полоска, а не две."""
        _blink_drop(idle)
        sleep0(ab, idle, B)
        pose = next(a for a in ab.iter('LinearAnimation') if a.get('name') == 'pose_eyes_shut')
        for s in 'lr':
            ko = ET.SubElement(pose, 'KeyedObject', {'objectId': rr.E_IDS[f'face_lash_{s}']})
            kp = ET.SubElement(ko, 'KeyedProperty', {'propertyKey': '18'})
            ET.SubElement(kp, 'KeyFrameDouble', {'value': '1', 'frame': '0', 'interpolationType': 'hold'})
    rr.sleep_clips = sleep_clips
    rr.saccades = saccades

    closed = mouth.closed
    mouth.closed = lambda name: VMOUTHS[name] if name in VMOUTHS else closed(name)
    build_tiles = mouth.build

    def build_cavities(*a, **kw):
        """Плитки полостей — только у растровых ртов."""
        kinds = list(mouth.KINDS)
        mouth.KINDS[:] = [k for k in kinds if k not in VMOUTHS]
        try:
            return build_tiles(*a, **kw)
        finally:
            mouth.KINDS[:] = kinds
    mouth.build = build_cavities
    _patch_emo()


def saccades():
    """Бусины по горизонтали в покое («Спокойствие 2»): скачки SACCADES, а
    на поворотах головы LOOKS глаза опережают поворот на 10 кадров, через
    0,3 с после прихода головы уходят на 3 px против поворота — смотрят на
    зрителя — и держатся там до возврата; вернулась голова — через 0,3 с
    глаза в середину."""
    sm = rr.smooth

    def look_x(t):
        out = 0.0
        for a, b, v, *_ in rr.LOOKS:
            lead = sm(a - rr.EYES_LEAD, a + 40 - rr.EYES_LEAD, t)
            back = sm(a + 58, a + 66, t) * (1 - sm(b + 18, b + 26, t))
            out += v * (rr.EYES_TURN * lead * (1 - sm(a + 58, a + 66, t)) - 3.0 * back)
        return out

    def jump(t):
        prev = rr.SACCADES[0][1]
        for (f0, v0), (f1, v1) in zip(rr.SACCADES, rr.SACCADES[1:]):
            if t < f1:
                return v0
            if t < f1 + 4:
                return v0 + (v1 - v0) * sm(f1, f1 + 4, t)
            prev = v1
        return prev

    return {w: [(t, rr.E_REST[w]['x'] + jump(t) + look_x(t)) for t in range(0, rr.DUR + 1, 2)]
            for w in ('bead_l', 'bead_r')}


def _blink_drop(idle):
    """Ключи y обёрток бусин в `idle_life`: сдвиг вниз на SHUT_DY · доля
    сплющивания бусины (её scaleY из ключей моргания исходника)."""
    for img, wrap in ((rr.BEAD_L, 'bead_l'), (rr.BEAD_R, 'bead_r')):
        ko = next((k for k in idle.findall('KeyedObject') if k.get('objectId') == img), None)
        kp = ko and next((k for k in ko.findall('KeyedProperty') if k.get('propertyKey') == '17'), None)
        if kp is None:
            continue
        keys = sorted((int(k.get('frame', '0')), float(k.get('value', '0'))) for k in kp)
        rest = rr.BEAD_REST[img]
        y0 = rr.E_REST[wrap]['y']
        drop = {f: SHUT_DY * min(1.0, max(0.0, 1 - v / rest)) for f, v in keys}
        frames = sorted({f for f, d in drop.items() if d > 1e-3} | {0, keys[-1][0]})
        frames = sorted(set(frames) | {f2 for f in frames for f2 in (f - 2, f + 2) if f2 in drop})
        nko = ET.SubElement(idle, 'KeyedObject', {'objectId': rr.WRAP_IDS[wrap]})
        nkp = ET.SubElement(nko, 'KeyedProperty', {'propertyKey': '14'})
        for f in frames:
            ET.SubElement(nkp, 'KeyFrameDouble', {'value': rr.fmt(y0 + drop.get(f, 0.0)), 'frame': str(f),
                                                  'interpolationType': 'linear'})


# --- Клипы: рты-линии → позы шва ---------------------------------------------
def _patch_emo():
    mouth_open0, build0, mood_mouth0 = rr.Emo.mouth_open, rr.Emo.build, rr._mood_mouth

    def mouth_open(self, pts, kind='open'):
        """Рты-линии прежних клипов — поза шва; доля позы — «высота» рта.
        Полости и свои рты — как раньше."""
        if kind not in SEAM_KINDS:
            return mouth_open0(self, pts, kind)
        ez = (lambda p: p[3] if len(p) > 3 else rr.EI)
        self.track(f'mh_{kind}', self.Y, [(p[0], p[2], ez(p)) for p in pts])
        self.__dict__.setdefault('_seam', []).append(
            (SEAM_KINDS[kind], [(p[0], min(1.0, max(0.0, p[2])), ez(p)) for p in pts]))
        self.mouth_h.setdefault(kind, [(0, 0.0)])
        return self

    def build(self):
        """Позы шва клипа — в ключи костей шва; несколько поз складываются.
        Рот-линия считается ртом клипа: ротик покоя (шов) не гаснет — это он
        и есть, а рты петли клип закрывает, как раньше (`Emo._rest_mouth`)."""
        seams = self.__dict__.pop('_seam', [])
        if seams:
            end = self.dur - 2
            frames = sorted(set(range(0, end + 1, 2)) | {f for _, amt in seams for f, _, _ in amt if 0 < f < end})
            tracks = {}
            for pose, amt in seams:
                curve = [(0, 0.0, rr.EI)] + [p for p in amt if 0 < p[0] < end] + [(end, 0.0, None)]
                for fr in frames:
                    a = rr.track_at(curve, fr)
                    for bone, (dx, dy) in pose_offsets(pose, a).items():
                        acc = tracks.setdefault(bone, {}).setdefault(fr, [0.0, 0.0])
                        acc[0] += dx
                        acc[1] += dy
            for bone, by_fr in tracks.items():
                for i, key in ((0, self.X), (1, self.Y)):
                    pts = rr._simplify([(fr, to_local(*by_fr[fr])[i]) for fr in frames], 0.03)
                    self.track(bone, key, [(fr, v, rr.LIN) for fr, v in pts if 0 < fr < end])
        return build0(self)

    def mood_mouth(spec, kind, w, h):
        """Рот петли настроения: рты-линии — поза шва (доля — высота рта);
        рот-линза — ещё и кости глубины."""
        if kind in GROWN:
            for b in SD_BONES:
                spec[(b, rr.Emo.X)] = (lambda b: lambda t: lens_depth(kind, h(t))[b])(b)
        if kind not in SEAM_KINDS:
            return mood_mouth0(spec, kind, w, h)
        spec[(f'mh_{kind}', rr.Emo.Y)] = h
        _mood_pose(spec, SEAM_KINDS[kind], h)

    def build_moods():
        """Петли — с прореженными дорожками (точка, которую соседи дают с
        погрешностью меньше `_TOL`, не нужна; концы петли на месте)."""
        out = build_moods0()
        for name, (dur, ch) in out.items():
            for k, frames in ch.items():
                if len(frames) > 2:
                    tol = TOL_OP if k[1] == OP else rr._TOL.get(k[1], 0.001)
                    pts = rr._simplify([(f, v) for f, v, _ in frames], tol)
                    ch[k] = [(f, v, rr.LIN) for f, v in pts]
        return out
    build_moods0 = rr.build_moods

    rr.Emo.mouth_open = mouth_open
    rr.Emo.build = build
    rr._mood_mouth = mood_mouth
    rr.build_moods = build_moods


def _mood_pose(spec, pose, amt):
    """Поза шва в петле: amt — функция кадра (доля позы); складывается с уже
    заданной."""
    for bone, (dx, dy) in pose_offsets(pose).items():
        lx, ly = to_local(dx, dy)
        for key, v in ((rr.Emo.X, lx), (rr.Emo.Y, ly)):
            prev = spec.get((bone, key))
            spec[(bone, key)] = (lambda v, prev: lambda t: v * min(1.0, max(0.0, amt(t)))
                                 + (prev(t) if prev else 0.0))(v, prev)


# --- Выражения -------------------------------------------------------------------
# Каналы (нет в выражении — покой, 0):
#   sq, sq_l, sq_r   — бусина сплющивается к середине (0–1; 1 — черта)
#   top, top_l/_r    — верхнее веко вниз (0–1; бусина ниже и уже)
#   wide             — глаза шире (доля масштаба)
#   gx, gy           — взгляд, px (gy только вниз)
#   shut             — закрыты вышитой чертой ◡ (моргание, сон)
#   arc, arc_l/_r    — закрыты дужкой; arch, arch_l/_r — высота дужки px (+◠, −◡)
#   lash, sarch      — реснички черты сна (0–1), прогиб черты px (+◠);
#   stilt, sbold     — наклон черты (наружный конец вверх, px), толщина (доля)
#   cut, slant       — срез бусины веком (доля высоты), наклон среза ° (+ —
#                      внутренний конец ниже); ulid — мех века вниз (−px)
#   tilt, bsx        — наклон бусины ° (+ — внутренний край ниже), ширина
#   white, dull      — белок (взгляд вбок), бусина без блика (зажмурился)
#   olash, lidcap    — реснички открытого глаза, тяжёлое светлое веко
#   bthick, crease   — толстая мягкая бровка, складки между бровями
#   flush, tongue    — краска на всё лицо, большой язык «вкусно!»
#   wet              — мокрые глаза; tears — слёзы текут; blush; red; heart;
#   bounce           — отсвет сердца на подбородке
#   brow, brow_l/_r  — бровки видны (0–1); bup, bup_l/_r — подняты, px
#   b_arch, b_sad, b_angry, b_flat (+ _l/_r) — форма бровок (доля)
#   cheek (px вверх), cheek_sy, lid (мех нижнего века вверх, px), corner
#   (уголки рта вверх, px), corner_out (px), chin, muzzle (px)
#   p_<поза> — поза шва (доля); h_<рот>, w_<рот> — полость или свой рот
EXPR = {
    'calm': {},
}
SIDES = ('l', 'r')
LAYER_CH = {'blush': 'face_blush', 'red': 'face_red', 'heart': 'face_heart', 'pad': 'face_pad',
            'bounce': 'face_heart_bounce', 'flush': 'face_flush'}


def expr(x):
    """Выражение: имя, словарь или (имя, поправки)."""
    if isinstance(x, str):
        return dict(EXPR[x])
    if isinstance(x, tuple):
        base = expr(x[0])
        base.update(x[1])
        return base
    return dict(x)


def _side(e, ch, s):
    return e.get(ch, 0.0) + e.get(f'{ch}_{s}', 0.0)


def channels(ex):
    """Выражение → {(имя, ключ): значение} — сдвиги от покоя (кости), прозрачности
    (слои `face_*`), рты: ('_mouth', вид): (ширина, высота), ('_pose', поза): доля."""
    out = {}
    shut = ex.get('shut', 0.0)
    for s in SIDES:
        # закрываясь, бусина сплющивается в черту раньше, чем проявляется
        # дужка или вышитая черта: на половине — уже черта
        arc = _side(ex, 'arc', s)
        k_arc = min(1.0, 2.0 * arc)          # серп: веко опускает бусину к его линии
        sq = min(1.0, _side(ex, 'sq', s) + 2.0 * shut + k_arc)
        top, wide = max(_side(ex, 'top', s), (ARC_DY / rr.BEAD_H) * k_arc), ex.get('wide', 0.0)
        sy = -min(0.997, sq + top) * (1 + wide) + wide
        out[(f'bead_{s}', SY)] = sy
        if wide or _side(ex, 'bsx', s):           # bsx — шире / уже только по горизонтали
            out[(f'bead_{s}', SX)] = wide + _side(ex, 'bsx', s)
        if _side(ex, 'tilt', s):                  # наклон бусины, °: + — внутренний край ниже
            out[(f'bead_{s}', R)] = math.radians(_side(ex, 'tilt', s)) * (-1 if s == 'l' else 1)
        if top:
            out[(f'bead_{s}', Y)] = rr.BEAD_H * top
        if ex.get('gx'):
            out[(f'bead_{s}', X)] = ex['gx']
        if ex.get('gy'):
            out[(f'bead_{s}', Y)] = out.get((f'bead_{s}', Y), 0.0) + max(0.0, ex['gy'])
        if shut:                               # бусина сплющивается к черте сна
            out[(f'bead_{s}', Y)] = out.get((f'bead_{s}', Y), 0.0) + SHUT_DY * min(1.0, 2.0 * shut)
        out[(f'face_arc_{s}', OP)] = min(1.0, max(0.0, (arc - 0.4) / 0.6))
        out[(f'arc_{s}', X)] = _side(ex, 'arch', s)
        out[(f'face_brow_{s}', OP)] = min(1.0, _side(ex, 'brow', s))
        out[(f'brow_{s}', X)] = _side(ex, 'bup', s)
        lift = _side(ex, 'blift', s)               # подъём штриха без меха
        if lift:
            for p in 'omi':
                out[(f'bw_{s}{p}', X)] = out.get((f'bw_{s}{p}', X), 0.0) + lift
        for shape in BROW_SHAPES:
            k = _side(ex, f'b_{shape}', s)
            if k:
                for bone, (dx, dy) in brow_offsets(shape, s, k).items():
                    lx, ly = to_local(dx, dy)
                    out[(bone, X)] = out.get((bone, X), 0.0) + lx
                    out[(bone, Y)] = out.get((bone, Y), 0.0) + ly
        out[(f'face_wet_{s}', OP)] = ex.get('wet', 0.0)
        out[(f'face_rim_{s}', OP)] = min(1.0, _side(ex, 'rim', s))
        if not G.get('lash_rest'):                 # реснички черты сна
            out[(f'face_lash_{s}', OP)] = min(1.0, _side(ex, 'lash', s))
        # срез бусины веком: край — прямая через lc_<s>o/i (X — вверх)
        cut, slant = _side(ex, 'cut', s), math.tan(math.radians(_side(ex, 'slant', s)))
        if cut or slant:
            down = (CUT_REST - rr.BEAD_H) * min(1.0, cut / 0.01) + 2 * rr.BEAD_H * cut
            out[(f'lc_{s}o', X)] = -(down - CUT_HALF * slant)
            out[(f'lc_{s}i', X)] = -(down + CUT_HALF * slant)
        if _side(ex, 'ulid', s):                  # мех верхнего века наползает
            out[(f'ulid_{s}', X)] = _side(ex, 'ulid', s)
        # черта сна: прогиб (sarch), наклон (stilt, slant), толщина (sbold)
        so, sm, si = (_side(ex, 'stilt', s) + SHUT_HALF * slant, _side(ex, 'sarch', s),
                      -_side(ex, 'stilt', s) / 2 - SHUT_HALF * slant)
        for p, v in (('o', so), ('m', sm), ('i', si)):
            if v:
                out[(f'shut_{s}{p}', X)] = v
            if _side(ex, 'sbold', s):
                out[(f'shut_{s}{p}', SX)] = 0.8 * _side(ex, 'sbold', s)
        out[(f'face_streak_{s}', OP)] = 0.85 * min(1.0, ex.get('tears', 0.0) * 1.5)
        out[(f'face_pool_{s}', OP)] = min(1.0, 1.2 * ex.get('tears', 0.0))
        out[(f'face_white_{s}', OP)] = min(1.0, _side(ex, 'white', s))
        out[(f'face_dull_{s}', OP)] = min(1.0, _side(ex, 'dull', s))
        out[(f'face_olash_{s}', OP)] = 0.9 * min(1.0, _side(ex, 'olash', s))
        out[(f'face_lidcap_{s}', OP)] = (min(1.0, _side(ex, 'lidcap', s))
                                         * min(1.0, max(0.0, (_side(ex, 'top', s) - 0.4) / 0.45)))
        brow = min(1.0, _side(ex, 'brow', s))
        out[(f'face_browk_{s}', OP)] = brow * min(1.0, _side(ex, 'bthick', s))
        out[(f'face_bshade_{s}', OP)] = 0.35 * brow * min(1.0, _side(ex, 'b_anger', s))
        for name, key, ch in (('cheek', X, 'cheek'), ('cheek', SY, 'cheek_sy'), ('lid', X, 'lid'),
                              ('mouth', X, 'corner'), ('apple', X, 'apple')):
            if _side(ex, ch, s):
                out[(f'{name}_{s}', key)] = _side(ex, ch, s)
        if ex.get('corner_out'):
            out[(f'mouth_{s}', Y)] = ex['corner_out'] * (-1 if s == 'l' else 1)
    for ch, layer in LAYER_CH.items():
        out[(layer, OP)] = min(1.0, ex.get(ch, 0.0))
    out[('face_shut', OP)] = min(1.0, max(0.0, (shut - 0.4) / 0.6))
    out[('face_heart_glow', OP)] = min(1.0, ex.get('heart', 0.0) * ex.get('glow', 1.0))
    out[('face_crease', OP)] = min(1.0, ex.get('crease', 0.0))
    if ex.get('tongue'):                        # большой язык «вкусно!» («Еда 4»)
        out[('d_tongue', Y)] = -5.5 * ex['tongue']
        out[('d_tongue', SX)] = 0.45 * ex['tongue']
    for name in ('chin', 'muzzle'):
        if ex.get(name):
            out[(name, X)] = ex[name]
    for k, v in ex.items():
        if k.startswith('p_') and v:
            out[('_pose', k[2:])] = v
        if k.startswith('h_') and v:
            out[('_mouth', k[2:])] = (ex.get(f'w_{k[2:]}', v), v)
    return out


FAMILY = ('eyes', 'brows', 'mouth', 'cheeks', 'layers')


def family(name):
    """К какой части лица относится канал (для `reface`); None — тело."""
    if name in ('bead_l', 'bead_r', 'sock_l', 'sock_r', 'eye_l', 'eye_r', 'lid_l', 'lid_r', 'ulid_l', 'ulid_r',
                'face_shut', 'face_blink') or name.startswith(('arc_', 'face_arc_', 'face_wet_', 'face_rim_',
                                                               'face_lash_', 'shut_', 'lc_', 'face_pool_',
                                                               'face_white_', 'face_dull_', 'face_olash_',
                                                               'face_lidcap_')):
        return 'eyes'
    if name.startswith(('brow_', 'bw_', 'face_brow_', 'face_browk_', 'face_bshade_')) or name == 'face_crease':
        return 'brows'
    if name.startswith(('mouth', 'jaw_', 'mh_', 'seam_', 'sd_')) or name in ('chin', 'jaw', 'face_mouth_rest',
                                                                            'd_tongue'):
        return 'mouth'
    if name.startswith(('cheek_', 'apple_', 'zyg_')) or name == 'muzzle':
        return 'cheeks'
    if name.startswith(('face_', 'tear_')):
        return 'layers'
    return None


def _tears(e, spans):
    """Капли по дорожке: в каждом отрезке со слезами — капля за каплей
    (вторая — со сдвигом полпериода), стекают и тают."""
    for s in SIDES:
        for i in (1, 2):
            pos, op = [], []
            for a, b in spans:
                t = a + (0 if i == 1 else TEAR_PERIOD // 2)
                while t + TEAR_PERIOD <= b:
                    pos += [(t, 0.0, None), (t + TEAR_PERIOD, -TEAR_FALL, rr.EIN)]
                    op += [(t, 0.0, rr.LIN), (t + 8, 0.95, rr.LIN), (t + TEAR_PERIOD - 10, 0.85, rr.LIN),
                           (t + TEAR_PERIOD, 0.0, None)]
                    t += TEAR_PERIOD
            if not pos:
                continue
            e.track(f'tear_{s}{i}', X, [p for p in pos if 0 < p[0] < e.dur - 2])
            fade(e, f'face_tear_{s}{i}', [p for p in op if 0 < p[0] < e.dur - 2])


def fade(e, name, pts):
    """Прозрачность своего слоя (в покое 0): pts [(кадр, значение[, кривая])]."""
    e.ch[(rr.E_IDS[name], OP)] = ([(0, 0.0, rr.EI)] + [(p[0], p[1], p[2] if len(p) > 2 else rr.EI) for p in pts]
                                  + [(e.dur - 2, 0.0, None)])


TOL_OP = 0.01


def face(e, keys, step=2, mouth=True):
    """Лицо клипа по ключам [(кадр, выражение[, кривая])]: параметры
    выражений перетекают от ключа к ключу по кривой ключа (как в Rive —
    кривая ведёт отрезок до следующего), каналы считаются по кадрам и
    прореживаются; начало и конец клипа — покой. Рты: позы шва складываются
    (`_seam`), полости и свои рты — `Emo.mouth_open` (шов гаснет под ними сам);
    клип с лицом закрывает рты петли (как клипы со ртом). mouth=False — рот
    клипа свой (не трогать шов и рты)."""
    end = e.dur - 2
    ks = [(k[0], expr(k[1]), k[2] if len(k) > 2 else rr.EI) for k in keys if 0 <= k[0] <= end]
    if not ks or ks[0][0] > 0:
        ks.insert(0, (0, {}, rr.EI))
    if ks[-1][0] < end:
        ks.append((end, {}, None))
    params = sorted({p for _, ex, _ in ks for p in ex})
    curves = {p: [(f, ex.get(p, 0.0), ez) for f, ex, ez in ks] for p in params}
    frames = sorted(set(range(0, end + 1, step)) | {f for f, _, _ in ks})
    samples = {}
    for fr in frames:
        ex = {p: rr.track_at(curves[p], fr) for p in params}
        for c, v in channels(ex).items():
            samples.setdefault(c, {})[fr] = v
    zero = lambda c: (0.0, 0.0) if c[0] == '_mouth' else 0.0
    poses = False
    for c in sorted(samples, key=str):
        pts = [(fr, samples[c].get(fr, zero(c))) for fr in frames]
        if c[0] == '_pose':
            poses = True
            e.__dict__.setdefault('_seam', []).append((c[1], [(f, v, rr.LIN) for f, v in pts]))
            continue
        if c[0] == '_mouth':
            ws = rr._simplify([(f, w) for f, (w, _) in pts], 0.004)
            hs = rr._simplify([(f, h) for f, (_, h) in pts], 0.004)
            fs = sorted({f for f, _ in ws} | {f for f, _ in hs})
            e.mouth_open([(f, samples[c].get(f, (0.0, 0.0))[0], samples[c].get(f, (0.0, 0.0))[1], rr.LIN)
                          for f in fs if 0 < f < end], kind=c[1])
            if c[1] in GROWN:                  # рот-линза: низ уходит от шва вниз
                hs = {f: h for f, (_, h) in pts}
                for b in SD_BONES:
                    v = rr._simplify([(f, lens_depth(c[1], hs[f])[b]) for f in frames], 0.05)
                    e.track(b, X, [(f, x, rr.LIN) for f, x in v if 0 < f < end])
            continue
        if all(abs(v) < 1e-6 for _, v in pts):
            continue
        name, key = c
        pts = rr._simplify(pts, TOL_OP if name.startswith('face_') else rr._TOL.get(key, 0.001))
        vals = [(f, v, rr.LIN) for f, v in pts if 0 < f < end]
        if name.startswith('face_'):
            fade(e, name, vals)
        else:
            e.track(name, key, vals)
    if mouth:
        if not poses:                      # шов клипа — в покое, а не позой петли
            e.__dict__.setdefault('_seam', []).append(('rest', [(end // 2, 0.0, rr.LIN)]))
        # рты петли — закрыть (`_rest_mouth` закрывает все виды, кроме своих;
        # метка — не вид рта: с 'content' улыбка петли оставалась раскрытой
        # и приложение выбирало её вместо «D» клипа)
        e.mouth_h.setdefault('_v2', [(0, 0.0)])
    # слёзы: капли бегут, пока плачет в полную силу (tears ≥ 0,7); на
    # затихании дорожка подсыхает без новых капель
    spans, on = [], None
    for fr in frames:
        t = 'tears' in curves and rr.track_at(curves['tears'], fr) >= 0.7
        if t and on is None:
            on = fr
        if not t and on is not None:
            spans.append((on, fr))
            on = None
    if on is not None:
        spans.append((on, end))
    if spans:
        _tears(e, spans)
    return e


def reface(builder, keys, keep=(), dur=None, body=None):
    """Клип builder с новым лицом: каналы лица (кроме семейств keep — eyes,
    brows, mouth, cheeks, layers) убираются, на их место — `face(keys)`;
    тело, голова, уши — как были. keys — список или функция длины клипа;
    dur — своя длина (не короче тела); body(e) — свои дорожки тела поверх."""
    def build():
        d0, ch = builder()
        dur_ = max(d0, dur or d0)
        inv = {}
        for n, i in rr.E_IDS.items():
            inv.setdefault(i, n)
        drop = {i for i, n in inv.items() if family(n) and family(n) not in keep}
        # рот покоя (шов): его прозрачность ставит лицо, если рот не сохранён
        if 'mouth' not in keep:
            drop.add(rr.E_IDS['mouth_rest_img'])
        ch = {k: v for k, v in ch.items() if k[0] not in drop}
        e = rr.Emo(dur_)
        face(e, keys(dur_) if callable(keys) else keys, mouth='mouth' not in keep)
        if body:
            body(e)
        ch.update(e.build()[1])
        return dur_, ch
    return build


def loop_face(spec, ex, mod=None):
    """Петля (12 с): лицо — выражение ex; mod {параметр: f(кадр)} — множитель
    0–1 к параметру во времени (например, бровки то видны, то нет)."""
    mod = mod or {}
    ex = expr(ex)
    cache = {}

    def at(t):
        if t not in cache:
            cache[t] = channels({k: (v * mod[k](t) if k in mod else v) for k, v in ex.items()})
        return cache[t]
    base = channels(ex)
    for c in base:
        if c[0] == '_pose':
            _mood_pose(spec, c[1], (lambda c: lambda t: at(t).get(c, 0.0))(c))
        elif c[0] == '_mouth':
            rr._mood_mouth(spec, c[1], (lambda c: lambda t: at(t).get(c, (0.0, 0.0))[0])(c),
                           (lambda c: lambda t: at(t).get(c, (0.0, 0.0))[1])(c))
        elif any(abs(at(t).get(c, 0.0)) > 1e-6 for t in range(0, rr.MOOD_T, 30)):
            spec[c] = (lambda c: lambda t: at(t).get(c, 0.0))(c)
    return spec


def reface_mood(fn, ex, mod=None, keep=()):
    """Петля fn с новым лицом (как `reface` для клипов)."""
    def mood():
        sp = fn()
        sp = {k: v for k, v in sp.items() if k == '_mouth_h' or not (family(k[0]) and family(k[0]) not in keep)}
        if 'mouth' not in keep:
            sp.pop('_mouth_h', None)
        return loop_face(sp, ex, mod)
    return mood


def main():
    import clips_v2  # noqa: F401  (выражения и клипы v2)
    install(BOY)
    clips_v2.register()
    build_bear.main(out=G['out'], prepare=prepare)


if __name__ == '__main__':
    main()
