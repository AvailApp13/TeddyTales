#!/usr/bin/env python3
"""Эталон героя из фотографии продукта — детерминированно, без генерации.

Вход:  docs/reference/bear-source.jpg — фото мишки на студийном фоне
       (капюшон надет, уши через прорези, жёлтые шорты).
Выход: docs/reference/bear-etalon-2048.png — мишка без единого изменённого
       пикселя на ровном #808080, 2048×2048, поле ~10%;
       docs/reference/bear-mask.png — итоговая маска силуэта.

Конвейер: GrabCut по стартовому прямоугольнику → чистка нейтрального пола
и белых окон фона по насыщенности (мех S>=39 в нижней зоне, пол/тень S<=10,
подкладка капюшона S>=19 — пороги замерены по этому фото) → узкий полигон
тёплой тени в щели между ног (цветом от меха не отделяется) → эрозия нижней
полосы, чтобы растушёвка не подсасывала цвет пола → альфа-композит.

ВНИМАНИЕ: пороги и полигон подобраны под конкретный кадр bear-source.jpg.
Новое фото — пересмотреть числа (замеры: HSV-пробы по зонам).
"""

from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'docs/reference/bear-source.jpg'
OUT = ROOT / 'docs/reference/bear-etalon-2048.png'
MASK_OUT = ROOT / 'docs/reference/bear-mask.png'

CANVAS = 2048
MARGIN = 0.10
GREY = 128


def build_mask(img):
    h, w = img.shape[:2]
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    s, v = hsv[:, :, 1], hsv[:, :, 2]

    mask = np.zeros((h, w), np.uint8)
    rect = (int(w*0.18), int(h*0.24), int(w*0.66), int(h*0.62))
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(img, mask, rect, bgd, fgd, 8, cv2.GC_INIT_WITH_RECT)
    m = np.where((mask == 2) | (mask == 0), 0, 255).astype(np.uint8)

    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    m = np.where(lab == 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA]), 255, 0
                 ).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))

    # Пол, белая щель, тень-кайма под ступнями.
    band = np.zeros((h, w), bool)
    band[1440:, :] = True
    m[band & (s < 18) & (v > 150)] = 0

    # Тёплая тень между ног — только полигоном: по цвету она совпадает с мехом.
    slit = np.array([(662, 1465), (680, 1465), (686, 1520), (688, 1545),
                     (690, 1655), (670, 1655), (672, 1545), (668, 1520)])
    cv2.fillPoly(m, [slit], 0)
    m[1656:, :] = 0

    # Белые окна фона в проймах (между лапами и туловищем).
    arm_band = np.zeros((h, w), bool)
    arm_band[1100:1500, :] = True
    m[arm_band & (s < 15) & (v > 225)] = 0

    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    m = np.where(lab == 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA]), 255, 0
                 ).astype(np.uint8)

    # Нижняя полоса: край альфы внутрь меха, чтобы не тянуть цвет пола.
    er = cv2.erode(m, np.ones((7, 7), np.uint8))
    m[1590:, :] = er[1590:, :]
    return cv2.medianBlur(m, 3)


def compose(img, m):
    alpha = cv2.GaussianBlur(m, (5, 5), 1.2).astype(np.float32) / 255.0
    ys, xs = np.where(m > 0)
    h, w = img.shape[:2]
    x0, x1 = max(0, xs.min()-6), min(w, xs.max()+6)
    y0, y1 = max(0, ys.min()-6), min(h, ys.max()+6)
    bear = img[y0:y1, x0:x1].astype(np.float32)
    a = alpha[y0:y1, x0:x1][..., None]
    bh, bw = bear.shape[:2]

    scale = (CANVAS * (1 - 2*MARGIN)) / max(bh, bw)
    nw, nh = int(round(bw*scale)), int(round(bh*scale))
    bear = cv2.resize(bear, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
    a = np.clip(cv2.resize(a, (nw, nh), interpolation=cv2.INTER_LANCZOS4),
                0, 1)[..., None]

    canvas = np.full((CANVAS, CANVAS, 3), GREY, np.float32)
    ox, oy = (CANVAS - nw)//2, (CANVAS - nh)//2
    canvas[oy:oy+nh, ox:ox+nw] = bear * a + canvas[oy:oy+nh, ox:ox+nw] * (1-a)
    return np.clip(canvas, 0, 255).astype(np.uint8)


if __name__ == '__main__':
    img = cv2.imread(str(SRC))
    m = build_mask(img)
    cv2.imwrite(str(MASK_OUT), m)
    out = compose(img, m)
    cv2.imwrite(str(OUT), out)
    bg = (np.abs(out.astype(int) - GREY).sum(axis=2) == 0).mean()
    print(f'OK: {OUT.name}, ровный фон {bg*100:.1f}% кадра')
