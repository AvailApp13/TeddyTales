"""Мягкие веки из меха (заказчик 26.09: «живые эмоции, веки»).

Бусины глаз лежат поверх лица и глазниц жёсткими картинками — сжать их
можно, прикрыть мехом нельзя. Здесь вокруг каждой бусины вырезается кольцо
меха (лицо + глазница, ровно как они видны в покое) и кладётся поверх
бусин. У кольца та же сетка и те же веса, что у лица, поэтому в покое оно
невидимо, а когда кости век сдвигают мех, край кольца наползает на бусину:
нижнее веко — улыбка, верхнее — грусть и сон.

Глазницы при этом впекаются в текстуру лица (их картинки скрыты): иначе
жёсткая глазница под бусиной не двигалась бы вместе с мехом век, и при
закрытых глазах проступал бы бледный кружок.
"""

import copy
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

from xf import M, f

BEAD_R = 19.3        # бусина с ворсинками кончается здесь (px мира)
EDGE = 1.4           # мягкость края века
RING = (38, 40)      # кольцо до эллипса (полуоси по x и y)


def _bilinear(img, x, y):
    h, w = img.shape[:2]
    x0 = np.clip(np.floor(x).astype(int), 0, w - 2)
    y0 = np.clip(np.floor(y).astype(int), 0, h - 2)
    fx = np.clip(x - x0, 0, 1)[..., None]
    fy = np.clip(y - y0, 0, 1)[..., None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    out = a * (1 - fy) + b * fy
    inside = (x >= 0) & (x <= w - 1) & (y >= 0) & (y <= h - 1)
    return out * inside[..., None]


def build(project, rive_root, ab, W, byname, face_skin, eyes, next_id):
    """eyes: [(картинка глазницы, картинка бусины)]. Добавляет картинку
    `lid_patch_img` перед `face_fx` и возвращает её."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    face_img = byname['face_img']
    face_asset = assets[face_img.attrib['assetId']]
    face = np.asarray(Image.open(os.path.join(project, face_asset.attrib['file'])).convert('RGBA'),
                      dtype=np.float64) / 255
    H, Wd = face.shape[:2]
    out = np.zeros_like(face)
    baked = face.copy()
    to_world = face_skin
    to_face = face_skin.inv()
    for sock, bead in eyes:
        sw = W[sock]
        cx, cy = W[bead].apply(0, 0)
        # область вокруг глаза в пикселях текстуры лица
        (ax, ay) = to_face.apply(cx - RING[0] - 4, cy - RING[1] - 4)
        (bx, by) = to_face.apply(cx + RING[0] + 4, cy + RING[1] + 4)
        x0, x1 = int(np.floor(ax + Wd / 2)), int(np.ceil(bx + Wd / 2))
        y0, y1 = int(np.floor(ay + H / 2)), int(np.ceil(by + H / 2))
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float64)
        lx, ly = xx + 0.5 - Wd / 2, yy + 0.5 - H / 2
        a = to_world.v
        wx = a[0] * lx + a[2] * ly + a[4]
        wy = a[1] * lx + a[3] * ly + a[5]
        # глазница поверх лица — как в покое
        s_asset = assets[sock.attrib['assetId']]
        simg = np.asarray(Image.open(os.path.join(project, s_asset.attrib['file'])).convert('RGBA'),
                          dtype=np.float64) / 255
        sh, sww = simg.shape[:2]
        si = sw.inv().v
        sx = si[0] * wx + si[2] * wy + si[4] + sww / 2 - 0.5
        sy = si[1] * wx + si[3] * wy + si[5] + sh / 2 - 0.5
        s = _bilinear(simg, sx, sy)
        base = face[y0:y1, x0:x1]
        sa = s[..., 3:4]
        rgb = s[..., :3] * sa + base[..., :3] * (1 - sa)
        # глазница впекается в лицо: под бусиной мех гнётся вместе с веками
        baked[y0:y1, x0:x1, :3] = rgb
        sock.set('opacity', '0')
        # кольцо: снаружи бусины, внутри эллипса
        d = np.hypot(wx - cx, wy - cy)
        inner = np.clip((d - BEAD_R) / EDGE, 0, 1)
        e = np.hypot((wx - cx) / RING[0], (wy - cy) / RING[1])
        outer = np.clip((1 - e) * 40, 0, 1)
        alpha = inner * outer * base[..., 3]
        patch = out[y0:y1, x0:x1]
        keep = alpha > patch[..., 3]
        patch[keep, :3] = rgb[keep]
        patch[keep, 3] = alpha[keep]
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(project, 'bear_lids.png'))
    Image.fromarray((baked * 255 + 0.5).astype(np.uint8), 'RGBA').save(
        os.path.join(project, face_asset.attrib['file']))

    asset_id = next_id()
    ET.SubElement(rive_root, 'ImageAsset', {'file': 'bear_lids.png', 'height': str(H), 'width': str(Wd),
                                             'assetId': '9900001', 'name': 'bear_lids', 'id': asset_id})
    patch = copy.deepcopy(face_img)
    for el in patch.iter():
        if 'id' in el.attrib:
            el.set('id', next_id())
    patch.set('assetId', asset_id)
    patch.set('name', 'lid_patch_img')
    fx = byname['face_fx']
    holder = next(p for p in ab.iter() if fx in list(p))
    holder.insert(list(holder).index(fx), patch)
    return patch
