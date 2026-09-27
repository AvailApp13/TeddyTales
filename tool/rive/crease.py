"""Складка под мышкой расправляется, когда мишка поднимает руку (заказчик
27.09: «при поднятии рук кофта должна выравниваться… складка должна
пропадать плавно, как у человека»).

Как делают в Live2D (параметр руки меняет вид сетки) и Spine (вторая
картинка проявляется ключами): поверх кофты лежит её же копия с той же
сеткой и весами, но с расправленной тканью у подмышек — `shirt_flat_l_img`
и `shirt_flat_r_img`. В покое прозрачность 0; эмоции проявляют копию
вместе с подъёмом плеча (`Emo.track`, `RAISE_FULL` в rebuild_rig.py).

Расправленная ткань — ретушь разделением частот: крупная светотень
(складка, тень в подмышке) заменяется ровным цветом соседней светлой ткани,
мелкий рисунок вязки (мельче 13 px) остаётся свой; где в глубокой тени и
у полупрозрачного края вязки не видно, она ставится штампом с чистого куска
ткани под грудью. Маска — подмышка и складка к середине груди, мягкий
край.
"""

import copy
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy import ndimage

# зоны складки в пикселях текстуры кофты: (cx, cy, rx, ry)
ZONES = {'l': [(462, 1252, 42, 42), (505, 1248, 60, 34), (428, 1240, 34, 60)],
         'r': [(915, 1292, 42, 42), (862, 1262, 62, 38), (948, 1282, 34, 60)]}
PATCH = (1330, 470, 48, 48)   # чистая ткань под грудью: (y, x, высота, ширина)


def _blur(x, s, w):
    return ndimage.gaussian_filter(x * w, s) / np.maximum(ndimage.gaussian_filter(w, s), 1e-4)


def flatten(rgba):
    """{сторона: RGBA 0..1} — расправленная ткань только в зоне складки."""
    rgb, a = rgba[..., :3], rgba[..., 3]
    H, W = a.shape
    lum = rgb.mean(2)
    med = np.median(lum[a > 0.9])
    solid = a > 0.95                                 # альфа ткани 0,988
    inner = ndimage.binary_erosion(solid, iterations=8)
    good = (inner & (lum > med - 0.06)).astype(float)   # светлая ткань без теней и края
    base = np.dstack([_blur(rgb[..., i], 35, good) for i in range(3)])
    low = np.dstack([_blur(rgb[..., i], 13, a) for i in range(3)])   # складка уходит в «светотень»
    detail = (rgb - low) * inner[..., None]
    # вязка для тени и края — штампом с чистого куска ткани (PATCH), как
    # штамп-кистью: в глубокой тени и у полупрозрачного края своей нет
    py, px, ph, pw = PATCH
    patch = rgb[py:py + ph, px:px + pw] - low[py:py + ph, px:px + pw]
    tiled = np.tile(patch, (a.shape[0] // ph + 1, a.shape[1] // pw + 1, 1))[:a.shape[0], :a.shape[1]]
    dark = np.clip((med - 0.1 - _blur(lum, 3, a)) / 0.1, 0, 1)
    use = np.maximum(dark, 1 - inner)[..., None]
    detail = detail * (1 - use) + tiled * use
    flat = np.clip(base + detail, 0, 1)
    yy, xx = np.mgrid[0:H, 0:W]
    out = {}
    for side, zones in ZONES.items():
        m = np.zeros_like(a)
        for cx, cy, rx, ry in zones:
            m = np.maximum(m, np.clip((1.25 - np.hypot((xx - cx) / rx, (yy - cy) / ry)) / 0.25, 0, 1))
        # край ткани полупрозрачный — копия закрывает его целиком, иначе
        # сквозь неё просвечивает старая тень
        al = m * np.clip(a * 3, 0, 1)
        # вне зоны — пусто (иначе картинка на весь холст раздувает файл)
        out[side] = np.dstack([flat * (al > 0)[..., None], al])
    return out


def build(project, rive_root, ab, byname, next_id):
    """Кладёт `shirt_flat_<l|r>_img` перед кофтой; {сторона: id картинки}."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    shirt_img = byname['shirt_img']
    sa = assets[shirt_img.attrib['assetId']]
    rgba = np.asarray(Image.open(os.path.join(project, sa.attrib['file'])).convert('RGBA'), np.float64) / 255
    holder = next(p for p in ab.iter() if shirt_img in list(p))
    ids = {}
    for i, (side, tex) in enumerate(flatten(rgba).items()):
        fn = f'bear_shirt_flat_{side}.png'
        Image.fromarray((tex * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(project, fn))
        asset_id = next_id()
        ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': sa.attrib['height'],
                                                 'width': sa.attrib['width'], 'assetId': str(9900060 + i),
                                                 'name': f'bear_shirt_flat_{side}', 'id': asset_id})
        img = copy.deepcopy(shirt_img)
        for el in img.iter():
            if 'id' in el.attrib:
                el.set('id', next_id())
        img.set('assetId', asset_id)
        img.set('name', f'shirt_flat_{side}_img')
        img.set('opacity', '0')
        holder.insert(list(holder).index(shirt_img), img)
        ids[side] = img.attrib['id']
    return ids
