"""Руки — отдельные детали с круглым плечом (заказчик 27.09: «в плече
косточка, а не лапка с шерстью… сделай так, как делают профессионалы»).

Как в Harmony, Spine, Live2D и Character Animator (разбор 27.09,
claude.ai/artifact/VePXyHSiuAJf15uF6wRw8Y):

* рука — одна картинка: рукав с закрытой круглой головкой и лапа
  (Higgsfield, «да» заказчика 27.09; кадры 2dfe0da4 и d9dd56a1 — правка
  рук 8765366b и d8f1de3e);
* ось вращения — в центре круга головки рукава (`joint` в arms.json), круг
  при повороте вокруг центра остаётся кругом, плечо не сужается;
* порядок слоёв: кофта, над ней рука, над рукой капюшон — он закрывает
  шов сверху, как «накладка» в Character Animator;
* под рукой кофта дорисована: плечи и бока из «тела без рук» (кадр
  e4fca526) вклеены в нынешнюю кофту с мягким краем, остальная кофта —
  своя, в полном разрешении.

Картинки уже совмещены с мишкой и лежат в пикселях текстуры 1333×2000
(assets_src/rive/arms/, `off` — левый верхний угол). Сетки рук и кофты
строятся заново по силуэту: контур через ~8 px, внутри сетка ~14 px,
треугольники Делоне внутри силуэта. Веса ставит rebuild_rig.py.
"""

import copy
import json
import os
import xml.etree.ElementTree as ET

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import Delaunay

from mesh_refine import _write_indices, VERT_TAGS

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                   'assets_src', 'rive', 'arms')
K = 0.62981683                     # мир = K · (пиксель текстуры − центр) + сдвиг
T0 = (666.5, 1000.0)
W0 = (505.70, 480.52)


def meta():
    return json.load(open(os.path.join(SRC, 'arms.json')))


def to_tex(p):
    return ((p[0] - W0[0]) / K + T0[0], (p[1] - W0[1]) / K + T0[1])


def _load(name):
    return np.asarray(Image.open(os.path.join(SRC, name)).convert('RGBA'), np.float64) / 255


def _place(rgba, off, shape):
    out = np.zeros(shape)
    h, w = rgba.shape[:2]
    out[off[1]:off[1] + h, off[0]:off[0] + w] = rgba
    return out


def _smooth(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def shirt(old, hood_alpha, m):
    """Кофта: плечи и бока под руками — из тела без рук, остальное своё."""
    H, W = old.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    # нижний край капюшона по столбцам: выше него кофту не трогаем (там
    # лицо и сам капюшон — при повороте головы из-под них видна кофта)
    rim = np.full(W, H)
    for x in range(W):
        ys = np.nonzero(hood_alpha[:, x] > 0.5)[0]
        if len(ys):
            rim[x] = ys.max()
    new = old.copy()
    for side in ('l', 'r'):
        g = _place(_load(f'torso_{side}.webp'), m[f'torso_{side}']['off'], old.shape)
        box = g[..., 3] > 0
        both = (old[..., 3] > 0.95) & (g[..., 3] > 0.95)
        g[..., :3] += old[..., :3][both].mean(0) - g[..., :3][both].mean(0)   # тон ткани
        a = m[f'arm_{side}']
        cx, cy = to_tex(a['joint'])
        r = a['r'] / K
        # круг плеча с запасом и полоса бока от подмышки до подола
        zone = 1 - _smooth(1.5 * r, 1.9 * r, np.hypot(xx - cx, yy - cy))
        ga = g[..., 3] > 0.5
        sgn = 1 if side == 'l' else -1
        band = np.zeros((H, W))
        for y in range(int(cy), H):
            xs = np.nonzero(ga[y])[0]
            if len(xs):
                edge = xs.min() if side == 'l' else xs.max()
                band[y] = 1 - _smooth(60, 110, sgn * (xx[y] - edge))
        # бок — от подмышки до складки, подол остаётся свой
        band *= _smooth(cy - 10, cy + 30, yy) * (1 - _smooth(cy + 3.2 * r, cy + 3.8 * r, yy))
        keep = _smooth(-6, 14, yy - rim[None, :]) * ndimage.gaussian_filter(box.astype(float), 6)
        kz = ndimage.gaussian_filter(zone * keep, 4)      # у плеча — и силуэт тоже
        kb = ndimage.gaussian_filter(band * keep, 4)      # бок — только ткань
        # под краем капюшона у плеча кофта сплошная: на стыке капюшона,
        # кофты и руки не остаётся просветов
        under = ndimage.gaussian_filter(ndimage.maximum_filter(hood_alpha > 0.3, 9).astype(float), 2)
        kf = zone * under * box
        k = np.maximum(np.maximum(kz, kb * g[..., 3]), kf)
        pa = new[..., :3] * new[..., 3:]
        pb = g[..., :3] * g[..., 3:]
        al = np.maximum(new[..., 3] * (1 - kz) + g[..., 3] * kz, g[..., 3] * np.maximum(kb, kf))
        p = pa * (1 - k[..., None]) + pb * k[..., None]
        on = k > 1e-3
        new[..., 3] = np.where(on, al, new[..., 3])
        new[..., :3] = np.where(on[..., None], p / np.maximum(al[..., None], 1e-6), new[..., :3])
    new[..., :3] *= (new[..., 3:] > 0)          # вне силуэта — пусто, меньше файл
    return np.clip(new, 0, 1)


def mesh_points(alpha, step=14, edge=8, pad=3):
    """Контур (по порядку) и внутренние точки силуэта, треугольники."""
    m = (alpha > 0.02).astype(np.uint8)
    m = cv2.dilate(m, np.ones((2 * pad + 1, 2 * pad + 1), np.uint8))
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    # равномерно по длине контура
    seg = np.hypot(*(np.roll(c, -1, 0) - c).T)
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(12, int(s[-1] / edge))
    ts = np.linspace(0, s[-1], n, endpoint=False)
    cc = np.concatenate([c, c[:1]])
    contour = np.stack([np.interp(ts, s, cc[:, 0]), np.interp(ts, s, cc[:, 1])], 1)
    inner = cv2.erode(m, np.ones((9, 9), np.uint8))
    ys, xs = np.mgrid[step // 2:alpha.shape[0]:step, step // 2:alpha.shape[1]:step]
    ys, xs = ys.ravel(), xs.ravel()
    keep = inner[ys, xs] > 0
    grid = np.stack([xs[keep], ys[keep]], 1).astype(np.float64)
    # внутренние точки не ближе edge/2 к контуру
    pts = np.concatenate([contour, grid])
    tri = Delaunay(pts)
    poly = contour.astype(np.float32).reshape(-1, 1, 2)
    good = []
    for t in tri.simplices:
        p = pts[t]
        probes = [p.mean(0)] + [(p[i] + p[(i + 1) % 3]) / 2 for i in range(3)]
        if all(cv2.pointPolygonTest(poly, (float(q[0]), float(q[1])), True) >= -1.0 for q in probes):
            good.append(t)
    return contour, grid, np.array(good)


def replace_mesh(img, alpha, next_id, **kw):
    """Новая сетка картинки по силуэту alpha (текстура целиком)."""
    H, W = alpha.shape
    contour, grid, tris = mesh_points(alpha, **kw)
    mesh = img.find('Mesh')
    old = [v for v in mesh if v.tag in VERT_TAGS]
    tmpl = old[0]
    for v in old:
        mesh.remove(v)
    verts = []
    for tag, pts in (('ContourMeshVertex', contour), ('MeshVertex', grid)):
        for x, y in pts:
            x, y = float(x), float(y)
            v = ET.Element(tag, {'u': repr(x / W), 'v': repr(y / H), 'x': repr(x - W / 2),
                                 'y': repr(y - H / 2), 'name': 'Component', 'id': next_id()})
            wt = copy.deepcopy(tmpl.find('Weight'))
            wt.set('id', next_id())
            v.append(wt)
            verts.append(v)
    for i, v in enumerate(verts):
        mesh.insert(i, v)
    mesh.set('triangleIndexBytes', _write_indices([int(i) for i in tris.ravel()]))
    return len(verts)


def build(project, rive_root, ab, byname, next_id):
    """Руки и кофта: новые картинки и сетки, лапы-картинки убраны."""
    m = meta()
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    path = lambda img: os.path.join(project, assets[img.attrib['assetId']].attrib['file'])  # noqa: E731
    shirt_img = byname['shirt_img']
    old = np.asarray(Image.open(path(shirt_img)).convert('RGBA'), np.float64) / 255
    hood = np.asarray(Image.open(path(byname['hood_img'])).convert('RGBA'), np.float64)[..., 3] / 255
    new = shirt(old, hood, m)
    Image.fromarray((new * 255 + 0.5).astype(np.uint8), 'RGBA').save(path(shirt_img))
    n = {'shirt': replace_mesh(shirt_img, new[..., 3], next_id)}
    for side, layer in (('l', 'sleeve_left_img'), ('r', 'sleeve_right_img')):
        img = byname[layer]
        tex = _place(_load(f'arm_{side}.webp'), m[f'arm_{side}']['off'], old.shape)
        Image.fromarray((tex * 255 + 0.5).astype(np.uint8), 'RGBA').save(path(img))
        n[layer] = replace_mesh(img, tex[..., 3], next_id, step=12, edge=7)
    # лапа теперь часть руки: прежние картинки лап убрать
    parent = {c: p for p in ab.iter() for c in p}
    gone = set()
    for layer in ('paw_left_img', 'paw_right_img'):
        img = byname.pop(layer)
        gone.add(img.attrib['id'])
        parent[img].remove(img)
    for an in rive_root.iter('LinearAnimation'):
        for ko in list(an.findall('KeyedObject')):
            if ko.attrib['objectId'] in gone:
                an.remove(ko)
    print('arms: mesh points', n)
    return m


def chain(m, side):
    """Кости руки от центра круга плеча вдоль оси: плечо, середина,
    предплечье, кисть. [(имя, начало, конец)] в мире."""
    a = m[f'arm_{side}']
    (jx, jy), (dx, dy), L = a['joint'], a['axis'], a['length']
    cuts = [0.0, 0.40, 0.62, 0.80, 1.0]
    names = [f'arm_{side}1', f'arm_{side}2', f'arm_{side}3', f'hand_{side}']
    pts = [(jx + dx * L * c, jy + dy * L * c) for c in cuts]
    return [(nm, pts[i], pts[i + 1]) for i, nm in enumerate(names)]


def along(m, side, x, y):
    a = m[f'arm_{side}']
    (jx, jy), (dx, dy), L = a['joint'], a['axis'], a['length']
    return ((x - jx) * dx + (y - jy) * dy) / L

