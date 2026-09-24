#!/usr/bin/env python3
"""Проверка: готовые блюда на столе кухни не заходят на лапки мишки.

Заказчик 24.09: «тарелка перед мишкой закрывает лапки — так не должно быть
ни с одним блюдом». Скрипт повторяет геометрию `lib/widgets/dish_carousel.dart`
(DishArcGeometry, _Placed.at) и считает пиксели блюда поверх лапок по
маскам картинок (альфа > 60) в кадре 941 × 1672.

    python3 tool/check_dish_paws.py          # покой и весь путь прокрутки
    python3 tool/check_dish_paws.py --fit    # подобрать доли tableFit

В покое (s = 0 и ±1) должно быть 0. На лету высокая миска может задеть
лапку на долю секунды — в приложении она проходит под лапкой (блюда
нарисованы в сцене кухни под лапками), поэтому это видно как «за
лапкой», а не «поверх». Числа пути печатаются для сведения.

Поменялись картинки блюд или лапок — запустить с --fit и перенести доли
в DishArcGeometry.tableFit.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
KITCHEN = ROOT / 'assets/rooms/kitchen'
W, H = 941, 1672

# Из KitchenScene.pawLeft / pawRight.
PAW_LEFT = (0.335648, 0.579427, 0.092593, 0.037760)
PAW_RIGHT = (0.562500, 0.579427, 0.086806, 0.037760)

# Из DishArcGeometry.
CENTER_X, STEP = 0.5, 0.276
CENTER_BOTTOM, SIDE_BOTTOM = 0.6754, 0.6043
CENTER_WIDTH, SIDE_WIDTH = 0.209, 0.158
LIFT_FROM, SIDE_TILT = 0.55, 0.105
TABLE_FIT = {'porridge': 0.92, 'soup': 0.85, 'yogurt': 0.87}

DISHES = ['porridge', 'soup', 'sandwich', 'fruit', 'yogurt', 'cookie',
          'salad', 'pasta', 'omelette', 'pie']


def place(path, rect):
    x, y, w, h = rect
    im = Image.open(path).convert('RGBA').resize(
        (round(w * W), round(h * H)), Image.BILINEAR)
    a = np.array(im)[:, :, 3] > 60
    m = np.zeros((H, W), bool)
    X, Y = round(x * W), round(y * H)
    m[Y:Y + a.shape[0], X:X + a.shape[1]] = a
    return m


PAWS = place(KITCHEN / 'paw_left.png', PAW_LEFT) | \
    place(KITCHEN / 'paw_right.png', PAW_RIGHT)


def geometry(s, fit):
    k = min(abs(s), 1.0)
    side = -1 if s < 0 else 1
    across = math.sin(math.pi / 2 * k) if abs(s) <= 1 else abs(s)
    t = max(0.0, min(1.0, (k - LIFT_FROM) / (1 - LIFT_FROM)))
    lift = t * t * (3 - 2 * t)
    width = fit * (CENTER_WIDTH + (SIDE_WIDTH - CENTER_WIDTH) * min(across, 1))
    bottom = CENTER_BOTTOM + (SIDE_BOTTOM - CENTER_BOTTOM) * lift
    cx = CENTER_X + STEP * side * across
    return width, bottom, cx, -SIDE_TILT * side * lift


def mask(dish, s, fit):
    width, bottom, cx, tilt = geometry(s, fit)
    im = Image.open(KITCHEN / 'dishes' / f'{dish}.webp').convert('RGBA')
    scale = width * W / im.width
    iw, ih = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    im = im.resize((iw, ih), Image.BILINEAR)
    # Поворот вокруг середины низа, как Transform.rotate(bottomCenter).
    big = Image.new('RGBA', (iw * 2 + 4, ih * 2 + 4))
    big.paste(im, (iw // 2 + 2, ih + 2))
    big = big.rotate(-math.degrees(tilt), center=(iw + 2, 2 * ih + 2),
                     resample=Image.BILINEAR)
    a = np.array(big)[:, :, 3] > 60
    X, Y = round(cx * W - (iw + 2)), round(bottom * H - (2 * ih + 2))
    m = np.zeros((H, W), bool)
    x0, y0 = max(0, X), max(0, Y)
    x1, y1 = min(W, X + a.shape[1]), min(H, Y + a.shape[0])
    if x1 > x0 and y1 > y0:
        m[y0:y1, x0:x1] = a[y0 - Y:y1 - Y, x0 - X:x1 - X]
    return m


def overlap(dish, s, fit, paws=PAWS):
    return int((mask(dish, s, fit) & paws).sum())


def check():
    bad = 0
    for dish in DISHES:
        fit = TABLE_FIT.get(dish, 1.0)
        rest = [overlap(dish, s, fit) for s in (0, 1, -1)]
        path = max(overlap(dish, i / 20, fit) for i in range(-30, 31))
        bad += sum(rest)
        print(f'{dish:9s} покой {rest}  на лету до {path} px')
    print('OK' if bad == 0 else 'ЕСТЬ КАСАНИЯ В ПОКОЕ')
    return bad == 0


def fit_all(margin=4):
    paws = PAWS.copy()
    for _ in range(margin):
        grown = paws.copy()
        grown[1:] |= paws[:-1]
        grown[:-1] |= paws[1:]
        grown[:, 1:] |= paws[:, :-1]
        grown[:, :-1] |= paws[:, 1:]
        paws = grown
    for dish in DISHES:
        lo, hi = 0.5, 1.0
        for _ in range(12):
            mid = (lo + hi) / 2
            if all(overlap(dish, s, mid, paws) == 0 for s in (0, 1, -1)):
                lo = mid
            else:
                hi = mid
        print(f'{dish:9s} {lo:.3f}')


if __name__ == '__main__':
    if '--fit' in sys.argv:
        fit_all()
    else:
        sys.exit(0 if check() else 1)
