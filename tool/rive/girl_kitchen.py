"""Тело девочки за кухонным столом — кофточка с рукавами и лапами.

    python3 tool/rive/girl_kitchen.py      # → assets/rooms/kitchen/girl_seat.png

У мальчика за столом риг показывает только голову (`pose_body_off`), а
кофта и лапы на столе — от прежнего нарисованного мишка
(`tool/cut_kitchen_seat.py`). Прежней нарисованной девочки нет, поэтому
её тело — из её же слоёв (`girl_layers.py`): кофточка, лапы и рукава в
порядке рига, в координатах артборда 1024 (как голова рига), до кромки
стола; лапы уходят под стол. ⚠ Лапы на столе, как у мальчика, — нужен
рисунок лап сверху (ждёт согласования).

Кромка стола — `KitchenScene.tableFront.top` (0,6065 кадра 941 × 1672),
голова рига — квадрат `KitchenBear` (левый верхний угол (146, 611),
сторона 640): в артборде это y = (0,6065 · 1672 − 611) / 640 · 1024.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from girl_layers import bleed  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYERS = os.path.join(ROOT, 'assets_src/rive/girl/layers')
OUT = os.path.join(ROOT, 'assets/rooms/kitchen/girl_seat.png')

K, T = 0.62981683, (85.92885, -149.30008)     # кадр слоёв → артборд
ORDER = ('shirt', 'arm_left', 'arm_right', 'sleeve_left', 'sleeve_right')
TOP = 420                                       # верх полосы в артборде
TABLE = (0.6065 * 1672 - 611) / 640 * 1024      # кромка стола в артборде


def main():
    acc = None
    for name in ORDER:
        im = Image.open(os.path.join(LAYERS, f'{name}.png')).convert('RGBA')
        # кадр 1333 × 2000 → артборд 1024 × 1024 (премультипликация)
        a = np.asarray(im).astype(np.float64)
        pm = np.dstack([a[..., :3] * a[..., 3:4] / 255, a[..., 3]])
        ch = []
        for c in range(4):
            f = Image.fromarray(pm[..., c].astype(np.float32), 'F')
            ch.append(np.asarray(f.transform((1024, 1024), Image.AFFINE,
                                             (1 / K, 0, -T[0] / K, 0, 1 / K, -T[1] / K),
                                             resample=Image.BICUBIC)))
        lay = np.stack(ch, -1)
        if acc is None:
            acc = lay
        else:
            la = np.clip(lay[..., 3:4] / 255, 0, 1)
            acc = lay + acc * (1 - la)
    y0, y1 = TOP, int(np.ceil(TABLE))
    band = acc[y0:y1].copy()
    # кромка стола: последняя строка — доля пикселя
    frac = TABLE - (y1 - 1)
    band[-1] *= frac
    alpha = np.clip(band[..., 3], 0, 255)
    rgb = np.where(alpha[..., None] > 0.5, band[..., :3] / np.maximum(alpha[..., None], 1e-6) * 255, 0)
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).round().astype(np.uint8)
    Image.fromarray(bleed(out), 'RGBA').save(OUT, optimize=True)
    print(f'{OUT}: артборд y {y0}…{TABLE:.1f}, {out.shape[1]} × {out.shape[0]}')


if __name__ == '__main__':
    main()
