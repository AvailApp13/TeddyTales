"""Рот раскрывается костью, а не сменой картинок (заказчик 27.09: «в покое
мишка живой, а в смехе рот по кадрово — нужно плавно, как в покое»).

Так делают в Live2D и Spine: полость рта (тёмный рот и язык) лежит
отдельным слоем, и параметр «рот открыт» плавно растягивает его от
щёлочки до полного рта. Полости вырезаны из утверждённых картинок
выражений (`assets_src/rive/faces/`, 26.09) — новых картинок нет:

- `open`  — широкий рот смеха (`laugh.webp`): смех, улыбка;
- `yawn`  — высокий рот «о» зевка (`yawn.webp`);
- `chew`  — небольшой рот жевания (`chew_open.webp`).

Каждый слой `mouth_<имя>_img` — копия сетки лица с той же раскладкой u/v
(как выражения в `faces.py`), все точки на своей кости `mouth_<имя>`. Кость
стоит на линии рта в покое (`CENTER_Y`, по x — середина полости); в покое
она сжата (`CLOSED`): полость — тонкая щёлочка шириной с ротик покоя,
прозрачная. Эмоция масштабирует кость (`Emo.mouth_open`): ширина и высота
растут непрерывно, в любой момент рот — та же картинка, только растянутая.

Ротик покоя (заказчик 27.09, раскадровка по 0,1 с: «под раскрытым ртом
виден ротик покоя — будто два рта»). Треугольничек под носом стёрт с
текстуры лица (закрашен мехом: заливка по краям + мелкий рисунок ворса
из меха ниже) и лежит отдельным слоем `face_mouth_rest_img` с весами
лица — в покое картинка та же до пикселя. Полость раскрывается ровно с
его места (`CENTER_Y` — середина треугольничка), а сам он гаснет, пока
полость ещё щёлочка (`Emo.mouth_open`): уголки уже подняты, треугольник
выпрямился — ротик покоя переходит в открытый рот, а не лежит под ним.
"""

import copy
import os
import xml.etree.ElementTree as ET
from functools import lru_cache

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

from faces import SRC, FRAME, BOX, PAD
from mesh_refine import _read_indices, _write_indices, VERT_TAGS

CENTER_Y = 507.5          # середина ротика покоя (мир)
TEX_K = 0.62981683        # пиксель текстуры лица → мир
TEX_O = (505.70184, 480.51669, 666.5, 1000.0)
# имя → (картинка, верх и низ зоны поиска в плитке, сглаживание контура,
#        масштаб кости в покое: ширина, высота)
CAVITIES = {
    'open': ('laugh', 184, 265, 2.2, (0.35, 0.03)),
    'yawn': ('yawn', 190, 292, 5.0, (0.6, 0.03)),     # «о» — круглее, без прямых углов
    'chew': ('chew_open', 184, 265, 2.2, (0.55, 1.0)),   # высоту делает челюсть (jaw_chew)
}
# Жевание (заказчик 27.09: «рот целиком ездит влево-вправо — так не
# должно быть»): верхняя губа сидит на черепе и стоит на месте, двигается
# только нижняя челюсть — вниз, вбок и чуть наклоняется. Поэтому у полости
# жевания две кости: `mouth_chew` — на верхней губе (верх полости, только
# ширина), `jaw_chew` — на нижней губе (низ полости), её ребёнок. Веса по
# высоте: верх — губа, низ — челюсть, между — линейно. В покое челюсть
# поднята к губе (полость сомкнута); опускается — рот раскрывается вниз.
# Рты-линии (заказчик 27.09: «у каждой эмоции должна быть мимика рта») —
# не полость, а тёмная линия губ с утверждённых картинок; растут из ротика
# покоя той же костью. имя → (картинка, порог темноты, масштаб в покое)
SHAPES = {
    'sad': ('sad', 115, (0.45, 0.35)),            # дуга уголками вниз
    'pout': ('upset', 115, (0.45, 0.35)),         # надутые губы обиды
    'sleepy': ('sleepy', 125, (0.5, 0.5)),        # расслабленная линия
    'content': ('chew_closed', 125, (0.45, 0.5)),  # сомкнутая довольная улыбка
}
KINDS = list(CAVITIES) + list(SHAPES)
REST = (679, 1043, 27, 16)   # ротик покоя в пикселях текстуры лица: центр, полуоси


def _shape(name):
    """Линия губ: маска по темноте, край — по тому, насколько пиксель
    темнее меха вокруг (сглаженный, как на фото)."""
    pic, thr, _ = SHAPES[name]
    im = np.asarray(Image.open(os.path.join(SRC, f'{pic}.webp')).convert('RGB'), np.float64)
    h, w = im.shape[:2]
    lum = im.mean(2)
    yy, xx = np.mgrid[0:h, 0:w]
    reg = (yy >= 188) & (yy < 260) & (xx > 95) & (xx < 250)
    loc = ndimage.gaussian_filter(lum, 6)
    m = ((lum < thr) | ((loc - lum) > 30)) & reg
    m = ndimage.binary_closing(m, iterations=2)
    lab, n = ndimage.label(m)
    sz = ndimage.sum(m, lab, range(1, n + 1))
    m = np.isin(lab, [i + 1 for i, v in enumerate(sz) if v >= 0.15 * sz.max()])
    fur = ndimage.maximum_filter(np.where(m, 0, lum), 9)       # мех рядом с линией
    a = np.clip((fur - lum) / 70, 0, 1) * ndimage.binary_dilation(m, iterations=2)
    return im, m, ndimage.gaussian_filter(a, 0.6)


@lru_cache(maxsize=None)
def cavity(name):
    """(RGBA uint8 плитки с рамкой PAD, рамка полости в плитке, x середины в мире)."""
    if name in SHAPES:
        im, m, a = _shape(name)
        h, w = im.shape[:2]
        return _pack(im, a, m, h, w)
    pic, ymin, ymax, sigma, _ = CAVITIES[name]
    im = np.asarray(Image.open(os.path.join(SRC, f'{pic}.webp')).convert('RGB'), np.float64)
    h, w = im.shape[:2]
    lum = im.mean(2)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]
    # под носом, в зоне рта: тёмный рот или розовый язык
    reg = (yy >= ymin) & (yy < ymax) & (xx > 95) & (xx < 250)
    m = ((lum < 105) | ((r - g > 40) & (r - b > 30))) & reg
    m = ndimage.binary_closing(m, iterations=4)
    m = ndimage.binary_fill_holes(m)
    lab, n = ndimage.label(m)
    m = lab == (np.argmax(ndimage.sum(m, lab, range(1, n + 1))) + 1)
    m = ndimage.binary_opening(m, iterations=2)
    # ровный контур без зубцов порога, край мягкий, как у ворса
    m = ndimage.gaussian_filter(m.astype(np.float64), sigma) > 0.5
    a = ndimage.gaussian_filter(m.astype(np.float64), 1.1)
    return _pack(im, a, m, h, w)


def _pack(im, a, m, h, w):
    img = np.dstack([im, a * 255]).astype(np.uint8)
    out = np.zeros((h + 2 * PAD, w + 2 * PAD, 4), np.uint8)
    out[PAD:PAD + h, PAD:PAD + w] = img
    ys, xs = np.nonzero(m)
    tx = FRAME[0] + BOX[0] + (xs.min() + xs.max()) / 2 + 0.5
    cx = TEX_O[0] + (tx - TEX_O[2]) * TEX_K
    return out, (xs.min(), ys.min(), xs.max(), ys.max()), round(float(cx), 1)


def _row_y(r):
    """Строка плитки (без рамки) → y мира."""
    return TEX_O[1] + (FRAME[1] + BOX[1] + r + 0.5 - TEX_O[3]) * TEX_K


def chew_rows():
    """(x середины, y верха, y низа) полости жевания в мире."""
    _, (_, y0, _, y1), cx = cavity('chew')
    return cx, round(_row_y(y0), 1), round(_row_y(y1), 1)


def center(name):
    if name == 'chew':
        cx, top, _ = chew_rows()
        return (cx, top)
    return (cavity(name)[2], CENTER_Y)


def closed(name):
    return CAVITIES[name][4] if name in CAVITIES else SHAPES[name][2]


def rest_mouth(face):
    """face: RGBA uint8 текстуры лица. (лицо без ротика покоя, маска ротика 0..1)."""
    rgb = face[..., :3].astype(np.float64)
    lum = rgb.mean(2)
    cx, cy, rx, ry = REST
    yy, xx = np.mgrid[0:face.shape[0], 0:face.shape[1]]
    ell = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1
    dark = ndimage.gaussian_filter(lum, 7) - lum      # темнее меха вокруг
    m = ndimage.binary_opening((dark > 9) & ell, iterations=1) | ((dark > 25) & ell)
    m = ndimage.binary_dilation(m, iterations=3)
    bgr = np.ascontiguousarray(face[..., 2::-1])
    base = cv2.inpaint(bgr, (m * 255).astype(np.uint8), 5, cv2.INPAINT_TELEA)[..., ::-1].astype(np.float64)
    # мелкий рисунок ворса — из меха ниже ротика, иначе заливка гладкая
    src = np.roll(rgb, -30, axis=0)
    det = src - np.dstack([ndimage.gaussian_filter(src[..., i], 3) for i in range(3)])
    f = ndimage.gaussian_filter(m.astype(np.float64), 1.5)
    out = face.copy()
    out[..., :3] = np.clip(rgb * (1 - f[..., None]) + (base + det * 0.9) * f[..., None], 0, 255).astype(np.uint8)
    return out, f


def _tile_layer(face_img, W, H, tile, box, name, asset_id, next_id):
    """Копия сетки лица с плиткой tile (в рамке PAD плитки выражений):
    u/v пересчитаны, треугольники — только у box (рамка в плитке)."""
    th, tw = tile.shape[:2]
    px0, py0 = FRAME[0] + BOX[0] - PAD, FRAME[1] + BOX[1] - PAD    # плитка в пикселях текстуры
    bx0, by0, bx1, by1 = box
    img = copy.deepcopy(face_img)
    for el in img.iter():
        if 'id' in el.attrib:
            el.set('id', next_id())
    img.set('assetId', asset_id)
    img.set('name', name)
    mesh = img.find('Mesh')
    verts = [v for v in mesh if v.tag in VERT_TAGS]
    uv = []
    for v in verts:
        u, vv = float(v.get('u')) * W, float(v.get('v')) * H
        uv.append((u, vv))
        v.set('u', repr((u - px0) / tw))
        v.set('v', repr((vv - py0) / th))
    cx0, cy0 = px0 + PAD + bx0 - 6, py0 + PAD + by0 - 6
    cx1, cy1 = px0 + PAD + bx1 + 6, py0 + PAD + by1 + 6
    tris = _read_indices(mesh.get('triangleIndexBytes'))
    keep = []
    for j in range(0, len(tris), 3):
        t = tris[j:j + 3]
        xs = [uv[k][0] for k in t]
        ys = [uv[k][1] for k in t]
        if min(xs) < px0 or max(xs) > px0 + tw or min(ys) < py0 or max(ys) > py0 + th:
            continue
        if max(xs) < cx0 or min(xs) > cx1 or max(ys) < cy0 or min(ys) > cy1:
            continue
        keep += t
    mesh.set('triangleIndexBytes', _write_indices(keep))
    return img


def build(project, rive_root, ab, byname, next_id):
    """Кладёт `mouth_<имя>_img` над лицом (под выражениями); {имя: id}."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    face_img = byname['face_img']
    fa = assets[face_img.attrib['assetId']]
    W, H = int(fa.attrib['width']), int(fa.attrib['height'])
    top = byname['lid_patch_img']
    holder = next(p for p in ab.iter() if top in list(p))
    ids = {}
    px0, py0 = FRAME[0] + BOX[0] - PAD, FRAME[1] + BOX[1] - PAD
    for i, name in enumerate(KINDS):
        tile, box, _ = cavity(name)
        th, tw = tile.shape[:2]
        fn = f'bear_mouth_{name}.png'
        Image.fromarray(tile, 'RGBA').save(os.path.join(project, fn))
        asset_id = next_id()
        ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': str(th), 'width': str(tw),
                                                 'assetId': str(9900200 + i), 'name': f'bear_mouth_{name}',
                                                 'id': asset_id})
        img = _tile_layer(face_img, W, H, tile, box, f'mouth_{name}_img', asset_id, next_id)
        img.set('opacity', '0')
        holder.insert(list(holder).index(top), img)
        ids[name] = img.attrib['id']

    # ротик покоя: стереть с лица, положить отдельным слоем над лицом
    path = os.path.join(project, fa.attrib['file'])
    face = np.asarray(Image.open(path).convert('RGBA'))
    clean, f = rest_mouth(face)
    Image.fromarray(clean, 'RGBA').save(path)
    th, tw = cavity('open')[0].shape[:2]
    tile = np.zeros((th, tw, 4), np.uint8)
    sub = face[py0:py0 + th, px0:px0 + tw]
    tile[..., :3] = sub[..., :3]
    tile[..., 3] = (f[py0:py0 + th, px0:px0 + tw] * sub[..., 3]).astype(np.uint8)
    ys, xs = np.nonzero(tile[..., 3] > 0)
    box = (xs.min() - PAD, ys.min() - PAD, xs.max() - PAD, ys.max() - PAD)
    fn = 'bear_mouth_rest.png'
    Image.fromarray(tile, 'RGBA').save(os.path.join(project, fn))
    asset_id = next_id()
    ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': str(th), 'width': str(tw),
                                             'assetId': '9900210', 'name': 'bear_mouth_rest', 'id': asset_id})
    img = _tile_layer(face_img, W, H, tile, box, 'face_mouth_rest_img', asset_id, next_id)
    fh = next(p for p in ab.iter() if face_img in list(p))
    fh.insert(list(fh).index(face_img), img)
    ids['rest'] = img.attrib['id']
    return ids
