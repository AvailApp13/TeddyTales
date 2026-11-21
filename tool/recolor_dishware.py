"""Цветная посуда для готовых блюд (Ирина 28.09: «суп в розовой чаше, печенье
— жёлтая тарелка, салат — голубая»; заказчик 01.10: «цвета посуды — супер»).

    python3 tool/recolor_dishware.py

Картинки блюд утверждены 24.09 — ракурс и еду не трогаем, перекрашиваем
только посуду. Исходники лежат в `tool/dish_originals/` (кремовый фарфор),
результат — в `assets/rooms/kitchen/dishes/`.

Как: посуда — самая большая связная область цвета кремового фарфора
(расстояние в Lab до цвета обода). Еда того же цвета (банан, хлеб) — мелкие
отдельные пятна, в эту область не попадают. Цвет меняется в Lab: оттенок
(a, b) — новый, яркость (L) — своя у каждого пикселя, сдвинутая на разницу
средних, так что тени, блики и мордочка мишки на чаше остаются.
"""

import os
import shutil

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DISHES = os.path.join(ROOT, 'assets/rooms/kitchen/dishes')
ORIG = os.path.join(ROOT, 'tool/dish_originals')

# Цвет посуды для каждого блюда. Три — от Ирины, остальные — пастель из
# той же гаммы, все разные.
COLORS = {
    'soup': '#F3C6CB',      # розовая (Ирина)
    'cookie': '#F6E3A1',    # жёлтая (Ирина)
    'salad': '#C3D9EF',     # голубая (Ирина)
    'porridge': '#C8E6D6',  # мятная
    'fruit': '#DCCFF0',     # лавандовая
    'pasta': '#D3E3C5',     # шалфейная
    'omelette': '#F7CDB0',  # абрикосовая
    'sandwich': '#E8C7D2',  # пыльная роза
}

# Насколько оттенок пикселя (a, b в Lab, OpenCV 8-bit) может отличаться от
# фарфора. Яркость не сравниваем: у посуды есть и тень, и блик.
TOL = 9
TOL_GROW = 15
# Где еда по оттенку близка к фарфору (овсянка, банан), рост — уже.
TOL_GROW_BY = {'porridge': 13, 'fruit': 10.5}
# Обод: полоса у края силуэта (доля ширины) — там только посуда, еда до
# края не доходит; тёплые блики на ободе берутся с допуском пошире.
RIM = 0.07
RIM_BY = {'porridge': 0.08}
TOL_RIM = 20
# Фарфор гладкий, каша зернистая: где оттенки близки, рост только по
# гладкому (разброс яркости в окне 5×5).
SMOOTH_BY = {'porridge': 6.5}


def lab_of(hexc):
    rgb = np.array([[[int(hexc[i:i + 2], 16) for i in (1, 3, 5)]]], np.uint8)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)[0, 0].astype(np.float32)


def recolor(name, target):
    grow = TOL_GROW_BY.get(name, TOL_GROW)
    src = os.path.join(ORIG, f'{name}.webp')
    im = np.asarray(Image.open(src).convert('RGBA'))
    rgb, alpha = im[..., :3], im[..., 3]
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)

    # цвет фарфора — медиана по нижней трети непрозрачного силуэта (там
    # всегда стенка посуды, а не еда)
    H, W = alpha.shape
    solid = alpha > 200
    ys = np.nonzero(solid.any(axis=1))[0]
    low = solid.copy()
    low[: ys.min() + int((ys.max() - ys.min()) * 0.72)] = False
    ref = np.median(lab[low], axis=0)

    dist = np.linalg.norm(lab[..., 1:] - ref[1:], axis=2)
    H0, W0 = alpha.shape
    L0 = lab[..., 0]
    m0 = cv2.blur(L0, (5, 5))
    sd0 = np.sqrt(np.maximum(cv2.blur(L0 * L0, (5, 5)) - m0 * m0, 0))
    inside = (alpha > 20).astype(np.uint8)
    rim = RIM_BY.get(name, RIM)
    edge = cv2.distanceTransform(inside, cv2.DIST_L2, 5) < rim * W0
    smooth0 = edge | (sd0 < SMOOTH_BY.get(name, 1e9))
    cand = ((dist < TOL) & (L0 > 90) & (alpha > 20) & smooth0).astype(np.uint8)
    n, lbl, stats, _ = cv2.connectedComponentsWithStats(cand, 8)
    if n <= 1:
        raise SystemExit(f'{name}: посуда не найдена')
    big = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    core = (lbl == big).astype(np.uint8)
    # второй проход: тёплые блики на ободе чуть дальше по оттенку — маска
    # разрастается от найденной посуды по соседним пикселям с допуском
    # пошире, но только по связной области и только светлым (еда темнее и
    # насыщеннее, в неё рост не заходит)
    L = lab[..., 0]
    mean = cv2.blur(L, (5, 5))
    sd = np.sqrt(np.maximum(cv2.blur(L * L, (5, 5)) - mean * mean, 0))
    smooth = sd < SMOOTH_BY.get(name, 1e9)
    loose = ((((dist < grow) & smooth) | (edge & (dist < TOL_RIM)))
             & (L > 120) & (alpha > 20)).astype(np.uint8)
    for _ in range(40):
        grown = cv2.dilate(core, np.ones((3, 3), np.uint8)) & loose
        if (grown == core).all():
            break
        core = grown
    mask = core.astype(np.float32)
    # мелкие дырки (блики, мордочка мишки на чаше) закрыть, край смягчить:
    # на стыке с едой цвет переходит плавно
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    mask = cv2.GaussianBlur(mask, (0, 0), 1.0) * np.clip((np.where(edge, TOL_RIM, grow) + 4 - dist) / 4, 0, 1)

    tgt = lab_of(target)
    out = lab.copy()
    out[..., 0] = np.clip(lab[..., 0] + (tgt[0] - ref[0]), 0, 255)
    out[..., 1] = tgt[1] + (lab[..., 1] - ref[1])
    out[..., 2] = tgt[2] + (lab[..., 2] - ref[2])
    out = np.clip(out, 0, 255)
    m = mask[..., None]
    res = lab * (1 - m) + out * m
    res_rgb = cv2.cvtColor(res.astype(np.uint8), cv2.COLOR_LAB2RGB)
    result = np.dstack([res_rgb, alpha])
    Image.fromarray(result, 'RGBA').save(
        os.path.join(DISHES, f'{name}.webp'), 'WEBP', quality=88, method=6)
    return float(mask.mean())


def main():
    os.makedirs(ORIG, exist_ok=True)
    for name, color in COLORS.items():
        orig = os.path.join(ORIG, f'{name}.webp')
        if not os.path.exists(orig):  # исходник кладём один раз
            shutil.copy(os.path.join(DISHES, f'{name}.webp'), orig)
        share = recolor(name, color)
        print(f'{name:9} {color}  посуда {share:.0%} картинки')


if __name__ == '__main__':
    main()
