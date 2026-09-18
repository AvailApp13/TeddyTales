#!/usr/bin/env python3
"""Чистая морда героя: убрать глаза и стежок рта донорским мехом.

Вход: docs/reference/bear-etalon-2048.png. Выход: bear-etalon-clean-face.png.
Зоны замерены детектором тёмных пятен: глаза (918,860) и (1113,860) r~45,
стежок (1018,1022). Донор — мех лба (+150px по Y) и щеки (-120px по X),
с приведением к среднему цвету кольца вокруг цели и растушёвкой.
Генерация не используется: это пиксели того же фото.
"""
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'docs/reference/bear-etalon-2048.png'
OUT = ROOT / 'docs/reference/bear-etalon-clean-face.png'


def patch_fill(img, cx, cy, rx, ry, dx, dy, feather=9):
    h, w = img.shape[:2]
    mask = np.zeros((h, w), np.float32)
    cv2.ellipse(mask, (cx, cy), (rx, ry), 0, 0, 360, 1.0, -1)
    mask_soft = cv2.GaussianBlur(mask, (0, 0), feather)
    donor = np.roll(np.roll(img, dy, axis=0), dx, axis=1)

    ring = np.zeros((h, w), np.uint8)
    cv2.ellipse(ring, (cx, cy), (rx+30, ry+30), 0, 0, 360, 255, -1)
    cv2.ellipse(ring, (cx, cy), (rx+6, ry+6), 0, 0, 360, 0, -1)
    tgt = img[ring > 0].reshape(-1, 3).mean(axis=0)
    dp = np.zeros((h, w), np.uint8)
    cv2.ellipse(dp, (cx, cy), (rx, ry), 0, 0, 360, 255, -1)
    don = donor[dp > 0].reshape(-1, 3).mean(axis=0)
    donor = np.clip(donor * (tgt / np.maximum(don, 1)), 0, 255)

    m = mask_soft[..., None]
    return img * (1 - m) + donor * m


if __name__ == '__main__':
    img = cv2.imread(str(SRC)).astype(np.float32)
    img = patch_fill(img, 918, 860, 45, 46, 0, 150)     # левый глаз
    img = patch_fill(img, 1113, 860, 45, 46, 0, 150)    # правый глаз
    img = patch_fill(img, 1018, 1022, 26, 40, -120, 0)  # стежок рта
    cv2.imwrite(str(OUT), np.clip(img, 0, 255).astype(np.uint8))
    print(f'OK: {OUT.name}')
