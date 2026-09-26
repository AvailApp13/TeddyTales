"""Рты в стиле фото (заказчик 26.09: «рот в одном положении везде»).

Открытого рта, языка, «о» в фотографии мишки нет — их нарисовал
Higgsfield (gpt_image_2_5, правка фото лица, меняется только рот;
утверждено заказчиком 26.09). Картинки: `assets_src/rive/mouths/
mouth_<имя>_tile.png` — плитка 240×280 из кадра лица 1024×1024 (кадр —
текстура лица, клетка (470, 753)–(883, 1166)), с мягкой маской.

Каждый рот — копия сетки лица с той же привязкой к костям (как веки в
`lids.py`), поверх лица, прозрачность 0; эмоция проявляет нужный рот.
"""

import copy
import os
import xml.etree.ElementTree as ET

from PIL import Image

NAMES = ('smile', 'laugh', 'yawn', 'chew', 'lick', 'o')
SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                   'assets_src', 'rive', 'mouths')
# плитка в кадре 1024: (392, 600)–(632, 880); кадр = текстура (470, 753)+413
CROP, SCALE = (470, 753), 413 / 1024
TILE_AT = (392, 600)


def build(project, rive_root, ab, byname, next_id):
    """Добавляет картинки `mouth_<имя>_img` над лицом; {имя: id}."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    face_img = byname['face_img']
    fa = assets[face_img.attrib['assetId']]
    Wd, H = int(fa.attrib['width']), int(fa.attrib['height'])
    x0 = CROP[0] + TILE_AT[0] * SCALE
    y0 = CROP[1] + TILE_AT[1] * SCALE
    holder = next(p for p in ab.iter() if face_img in list(p))
    ids = {}
    for n in NAMES:
        tile = Image.open(os.path.join(SRC, f'mouth_{n}_tile.png')).convert('RGBa')
        tw, th = round(tile.width * SCALE), round(tile.height * SCALE)
        small = tile.resize((tw, th), Image.LANCZOS).convert('RGBA')
        canvas = Image.new('RGBA', (Wd, H), (0, 0, 0, 0))
        canvas.paste(small, (round(x0), round(y0)))
        fn = f'bear_mouth_{n}.png'
        canvas.save(os.path.join(project, fn))
        asset_id = next_id()
        ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': str(H), 'width': str(Wd),
                                                 'assetId': str(9900010 + NAMES.index(n)),
                                                 'name': f'bear_mouth_{n}', 'id': asset_id})
        img = copy.deepcopy(face_img)
        for el in img.iter():
            if 'id' in el.attrib:
                el.set('id', next_id())
        img.set('assetId', asset_id)
        img.set('name', f'mouth_{n}_img')
        img.set('opacity', '0')
        holder.insert(list(holder).index(face_img), img)
        ids[n] = img.attrib['id']
    return ids
