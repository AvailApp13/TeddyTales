"""Лапы на столе для кухни (заказчик 27.09): манжета рукава и лапа из
текстур самого рига, чтобы цвет и мех совпадали до пикселя.

    python3 tool/cut_table_paws.py <папка RML-проекта мишки>

Папку даёт `rive create bear --from-rev=assets_src/rive/bear_boy_v2.rev`.
Лапа и рукав лежат в одной текстуре 1333 × 2000 (мир = 0,6298 · текстура +
(85,93; −149,30)). Складываем лапу и рукав над ней как в риге, берём низ
руки ниже линии поперёк руки (у манжеты), верх растушёвываем — там картинка
уходит в рукав самого рига. Печатает, где лежит картинка в мире покоя —
эти числа стоят в `KitchenBear` (`TablePaw`).
"""
import os
import sys

import numpy as np
from PIL import Image

K, TX, TY = 0.6298168, 85.93, -149.30
# ось руки в мире: плечо → кисть (CHAIN в rebuild_rig.py)
SHOULDER = {'left': (368, 556), 'right': (656, 556)}
HAND = {'left': (258, 703), 'right': (766, 703)}
CUT = 88        # срез поперёк руки: столько px мира от плеча вдоль оси
FEATHER = 22    # растушёвка среза, px мира
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'assets/rooms/kitchen')


def main(project):
    for side in ('left', 'right'):
        paw = Image.open(f'{project}/bear_paw_{side}.png').convert('RGBA')
        sleeve = Image.open(f'{project}/bear_sleeve_{side}.png').convert('RGBA')
        img = Image.new('RGBA', paw.size)
        img.alpha_composite(paw)
        img.alpha_composite(sleeve)
        a = np.asarray(img).astype(np.float64)
        H, W = a.shape[:2]
        # координата вдоль оси руки для каждого пикселя
        sx, sy = SHOULDER[side]
        hx, hy = HAND[side]
        ax, ay = hx - sx, hy - sy
        n = (ax * ax + ay * ay) ** 0.5
        ax, ay = ax / n, ay / n
        yy, xx = np.mgrid[0:H, 0:W]
        wx, wy = K * xx + TX, K * yy + TY
        along = (wx - sx) * ax + (wy - sy) * ay
        keep = np.clip((along - CUT) / FEATHER, 0, 1)
        keep = keep * keep * (3 - 2 * keep)
        a[..., 3] *= keep
        out = Image.fromarray(a.clip(0, 255).astype(np.uint8))
        x0, y0, x1, y1 = out.getbbox()
        out = out.crop((x0, y0, x1, y1))
        out.save(f'{OUT}/table_paw_{side}.png', optimize=True)
        print(side, 'мир покоя: left %.1f top %.1f width %.1f height %.1f' % (
            K * x0 + TX, K * y0 + TY, K * (x1 - x0), K * (y1 - y0)), 'px', out.size)


if __name__ == '__main__':
    main(sys.argv[1])
