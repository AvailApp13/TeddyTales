"""Тело девочки за кухонным столом — кофточка, рукава и лапы на столе.

    python3 tool/rive/girl_kitchen.py      # → assets/rooms/kitchen/girl_*.png

У мальчика за столом риг показывает только голову (`pose_body_off`), а
кофта и лапы на столе — от прежнего нарисованного мишка
(`tool/cut_kitchen_seat.py`). Прежней нарисованной девочки нет, поэтому
её тело — из её же слоёв (`girl_layers.py`), в координатах артборда 1024
(как голова рига).

Лапы на столе (заказчик 14.10: «делай лапки девочки на столе»): руки
тянутся к столу — рукава и руки сжаты по высоте к плечу (`REACH`, рука
смотрит вперёд, к зрителю, и видна короче), лапы выходят из рукавов и
лежат у дальнего края скатерти, как у мальчика. Кофточка срезана по кромке
стола, концы рукавов лежат на столе — срез на `DROP` ниже кромки, лапы —
целиком на скатерти.

Картинки (рисуются снизу вверх: кофточка → лапы → рукава):
- `girl_seat.png` — кофточка до кромки стола;
- `girl_paw_left.png`, `girl_paw_right.png` — рука с лапой; часть руки под
  рукавом срезана, как рукав;
- `girl_sleeves.png` — рукава.

Кофточка и рукава — одна рамка (`KitchenBear.girlBody`), лапы — свои;
рамки и тень лап — в долях кадра кухни 941 × 1672, печатаются для
`KitchenBear`.

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
OUT = os.path.join(ROOT, 'assets/rooms/kitchen')

K, T = 0.62981683, (85.92885, -149.30008)     # кадр слоёв → артборд
FW, FH = 941, 1672                              # кадр кухни
HX, HY, HS = 146, 611, 640                      # квадрат головы рига в кадре
TABLE = (0.6065 * 1672 - HY) / HS * 1024        # кромка стола в артборде
REACH = 0.75        # рука к столу: рукав и рука по высоте от плеча
DROP = 20           # концы рукавов лежат на столе: срез ниже кромки, артборд
FADE = 5            # мягкость среза рукава, артборд
BAND = (420, 700)   # полоса артборда для кофточки и рукавов


def layer(name):
    return np.asarray(Image.open(os.path.join(LAYERS, f'{name}.png')).convert('RGBA')).astype(np.float64)


def premul(a):
    return np.dstack([a[..., :3] * a[..., 3:4] / 255, a[..., 3]])


def shoulder(side):
    """Плечо рукава (кадр слоёв): у шеи, ниже язычка под воротом."""
    a = layer(f'sleeve_{side}')[..., 3]
    ys, xs = np.nonzero(a > 200)
    top = ys.min() + 60
    row = xs[ys == top]
    return (row.max() if side == 'left' else row.min()), top


def reach(side):
    """Кадр слоёв → артборд для руки и рукава: сжатие по высоте к плечу."""
    px, py = shoulder(side)
    A = np.array([[1, 0, 0], [0, REACH, py * (1 - REACH)], [0, 0, 1]])
    return np.array([[K, 0, T[0]], [0, K, T[1]], [0, 0, 1]]) @ A


def to_artboard(pm, A):
    """Премультипликация кадра слоёв → артборд 1024 × 1024."""
    inv = np.linalg.inv(A)
    out = []
    for c in range(4):
        f = Image.fromarray(pm[..., c].astype(np.float32), 'F')
        out.append(np.asarray(f.transform((1024, 1024), Image.AFFINE, tuple(inv[:2].ravel()),
                                          resample=Image.BICUBIC)))
    return np.stack(out, -1)


def over(dst, src):
    return src + dst * (1 - np.clip(src[..., 3:4] / 255, 0, 1))


def cut_below(pm, y, fade=1.0):
    """Срез по строке y артборда: ниже — прозрачно, край мягкий."""
    rows = np.arange(pm.shape[0])[:, None] + 0.5
    return pm * np.clip((y - rows) / fade + 0.5, 0, 1)[..., None]


def to_rgba(pm):
    alpha = np.clip(pm[..., 3], 0, 255)
    rgb = np.where(alpha[..., None] > 0.5, pm[..., :3] / np.maximum(alpha[..., None], 1e-6) * 255, 0)
    return bleed(np.dstack([np.clip(rgb, 0, 255), alpha]).round().astype(np.uint8))


def frac(x0, y0, x1, y1):
    """Прямоугольник артборда → доли кадра кухни (left, top, width, height)."""
    s = HS / 1024
    return ((HX + x0 * s) / FW, (HY + y0 * s) / FH, (x1 - x0) * s / FW, (y1 - y0) * s / FH)


def main():
    plain = np.array([[K, 0, T[0]], [0, K, T[1]], [0, 0, 1]])
    shirt = cut_below(to_artboard(premul(layer('shirt')), plain), TABLE)
    sleeves = None
    paws = {}
    for side in ('left', 'right'):
        A = reach(side)
        sl = layer(f'sleeve_{side}')
        arm = layer(f'arm_{side}')
        under = sl[..., 3:4] / 255
        # видимая лапа — целиком на скатерти; часть руки под рукавом — как рукав
        vis = premul(arm) * (1 - under)
        hid = premul(arm) * under
        paws[side] = (to_artboard(vis, A)
                      + cut_below(to_artboard(hid, A), TABLE + DROP, FADE))
        s = cut_below(to_artboard(premul(sl), A), TABLE + DROP, FADE)
        sleeves = s if sleeves is None else over(sleeves, s)

    y0, y1 = BAND
    # общая рамка кофточки и рукавов — по ширине содержимого
    cols = np.nonzero((shirt[y0:y1, :, 3] > 1).any(0) | (sleeves[y0:y1, :, 3] > 1).any(0))[0]
    x0, x1 = int(cols.min()) - 2, int(cols.max()) + 3
    Image.fromarray(to_rgba(shirt[y0:y1, x0:x1]), 'RGBA').save(
        os.path.join(OUT, 'girl_seat.png'), optimize=True)
    Image.fromarray(to_rgba(sleeves[y0:y1, x0:x1]), 'RGBA').save(
        os.path.join(OUT, 'girl_sleeves.png'), optimize=True)
    print('girlBody = Rect.fromLTWH(%.6f, %.6f, %.6f, %.6f)' % frac(x0, y0, x1, y1))

    for side, pm in paws.items():
        a = pm[..., 3]
        ys, xs = np.nonzero(a > 1)
        bx0, by0, bx1, by1 = xs.min() - 2, ys.min() - 2, xs.max() + 3, ys.max() + 3
        Image.fromarray(to_rgba(pm[by0:by1, bx0:bx1]), 'RGBA').save(
            os.path.join(OUT, f'girl_paw_{side}.png'), optimize=True)
        # тень — под той частью лапы, что лежит на скатерти
        on = a > 128
        on[:int(np.ceil(TABLE))] = False
        sy, sx = np.nonzero(on)
        w, h = bx1 - bx0, by1 - by0
        l, r = sx.min(), sx.max()
        inset = 0.12 * (r - l)
        bottom = sy.max()
        sh_h = 0.6 * (bottom - TABLE) + 6
        shadow = ((l + inset - bx0) / w, (bottom - 0.7 * sh_h - by0) / h,
                  (r - l - 2 * inset) / w, sh_h / h)
        name = 'girlPaw' + side.capitalize()
        print('%s = Rect.fromLTWH(%.6f, %.6f, %.6f, %.6f)' % ((name,) + frac(bx0, by0, bx1, by1)))
        print('%sShadow = Rect.fromLTWH(%.4f, %.4f, %.4f, %.4f)' % ((name,) + shadow))
    print(f'кромка стола — артборд y {TABLE:.1f}, рукава — до {TABLE + DROP:.1f}')


if __name__ == '__main__':
    main()
