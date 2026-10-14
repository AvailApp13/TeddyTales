"""Кадр мордочки девочки (JOY) для выражений Higgsfield — как у мальчика.

    python3 tool/rive/girl_face.py        # → assets_src/rive/girl/joy_face_1024.jpg

У мальчика выражения рисовал Higgsfield по кадру лица 1024 × 1024: кусок
текстуры лица (470, 753) + 413 в кадре слоёв 1333 × 2000, увеличенный до
1024 (`faces.py`). Девочка ставится в тот же кадр слоёв по глазам: центры
бусин на фото (774,3; 1290,0) и (933,4; 1289,4) ложатся на глаза мальчика
(588,0; 895,9) и (765,1; 895,4) — масштаб 1,113, бусины выходят того же
размера (50 px против 51). Тогда зоны глаз и рта, маски и кости лица
мальчика подходят и ей.
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIR = os.path.join(ROOT, 'assets_src/rive/girl')
SRC = os.path.join(DIR, 'joy_photo.jpg')
OUT = os.path.join(DIR, 'joy_face_1024.jpg')

GIRL_EYES = ((774.3, 1290.0), (933.4, 1289.4))   # на фото
BOY_EYES = ((588.0, 895.9), (765.1, 895.4))      # в кадре слоёв 1333 × 2000
FRAME = (470, 753, 413)                          # кадр лица в кадре слоёв


def photo_to_layers():
    """(масштаб, сдвиг x, сдвиг y): точка фото → кадр слоёв мальчика."""
    s = (BOY_EYES[1][0] - BOY_EYES[0][0]) / (GIRL_EYES[1][0] - GIRL_EYES[0][0])
    gx = (GIRL_EYES[0][0] + GIRL_EYES[1][0]) / 2
    gy = (GIRL_EYES[0][1] + GIRL_EYES[1][1]) / 2
    bx = (BOY_EYES[0][0] + BOY_EYES[1][0]) / 2
    by = (BOY_EYES[0][1] + BOY_EYES[1][1]) / 2
    return s, bx - gx * s, by - gy * s


def face_frame(size=1024):
    s, dx, dy = photo_to_layers()
    x0, y0, side = FRAME
    k = side / size / s
    photo = Image.open(SRC).convert('RGB')
    return photo.transform((size, size), Image.AFFINE,
                           (k, 0, (x0 - dx) / s, 0, k, (y0 - dy) / s),
                           resample=Image.BICUBIC)


if __name__ == '__main__':
    face_frame().save(OUT, quality=96, subsampling=0)
    s, dx, dy = photo_to_layers()
    print(f'{OUT}: масштаб {s:.4f}, сдвиг ({dx:.1f}, {dy:.1f})')
