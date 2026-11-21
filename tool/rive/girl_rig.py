"""Девочка (JOY) в проекте рига мальчика: её слои вместо его картинок.

Вызывает `build_girl.py` после `rive create` из исходника мальчика и до
`rebuild_rig.main` (там — скелет, веса и все движения, общие с мальчиком).

Девочка стоит в кадре слоёв мальчика (совмещение по глазам, `girl_face.py`),
поэтому жёсткие картинки (лапы, стопы — полный кадр 1333 × 2000, бусины и
глазницы — по центрам глаз) встают на те же места без перестановки узлов.
У картинок с сеткой сетка строится заново по прозрачности её слоя
(`make_mesh`, библиотека Triangle): веса потом считает `rebuild_rig` по
положению точек.

Чего у девочки нет — капюшон, подкладка, запасные уши (`cup`, `droop`),
старые накладки мордочки из исходника — заменено пустыми картинками того же
размера (узлы и ключи остаются, ничего не видно).

Соответствие:
    bear_face.png        ← голова с мордочкой (лицо ходит внутри головы)
    bear_ear_*.png       ← уши
    bear_shirt.png       ← кофточка без рукавов
    bear_sleeve_*.png    ← рукава
    bear_paw_*.png       ← пушистые лапы (жёстко за кистью, как лапы мальчика)
    bear_shorts.png      ← юбка
    bear_foot_*.png      ← ноги со стопами
    bow_img (новая)      ← лента и бант, перед головой (в `outfit_head`)
"""
import copy
import os
import xml.etree.ElementTree as ET

import cv2
import numpy as np
import triangle
from PIL import Image
from scipy import ndimage

from girl_layers import bleed
from mesh_refine import _write_indices, VERT_TAGS

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYERS = os.path.join(ROOT, 'assets_src/rive/girl/layers')

# файл проекта мальчика → слой девочки
SWAP = {
    'bear_face.png': 'head',
    'bear_ear_left.png': 'ear_left', 'bear_ear_right.png': 'ear_right',
    'bear_shirt.png': 'shirt',
    'bear_sleeve_left.png': 'sleeve_left', 'bear_sleeve_right.png': 'sleeve_right',
    'bear_paw_left.png': 'arm_left', 'bear_paw_right.png': 'arm_right',
    'bear_shorts.png': 'skirt',
    'bear_foot_left.png': 'foot_left', 'bear_foot_right.png': 'foot_right',
}
# у девочки нет — пустые картинки
EMPTY_PREFIX = ('bear_hood', 'bear_ear_left_', 'bear_ear_right_', 'face_')
KEEP = ('face_gaze_',)   # бусины и глазницы — свои (eye_pieces)
# шаг сетки по слою, пиксели текстуры
SPACING = {'face_img': 11, 'ear_left_img': 9, 'ear_right_img': 9, 'shirt_img': 13,
           'sleeve_left_img': 11, 'sleeve_right_img': 11, 'shorts_img': 13, 'bow_img': 9}

# центры бусин и глазниц мальчика в кадре слоёв (узлы gaze_*), глаза
# девочки совмещены с ними
BEAD = {'l': (589.18, 896.47), 'r': (764.08, 895.89)}
SOCKET = {'l': (588.89, 896.47), 'r': (764.36, 895.89)}
BEAD_SIZE, SOCKET_SIZE = 61, 80
BEAD_R = 27.0        # бусина с ворсинками, px кадра
SOCKET_R = 38.0
FOREHEAD = (665, 610)  # чистый мех лба в кадре слоёв: (y, x) угла образца


def _window(rgba, center, size):
    """Окно size × size с центром ровно в center (дробном), бикубик."""
    cx, cy = center
    h = size / 2.0
    out = []
    for c in range(4):
        im = Image.fromarray(rgba[..., c].astype(np.float32), 'F')
        out.append(np.asarray(im.transform((size, size), Image.AFFINE, (1, 0, cx - h, 0, 1, cy - h),
                                           resample=Image.BICUBIC)))
    return np.clip(np.stack(out, -1), 0, 255)


def eye_pieces(head_rgba):
    """{файл: RGBA uint8} — бусины (тёмная бусина с ворсинками по краю) и
    глазницы (мех вокруг глаза без бусины — её место заполнено мехом)."""
    out = {}
    for s in ('l', 'r'):
        win = _window(head_rgba, BEAD[s], BEAD_SIZE)
        rgb = win[..., :3]
        lum = rgb.mean(2)
        yy, xx = np.mgrid[0:BEAD_SIZE, 0:BEAD_SIZE] + 0.5
        d = np.hypot(xx - BEAD_SIZE / 2, yy - BEAD_SIZE / 2)
        fur = np.median(lum[(d > BEAD_R) & (d < BEAD_SIZE / 2)])
        core = np.median(lum[d < 12])
        a = np.clip((fur - 18 - lum) / max(fur - 18 - core, 1), 0, 1)
        a *= np.clip((BEAD_R + 2 - d) / 3, 0, 1)
        a = np.maximum(a, (d < BEAD_R - 6).astype(float))
        # ворсинки поверх бусины — светлые пиксели внутри круга остаются как есть
        out[f'face_gaze_bead_{s}.png'] = np.dstack([rgb, a * 255]).round().astype(np.uint8)

        win = _window(head_rgba, SOCKET[s], SOCKET_SIZE)
        rgb = win[..., :3].copy()
        yy, xx = np.mgrid[0:SOCKET_SIZE, 0:SOCKET_SIZE] + 0.5
        d = np.hypot(xx - SOCKET_SIZE / 2, yy - SOCKET_SIZE / 2)
        hole = (d < BEAD_R + 6).astype(np.uint8)    # с ворсинками бусины по краю
        filled = cv2.inpaint(np.clip(rgb, 0, 255).astype(np.uint8), hole, 9, cv2.INPAINT_TELEA).astype(np.float64)
        # мелкий ворс поверх гладкой заливки — с чистого меха лба (у кольца
        # вокруг глаза в ворсе край бусины — дал бы дуги)
        fy, fx = FOREHEAD
        patch = head_rgba[fy:fy + SOCKET_SIZE, fx:fx + SOCKET_SIZE, :3]
        grain = patch - np.stack([ndimage.gaussian_filter(patch[..., c], 3) for c in range(3)], -1)
        soft = np.clip((BEAD_R + 6 - d) / 4, 0, 1)[..., None]
        rgb = rgb * (1 - soft) + (filled + grain * 0.8) * soft
        a = np.clip((SOCKET_R - d) / 5, 0, 1)
        out[f'face_gaze_socket_{s}.png'] = np.dstack([np.clip(rgb, 0, 255), a * 255]).round().astype(np.uint8)
    return out


def make_mesh(mesh, alpha, spacing, next_id):
    """Сетка картинки заново по её прозрачности: контур (с запасом 2 px) и
    внутренние точки (Triangle, «качественные» треугольники не больше
    spacing²/2). Первыми идут точки контура (ContourMeshVertex), потом
    внутренние; у каждой — заглушка веса (веса ставит rebuild_rig)."""
    H, W = alpha.shape
    m = ndimage.binary_dilation(alpha > 2, iterations=2).astype(np.uint8)
    m = ndimage.binary_fill_holes(m).astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    cs = [c for c in cs if cv2.contourArea(c) > 30]
    verts, segs = [], []
    for c in cs:
        poly = cv2.approxPolyDP(c, 1.2, True)[:, 0, :].astype(np.float64)
        # рёбра контура не длиннее шага
        pts = []
        for a_, b_ in zip(poly, np.roll(poly, -1, 0)):
            n = max(1, int(np.ceil(np.hypot(*(b_ - a_)) / (spacing * 0.8))))
            for k in range(n):
                pts.append(a_ + (b_ - a_) * k / n)
        base = len(verts)
        verts += pts
        segs += [(base + i, base + (i + 1) % len(pts)) for i in range(len(pts))]
    tri = triangle.triangulate({'vertices': np.array(verts), 'segments': np.array(segs)},
                               f'pq30a{spacing * spacing / 2:.1f}Q')
    V = tri['vertices']
    T = tri['triangles']
    marks = tri['vertex_markers'][:, 0]
    # треугольники вне картинки (между частями) — убрать
    cen = V[T].mean(1)
    inside = m[np.clip(cen[:, 1].astype(int), 0, H - 1), np.clip(cen[:, 0].astype(int), 0, W - 1)] > 0
    T = T[inside]
    used = np.unique(T)
    contour = [i for i in range(len(V)) if marks[i] == 1 and i in set(used)]
    interior = [i for i in used if marks[i] != 1]
    order = contour + interior
    remap = {old: new for new, old in enumerate(order)}
    for v in [v for v in mesh if v.tag in VERT_TAGS]:
        mesh.remove(v)
    at = 0
    for i in order:
        px, py = V[i]
        tag = 'ContourMeshVertex' if marks[i] == 1 else 'MeshVertex'
        el = ET.Element(tag, {'u': f'{px / W:.8g}', 'v': f'{py / H:.8g}', 'x': f'{px - W / 2:.8g}',
                              'y': f'{py - H / 2:.8g}', 'name': 'Component', 'id': next_id()})
        ET.SubElement(el, 'Weight', {'indices': '1', 'name': 'Component', 'id': next_id(), 'values': '255'})
        mesh.insert(at, el)
        at += 1
    mesh.set('triangleIndexBytes', _write_indices([remap[i] for t in T for i in t]))
    return len(order), len(T)


# Закрытые глаза поверх бусин (узел `fx_eyes_closed`: пик каждого
# моргания покоя, сон): центры картинок мальчика в кадре слоёв и масштаб
# картинка → кадр. Картинки — из выражения «глаза закрыты» Higgsfield.
CLOSED = {'l': (588.05, 881.92), 'r': (764.94, 881.92)}
CLOSED_K = 0.6307 / 0.62981683


def closed_eyes(project, head_rgba, boy_alpha):
    """{файл: RGBA} — мех с закрытым глазом девочки. Плитка «глаза закрыты»
    кладётся на её голову по зонам глаз (`faces._tiles`: мягкий край, цвет
    подогнан), окно 200 × 206 — с прозрачностью картинки мальчика."""
    import faces
    x0, y0 = faces.FRAME[0] + faces.BOX[0], faces.FRAME[1] + faces.BOX[1]
    w, h = faces.BOX[2] - faces.BOX[0], faces.BOX[3] - faces.BOX[1]
    tile = faces._tiles(head_rgba[y0:y0 + h, x0:x0 + w] / 255.0)['blink'].astype(np.float64)
    comp = head_rgba.astype(np.float64).copy()
    P = faces.PAD
    sub = comp[y0 - P:y0 + h + P, x0 - P:x0 + w + P]
    ta = tile[..., 3:4] / 255.0
    sub[..., :3] = tile[..., :3] * ta + sub[..., :3] * (1 - ta)
    out = {}
    for s in ('l', 'r'):
        a = boy_alpha[s]
        H, W = a.shape
        cx, cy = CLOSED[s]
        k = CLOSED_K
        rgb = []
        for c in range(3):
            im = Image.fromarray(comp[..., c].astype(np.float32), 'F')
            rgb.append(np.asarray(im.transform((W, H), Image.AFFINE,
                                               (k, 0, cx - k * W / 2, 0, k, cy - k * H / 2),
                                               resample=Image.BICUBIC)))
        out[f'face_eyes_closed_eye_{s}.png'] = np.dstack(rgb + [a]).clip(0, 255).round().astype(np.uint8)
    return out


def swap(project, rive_root, ab, next_id):
    """Картинки девочки вместо картинок мальчика, сетки заново, бант."""
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    by_file = {a.attrib['file']: a for a in assets.values()}
    layers = {n: np.asarray(Image.open(os.path.join(LAYERS, f'{n}.png')).convert('RGBA'))
              for n in set(SWAP.values()) | {'bow'}}
    boy_alpha = {s: np.asarray(Image.open(os.path.join(project, f'face_eyes_closed_eye_{s}.png'))
                               .convert('RGBA'))[..., 3].astype(np.float64) for s in ('l', 'r')}
    for fn, asset in by_file.items():
        path = os.path.join(project, fn)
        if fn in SWAP:
            Image.fromarray(layers[SWAP[fn]], 'RGBA').save(path)
        elif fn.startswith(KEEP):
            continue
        elif fn.startswith(EMPTY_PREFIX) or fn.startswith('Снимок'):
            w, h = int(asset.attrib['width']), int(asset.attrib['height'])
            Image.new('RGBA', (w, h), (0, 0, 0, 0)).save(path)
    for fn, rgba in eye_pieces(layers['head'].astype(np.float64)).items():
        Image.fromarray(bleed(rgba), 'RGBA').save(os.path.join(project, fn))
        a = by_file[fn]
        a.set('width', str(rgba.shape[1]))
        a.set('height', str(rgba.shape[0]))
    for fn, rgba in closed_eyes(project, layers['head'], boy_alpha).items():
        Image.fromarray(bleed(rgba), 'RGBA').save(os.path.join(project, fn))

    # бант: копия картинки капюшона (та же сетка-«рамка» и кожа), в той же
    # папке `outfit_head` — перед мордочкой
    hood = next(e for e in ab.iter('Image') if e.attrib.get('name') == 'hood_img')
    holder = next(p for p in ab.iter() if hood in list(p))
    bow_asset = ET.SubElement(rive_root, 'ImageAsset', {
        'file': 'girl_bow.png', 'height': '2000', 'width': '1333', 'assetId': '9900300',
        'name': 'girl_bow', 'id': next_id()})
    Image.fromarray(layers['bow'], 'RGBA').save(os.path.join(project, 'girl_bow.png'))
    bow = copy.deepcopy(hood)
    for el in bow.iter():
        if 'id' in el.attrib:
            el.set('id', next_id())
    bow.set('assetId', bow_asset.attrib['id'])
    bow.set('name', 'bow_img')
    holder.insert(list(holder).index(hood), bow)

    # сетки заново — по слоям девочки
    alpha_of = {'face_img': 'head', 'ear_left_img': 'ear_left', 'ear_right_img': 'ear_right',
                'shirt_img': 'shirt', 'sleeve_left_img': 'sleeve_left', 'sleeve_right_img': 'sleeve_right',
                'shorts_img': 'skirt', 'bow_img': 'bow'}
    stats = {}
    for img in ab.iter('Image'):
        name = img.attrib.get('name')
        if name in alpha_of:
            mesh = img.find('Mesh')
            stats[name] = make_mesh(mesh, layers[alpha_of[name]][..., 3], SPACING[name], next_id)
    return stats
