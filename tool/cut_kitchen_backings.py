"""Подложки под уши кухни — из цельного мишки GPT.

Заказчик 23.09: «уши не прилегают к капюшону… сделать подложки, не
цельное ухо, а именно подложки». У вырезанных спрайтов край уха и край
капюшона не сходятся точка в точку, и по шву просвечивает стена. В
цельной картинке шага 1 (`tool/kitchen_gpt_originals/bear_whole_941.png`,
кадр 941 × 1672) шва нет: оттуда и берётся рамка каждого уха целиком —
мех уха вместе с прилегающим капюшоном. В сцене подложка лежит под ухом
и под головой и обрезана до половины со стороны капюшона (`_HalfClipper`),
чтобы со стороны стены не читалось второе ухо.

    python3 tool/cut_kitchen_backings.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'tool/kitchen_gpt_originals/bear_whole_941.png'
OUT = ROOT / 'assets/rooms/kitchen'

# Рамки ушей в долях кадра — те же, что в kitchen_scene.dart.
EARS = {
    'ear_left_back': (0.348380, 0.444010, 0.079861, 0.065104),
    'ear_right_back': (0.567130, 0.445312, 0.079861, 0.063802),
}


def main():
    im = Image.open(SRC).convert('RGBA')
    w, h = im.size
    for name, (x, y, bw, bh) in EARS.items():
        box = (round(x * w), round(y * h), round((x + bw) * w), round((y + bh) * h))
        im.crop(box).save(OUT / f'{name}.png')
        print(name, box)


if __name__ == '__main__':
    main()
