"""Выражения лица целиком (заказчик 26.09: «мимика должна отрабатывать себя,
как на живом человеке» — глаза, брови, щёки и рот меняются вместе).

Так делают в Talking Tom, Live2D, Spine/Moho: у лица есть набор готовых
выражений, и они переключаются мгновенно — в момент моргания или рывка
головы, а движение между переключениями дают кости. Плавное проявление
одного рта сквозь другой давало «полоски старого рта» — его больше нет.

Картинки нарисовал Higgsfield (gpt_image_2_5, правка фото лица, 24 штуки,
утверждено заказчиком 26.09; лучшие 12 — в `assets_src/rive/faces/`).
Плитка — кусок кадра лица 1024×1024 в масштабе текстуры: кадр = текстура
(470, 753)+413, плитка — (40, 70)–(375, 370) этого кадра.

Каждое выражение — копия сетки лица с теми же весами (как веки в
`lids.py`), но со своей маленькой картинкой: u/v пересчитаны на плитку,
остаются только треугольники целиком внутри плитки (зоны отстоят от её
края на 10+ px). Лежит поверх бусин и век, прозрачность
0; эмоция включает нужное ключом «hold».

Маска — зоны глаз с бровями и рта со щеками, мягкий край, нос свой
(не прыгает). Цвет плитки подгоняется к текстуре по краю зоны.
"""

import copy
import os
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageFilter

from mesh_refine import _read_indices, _write_indices, VERT_TAGS

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                   'assets_src', 'rive', 'faces')
FRAME = (470, 753)        # кадр 1024 → текстура: FRAME + p · 413/1024
K = 413 / 1024
BOX = (40, 70, 375, 370)  # плитка в кадре 413
PAD = 4                   # прозрачная рамка вокруг плитки

# зоны в кадре 1024: (cx, cy, ax, ay)
EYES = [(297, 345, 175, 145), (729, 345, 175, 145)]
MOUTH = [(512, 735, 250, 150)]

# имя → (картинка, зоны) или (имя, [(картинка, зоны), …]) — лицо, собранное
# из частей разных картинок; порядок — сверху вниз.
# Рты-ступени (заказчик 26.09: «рот дёргается вверх-вниз, нужна
# плавность» → промежуточные рты из Higgsfield, 4 × 2 ≈ 12 кредитов,
# «да» 26.09): только зона рта, лежат над лицом смеха или жевания и
# сменяют друг друга каждые 3 кадра — рот открывается и закрывается по
# ступеням. Смех: сомкнутая улыбка → чуть → приоткрыт → широкий (сам
# `laugh`). Жуёт: сомкнут (сам `chew`) → щёлочка → приоткрыт → открыт.
# laugh2 не используется: он уже соседних — рот сужался бы и расширялся.
OVERLAYS = [
    ('blink', 'eyes_closed', EYES),          # моргание: только глаза
    ('laugh_m0', 'laugh_m0', MOUTH),
    ('laugh_m1', 'laugh_m1', MOUTH),
    ('laugh_m2', 'laugh_m2', MOUTH),
    ('chew_m1', 'chew_m1', MOUTH),
    ('chew_m2', 'chew_m2', MOUTH),
    ('chew_m3', 'chew_open', MOUTH),
    ('smile', 'smile', EYES + MOUTH),
    ('laugh', 'laugh', EYES + MOUTH),
    ('surprised', 'surprised', EYES + MOUTH),
    ('sad', 'sad', EYES + MOUTH),
    ('chew', 'chew_closed', EYES + MOUTH),
    ('lick', 'lick', EYES + MOUTH),
    ('yawn', 'yawn', EYES + MOUTH),
    ('sleepy', 'sleepy', EYES + MOUTH),
    ('asleep', 'eyes_closed', EYES + MOUTH),
    # обида (заказчик 26.09: «глаза злые — не нужно»): надулся — тяжёлые
    # веки «Сонного» и надутые губы «Обиды»; «хмф!» — глаза закрыты
    ('pout', [('sleepy', EYES), ('upset', MOUTH)]),
    ('pout_shut', [('eyes_closed', EYES), ('upset', MOUTH)]),
]


def _zones(zones, w, h):
    """Мягкая маска зон в координатах плитки."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    fx, fy = xx + BOX[0] + 0.5, yy + BOX[1] + 0.5      # кадр 413
    m = np.zeros((h, w), bool)
    for cx, cy, ax, ay in zones:
        m |= ((fx - cx * K) / (ax * K - 6)) ** 2 + ((fy - cy * K) / (ay * K - 6)) ** 2 <= 1
    a = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    return np.asarray(a, np.float64) / 255


def _tiles(tex):
    """tex: кусок текстуры лица под плиткой (RGBA 0..1). {имя: RGBA uint8}."""
    h, w = tex.shape[:2]
    rgb, alpha = tex[..., :3] * 255, tex[..., 3]
    # нос свой: не даём ему прыгать между выражениями
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    nose = (r - b > 40) & (rgb.mean(2) < 150)
    yy, xx = np.mgrid[0:h, 0:w]
    fx, fy = xx + BOX[0], yy + BOX[1]
    nose &= (fx > 409 * K) & (fx < 627 * K) & (fy > 474 * K) & (fy < 645 * K)
    nose = Image.fromarray((nose * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))
    nose = np.asarray(nose.filter(ImageFilter.GaussianBlur(2)), np.float64) / 255
    out = {}
    for name, *spec in OVERLAYS:
        parts = spec[0] if len(spec) == 1 else [(spec[0], spec[1])]
        gen_all = np.zeros((h, w, 3))
        a = np.zeros((h, w))
        for pic, zones in parts:
            gen = np.asarray(Image.open(os.path.join(SRC, f'{pic}.webp')).convert('RGB'), np.float64)
            # цвет: сдвиг к текстуре по кольцу у края каждой зоны
            for zone in zones:
                za = _zones([zone], w, h)
                band = (za > 0.05) & (za < 0.6) & (alpha > 0.9)
                if band.sum() > 50:
                    d = (rgb[band] - gen[band]).mean(0)
                    gen = gen + d * (za[..., None] > 0.01)
            za = _zones(zones, w, h)
            gen_all += gen * za[..., None]
            a += za
        gen = gen_all / np.maximum(a, 1e-6)[..., None]
        a = np.clip(a, 0, 1) * (1 - nose) * alpha
        img = np.dstack([np.clip(gen, 0, 255), a * 255]).astype(np.uint8)
        pad = np.zeros((h + 2 * PAD, w + 2 * PAD, 4), np.uint8)
        pad[PAD:PAD + h, PAD:PAD + w] = img
        out[name] = pad
    return out


def build(project, rive_root, ab, byname, next_id):
    """Добавляет картинки `face_<имя>_img` поверх бусин и век; {имя: id}."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    face_img = byname['face_img']
    fa = assets[face_img.attrib['assetId']]
    W, H = int(fa.attrib['width']), int(fa.attrib['height'])
    face = np.asarray(Image.open(os.path.join(project, fa.attrib['file'])).convert('RGBA'), np.float64) / 255
    x0, y0 = FRAME[0] + BOX[0], FRAME[1] + BOX[1]
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    tiles = _tiles(face[y0:y0 + h, x0:x0 + w])
    tw, th = w + 2 * PAD, h + 2 * PAD
    px0, py0 = x0 - PAD, y0 - PAD             # плитка с рамкой в пикселях текстуры

    top = byname['lid_patch_img']
    holder = next(p for p in ab.iter() if top in list(p))
    at = list(holder).index(top)
    ids = {}
    for n, *_ in OVERLAYS:
        fn = f'bear_face_{n}.png'
        Image.fromarray(tiles[n], 'RGBA').save(os.path.join(project, fn))
        asset_id = next_id()
        ET.SubElement(rive_root, 'ImageAsset', {'file': fn, 'height': str(th), 'width': str(tw),
                                                 'assetId': str(9900100 + len(ids)),
                                                 'name': f'bear_face_{n}', 'id': asset_id})
        img = copy.deepcopy(face_img)
        for el in img.iter():
            if 'id' in el.attrib:
                el.set('id', next_id())
        img.set('assetId', asset_id)
        img.set('name', f'face_{n}_img')
        img.set('opacity', '0')
        mesh = img.find('Mesh')
        verts = [v for v in mesh if v.tag in VERT_TAGS]
        uv = []
        for v in verts:
            u = float(v.get('u')) * W
            vv = float(v.get('v')) * H
            uv.append((u, vv))
            v.set('u', repr((u - px0) / tw))
            v.set('v', repr((vv - py0) / th))
        tris = _read_indices(mesh.get('triangleIndexBytes'))
        keep = []
        for i in range(0, len(tris), 3):
            t = tris[i:i + 3]
            xs = [uv[k][0] for k in t]
            ys = [uv[k][1] for k in t]
            # только целиком внутри плитки: вне её u/v не выбирать
            if min(xs) < px0 or max(xs) > px0 + tw or min(ys) < py0 or max(ys) > py0 + th:
                continue
            keep += t
        mesh.set('triangleIndexBytes', _write_indices(keep))
        holder.insert(at + len(ids), img)
        ids[n] = img.attrib['id']
    return ids
