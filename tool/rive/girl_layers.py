"""Слои девочки (JOY) из вырезки — по образцу слоёв мальчика.

    python3 tool/rive/girl_layers.py           # → assets_src/rive/girl/layers/
    python3 tool/rive/girl_layers.py --masks   # только раскраска частей (проверка)

Мальчик собран из 19 полных слоёв, присланных заказчиком 26.09: каждая
деталь дорисована целиком, и то, что закрыто соседом, — тоже, иначе при
движении откроются дыры. Девочку режем сами из фото (вариант «Б», 14.10):

    ear_left, ear_right       уши — за головой
    foot_left, foot_right     ноги со стопами — за юбкой
    skirt                     юбка с кружевом
    shirt                     кофточка без рукавов (бока, ворот)
    arm_left, arm_right       пушистые лапы — выходят из рукавов
    sleeve_left, sleeve_right рукава
    head                      голова с мордочкой
    bow                       лента и бант

(порядок — сзади наперёд). Границы:
- цвет: зелёная ткань, розовая юбка, белый мех, тёмное (глаза, нос, рот);
- швы реглана, стык уха с головой, низ кружева — ломаные по фото
  (координаты фото 1718 × 2576, сняты по увеличенным кадрам с сеткой);
- голова и мех лап — по меху; бант на голове — по зелёному.

Что закрыто соседом, дорисовано с запасом (`fill_*`): ворот под
подбородком, кофта под рукавами, юбка под кофтой, ноги под юбкой, мех
под бантом, уши под головой. В покое слои складываются в исходную вырезку
пиксель в пиксель (проверка в конце), при движении на несколько пикселей
открывается дорисованное.

Слои сохраняются в кадре слоёв мальчика 1333 × 2000 (`girl_face.py`:
совмещение по глазам, масштаб 1,113): кости и веса мальчика встают на
девочку. Стопы приходятся на тот же пол (низ 1796 против 1800 px).

Зависимости: numpy, scipy, Pillow, opencv-python-headless.
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from girl_face import photo_to_layers  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, 'assets_src/rive/girl')
CUT = os.path.join(DIR, 'joy_cut.png')
OUT = os.path.join(DIR, 'layers')
FRAME = (1333, 2000)

# --- границы (координаты фото) ---------------------------------------------
# Стык левого уха с головой: от выемки силуэта у макушки (693, 1007) по
# складке у основания уха к выемке у щеки (603, 1203); концы выведены за
# силуэт.
EAR_L = [(690, 950), (693, 1004), (706, 1050), (700, 1095), (672, 1140),
         (640, 1175), (603, 1203), (560, 1240)]
# Правое ухо: от выемки между бантом и ухом (991, 999) до выемки, где ухо
# уходит под хвост банта (1143, 1121). Низ уха под бантом — не виден.
EAR_R = [(985, 950), (991, 999), (1005, 1050), (1040, 1095), (1090, 1118),
         (1143, 1121), (1200, 1125)]
# Швы реглана (тёмная тень шва — у рукава, светлый рубчик — у кофты) и
# подмышка.
SEAM_L = [(700, 1440), (700, 1467), (687, 1483), (673, 1503), (663, 1523),
          (657, 1547), (652, 1573), (649, 1600), (647, 1627), (642, 1653),
          (633, 1673), (623, 1693), (600, 1708), (380, 1708)]
SEAM_R = [(1013, 1440), (1013, 1457), (1030, 1472), (1043, 1490),
          (1052, 1507), (1057, 1523), (1060, 1557), (1060, 1590),
          (1066, 1620), (1076, 1650), (1090, 1680), (1100, 1700),
          (1140, 1704), (1340, 1704)]
# Низ кружева над ногами; ниже — ноги. Между ногами — просвет у x 885.
LACE = [(520, 1960), (560, 1975), (600, 1985), (650, 1995), (700, 2010),
        (750, 2020), (800, 2030), (840, 2035), (870, 2040), (885, 2042),
        (900, 2032), (950, 2025), (1000, 2025), (1050, 2025), (1075, 2005),
        (1100, 1995), (1130, 1993), (1150, 1985), (1170, 1972), (1200, 1962),
        (1240, 1950)]
FEET_SPLIT = 885
COLLAR_Y = 1500          # ниже — уже не голова
BOW_Y = 1300             # зелёное выше — лента и бант
ARM_Y = (1540, 1760)     # мех лап по высоте

FUR = np.array([232.0, 233.0, 226.0])
CARDIGAN = np.array([124.0, 185.0, 139.0])


def load():
    im = np.asarray(Image.open(CUT).convert('RGBA')).astype(np.float64)
    return im[..., :3], im[..., 3] / 255.0


def classes(rgb, alpha):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb.mean(2)
    sat = rgb.max(2) - rgb.min(2)
    on = alpha > 0.02
    green = on & (g - r > 25) & (g - b > 10)
    dark = on & ~green & (lum < 90)
    pink = on & ~green & ~dark & (r - g > 8) & (r - b > 4) & (sat > 12) & (lum > 150)
    fur = on & ~green & ~dark & ~pink
    return on, green, pink, fur, dark


def side_of(shape, line, close):
    """Маска области, которую ломаная `line` отсекает вместе с точками
    `close` (обход замыкается через них)."""
    m = np.zeros(shape, np.uint8)
    pts = np.array(list(line) + list(close), np.int32)
    cv2.fillPoly(m, [pts], 1)
    return m.astype(bool)


def components(mask, min_size=50):
    lab, n = ndimage.label(mask)
    if n == 0:
        return lab, []
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    return lab, [i + 1 for i, s in enumerate(sizes) if s >= min_size]


def parts(rgb, alpha):
    """Маски частей в координатах фото (bool), без дорисовки."""
    h, w = alpha.shape
    on, green, pink, fur, dark = classes(rgb, alpha)
    yy, xx = np.mgrid[0:h, 0:w]
    # части — только по плотным пикселям; полупрозрачная кайма силуэта
    # потом отходит к ближайшей части (иначе кайма рукава — «голова»)
    solid = alpha > 0.5
    on = solid

    # лента и бант: зелёное наверху + тёмный узел внутри банта
    bow = green & solid & (yy < BOW_Y)
    bow = ndimage.binary_closing(bow, iterations=3)
    bow |= ndimage.binary_fill_holes(bow) & (dark | green | (alpha < 0.98))
    lab, keep = components(bow, 400)
    bow = np.isin(lab, keep)
    bow = ndimage.binary_fill_holes(bow) & on

    # кофта: самая большая зелёная область (с пуговицами, сердечком, тенями)
    body = green & solid & (yy >= BOW_Y)
    lab, keep = components(body, 1000)
    biggest = max(keep, key=lambda i: (lab == i).sum())
    # с дырами: пуговицы и сердечко с белой каймой — тоже кофта
    cardigan = ndimage.binary_fill_holes(ndimage.binary_closing(lab == biggest, iterations=2)) & on
    sleeve_l = cardigan & side_of((h, w), SEAM_L, [(380, 1380), (700, 1380)])
    sleeve_r = cardigan & side_of((h, w), SEAM_R, [(1340, 1380), (1013, 1380)])
    shirt = cardigan & ~sleeve_l & ~sleeve_r

    # голова с ушами: всё не зелёное выше ворота, кроме банта
    top = on & ~cardigan & ~bow & (yy < COLLAR_Y)
    lab, keep = components(top & solid, 2000)
    top &= ndimage.binary_dilation(np.isin(lab, keep), iterations=4)
    # светлая полоска по верху рукава касается щеки — не голова: тонкое
    # (уже ~10 px) отрезается раскрытием и уходит к ближайшей части
    top = ndimage.binary_opening(top, iterations=5)
    # зеленоватая кайма ленты на мехе — к банту: под ним голова дорисована,
    # иначе при покачивании банта на голове остался бы зелёный контур
    tint = (rgb[..., 1] - rgb[..., 0]) > 5
    bow |= ndimage.binary_dilation(bow, iterations=5) & top & tint
    top &= ~bow
    ear_l = top & side_of((h, w), EAR_L, [(480, 1240), (480, 900), (690, 900)])
    ear_r = top & side_of((h, w), EAR_R, [(1260, 1125), (1260, 900), (985, 900)])
    head = top & ~ear_l & ~ear_r

    # низ: ноги под кружевом, юбка — между кофтой и кружевом
    below = side_of((h, w), LACE, [(1240, 2300), (520, 2300)])
    feet = on & below & (yy > 1900) & (xx > 590) & (xx < 1145)
    foot_l = feet & (xx < FEET_SPLIT)
    foot_r = feet & (xx >= FEET_SPLIT)

    # мех лап: белое по бокам на высоте рукавов, отдельно от юбки
    rest = on & ~cardigan & ~bow & ~top & ~feet
    side = (yy > ARM_Y[0]) & (yy < ARM_Y[1])
    lab, keep = components(rest & solid, 300)
    arm_l = np.zeros_like(on)
    arm_r = np.zeros_like(on)
    skirt = np.zeros_like(on)
    for i in keep:
        comp = lab == i
        ys, xs = np.nonzero(comp)
        cy, cx = ys.mean(), xs.mean()
        if side[int(cy), int(cx)] and cx < 700 and fur[comp].mean() > 0.6:
            arm_l |= comp
        elif side[int(cy), int(cx)] and cx > 1000 and fur[comp].mean() > 0.6:
            arm_r |= comp
        else:
            skirt |= comp
    # полупрозрачная кайма вокруг: к ближайшей части
    named = {'ear_left': ear_l, 'ear_right': ear_r, 'foot_left': foot_l,
             'foot_right': foot_r, 'skirt': skirt, 'shirt': shirt,
             'arm_left': arm_l, 'arm_right': arm_r, 'sleeve_left': sleeve_l,
             'sleeve_right': sleeve_r, 'head': head, 'bow': bow}
    taken = np.zeros_like(on)
    for m in named.values():
        taken |= m
    left = (alpha > 0.02) & ~taken
    if left.any():
        idx = np.zeros(on.shape, np.int32)
        for k, m in enumerate(named.values(), 1):
            idx[m] = k
        _, (iy, ix) = ndimage.distance_transform_edt(idx == 0, return_indices=True)
        nearest = idx[iy, ix]
        for k, name in enumerate(named, 1):
            named[name] = named[name] | (left & (nearest == k))
    for name in named:
        named[name] = named[name] & (alpha > 0.02)
    return named


ORDER = ['ear_left', 'ear_right', 'foot_left', 'foot_right', 'skirt', 'shirt',
         'arm_left', 'arm_right', 'sleeve_left', 'sleeve_right', 'head', 'bow']
# На сколько пикселей фото слой продолжается под соседями спереди.
EXTEND = {'ear_left': 60, 'ear_right': 60, 'foot_left': 90, 'foot_right': 90,
          'skirt': 70, 'shirt': 110, 'arm_left': 45, 'arm_right': 45,
          'sleeve_left': 40, 'sleeve_right': 40, 'head': 0, 'bow': 0}
BAND = 0          # под соседом спереди — сразу дорисовка: свой край у него жёсткий


def mirror_fill(rgb, core, region):
    """Цвет `region` — отражение своей ткани от ближайшего края `core`:
    точка p берёт цвет из 2q − p (q — ближайшая точка core), за пределами
    core — из самой q. Фактура и светотень продолжаются за край."""
    out = rgb.copy()
    _, (iy, ix) = ndimage.distance_transform_edt(~core, return_indices=True)
    py, px = np.nonzero(region)
    qy, qx = iy[py, px], ix[py, px]
    ry = np.clip(2 * qy - py, 0, core.shape[0] - 1)
    rx = np.clip(2 * qx - px, 0, core.shape[1] - 1)
    ok = core[ry, rx]
    sy = np.where(ok, ry, qy)
    sx = np.where(ok, rx, qx)
    out[py, px] = rgb[sy, sx]
    # шов отражения смягчить: лёгкое размытие только внутри дорисовки
    soft = rgb.copy()
    soft[py, px] = out[py, px]
    blur = np.stack([ndimage.gaussian_filter(soft[..., c], 0.7) for c in range(3)], -1)
    out[py, px] = blur[py, px]
    return out


# Чистые образцы фактуры (x, y, сторона — пиксели фото) и из чего берётся
# свет и тень для продолжения слоя.
PATCH = {'fur': (790, 1080, 96), 'knit': (700, 1540, 96),
         'knit_l': (540, 1500, 64), 'knit_r': (1080, 1490, 64),
         'skirt': (760, 1840, 96)}
GRAIN = {'fur': 0.8, 'knit': 1.0, 'knit_l': 1.0, 'knit_r': 1.0, 'skirt': 1.0}
MATERIAL = {'ear_left': 'fur', 'ear_right': 'fur', 'foot_left': 'fur',
            'foot_right': 'fur', 'skirt': 'skirt', 'shirt': 'knit',
            'arm_left': 'fur', 'arm_right': 'fur', 'sleeve_left': 'knit_l',
            'sleeve_right': 'knit_r', 'head': 'fur'}


def texture(rgb, material, shape):
    """Мелкая фактура материала (без света и тени) на весь кадр: образец
    минус его размытие, бесшовная плитка (образец смешан со своим сдвигом на
    полстороны: у краёв плитки — сдвинутый, в середине — сам; без зеркал,
    иначе мех складывается в «кружевной» узор)."""
    x, y, n = PATCH[material]
    patch = rgb[y:y + n, x:x + n]
    hf = patch - np.stack([ndimage.gaussian_filter(patch[..., c], 4) for c in range(3)], -1)
    rolled = np.roll(hf, (n // 2, n // 2), (0, 1))
    t = np.sin(np.pi * (np.arange(n) + 0.5) / n)
    w = np.sqrt(np.outer(t, t))[..., None]
    tile = (w * hf + (1 - w) * rolled) / np.sqrt(w ** 2 + (1 - w) ** 2)
    reps = (shape[0] // n + 1, shape[1] // n + 1, 1)
    return np.tile(tile, reps)[:shape[0], :shape[1]] * GRAIN[material]


def smooth_fill(rgb, core, region, material):
    """Цвет `region`: свет и тень своего слоя плавно продолжены за край
    (размытое своё + inpaint), поверх — фактура чистого образца."""
    out = rgb.copy()
    g = ndimage.gaussian_filter(core.astype(float), 5)
    lf = np.stack([ndimage.gaussian_filter(rgb[..., c] * core, 5) for c in range(3)], -1)
    lf = lf / np.maximum(g, 1e-6)[..., None]
    known = g > 0.3
    # продолжить свет и тень: inpaint в уменьшенном виде (быстро и гладко)
    ys, xs = np.nonzero(region | ~known & ndimage.binary_dilation(region, iterations=8))
    if len(ys) == 0:
        return out
    y0, y1 = max(0, ys.min() - 40), min(rgb.shape[0], ys.max() + 41)
    x0, x1 = max(0, xs.min() - 40), min(rgb.shape[1], xs.max() + 41)
    kn = known[y0:y1, x0:x1].astype(np.float32)
    sub = np.where(known[y0:y1, x0:x1, None], lf[y0:y1, x0:x1], 0).astype(np.float32)
    k = 4
    size = ((x1 - x0) // k + 1, (y1 - y0) // k + 1)
    # уменьшить с нормировкой по известному: пустота не темнит край
    ksmall = cv2.resize(kn, size, interpolation=cv2.INTER_AREA)
    small = cv2.resize(sub * kn[..., None], size, interpolation=cv2.INTER_AREA)
    small = small / np.maximum(ksmall, 1e-6)[..., None]
    hsmall = (ksmall < 0.5).astype(np.uint8)
    small = np.where(hsmall[..., None] > 0, 0, small)
    filled = cv2.inpaint(np.clip(small, 0, 255).astype(np.uint8), hsmall, 6, cv2.INPAINT_TELEA)
    big = cv2.resize(filled, (x1 - x0, y1 - y0), interpolation=cv2.INTER_CUBIC).astype(np.float64)
    big = np.stack([ndimage.gaussian_filter(big[..., c], 3) for c in range(3)], -1)
    lf_full = lf.copy()
    sl = (slice(y0, y1), slice(x0, x1))
    lf_full[sl] = np.where(known[sl][..., None], lf[sl], big)
    tex = texture(rgb, material, rgb.shape[:2])
    fill = np.clip(lf_full + tex, 0, 255)
    out[region] = fill[region]
    return out


def layers(rgb, alpha, named):
    """{имя: RGBA float (0..255, альфа 0..1)} в координатах фото."""
    h, w = alpha.shape
    solid = alpha > 0.98
    opaque = ndimage.binary_erosion(solid, iterations=2)
    hull_head = np.zeros((h, w), np.uint8)
    ys, xs = np.nonzero(named['head'])
    hull = cv2.convexHull(np.stack([xs, ys], 1).astype(np.int32))
    cv2.fillPoly(hull_head, [hull], 1)
    hull_head = hull_head.astype(bool)
    ear_poly_r = side_of((h, w), EAR_R, [(1260, 1125), (1260, 900), (985, 900)])
    ear_poly_l = side_of((h, w), EAR_L, [(480, 1240), (480, 900), (690, 900)])
    yy, xx = np.mgrid[0:h, 0:w]
    _, green, pink, fur, _ = classes(rgb, alpha)
    r, g = rgb[..., 0], rgb[..., 1]
    button = green & (g - r > 90)
    button = ndimage.binary_dilation(button, iterations=6)
    out = {}
    for k, name in enumerate(ORDER):
        m = named[name]
        front = np.zeros((h, w), bool)
        for other in ORDER[k + 1:]:
            front |= named[other]
        base = m | (ndimage.binary_dilation(m, iterations=BAND) & front & solid) if BAND else m.copy()
        ext = np.zeros((h, w), bool)
        grow = ndimage.binary_dilation(m, iterations=EXTEND[name]) if EXTEND[name] else ext
        ys, xs = np.nonzero(m)
        if name.startswith('ear'):
            # ухо — диск: продолжение под головой не дальше его круга
            cy, cx = ys.mean(), xs.mean()
            r = np.sqrt(((ys - cy) ** 2 + (xs - cx) ** 2).max()) + 10
            disc = (yy - cy) ** 2 + (xx - cx) ** 2 <= r * r
            poly = ear_poly_r if name == 'ear_right' else ear_poly_l
            ext = ((grow & front) | (poly & named['bow'])) & disc & opaque
        elif name.startswith('foot'):
            # нога — вверх под юбку, в своих границах по ширине
            ext = grow & front & opaque & (xx >= xs.min() - 6) & (xx <= xs.max() + 6)
        elif name == 'skirt':
            ext = grow & named['shirt'] & opaque
        elif name == 'shirt':
            ext = grow & (named['head'] | named['sleeve_left'] | named['sleeve_right']) & opaque
        elif name.startswith('arm'):
            side = 'left' if name.endswith('left') else 'right'
            ext = grow & named['sleeve_' + side] & opaque
        elif name.startswith('sleeve'):
            ext = grow & named['head'] & opaque
        elif name == 'head':
            ext = named['bow'] & hull_head & ~ear_poly_r & ~ear_poly_l & opaque
        ext &= ~base
        # источник света и тени — чистый свой материал, подальше от чужих
        cls = {'fur': fur, 'knit': green & ~button, 'knit_l': green, 'knit_r': green,
               'skirt': pink | (fur & (yy < 1940))}[MATERIAL.get(name, 'fur')] if name != 'bow' else m
        core = ndimage.binary_erosion(m & cls & (alpha > 0.95), iterations=3)
        if name.startswith('ear') or name == 'head':
            core &= ~ndimage.binary_dilation(named['bow'], iterations=5)
        if ext.any() and core.any():
            col = smooth_fill(rgb, core, ext, MATERIAL[name])
        else:
            col = rgb.copy()
        support = base | ext
        # своё — целиком; мягкий край выходит наружу только внутри
        # непрозрачного (на стыках с соседями сзади, у них там исходные
        # пиксели). По силуэту край уже мягкий — прозрачность вырезки.
        ramp = np.clip(ndimage.gaussian_filter(support.astype(float), 1.2) * 2, 0, 1)
        soft = np.where(support, 1.0, np.where(solid, ramp, 0.0))
        a = np.where(ext, 1.0, alpha) * soft
        # дорисовка гаснет у своего внешнего края (если откроется — без ступеньки)
        fade = ndimage.gaussian_filter(support.astype(float), 2.0)
        a = np.where(ext, a * np.clip(fade * 2 - 0.2, 0, 1), a)
        out[name] = np.dstack([col, a])
    return out


def to_frame(layer):
    """Слой фото → кадр слоёв мальчика 1333 × 2000 (премультипликация, бикубик)."""
    s, dx, dy = photo_to_layers()
    a = layer[..., 3]
    pm = np.dstack([layer[..., :3] * a[..., None], a * 255.0]).clip(0, 255).astype(np.float32)
    res = []
    for c in range(4):
        im = Image.fromarray(pm[..., c], 'F')
        res.append(np.asarray(im.transform(FRAME, Image.AFFINE, (1 / s, 0, -dx / s, 0, 1 / s, -dy / s),
                                           resample=Image.BICUBIC)))
    pm = np.stack(res, -1)
    a = np.clip(pm[..., 3] / 255.0, 0, 1)
    rgb = np.where(a[..., None] > 1e-4, pm[..., :3] / np.maximum(a[..., None], 1e-4), 0)
    return np.dstack([np.clip(rgb, 0, 255), a * 255]).round().astype(np.uint8)


def composite(stack):
    """Наложение слоёв (RGBA float, альфа 0..1) по порядку на прозрачном:
    (цвет, умноженный на альфу; альфа)."""
    rgb = np.zeros(stack[0].shape[:2] + (3,))
    a = np.zeros(stack[0].shape[:2])
    for lay in stack:
        la = lay[..., 3]
        rgb = lay[..., :3] * la[..., None] + rgb * (1 - la[..., None])
        a = la + a * (1 - la)
    return rgb, a


COLORS = {'ear_left': (255, 200, 120), 'ear_right': (255, 160, 60),
          'foot_left': (150, 120, 255), 'foot_right': (100, 70, 220),
          'skirt': (250, 140, 180), 'shirt': (60, 170, 90),
          'arm_left': (120, 220, 255), 'arm_right': (40, 160, 220),
          'sleeve_left': (170, 230, 120), 'sleeve_right': (110, 200, 60),
          'head': (245, 245, 245), 'bow': (20, 110, 40)}


def show_masks(named, alpha, path):
    h, w = alpha.shape
    out = np.zeros((h, w, 3)) + (60, 90, 170)
    for name, m in named.items():
        out[m] = COLORS[name]
    out = out * alpha[..., None] + np.array([60, 90, 170]) * (1 - alpha[..., None])
    Image.fromarray(out.astype(np.uint8)).crop((400, 900, 1320, 2120)).save(path)


def main():
    rgb, alpha = load()
    named = parts(rgb, alpha)
    if '--masks' in sys.argv:
        for name, m in named.items():
            print(f'{name:13s} {int(m.sum()):7d}')
        i = sys.argv.index('--masks')
        show_masks(named, alpha, sys.argv[i + 1] if len(sys.argv) > i + 1 else '/tmp/girl_masks.png')
        return
    lays = layers(rgb, alpha, named)
    # проверка: в покое слои складываются в исходную вырезку
    crgb, ca = composite([lays[n] for n in ORDER])     # премультиплицированный цвет
    diff = np.abs(crgb - rgb * alpha[..., None]).max(2)
    print(f'покой: наибольшая разница {diff.max():.1f}, средняя {diff[alpha > 0.02].mean():.3f}, '
          f'точек > 8: {(diff > 8).sum()}; альфа: {np.abs(ca - alpha).max():.3f}')
    os.makedirs(OUT, exist_ok=True)
    for name in ORDER:
        Image.fromarray(to_frame(lays[name]), 'RGBA').save(os.path.join(OUT, f'{name}.png'), optimize=True)
        print('слой', name)


if __name__ == '__main__':
    main()
