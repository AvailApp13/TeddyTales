"""Уши кухни — из цельного мишки GPT, вместе с куском капюшона.

Заказчик 23.09: «уши не прилегают к капюшону». У вырезанных GPT спрайтов
край уха и край капюшона не сходятся точка в точку, и по шву просвечивала
стена; подложка с прямым срезом при сгибе уха выглядывала «треугольником».
Поэтому ухо режется из цельной картинки шага 1
(`tool/kitchen_gpt_originals/bear_whole_941.png`, кадр 941 × 1672) рамкой
целиком: мех уха плюс прилегающий капюшон. В сцене ухо лежит под головой,
и капюшон в спрайте накрыт капюшоном головы — видна только сама подушка
уха, а шов на месте исходника, где его нет. Ни копий, ни подложек.

    python3 tool/cut_kitchen_backings.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'tool/kitchen_gpt_originals/bear_whole_941.png'
OUT = ROOT / 'assets/rooms/kitchen'

# Рамки ушей в долях кадра — те же, что в kitchen_scene.dart.
EARS = {
    'ear_left': (0.348380, 0.444010, 0.079861, 0.065104),
    'ear_right': (0.567130, 0.445312, 0.079861, 0.063802),
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
