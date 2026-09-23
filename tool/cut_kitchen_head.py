"""Голова кухни — из цельного мишки GPT, без ушей.

У вырезанной GPT головы подбородок кончался на пиксель выше воротника, и
между ними просвечивала полоска комнаты (23.09, кадры покоя). Голова
режется рамкой из цельной картинки шага 1: подбородок лежит на воротнике,
как в исходнике. В рамках ушей пиксели берутся из головы GPT
(`tool/kitchen_gpt_originals/head.png`): там под ухом капюшон целый, а
меха уха нет — иначе под гнущимся ухом стояла бы его копия.

    python3 tool/cut_kitchen_head.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
WHOLE = ROOT / 'tool/kitchen_gpt_originals/bear_whole_941.png'
GPT_HEAD = ROOT / 'tool/kitchen_gpt_originals/head.png'
OUT = ROOT / 'assets/rooms/kitchen/head.png'

# Рамки в долях кадра 941 × 1672 — те же, что в kitchen_scene.dart.
HEAD = (0.357639, 0.382161, 0.275463, 0.185547)
EARS = [
    (0.348380, 0.444010, 0.079861, 0.065104),
    (0.567130, 0.445312, 0.079861, 0.063802),
]


def px(box, w, h):
    x, y, bw, bh = box
    return (round(x * w), round(y * h), round((x + bw) * w), round((y + bh) * h))


def main():
    whole = Image.open(WHOLE).convert('RGBA')
    w, h = whole.size
    hx0, hy0, hx1, hy1 = px(HEAD, w, h)
    head = whole.crop((hx0, hy0, hx1, hy1))
    gpt = Image.open(GPT_HEAD).convert('RGBA').resize(head.size, Image.LANCZOS)
    for ear in EARS:
        ex0, ey0, ex1, ey1 = px(ear, w, h)
        box = (max(ex0 - hx0, 0), max(ey0 - hy0, 0), min(ex1 - hx0, head.width), min(ey1 - hy0, head.height))
        head.paste(gpt.crop(box), box)
    head.save(OUT)
    print('head', head.size, 'ears replaced from GPT head')


if __name__ == '__main__':
    main()
