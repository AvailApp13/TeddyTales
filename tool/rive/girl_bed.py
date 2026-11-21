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
- `girl_paws.png` — её собственные лапки (заказчик 14.10: «лапы… как
  будто бы не её, а от пацана… она белая, а лапы… серые»; до этого были
  лапы мальчика, перекрашенные в её мех, — чужой рисунок меха и серая
  кайма). Лапка — слой руки минус то, что закрывают рукав и кофточка, без
  кромки подрисовки у среза. На фото лапки смотрят вниз и срезаны рукавом,
  и кончиком вверх над одеялом торчал «клин»; поэтому лапка повёрнута
  срезом рукава вниз, вдоль края одеяла, и срез уходит под одеяло — над
  ним только её круглый пушистый край. Обе — её правая лапка (левая
  зеркально): левая на фото срезана наискось и торчала скошенным
  холмиком. Места и ширина — как у лап мальчика (`bear_paws.png`), цвет —
  её слоёв без перекраски, свет — тот же, что у головы.
"""
import math
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


# Лапки — в картинке той же рамки, что `bear_paws.png`: левая в левой
# половине, правая — в правой (приложение сдвигает её на `pawRightShift`).
PAW_X = {'left': 62, 'right': 381}             # середины лап, px картинки
PAW_W = {'left': 120, 'right': 120}            # ширина лап — как у лап мальчика
PAW_TILT = {'left': 0.1, 'right': -0.1}        # срез вдоль края одеяла, рад
PAW_SHIFT = {'left': 0, 'right': 14 * UP}      # BedroomScene.pawRightShift — 14 px кадра
PAW_RAISE = 6 * UP                             # BedroomScene.pawRaise — 6 px кадра
PAW_HIDE = 7                                   # срез рукава под краем одеяла, px картинки
PAW_TRIM = 5                                   # кромка подрисовки у среза, px слоя


def layer(name):
    return np.asarray(Image.open(os.path.join(LAYERS, name)).convert('RGBA')).astype(np.float64)


def own_paw(side):
    """Её лапка из слоёв: рука минус то, что закрывают рукав и кофточка,
    без светло-зелёной кромки подрисовки у среза рукава. → (rgb, альфа,
    точки среза, точки лапки) в кадре слоёв.

    Обе лапки — её правая, левая — зеркально: левая на фото срезана рукавом
    наискось, и над одеялом торчала скошенным холмиком с острым краем."""
    arm = layer('arm_right.png')
    cover = np.clip(layer('sleeve_right.png')[..., 3] + layer('shirt.png')[..., 3], 0, 255) / 255
    if side == 'left':
        arm, cover = arm[:, ::-1], cover[:, ::-1]
    a = arm[..., 3] * (1 - cover) * (1 - ndimage.binary_dilation(cover > 0.25, iterations=PAW_TRIM))
    core = ndimage.binary_opening(a > 128, iterations=3)
    lab, _ = ndimage.label(core)
    core = lab == np.argmax(np.bincount(lab.ravel())[1:]) + 1
    keep = ndimage.gaussian_filter(ndimage.binary_dilation(core, iterations=3).astype(np.float64), 1.0)
    a = a * np.clip(keep, 0, 1)
    ring = ndimage.binary_dilation(core, iterations=PAW_TRIM + 3) & ~core
    ys, xs = np.nonzero(ring & (cover > 0.5))
    cut = np.stack([xs, ys], 1).astype(np.float64)
    ys, xs = np.nonzero(core)
    return arm[..., :3], a, cut, np.stack([xs, ys], 1).astype(np.float64)


def blanket_edge(x, side):
    """Край одеяла над лапой — в координатах картинки лап, с подъёмом и
    сдвигом лап в приложении."""
    room_x = BX + (x + PAW_SHIFT[side]) / UP
    return (np.interp(room_x, *zip(*BLANKET)) - BY) * UP + PAW_RAISE


def paw(side, size):
    """Её лапка срезом рукава вниз: срез ложится вдоль края одеяла и уходит
    под него на PAW_HIDE, над одеялом — круглый пушистый край лапки."""
    rgb, a, cut, pts = own_paw(side)
    c = cut.mean(0)
    e = np.linalg.svd(cut - c)[2][0]               # вдоль среза
    n = np.array([-e[1], e[0]])
    if n @ (pts.mean(0) - c) < 0:
        n = -n                                     # от среза к кончику
    t = PAW_TILT[side]
    up = np.array([math.sin(t), -math.cos(t)])
    right = np.array([math.cos(t), math.sin(t)])
    if (e[0] * n[1] - e[1] * n[0]) * (right[0] * up[1] - right[1] * up[0]) < 0:
        e = -e                                     # поворот, не зеркало
    s = PAW_W[side] / np.ptp((pts - c) @ e)

    def out(p):
        return np.outer((p - c) @ e, right) * s + np.outer((p - c) @ n, up) * s
    o, oc = out(pts), out(cut)
    sx = PAW_X[side] - (o[:, 0].min() + o[:, 0].max()) / 2
    sy = (blanket_edge(oc[:, 0] + sx, side) + PAW_HIDE - oc[:, 1]).max()
    M = (np.outer(e, right) + np.outer(n, up)) / s  # картинка → слой
    off = c - M @ np.array([sx, sy])
    coef = (M[0, 0], M[0, 1], off[0], M[1, 0], M[1, 1], off[1])
    pm = np.dstack([rgb * a[..., None] / 255, a])
    return np.stack([np.asarray(Image.fromarray(pm[..., k].astype(np.float32), 'F').transform(
        size, Image.AFFINE, coef, resample=Image.BICUBIC)) for k in range(4)], -1)


def to_rgba(pm):
    alpha = np.clip(pm[..., 3], 0, 255)
    rgb = np.where(alpha[..., None] > 0.5, pm[..., :3] / np.maximum(alpha[..., None], 1e-6) * 255, 0)
    return np.dstack([np.clip(rgb, 0, 255), alpha]).round().astype(np.uint8)


def main():
    size = Image.open(os.path.join(DIR, 'bear_paws.png')).size
    Image.fromarray(bleed(to_rgba(collar(size))), 'RGBA').save(os.path.join(DIR, 'girl_collar.png'), optimize=True)
    paws = paw('left', size) + paw('right', size)
    Image.fromarray(bleed(to_rgba(paws)), 'RGBA').save(os.path.join(DIR, 'girl_paws.png'), optimize=True)
    print('→ girl_collar.png, girl_paws.png', size)


if __name__ == '__main__':
    main()
