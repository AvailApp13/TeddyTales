"""Мимика v2 мальчика — лицо как в видео Ирины.

    PYTHONHASHSEED=0 python3 tool/rive/face_v2.py   # → assets/rive/bear_boy_v3.riv

Заказчик 26.10: «всё, что я прислал, нужно полностью один в один
реализовать на нашего мишку… глазки, всё»; разбор кадров, замеры и этапы —
`docs/mimika-v2.md`. Риг тот же, что у мальчика (`build_bear.py`,
`rebuild_rig.py`), поверх — новое лицо; нынешний файл мальчика
(`bear_boy_v2.riv`) не меняется, пока заказчик не скажет «да» новому.

Сделано:
- рот — вышитый шов своим рисунком на костях (`vec.py`) вместо картинки
  ротика покоя: стежок от носа вниз и «домик» ∧ (замеры кадров «Спокойствие»:
  стежок 19–29 px, ножки 13–17 px под 30–45° вниз, ширина 27–34 px, цвет —
  тёмный шоколад, толщина ~2,2 px). Стежок от носа виден всегда, «домик» —
  ротик покоя: гаснет, когда раскрывается любой рот эмоции (`MOUTH_SWAP`);
- рты-линии мальчика (довольный, грусть, обида, сонный) — не картинки, а
  позы того же шва: у ножек по пять костей (`SEAM_BONES`), поза — их сдвиг
  от покоя (`POSES`). Все готовые клипы и петли зовут прежние
  `mouth_open(kind=...)` и `_mood_mouth(...)` — сюда они приходят позой шва,
  датчики `mh_<вид>` для приложения те же. Картинки ртов-линий не
  строятся; их прозрачности в приложении (`mop_<вид>`) — прозрачность шва;
- нос — выше, тёмный шоколад, «щиток» (`prepare` правит текстуру лица до
  сборки: веки и сетки строятся уже по новому лицу);
- бусины — глянцевые, почти чёрные, белый блик и вторая точка, светлый серп
  по нижнему краю;
- петли покоя, радости и характеров — глаза круглые (прищур ослаблен,
  `OPEN_EYES`), грусть и сонливость — как были;
- улыбка v2 — сомкнутая «ω» из шва, глаза открыты; смех v2 — дужки ◠
  вместо глаз, бровки, румянец, открытый «D» (`laugh_parts`,
  `emo_smile_v2`, `emo_laugh_v2` вместо прежних `emo_smile`, `emo_laugh`).

В приложении — плитка «Мимика v2 / Прежняя» проверочной ленты
(`kBoyFaceV2Asset`).
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_bear  # noqa: E402
import rebuild_rig as rr  # noqa: E402
import vec  # noqa: E402
from mesh_refine import _read_indices, _write_indices, VERT_TAGS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets/rive/bear_boy_v3.riv')

# --- Нос, бусины, прежний ротик: правка картинок до сборки рига --------------
# Текстура лица → мир (сетка лица в покое): x = 505,70 + (px − 666,5) · 0,6298,
# y = 480,52 + (py − 1000) · 0,6298.
# Нос видео («Спокойствие 1–6»): выше прежнего, тёмный шоколад, «щиток»
# шире своей высоты (1,1 : 1). Мир: верх 441, кончик 479, ширина 50.
NOSE_BOX = (638.0, 937.0, 718.0, 998.0)       # то же в пикселях текстуры
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


def _face(path):
    """Нос лица — контур прежнего, симметричный, перенесён в NOSE_BOX и
    перекрашен в шоколад видео; фактура ткани остаётся. Прежний ротик ∧
    стирает с лица `mouth.build` (его слой заменяет шов, `seam`).

    Прежний глаз под бусиной (в текстуре нарисован чёрный глаз с ворсом)
    закрашен мехом: глазница-заплатка над ним была светлее и серее меха,
    и сплющенная бусина (смех, моргание) открывала бледный овал. В видео
    глаз сидит прямо в меху."""
    face = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64)
    rgb, alpha = face[..., :3], face[..., 3]
    H, W = rgb.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    lum = rgb.mean(2)
    r, b = rgb[..., 0], rgb[..., 2]

    for cx, cy in OLD_EYES:
        d = np.hypot(xx - cx, yy - cy)
        hole = ndimage.binary_dilation((d < EYE_HOLE) | ((d < EYE_HOLE + 18) & (lum < 175)), iterations=3)
        rgb = _inpaint(rgb, hole, -80, axis=0)
        # цвет заплатки — как у меха вокруг (по краю глаза был серый ворс)
        ring = (d > EYE_HOLE + 22) & (d < EYE_HOLE + 40) & (alpha > 250)
        f = ndimage.gaussian_filter(hole.astype(np.float64), 4.0)[..., None]
        rgb = rgb + (rgb[ring].mean(0) - rgb[hole].mean(0)) * f
    lum = rgb.mean(2)

    x0, y0, x1, y1 = NOSE_ROI
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
    tx0, ty0, tx1, ty1 = NOSE_BOX
    sx, sy = (tx1 - tx0) / (cx1 - cx0), (ty1 - ty0) / (cy1 - cy0)
    F = np.array([[sx, 0, tx0 - cx0 * sx], [0, sy, ty0 - cy0 * sy]], np.float32)
    mask = cv2.warpAffine(core.astype(np.float32), F, (W, H), flags=cv2.INTER_LINEAR) > 0.5
    moved = cv2.warpAffine(rgb.astype(np.float32), F, (W, H), flags=cv2.INTER_LINEAR,
                           borderMode=cv2.BORDER_REPLICATE).astype(np.float64)

    shade = roi & (lum < 175) & (r - b > 22)
    hole = (ndimage.binary_dilation(core | shade, iterations=6)
            | (ndimage.binary_dilation(core, iterations=12) & (yy > 990)))
    rgb = _inpaint(rgb, hole)

    detail = moved.mean(2, keepdims=True) - moved[mask].mean()
    nose = np.array(NOSE_RGB) + detail * 0.75
    ys = np.nonzero(mask)[0]
    v = ((yy - ys.min()) / (ys.max() - ys.min())).clip(0, 1)[..., None]
    hl = np.exp(-(((xx - (tx0 + tx1) / 2) / 17.0) ** 2
                  + ((yy - (ys.min() + 0.25 * (ys.max() - ys.min()))) / 7.0) ** 2))[..., None] * 0.20
    nose = nose * (1 - 0.18 * v) * (1 - hl) + np.array([160.0, 120.0, 100.0]) * hl
    edge = ndimage.gaussian_filter(mask.astype(np.float64), 1.0)[..., None]
    rgb = rgb * (1 - edge) + nose * edge
    Image.fromarray(np.dstack([rgb.clip(0, 255), alpha]).astype(np.uint8), 'RGBA').save(path)


def _bead(path):
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


def _clear(path):
    """Картинка остаётся своего размера, но прозрачная: глазницу-заплатку
    `lids.py` впекает в лицо — теперь там мех самого лица."""
    im = Image.open(path).convert('RGBA')
    Image.new('RGBA', im.size, (0, 0, 0, 0)).save(path)


def _closed_eye(path):
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
    """Картинки проекта до сборки рига: веки (`lids.py`) и сетки строятся
    уже по новому лицу."""
    _face(os.path.join(project, 'bear_face.png'))
    for side in 'lr':
        _bead(os.path.join(project, f'face_gaze_bead_{side}.png'))
        _clear(os.path.join(project, f'face_gaze_socket_{side}.png'))
        _closed_eye(os.path.join(project, f'face_eyes_closed_eye_{side}.png'))


# Кость и зона носа — за новым носом (середина 460 вместо 468)
rr.CHAIN[:] = [('nose', 'face', (513, 460), (513, 450)) if c[0] == 'nose' else c for c in rr.CHAIN]
rr.FACE_ZONES[:] = [('nose', 513, 460, 27, 20) if z[0] == 'nose' else z for z in rr.FACE_ZONES]

# --- Рот-шов -------------------------------------------------------------------
SEAM_RGB = '#4a2610'        # тёмный шоколад (кадры видео: #3e2111–#58300d)
SEAM_W = 2.2                # толщина, px мира
NOSE_TIP = (513.5, 477.0)   # стежок начинается внутри низа носа
JUNCTION = (513.5, 503.0)   # развилка «домика»
LEG = 17.0                  # длина ножки
LEG_ANGLE = 35              # градусов вниз от горизонтали


LEG_T = (0.2, 0.4, 0.6, 0.8, 1.0)      # кости ножки — доли её длины
LEG_STEPS = 15                          # точек на ножку (линия гладкая)


def _rest_leg(s, t):
    """Ножка «домика» в покое, от развилки: s = −1 левая, +1 правая; конец
    чуть загибается вниз (кадры «Спокойствие 1–6»)."""
    a = math.radians(LEG_ANGLE)
    return s * LEG * t * math.cos(a), LEG * t * math.sin(a) + 1.6 * t * t


# Позы шва (замеры кадров, docs/mimika-v2.md; МГ = 112 px): сдвиг развилки и
# ножка от развилки как функция доли длины t.
POSES = {
    # «Спокойствие»: домик ∧
    'rest': ((0.0, 0.0), _rest_leg),
    # «Улыбка 1, 3»: сомкнутая «ω» шириной 0,40 МГ — от развилки ножка
    # уходит вниз (прогиб 0,07 МГ) и загибается вверх, уголок выше
    # развилки; стежок от носа короче
    'smile': ((0.0, -2.0), lambda s, t: (s * 22.5 * t, 8.5 * math.sin(math.pi * t) - 4.0 * t * t)),
    # «Улыбка 2, 4», «Радость 3»: широкая «ω» 0,80–0,85 МГ
    'smile_wide': ((0.0, -3.0), lambda s, t: (s * 46.0 * t, 7.0 * math.sin(math.pi * t) - 6.0 * t * t)),
    # «Грусть 1, 2, 4»: узкий домик 0,20–0,24 МГ, ножки загибаются вниз
    'sad': ((0.0, 1.0), lambda s, t: (s * 11.5 * t, 9.0 * t + 3.5 * t * t)),
    # «Обида 3»: крошечный домик 0,18–0,22 МГ, уголки сильно вниз
    'pout': ((0.0, 2.0), lambda s, t: (s * 10.5 * t, 7.0 * t + 6.0 * t * t)),
    # «Сонливость 1–2»: спокойный домик, чуть шире и положе
    'sleepy': ((0.0, 0.5), lambda s, t: (s * 15.0 * t, 7.0 * t + 1.5 * t * t)),
}
# ротик-линия прежних клипов → поза шва
SEAM_KINDS = {'content': 'smile', 'sad': 'sad', 'pout': 'pout', 'sleepy': 'sleepy'}
SEAM_BONES = ['seam_c'] + [f'seam_{side}{i}' for side in 'lr' for i in range(1, len(LEG_T) + 1)]


def _bone_world(name):
    if name == 'seam_c':
        return JUNCTION
    s = -1 if name[5] == 'l' else 1
    dx, dy = _rest_leg(s, LEG_T[int(name[6:]) - 1])
    return JUNCTION[0] + dx, JUNCTION[1] + dy


# кости шва — дети лица (мех у рта держится за лицо), в конце списка: id
# прежних костей не меняются
for _n in SEAM_BONES:
    _x, _y = _bone_world(_n)
    rr.CHAIN.append((_n, 'face', (round(_x, 3), round(_y, 3)), (round(_x, 3), round(_y, 3) - 10)))


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


def _to_local(dx, dy):
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
    common = dict(bones=B, pack=rr.pack, next_id=ctx['next_id'], holder_world=hw, stroke=(SEAM_W, SEAM_RGB))

    # стежок от носа: верх — за мехом носа, низ — за развилкой
    nose_pts = [(NOSE_TIP[0], NOSE_TIP[1] + (JUNCTION[1] - NOSE_TIP[1]) * i / 6) for i in range(7)]

    def nose_w(x, y):
        u = (y - NOSE_TIP[1]) / (JUNCTION[1] - NOSE_TIP[1])
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
            part.append(((JUNCTION[0] + dx, JUNCTION[1] + dy), _leg_weights(side, t)))
        if side == 'l':
            part = part[::-1]
        else:
            part = part[1:]
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


rr.HOOKS.append(seam)


# --- Дужки закрытых глаз, бровки, румянец (смех, улыбка) ---------------------
# «Смех 1–4», «Радость 1»: глазки закрыты дужками ◠ (тёмные, толщина 3,5–4,5,
# ширина 28–39, высота 6–9 px мира), бровки — тонкие дужки над глазами,
# румянец на щеках. В покое всё прозрачно. Дужка привязана плоской чертой
# ровно там, где сплющенная бусина становится чертой: бусина сплющивается —
# черта дужки проявляется на её месте — середина поднимается костью
# `arc_<сторона>` в ◠. Без подмены картинки.
BEADS = {'l': (457.0, 415.3), 'r': (567.2, 414.9)}
ARC_HALF, ARC_H, ARC_W, ARC_RGB = 16.0, 8.0, 3.8, '#2a1810'
BROW_Y, BROW_HALF, BROW_H, BROW_W, BROW_RGB = 380.0, 12.0, 3.0, 2.2, '#6b4630'
BLUSH = {'l': (431.0, 457.0), 'r': (593.0, 457.0)}
BLUSH_R, BLUSH_RGB, BLUSH_A = (15.0, 12.0), (236, 128, 128), 0.55   # σ по x/y, px мира

for _s, (_x, _y) in BEADS.items():
    rr.CHAIN.append((f'arc_{_s}', 'face', (_x, _y), (_x, _y - 10)))


def _face_layer(face_img, W, H, tile, origin, name, asset_id, next_id):
    """Копия сетки лица со своей картинкой tile, лежащей в текстуре с
    пикселя origin; остаются треугольники целиком внутри плитки."""
    th, tw = tile.shape[:2]
    px0, py0 = origin
    img = copy.deepcopy(face_img)
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


def _blush_tile():
    """Румянец обеих щёк одной картинкой (пиксели текстуры лица)."""
    k = 0.62981683
    to_tex = lambda x, y: (666.5 + (x - 505.70184) / k, 1000.0 + (y - 480.51669) / k)
    (lx, ly), (rx, ry) = to_tex(*BLUSH['l']), to_tex(*BLUSH['r'])
    sx, sy = BLUSH_R[0] / k, BLUSH_R[1] / k
    x0, y0 = int(lx - 3.2 * sx), int(min(ly, ry) - 3.2 * sy)
    x1, y1 = int(rx + 3.2 * sx) + 1, int(max(ly, ry) + 3.2 * sy) + 1
    yy, xx = np.mgrid[y0:y1, x0:x1] + 0.5
    a = np.zeros(xx.shape)
    for cx, cy in ((lx, ly), (rx, ry)):
        a = np.maximum(a, np.exp(-0.5 * (((xx - cx) / sx) ** 2 + ((yy - cy) / sy) ** 2)))
    tile = np.zeros(xx.shape + (4,), np.uint8)
    tile[..., :3] = BLUSH_RGB
    tile[..., 3] = (a * BLUSH_A * 255).round().astype(np.uint8)
    return tile, (x0, y0)


def laugh_parts(ctx):
    """Слои смеха и улыбки над веками: румянец, сверху — дужки и бровки."""
    ab, B, byname, root = ctx['ab'], ctx['B'], ctx['byname'], ctx['root']
    lid = byname['lid_patch_img']
    holder = next(p for p in ab.iter() if lid in list(p))
    hw = ctx['W'][holder]

    face_img = byname['face_img']
    fa = next(a for a in root.iter('ImageAsset') if a.get('id') == face_img.get('assetId'))
    tile, origin = _blush_tile()
    Image.fromarray(tile, 'RGBA').save(os.path.join(ctx['project'], 'bear_blush.png'))
    asset_id = ctx['next_id']()
    ET.SubElement(root, 'ImageAsset', {'file': 'bear_blush.png', 'height': str(tile.shape[0]),
                                       'width': str(tile.shape[1]), 'assetId': '9900300',
                                       'name': 'bear_blush', 'id': asset_id})
    blush = _face_layer(face_img, int(fa.get('width')), int(fa.get('height')), tile, origin,
                        'face_blush_img', asset_id, ctx['next_id'])
    blush.set('opacity', '0')
    holder.insert(list(holder).index(lid), blush)
    rr.E_IDS['face_blush'] = blush.get('id')

    common = dict(bones=B, pack=rr.pack, next_id=ctx['next_id'], holder_world=hw, opacity=0.0)
    for s, (cx, cy) in BEADS.items():
        n = 25
        pts = [(cx - ARC_HALF + 2 * ARC_HALF * i / (n - 1), cy) for i in range(n)]

        def arc_w(x, y, s=s, cx=cx):
            a = max(0.0, 1 - ((x - cx) / ARC_HALF) ** 2)
            fur = rr.weights_for('face_arc', x, y, B)
            w = {b: v * (1 - a) for b, v in fur.items()}
            w[f'arc_{s}'] = w.get(f'arc_{s}', 0) + a
            return {b: v for b, v in w.items() if v > 1e-4}
        arc = vec.shape(f'face_arc_{s}', pts, weights=arc_w, stroke=(ARC_W, ARC_RGB), **common)
        bx = cx + (1 if s == 'l' else -1) * 0.5
        brow_pts = [(bx - BROW_HALF + 2 * BROW_HALF * i / 14,
                     BROW_Y - BROW_H * (1 - ((2 * i / 14) - 1) ** 2)) for i in range(15)]
        brow = vec.shape(f'face_brow_{s}', brow_pts, weights=lambda x, y: rr.weights_for('face_brow', x, y, B),
                         stroke=(BROW_W, BROW_RGB, 0.9), **common)
        for el in (brow, arc):
            holder.insert(list(holder).index(blush), el)
        rr.E_IDS[f'face_arc_{s}'] = arc.get('id')
        rr.E_IDS[f'face_brow_{s}'] = brow.get('id')


rr.HOOKS.append(laugh_parts)


# --- Клипы: рты-линии → позы шва ---------------------------------------------
_mouth_open = rr.Emo.mouth_open
_build = rr.Emo.build


def mouth_open(self, pts, kind='open'):
    """Рты-линии прежних клипов — поза шва; доля позы — «высота» рта.
    Полости (смех, зевок, жевание) — как раньше."""
    if kind not in SEAM_KINDS:
        return _mouth_open(self, pts, kind)
    ez = (lambda p: p[3] if len(p) > 3 else rr.EI)
    self.track(f'mh_{kind}', self.Y, [(p[0], p[2], ez(p)) for p in pts])
    self.__dict__.setdefault('_seam', []).append(
        (SEAM_KINDS[kind], [(p[0], min(1.0, max(0.0, p[2])), ez(p)) for p in pts]))
    return self


def build(self):
    """Позы шва клипа — в ключи костей шва; несколько поз складываются.
    Рот-линия считается ртом клипа: ротик покоя (шов) не гаснет — это он и
    есть, а рты петли клип закрывает, как раньше (`Emo._rest_mouth`)."""
    seams = self.__dict__.pop('_seam', [])
    for pose, _ in seams:
        kind = next(k for k, p in SEAM_KINDS.items() if p == pose)
        self.mouth_h.setdefault(kind, [(0, 0.0)])
    if len(seams) == 1:
        pose, amt = seams[0]
        for bone, (dx, dy) in pose_offsets(pose).items():
            lx, ly = _to_local(dx, dy)
            self.track(bone, self.X, [(f, lx * a, e) for f, a, e in amt])
            self.track(bone, self.Y, [(f, ly * a, e) for f, a, e in amt])
    elif seams:
        end = self.dur - 2
        frames = list(range(0, end + 1, 2))
        tracks = {}
        for pose, amt in seams:
            curve = [(0, 0.0, rr.EI)] + amt + [(end, 0.0, None)]
            for fr in frames:
                a = rr.track_at(curve, fr)
                for bone, (dx, dy) in pose_offsets(pose, a).items():
                    acc = tracks.setdefault(bone, {}).setdefault(fr, [0.0, 0.0])
                    acc[0] += dx
                    acc[1] += dy
        for bone, by_fr in tracks.items():
            xs = [(fr, _to_local(*by_fr[fr])[0], rr.LIN) for fr in frames[1:-1]]
            ys = [(fr, _to_local(*by_fr[fr])[1], rr.LIN) for fr in frames[1:-1]]
            self.track(bone, self.X, xs)
            self.track(bone, self.Y, ys)
    return _build(self)


rr.Emo.mouth_open = mouth_open
rr.Emo.build = build

_mood_mouth = rr._mood_mouth


def mood_mouth(spec, kind, w, h):
    """Рот петли настроения: рты-линии — поза шва (доля — высота рта)."""
    if kind not in SEAM_KINDS:
        return _mood_mouth(spec, kind, w, h)
    spec[(f'mh_{kind}', rr.Emo.Y)] = h
    for bone, (dx, dy) in pose_offsets(SEAM_KINDS[kind]).items():
        lx, ly = _to_local(dx, dy)
        prev_x = spec.get((bone, rr.Emo.X))
        prev_y = spec.get((bone, rr.Emo.Y))
        spec[(bone, rr.Emo.X)] = (lambda lx, prev: lambda t: lx * min(1.0, max(0.0, h(t)))
                                  + (prev(t) if prev else 0.0))(lx, prev_x)
        spec[(bone, rr.Emo.Y)] = (lambda ly, prev: lambda t: ly * min(1.0, max(0.0, h(t)))
                                  + (prev(t) if prev else 0.0))(ly, prev_y)


rr._mood_mouth = mood_mouth

# --- Петли: глаза круглые -----------------------------------------------------
# В видео глаза в покое, в радости и при спокойном характере круглые
# («Спокойствие», «Радость», «Задумчивость»); прищур петель (`_mood_eyes`)
# делал их овальными. Доля прежнего прищура; грусть, сонливость, «грязный» —
# как были.
OPEN_EYES = {'mood_happy': 0.0, 'idle_trait_active': 0.0, 'idle_trait_calm': 0.15,
             'idle_trait_affectionate': 0.3, 'idle_trait_independent': 0.3,
             'idle_trait_reserved': 0.5}


def _open_eyes(fn, k):
    def mood():
        sp = fn()
        for side in 'lr':
            for key in (rr.Emo.SY, rr.Emo.Y):
                f = sp.get((f'bead_{side}', key))
                if f:
                    sp[(f'bead_{side}', key)] = (lambda f: lambda t: k * f(t))(f)
        return sp
    return mood


for _name, _k in OPEN_EYES.items():
    rr.MOODS[_name] = _open_eyes(rr.MOODS[_name], _k)


# --- Улыбка v2 и смех v2 -------------------------------------------------------
X, Y, SY, OP = rr.Emo.X, rr.Emo.Y, rr.Emo.SY, rr.Emo.OP


def _fade(e, name, pts):
    """Прозрачность своего слоя (в покое 0): pts [(кадр, значение[, кривая])]."""
    e.ch[(rr.E_IDS[name], OP)] = ([(0, 0.0, rr.EI)] + [(p[0], p[1], p[2] if len(p) > 2 else rr.EI) for p in pts]
                                  + [(e.dur - 2, 0.0, None)])


def emo_smile_v2():
    """Улыбка v2, 2,5 с («Улыбка 1–5»): рот закрыт — шов «домиком»
    растягивается в сомкнутую улыбку «ω», глаза открыты и круглые, щёки
    чуть вверх, бровки не видны. Тело — как в прежней улыбке: голова мягко
    наклоняется, мишка приподнимается, уши и капюшон догоняют."""
    e = rr.Emo(150)
    e.mouth_open([(6, 0.0, 0.0), (32, 1.0, 1.0, rr.EO), (110, 1.0, 0.94), (136, 0.0, 0.0)], kind='content')
    e.track('muzzle', X, [(34, 0.6), (110, 0.5), (136, 0)])
    e.pair('cheek', X, [(10, 0), (36, 3, rr.EO), (110, 2.6), (140, 0)])
    e.pair('cheek', SY, [(36, 0.04), (110, 0.035), (140, 0)])
    e.pair('brow', X, [(36, 1.5, rr.EO), (110, 1.3), (140, 0)])
    e.track('head', rr.Emo.R, [(8, -0.012), (44, 0.06, rr.EO), (80, 0.05), (104, 0.055)])
    e.track('face', X, [(40, 2), (104, 1.5)])
    e.track('face', Y, [(40, 3), (104, 2.5)])
    e.track('hips', Y, [(8, 2, rr.EO), (32, -4), (104, -3)])
    e.track('breath', SY, [(8, 0.02), (38, 0.035), (104, 0.03)])
    e.track('hood2', rr.Emo.R, [(22, 0), (46, -0.08), (72, 0.03), (96, -0.015)])
    e.track('hood1', rr.Emo.R, [(40, -0.025), (76, 0.008)])
    e.track('ear_l1', rr.Emo.R, [(18, -0.09, rr.EO), (44, 0.03), (74, -0.03)])
    e.track('ear_r1', rr.Emo.R, [(20, 0.09, rr.EO), (46, -0.03), (76, 0.03)])
    e.track('ear_l2', rr.Emo.R, [(24, -0.1, rr.EO), (50, 0.04), (78, -0.02)])
    e.track('ear_r2', rr.Emo.R, [(26, 0.1, rr.EO), (52, -0.04), (80, 0.02)])
    e.track('arm_l1', rr.Emo.R, [(40, 0.03), (104, 0.025)])
    e.track('arm_r1', rr.Emo.R, [(40, -0.03), (104, -0.025)])
    return e.build()


def emo_laugh_v2():
    """Смех v2, 4,2 с («Смех 1–4»): бусины сплющиваются в черту, черта
    становится дужкой ◠ (`laugh_parts`), щёки вверх и румянец, бровки
    проявляются и приподнимаются, рот — открытый «D» с язычком (полость
    прежнего смеха, `Emo.mouth_open`); пять мягких «ха-ха» волной, как в
    прежнем смехе. В конце дужки распрямляются в черту и глаза открываются."""
    e = rr.Emo(252)
    g = [60, 84, 108, 132, 156]
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
    # глаза: бусина сплющивается в черту тоньше пикселя (прозрачностью её
    # не гасить: выход клипа в покой смешивает её с покоем, и на медленном
    # кадре бусина оставалась серой), на её месте проявляется черта дужки,
    # середина дужки поднимается; в конце — обратно
    e.eyes([(4, 0.0), (18, 0.995, rr.EIN), (210, 0.995), (232, 0.0, rr.EO)])
    for s in 'lr':
        _fade(e, f'face_arc_{s}', [(13, 0.0), (18, 1.0), (209, 1.0), (213, 0.0)])
        e.track(f'arc_{s}', X, [(18, 0.0), (34, ARC_H, rr.EO)] + beats(ARC_H + 0.8, ARC_H) + [(196, ARC_H), (210, 0.0)])
        _fade(e, f'face_brow_{s}', [(20, 0.0), (40, 0.9), (200, 0.9), (230, 0.0)])
    _fade(e, 'face_blush', [(20, 0.0), (60, 0.85), (196, 0.8), (240, 0.0)])
    e.pair('lid', X, [(36, 5, rr.EO), (186, 5), (236, 1)])
    e.pair('cheek', X, [(36, 5, rr.EO)] + beats(6.5, 5) + [(196, 5), (236, 0.5)])
    e.pair('cheek', SY, [(36, 0.06), (186, 0.06), (236, 0.01)])
    e.pair('brow', X, [(36, 3.5, rr.EO), (186, 3.5), (236, 0.2)])
    e.pair('mouth', X, [(28, 7, rr.EO), (186, 7), (236, 1)])
    e.pair('mouth', Y, [(28, -2), (186, -2), (236, 0)], mirror=True)
    e.track('chin', X, [(56, -2.5)] + beats(-3.5, -2) + [(196, -2), (236, 0)])
    e.track('muzzle', X, [(36, 1), (186, 1), (236, 0)])
    e.track('breath', SY, [(6, -0.01), (30, 0.04, rr.EO)] + beats(0.055, 0.02, -2) + [(196, 0.02), (244, 0)])
    e.track('chest', rr.Emo.R, [(32, 0)] + beats(-0.012, 0.0, -2) + [(244, 0)])
    e.track('hips', Y, [(14, 1.5), (40, -2.5, rr.EO)] + beats(-3.5, -1.5, -2) + [(196, -1.5), (244, 0)])
    e.track('head', rr.Emo.R, [(40, 0.04, rr.EO)] + beats(0.05, 0.035) + [(196, 0.035), (244, 0)])
    e.track('face', X, [(40, 2.5, rr.EO)] + beats(3.5, 2.2) + [(196, 2), (244, 0)])
    e.track('face', Y, [(40, 2), (196, 2), (244, 0)])
    e.track('hood1', rr.Emo.R, [(44, -0.02), (196, -0.015), (244, 0)])
    e.track('hood2', rr.Emo.R, [(44, -0.05)] + beats(-0.07, -0.03, 5) + [(212, -0.02)])
    e.track('ear_l1', rr.Emo.R, [(40, -0.06)] + beats(-0.09, -0.04, 3) + [(212, -0.02)])
    e.track('ear_r1', rr.Emo.R, [(40, 0.06)] + beats(0.09, 0.04, 3) + [(212, 0.02)])
    e.track('ear_l2', rr.Emo.R, [(44, -0.05)] + beats(-0.07, -0.02, 6) + [(214, -0.01)])
    e.track('ear_r2', rr.Emo.R, [(44, 0.05)] + beats(0.07, 0.02, 6) + [(214, 0.01)])
    return e.build()


rr.EMOTION_ANIMS['emo_smile'] = emo_smile_v2
rr.EMOTION_ANIMS['emo_laugh'] = emo_laugh_v2


def main():
    build_bear.main(out=OUT, prepare=prepare)


if __name__ == '__main__':
    main()
