"""Ткань кофты под капюшоном (заказчик 27.09: «где есть движение головы —
разрывы» у воротника, слева, справа и посередине).

Кофта лежит под капюшоном, мордочкой и задней частью капюшона. В исходнике
её верх, спрятанный под ними, дорисован грубо: по бокам воротника —
блочные ступеньки и дыры в прозрачности, выше — размытая полоса с резким
краем. Пока голова стоит, это закрыто; стоит капюшону сдвинуться на
несколько пикселей — ступеньки и срез вылезают, и это видно как разрыв.

Так в подготовке к Live2D/Spine не делают: всё, что может открыться при
движении, прорисовывается с запасом. Здесь это делается сборкой: по
каждому столбцу текстуры находится верхний видимый край кофты (ниже
капюшона и мордочки), и всё, что выше, до `DEPTH` пикселей, заполняется
видимой тканью, отражённой вверх от этого края, — воротник как бы
продолжается под капюшон. Прозрачность в этой полосе — полная (дыры
закрыты). Край сглажен по столбцам, чтобы отражение не давало вертикальных
швов.

Все слои тела в исходнике на одной сетке текстуры (1333 × 2000, мир =
0,6298 · текстура + (85,9; −149,3)), поэтому «что закрыто» считается прямо
по прозрачностям соседних картинок в тех же пикселях.
"""

import os

import numpy as np
from PIL import Image, ImageFilter

COVER = ('hood_img', 'face_img', 'hood_back_img')   # что лежит над кофтой у ворота
DEPTH = 110          # на сколько пикселей текстуры (≈ 70 px мира) продолжать ткань вверх
GAP = 3              # отражать не от самой кромки, а чуть ниже — без двойной линии


def _alpha(project, assets, img):
    a = assets[img.attrib['assetId']]
    return np.asarray(Image.open(os.path.join(project, a.attrib['file'])).convert('RGBA'))[..., 3] / 255.0


def build(project, rive_root, byname):
    """Кофта и оба рукава: всё, что под капюшоном и мордочкой. Число
    перекрашенных пикселей."""
    return sum(_paint(project, rive_root, byname, layer)
               for layer in ('shirt_img', 'sleeve_left_img', 'sleeve_right_img'))


def _paint(project, rive_root, byname, layer):
    assets = {a.attrib['id']: a for a in rive_root.iter('ImageAsset')}
    shirt_img = byname[layer]
    fn = os.path.join(project, assets[shirt_img.attrib['assetId']].attrib['file'])
    shirt = np.asarray(Image.open(fn).convert('RGBA')).astype(np.float64)
    H, W = shirt.shape[:2]
    cover = np.zeros((H, W))
    for name in COVER:
        a = _alpha(project, assets, byname[name])
        if a.shape == cover.shape:
            cover = np.maximum(cover, a)
    sa = shirt[..., 3] / 255.0
    visible = (sa > 0.9) & (cover < 0.1)
    near = cover > 0.5          # над краем кофты — капюшон (для поиска края)
    # перекрашивать только закрытое (у капюшона альфа ≤ 253) и не ближе
    # 4 px к краю капюшона: покой до пикселя прежний, а при движении
    # дорисованная ткань не высовывается из-под края
    hidden = np.asarray(Image.fromarray((cover * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))) > 247

    # верхний видимый край кофты по столбцам (только там, где над ним капюшон)
    edge = np.full(W, -1)
    for x in range(W):
        ys = np.nonzero(visible[:, x])[0]
        if len(ys) == 0:
            continue
        y0 = ys[0]
        if y0 > 0 and near[max(0, y0 - 12):y0, x].any():
            edge[x] = y0
    cols = np.nonzero(edge >= 0)[0]
    if len(cols) == 0:
        return 0
    # сгладить край: медиана, потом среднее — без ступенек между столбцами
    e = edge.astype(np.float64)
    good = edge >= 0
    sm = e.copy()
    for x in cols:
        lo, hi = max(0, x - 12), min(W, x + 13)
        win = e[lo:hi][good[lo:hi]]
        sm[x] = np.median(win)
    sm2 = sm.copy()
    for x in cols:
        lo, hi = max(0, x - 6), min(W, x + 7)
        win = sm[lo:hi][good[lo:hi]]
        sm2[x] = win.mean()

    out = shirt.copy()
    painted = 0
    for x in cols:
        yb = int(round(sm2[x]))
        for y in range(max(0, yb - DEPTH), yb):
            if not hidden[y, x]:
                continue
            src = min(H - 1, 2 * yb - y + GAP)
            if shirt[src, x, 3] < 230:
                continue
            out[y, x, :3] = shirt[src, x, :3]
            out[y, x, 3] = 255
            painted += 1
    # мягко: по краю закрашенной зоны смешать с исходником на 2 px
    res = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')
    res.save(fn)
    return painted
