#!/usr/bin/env python3
"""
Скрытая часть уха под капюшоном — полный круг меха (D27).

Ухо сдвигается вдоль неподвижного края капюшона (ось в голове, D26); капюшон не двигается.
Прежнее продолжение уха под капюшоном было коротким (50 px) и темнело к линии капюшона —
при сдвиге из-под края выходили его обрез и тень: тёмные штрихи у концов стыка. Здесь всё,
что под плотным капюшоном (альфа ≥ 250), заполняется до круга уха (ear_pivots.circle,
ear_swing.py): мех берётся с видимой части уха отражением через центр круга (тот же ворс и
тон), остатки — инпейнтингом; край круга мягкий, как у самого уха. Видимая часть уха и всё,
что просвечивает сквозь кромку капюшона, не трогаются — в покое кадр прежний.

    python3 tools/scripts/ear_disc.py        # перезаписывает handoff/layers_v2/ear_{left,right}.png
"""
import json, os
import numpy as np
import cv2
from PIL import Image
from scipy import ndimage

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'handoff', 'layers_v2')
MARGIN = 3      # круг чуть больше подогнанного: край уха с ворсом
FEATHER = 6     # px под краем капюшона: переход от прежних пикселей уха к новому меху
meta = json.load(open(f'{D}/layers.json'))
HOOD = np.asarray(Image.open(f'{D}/hood.png').convert('RGBA')).astype(np.float32)
hood = HOOD[..., 3]
covered = ndimage.binary_erosion(hood >= 250, iterations=1)
# кромка капюшона над ухом: на фото на ухе под ней тень капюшона — при сдвиге уха она уезжала
# бы с ухом тёмной полосой. Под кромкой (альфа ≥ FRINGE_A) ухо получает чистый мех, а тень
# переносится в цвет капюшона так, что покой складывается в прежний кадр
FRINGE_A = 0.35 * 255
fringe = (hood >= FRINGE_A) & ~covered
H, W = hood.shape


def bleed(img):
    """Цвет в прозрачные пиксели — от ближайшего непрозрачного. Rive при отрисовке сетки
    смешивает соседние пиксели текстуры: чёрный цвет прозрачных пикселей у края давал тёмные
    штрихи («коготь» у нижнего конца стыка уха)."""
    a = (img[..., 3] >= 16) & (img[..., :3].sum(-1) >= 240)   # почти прозрачные и тёмные пиксели края — не источник
    _, (iy, ix) = ndimage.distance_transform_edt(~a, return_indices=True)
    out = img.copy(); fill = img[..., 3] < 16
    out[..., :3] = np.where(fill[..., None], img[iy, ix, :3], img[..., :3])
    return out
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
for e in ('ear_left', 'ear_right'):
    L = np.asarray(Image.open(f'{D}/{e}.png').convert('RGBA')).astype(np.float32)
    cx, cy, R = meta['ear_pivots'][e]['circle']; R += MARGIN
    r = np.hypot(xx - cx, yy - cy)
    disc = r <= R + 1
    T_in = disc & (covered | fringe)
    T_out = fringe & ~disc & (L[..., 3] > 0)     # угол уха под кромкой у концов стыка — тоже чистый мех
    T = T_in | T_out
    # источник меха: видимая, плотная часть уха вне капюшона
    src_ok = (L[..., 3] >= 250) & (hood < 20)
    sx = np.clip(np.round(2 * cx - xx), 0, W - 1).astype(int); sy = np.clip(np.round(2 * cy - yy), 0, H - 1).astype(int)
    mir = np.zeros_like(L[..., :3]); got = T & src_ok[sy, sx]
    mir[got] = L[sy[got], sx[got], :3]
    # где отражение не попало в видимое ухо — инпейнтинг от уже известного меха
    # (маска — всё неизвестное вокруг круга: иначе в мех затекает чёрный фон прозрачных пикселей)
    known = src_ok | got
    rgb = np.where(got[..., None], mir, L[..., :3]).clip(0, 255).astype(np.uint8)
    if (T & ~got).any() or T_out.any():
        mask = (~known & ndimage.binary_dilation(disc | T_out, iterations=12)).astype(np.uint8) * 255
        rgb = cv2.inpaint(rgb, mask, 9, cv2.INPAINT_TELEA)
    new = rgb.astype(np.float32)
    # переход от прежних пикселей уха к новому меху — в глубине под капюшоном
    t = np.clip(ndimage.distance_transform_edt(covered | fringe) / FEATHER, 0, 1)
    t = np.where(T, np.where(fringe, 1.0, t), 0)[..., None]
    # покой под кромкой: C = капюшон·a + ухо·(1−a) — прежний; новый цвет капюшона = (C − ухо'·(1−a)) / a
    a = (hood / 255)[..., None]
    old_c = HOOD[..., :3] * a + L[..., :3] * (L[..., 3:4] / 255) * (1 - a)
    # (там, где уха не было, — сразу новый мех: смешивать не с чем)
    had = (L[..., 3] > 0)[..., None]
    out = L.copy()
    out[..., :3] = np.where(T[..., None], np.where(had, L[..., :3] * (1 - t) + new * t, new), L[..., :3])
    edge = np.clip((R + 1 - r) / 2.5, 0, 1) * 255                      # мягкий край круга
    out[..., 3] = np.where(T_in, np.maximum(L[..., 3], edge), L[..., 3])
    out = bleed(out)
    fz = T & fringe
    new_c = (old_c - out[..., :3] * (out[..., 3:4] / 255) * (1 - a)) / np.maximum(a, 1e-3)
    HOOD[..., :3] = np.where(fz[..., None], new_c.clip(0, 255), HOOD[..., :3])
    print(e, 'кромка капюшона: тень перенесена на', int(fz.sum()), 'px')
    Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA').save(f'{D}/{e}.png', optimize=True)
    print(e, 'круг', (cx, cy, round(R, 1)), 'заполнено под капюшоном', int(T.sum()), 'из них отражением', int(got.sum()))
Image.fromarray(bleed(HOOD).clip(0, 255).astype(np.uint8), 'RGBA').save(f'{D}/hood.png', optimize=True)
