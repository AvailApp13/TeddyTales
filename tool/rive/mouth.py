"""Рот раскрывается костью, а не сменой картинок (заказчик 27.09: «в покое
мишка живой, а в смехе рот по кадрово — нужно плавно, как в покое»).

Так делают в Live2D и Spine: полость рта (тёмный рот и язык) лежит
отдельным слоем, и параметр «рот открыт» плавно растягивает его от
щёлочки до широкого рта. Здесь полость вырезана из утверждённой картинки
смеха (`assets_src/rive/faces/laugh.webp`, 26.09) — новых картинок нет.

Слой `mouth_open_img` — копия сетки лица с той же раскладкой u/v (как
выражения в `faces.py`), все точки на одной кости `mouth_open`. Кость
стоит на линии рта в покое (`CENTER`); в покое она сжата (`CLOSED`): полость —
тонкая щёлочка шириной с ротик покоя, прозрачная. Эмоция масштабирует кость
(`Emo.mouth_open`): ширина и высота растут непрерывно, в любой момент рот
— та же картинка, только растянутая.
"""

import copy
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy import ndimage

from faces import SRC, FRAME, BOX, PAD
from mesh_refine import _read_indices, _write_indices, VERT_TAGS

CENTER = (515.5, 497.0)   # линия рта в покое, середина полости (мир)
CLOSED = (0.35, 0.03)     # масштаб кости в покое: ширина, высота


def cavity():
    """RGBA uint8 плитки (с рамкой PAD): только полость рта смеха."""
    im = np.asarray(Image.open(os.path.join(SRC, 'laugh.webp')).convert('RGB'), np.float64)
    h, w = im.shape[:2]
    lum = im.mean(2)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]
    # под носом, в зоне рта: тёмный рот или розовый язык
    reg = (yy >= 184) & (yy < 265) & (xx > 95) & (xx < 250)
    m = ((lum < 105) | ((r - g > 40) & (r - b > 30))) & reg
    m = ndimage.binary_closing(m, iterations=4)
    m = ndimage.binary_fill_holes(m)
    lab, n = ndimage.label(m)
    m = lab == (np.argmax(ndimage.sum(m, lab, range(1, n + 1))) + 1)
    m = ndimage.binary_opening(m, iterations=2)
    # ровный контур без зубцов порога, край мягкий, как у ворса
    m = ndimage.gaussian_filter(m.astype(np.float64), 2.2) > 0.5
    a = ndimage.gaussian_filter(m.astype(np.float64), 1.1)
    img = np.dstack([im, a * 255]).astype(np.uint8)
    out = np.zeros((h + 2 * PAD, w + 2 * PAD, 4), np.uint8)
    out[PAD:PAD + h, PAD:PAD + w] = img
    ys, xs = np.nonzero(m)
    return out, (xs.min(), ys.min(), xs.max(), ys.max())


def build(project, rive_root, ab, byname, next_id):
    """Кладёт `mouth_open_img` над лицом (под выражениями); возвращает id."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    face_img = byname['face_img']
    fa = assets[face_img.attrib['assetId']]
    W, H = int(fa.attrib['width']), int(fa.attrib['height'])
    tile, (bx0, by0, bx1, by1) = cavity()
    th, tw = tile.shape[:2]
    px0, py0 = FRAME[0] + BOX[0] - PAD, FRAME[1] + BOX[1] - PAD    # плитка в пикселях текстуры
    fn = 'bear_mouth_open.png'
    Image.fromarray(tile, 'RGBA').save(os.path.join(project, fn))
    asset_id = next_id()
    ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': str(th), 'width': str(tw),
                                             'assetId': '9900200', 'name': 'bear_mouth_open', 'id': asset_id})
    img = copy.deepcopy(face_img)
    for el in img.iter():
        if 'id' in el.attrib:
            el.set('id', next_id())
    img.set('assetId', asset_id)
    img.set('name', 'mouth_open_img')
    img.set('opacity', '0')
    mesh = img.find('Mesh')
    verts = [v for v in mesh if v.tag in VERT_TAGS]
    uv = []
    for v in verts:
        u, vv = float(v.get('u')) * W, float(v.get('v')) * H
        uv.append((u, vv))
        v.set('u', repr((u - px0) / tw))
        v.set('v', repr((vv - py0) / th))
    # только треугольники у полости (с запасом) и целиком внутри плитки
    cx0, cy0 = px0 + PAD + bx0 - 6, py0 + PAD + by0 - 6
    cx1, cy1 = px0 + PAD + bx1 + 6, py0 + PAD + by1 + 6
    tris = _read_indices(mesh.get('triangleIndexBytes'))
    keep = []
    for i in range(0, len(tris), 3):
        t = tris[i:i + 3]
        xs = [uv[k][0] for k in t]
        ys = [uv[k][1] for k in t]
        if min(xs) < px0 or max(xs) > px0 + tw or min(ys) < py0 or max(ys) > py0 + th:
            continue
        if max(xs) < cx0 or min(xs) > cx1 or max(ys) < cy0 or min(ys) > cy1:
            continue
        keep += t
    mesh.set('triangleIndexBytes', _write_indices(keep))
    top = byname['lid_patch_img']
    holder = next(p for p in ab.iter() if top in list(p))
    holder.insert(list(holder).index(top), img)
    return img.attrib['id']
