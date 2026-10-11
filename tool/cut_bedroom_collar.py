"""Воротник прежнего мишка в спальне — под капюшон нынешнего.

    python3 tool/cut_bedroom_collar.py

Заказчик 11.10 (по снимку «Сна»): «около лапки появилась часть его кофты»,
«под подбородком эти складки ужасно выглядят… как на кухне, сделай так же
и в спальне». В кровати риг прячет своё тело (`RiveBearTrial.headOnly`):
плечо рига выглядывало у левой лапы, воротник его кофты мялся под
подбородком. Между капюшоном и краем одеяла теперь ровный край капюшона
прежнего мишка — из его же картинки (`bear_open.png`, слой прежней головы
в рамке `BedroomScene.bear`, ×2 к кадру 941 × 1672).

- Берётся только ткань (синее) между лапами: прежнее лицо, его лапы и бока
  его капюшона не попадают — их закрывает наш, а там, где наш капюшон уже
  прежнего, они торчали бы.
- Полоса доращена вверх до линии на 10 px кадра выше низа нашего капюшона
  (ходит при дыхании и кивке) и вниз до края одеяла с запасом — ближайшим
  цветом ткани, мягко.
- Цвет: прежняя ткань под ночником темнее и лиловее нашей (замер:
  101 / 125 / 169 против нашей кофты под `BedroomScene.night`
  134 / 169 / 190); множитель по каналам к нашей ткани в тени подбородка.

Пишет `assets/rooms/bedroom/bear_collar.png` — того же размера, что
`bear_open.png`, кладётся в ту же рамку.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, 'assets/rooms/bedroom')
W, H = 941, 1672
# рамка BedroomScene.bear в кадре
BX, BY = 0.381509 * W, 0.412679 * H
UP = 2  # картинка вдвое крупнее кадра

# Низ нашего капюшона в спальне (кадр, мишка поднят на 20 px, самый
# высокий за вдох): x → y. Замер 11.10 по кадрам рига.
HOOD = [(390, 885), (407, 886), (424, 896), (440, 901), (457, 904), (474, 905),
        (490, 904), (507, 903), (523, 899), (540, 890), (557, 889)]
# Край одеяла (верх непрозрачного `blanket_front.png`), кадр: x → y.
BLANKET = [(360, 915), (400, 927), (440, 917), (474, 913), (510, 911), (550, 931), (590, 924)]
LEFT, RIGHT = 402, 552      # между лапами (под ними края полосы)
ABOVE = 10                  # запас над низом капюшона, px кадра
BELOW = 10                  # запас под краем одеяла, px кадра
GAIN = np.array([1.24, 1.26, 1.04])   # к нашей ткани в тени подбородка


def line(points, xs):
    px, py = zip(*points)
    return np.interp(xs, px, py)


def main():
    old = np.asarray(Image.open(os.path.join(DIR, 'bear_open.png')).convert('RGBA')).astype(np.float64)
    h, w = old.shape[:2]
    rgb, a = old[..., :3], old[..., 3] / 255
    r, b = rgb[..., 0], rgb[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]
    fx = BX + xx / UP                       # координаты кадра
    fy = BY + yy / UP
    top = line(HOOD, fx[0]) - ABOVE
    bottom = line(BLANKET, fx[0]) + BELOW
    zone = (fx >= LEFT) & (fx <= RIGHT) & (fy >= top[None, :]) & (fy <= bottom[None, :])
    cloth = zone & (a > 0.95) & (b > r + 30)
    # ткань полосы без краёв: строчка, кромка и мех лап по краям не берутся
    core = ndimage.binary_erosion(cloth, iterations=3 * UP)
    base = np.median(rgb[core], axis=0)
    # Вне полосы — ровная ткань: цвет полосы, растянутый наружу
    # (нормированная свёртка по её середине), и мелкое зерно вязки — без
    # плитки, чтобы не повторялась строчка.
    weight = core.astype(np.float64)
    spread = ndimage.gaussian_filter(weight, 10)
    smear = np.dstack([ndimage.gaussian_filter(rgb[..., i] * weight, 10) for i in range(3)])
    smear = np.where(spread[..., None] > 1e-3, smear / np.maximum(spread, 1e-4)[..., None], base)
    grain = ndimage.gaussian_filter(np.random.default_rng(11).normal(0, 4.0, (h, w)), 0.7)
    plain = smear + grain[..., None]
    # Ровно всё: строчка и уголок посередине прежней полосы (там сходились
    # половинки его капюшона) под нашим капюшоном читались как залом.
    out_rgb = plain * GAIN
    # мягкие края зоны: сверху и с боков — под капюшоном и лапами
    soft = ndimage.gaussian_filter(zone.astype(np.float64), 1.5)
    out = np.dstack([np.clip(out_rgb, 0, 255), soft * 255])
    Image.fromarray(out.astype(np.uint8), 'RGBA').save(os.path.join(DIR, 'bear_collar.png'), optimize=True)
    print('bear_collar.png', (w, h), 'ткани', int(cloth.sum()), 'зона', int(zone.sum()))


if __name__ == '__main__':
    main()
