"""Голова кухни — из цельного мишки GPT, без ушей.

У вырезанной GPT головы подбородок кончался на пиксель выше воротника, и
между ними просвечивала полоска комнаты (23.09, кадры покоя). Голова
режется рамкой из цельной картинки шага 1: подбородок лежит на воротнике,
как в исходнике. В рамках ушей, глаз и рта пиксели берутся из
головы GPT (`tool/kitchen_gpt_originals/head.png`): там под ухом капюшон
целый без меха уха (иначе под гнущимся ухом стояла бы копия), а под
глазами и ртом — ворс без бусин и вышивки (веко стирает глаза до ворса,
выражения кладутся спрайтами сверху). Края вставок мягкие.

    python3 tool/cut_kitchen_head.py
"""
from pathlib import Path

from PIL import Image, ImageFilter

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
# Глаза и рот — с припуском 3 px кадра, чтобы вставка накрыла бусины и
# вышивку целиком.
FACE = [
    (0.430556, 0.505208, 0.129630, 0.033854),
    (0.458333, 0.536458, 0.071759, 0.023438),
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
    for zone in FACE:
        zx0, zy0, zx1, zy1 = px(zone, w, h)
        box = (zx0 - hx0 - 3, zy0 - hy0 - 3, zx1 - hx0 + 3, zy1 - hy0 + 3)
        mask = Image.new('L', head.size, 0)
        mask.paste(255, box)
        mask = mask.filter(ImageFilter.GaussianBlur(2))
        head = Image.composite(gpt, head, mask)
    head.save(OUT)
    print('head', head.size, 'ears, eyes and mouth replaced from GPT head')


if __name__ == '__main__':
    main()
