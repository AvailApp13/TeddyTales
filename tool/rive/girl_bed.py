"""Девочка в кровати — ворот кофточки под подбородком и лапы у края одеяла.

    python3 tool/rive/girl_bed.py      # → assets/rooms/bedroom/girl_*.png

Заказчик 14.10: «делай лапки девочки… у одеяла». Как у мальчика
(`tool/cut_bedroom_collar.py`, «Сон» 11.10): тело рига в кровати
спрятано (`RiveBearTrial.headOnly`), под подбородком — ровный ворот, у
подбородка — лапы, держат край одеяла. Обе картинки — в рамке
`BedroomScene.bear` (×2 к кадру спальни 941 × 1672), того же размера, что
`bear_paws.png` и `bear_collar.png`; цвет — как у слоёв рига, свет
спальни даёт приложение (`BedroomScene.night`).

- `girl_collar.png` — её кофточка (слой `shirt`) под подбородком: только
  ворот между лапами, к лапам мягко сходит на нет, снизу — до края одеяла
  с запасом. Рукава и плечи не берутся: над одеялом они торчали, и
  девочка казалась сидящей.
- `girl_paws.png` — круглые пушистые лапы прежнего мишки, те же, что у
  мальчика (`bear_paws.png`), в её мех: яркость меха сохраняется, цвет —
  медиана её щёк и лба. Её
  собственные лапы на фото смотрят вниз и срезаны рукавом — перевёрнутые,
  они торчали над одеялом треугольниками.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from girl_layers import bleed  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYERS = os.path.join(ROOT, 'assets_src/rive/girl/layers')
DIR = os.path.join(ROOT, 'assets/rooms/bedroom')
W, H = 941, 1672
BX, BY = 0.381509 * W, 0.412679 * H            # рамка BedroomScene.bear в кадре
UP = 2
K, T = 0.62981683, (85.92885, -149.30008)      # кадр слоёв → артборд
RL, RT, RS = 208.4, 638.0 - 20, 532.1          # коробка рига в кадре спальни
LEFT, RIGHT, SOFT = 404, 552, 12               # ворот между лапами, px кадра
# Край одеяла (верх непрозрачного `blanket_front.png`), кадр: x → y.
BLANKET = [(360, 915), (400, 927), (440, 917), (474, 913), (510, 911), (550, 931), (590, 924)]
BELOW = 10                                      # запас под краем одеяла


def collar(size):
    """Кофточка девочки в рамке, по ширине — между лапами."""
    shirt = np.asarray(Image.open(os.path.join(LAYERS, 'shirt.png')).convert('RGBA')).astype(np.float64)
    pm = np.dstack([shirt[..., :3] * shirt[..., 3:4] / 255, shirt[..., 3]])
    s = K * RS / 1024
    # кадр слоёв → кадр спальни → рамка ×2
    A = np.array([[s * UP, 0, (RL + T[0] * RS / 1024 - BX) * UP],
                  [0, s * UP, (RT + T[1] * RS / 1024 - BY) * UP], [0, 0, 1]])
    inv = np.linalg.inv(A)
    ch = []
    for c in range(4):
        f = Image.fromarray(pm[..., c].astype(np.float32), 'F')
        ch.append(np.asarray(f.transform(size, Image.AFFINE, tuple(inv[:2].ravel()), resample=Image.BICUBIC)))
    out = np.stack(ch, -1)
    xs = BX + (np.arange(size[0]) + 0.5) / UP
    ys = BY + (np.arange(size[1])[:, None] + 0.5) / UP
    side = np.clip((xs - LEFT) / SOFT, 0, 1) * np.clip((RIGHT - xs) / SOFT, 0, 1)
    edge = np.interp(xs, *zip(*BLANKET)) + BELOW
    keep = side[None, :] * np.clip((edge[None, :] - ys) / 3, 0, 1)
    return out * keep[..., None]


def fur():
    """Мех девочки — медиана щёк и лба (без глаз, носа и банта)."""
    h = np.asarray(Image.open(os.path.join(LAYERS, 'head.png')).convert('RGBA')).astype(np.float64)
    ys, xs = np.mgrid[0:h.shape[0], 0:h.shape[1]]
    m = (h[..., 3] > 250) & (np.abs(xs - 680) < 230) & (ys > 640) & (ys < 1040)
    rgb = h[..., :3][m]
    y = rgb @ [0.299, 0.587, 0.114]
    keep = (y > np.percentile(y, 30)) & (y < np.percentile(y, 90))
    return np.median(rgb[keep], axis=0)


def paws():
    """Лапы прежнего мишки в её мех: яркость своя, цвет — её. Кромка у
    этих лап голубовато-серая (≈8 % темнее меха) — на белом мехе это серое
    кольцо, поэтому к краю яркость сходит к средней, а полупрозрачная кайма
    не светлее меха."""
    p = np.asarray(Image.open(os.path.join(DIR, 'bear_paws.png')).convert('RGBA')).astype(np.float64)
    a = p[..., 3]
    y = p[..., :3] @ [0.299, 0.587, 0.114]
    k = y / np.median(y[a > 200])
    rim = np.clip((8 - ndimage.distance_transform_edt(a > 200)) / 8, 0, 1)
    k = k * (1 - rim) + rim
    k = np.where(a < 230, np.minimum(k, 1.0), k)
    rgb = np.clip(fur()[None, None] * np.clip(k, 0, 1.6)[..., None], 0, 255)
    # только сами лапы: голубой уголок над левой (край прежнего капюшона)
    # срезается
    core = ndimage.binary_opening(a > 40, iterations=4)
    lab, n = ndimage.label(core)
    sizes = np.bincount(lab.ravel())[1:]
    two = np.isin(lab, np.argsort(sizes)[-2:] + 1)
    keep = ndimage.gaussian_filter(ndimage.binary_dilation(two, iterations=4).astype(np.float64), 1.5)
    return np.dstack([rgb, a * np.clip(keep, 0, 1)])


def to_rgba(pm):
    alpha = np.clip(pm[..., 3], 0, 255)
    rgb = np.where(alpha[..., None] > 0.5, pm[..., :3] / np.maximum(alpha[..., None], 1e-6) * 255, 0)
    return np.dstack([np.clip(rgb, 0, 255), alpha]).round().astype(np.uint8)


def main():
    size = Image.open(os.path.join(DIR, 'bear_paws.png')).size
    Image.fromarray(bleed(to_rgba(collar(size))), 'RGBA').save(os.path.join(DIR, 'girl_collar.png'), optimize=True)
    Image.fromarray(bleed(paws().round().astype(np.uint8)), 'RGBA').save(os.path.join(DIR, 'girl_paws.png'), optimize=True)
    print('мех', fur().round(1), '→ girl_collar.png, girl_paws.png', size)


if __name__ == '__main__':
    main()
