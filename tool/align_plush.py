#!/usr/bin/env python3
"""Приводит независимые генерации мишки к одной сетке.

Каждый кадр от gpt_image_2_5 — самостоятельная генерация: масштаб и
положение героя гуляют на несколько процентов. Для рига это смертельно:
подменить рот из одного кадра в голову из другого можно только если оба
сняты «с одного штатива».

Якорим по трём величинам, которые не зависят ни от выражения, ни от позы рук:

* **низ** — самый нижний непрозрачный пиксель (ступни всегда на месте);
* **верх** — макушка капюшона; ищется только в центральной полосе кадра,
  иначе поднятая лапа перебивает капюшон и масштаб уезжает;
* **центр по горизонтали** — центроид альфы в полосе шорт и ног
  (60–95 % высоты тела): туда не дотягиваются ни руки, ни поворот головы.

Дальше подобие: масштаб по высоте тела, сдвиг по низу и центру. Поворота
нет — камера у всех кадров одна, вращать нечего.

Работает на голом Pillow, чтобы тот же файл запускался и локально, и в
песочнице Higgsfield, где кроме PIL ничего нет.

    python3 tool/align_plush.py out/ raw/*.png
    python3 tool/align_plush.py --grid=v6 out/ raw/*.png
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Холст назначения и место героя на нём. 3:4 — как у исходных генераций,
# так что ничего не растягивается.
CANVAS = (1024, 1365)
BODY_HEIGHT = 1180.0
BASELINE_Y = 1300.0
CENTRE_X = 512.0

GRIDS = {
    # Набор v5: генерации 2k, холст под них.
    'v5': {'canvas': (1024, 1365), 'body': 1180.0,
           'baseline': 1300.0, 'centre': 512.0},
    # Набор v6: генерации 2480 × 3312 в максимальном качестве. Холст почти
    # равен исходнику, коэффициенты масштаба выходят 1,01–1,07 — кадры не
    # пересэмплируются, и оплаченное разрешение остаётся в деталях.
    'v6': {'canvas': (2480, 3307), 'body': 3150.0,
           'baseline': 3250.0, 'centre': 1240.0},
}
"""Готовые сетки под наборы кадров: подставляются ключом --grid."""


def use_grid(name: str) -> None:
    """Переключает холст на заданный набор."""
    if name not in GRIDS:
        raise SystemExit(f'Нет сетки {name}. Есть: {", ".join(GRIDS)}')
    grid = GRIDS[name]
    global CANVAS, BODY_HEIGHT, BASELINE_Y, CENTRE_X
    CANVAS = grid['canvas']
    BODY_HEIGHT = grid['body']
    BASELINE_Y = grid['baseline']
    CENTRE_X = grid['centre']

ALPHA_MIN = 16
"""Ниже этого альфа — это шум по краю пушистого контура, не тело."""

APEX_BAND = 0.40
"""Доля ширины тела вокруг центра, в которой ищем макушку капюшона.

Поднятая лапа уходит от центра примерно на половину ширины головы, так что
0.40 её отсекает, а конус капюшона оставляет целиком.
"""

FOOT_BAND = (0.60, 0.95)
"""Полоса по высоте тела для горизонтального центра: шорты и ноги."""


class Anchors:
    """Три опорные величины кадра плюс диагностика."""

    def __init__(self, apex: int, baseline: int, centre: float):
        self.apex = apex
        self.baseline = baseline
        self.centre = centre

    @property
    def height(self) -> float:
        return float(self.baseline - self.apex)

    def __str__(self) -> str:
        return (
            f'верх={self.apex} низ={self.baseline} '
            f'высота={self.height:.0f} центр={self.centre:.0f}'
        )


def _solid(alpha: Image.Image) -> Image.Image:
    """Бинарная маска тела: всё, что плотнее ALPHA_MIN.

    Через point, а не через перебор пикселей: кадры по 4 Мп, десять штук,
    и любой цикл на Python по ним превращает секунды в минуты.
    """
    return alpha.point(lambda v: 255 if v >= ALPHA_MIN else 0)


def find_anchors(image: Image.Image) -> Anchors:
    """Ищет макушку, низ и горизонтальный центр героя."""
    if image.mode != 'RGBA':
        raise SystemExit(f'Нужен RGBA с альфой, а не {image.mode}')

    mask = _solid(image.getchannel('A'))
    box = mask.getbbox()
    if box is None:
        raise SystemExit('Кадр пустой: альфа везде прозрачная')

    left, _, right, lower = box
    baseline = lower - 1

    # Макушку ищем только в центральной полосе: поднятая лапа выше капюшона
    # перебила бы её и увела масштаб.
    mid = (left + right) / 2.0
    half = (right - left) * APEX_BAND / 2.0
    band = mask.crop((int(mid - half), 0, int(mid + half), mask.height))
    band_box = band.getbbox()
    if band_box is None:
        raise SystemExit('В центральной полосе нет тела — проверь кадр')
    apex = band_box[1]

    # Горизонтальный центр — по шортам и ногам: туда не дотягиваются ни
    # руки, ни поворот головы.
    body = baseline - apex
    y0 = apex + int(body * FOOT_BAND[0])
    y1 = min(apex + int(body * FOOT_BAND[1]), mask.height)
    feet = mask.crop((0, y0, mask.width, y1))

    # Центроид по X: сумма маски по столбцам — это одна строка после
    # resize по высоте в 1 пиксель с усреднением.
    profile = feet.resize((feet.width, 1), Image.BOX).getdata()
    total = sum(profile)
    if total == 0:
        raise SystemExit('В полосе ног нет тела — проверь границы FOOT_BAND')
    centre = sum(x * v for x, v in enumerate(profile)) / total

    return Anchors(apex, baseline, centre)


def align(image: Image.Image, anchors: Anchors) -> Image.Image:
    """Переносит кадр на общий холст по найденным якорям."""
    scale = BODY_HEIGHT / anchors.height
    new_size = (max(1, round(image.width * scale)),
                max(1, round(image.height * scale)))
    scaled = image.resize(new_size, Image.LANCZOS)

    # Куда уехали якоря после масштабирования.
    baseline = anchors.baseline * scale
    centre = anchors.centre * scale

    canvas = Image.new('RGBA', CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(
        scaled,
        (round(CENTRE_X - centre), round(BASELINE_Y - baseline)),
    )
    return canvas


def main(argv: list[str]) -> int:
    argv = list(argv)
    if len(argv) > 1 and argv[1].startswith('--grid='):
        use_grid(argv.pop(1).split('=', 1)[1])
    if len(argv) < 3:
        print(__doc__)
        return 2

    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)

    for raw in argv[2:]:
        src = Path(raw)
        image = Image.open(src).convert('RGBA')
        anchors = find_anchors(image)
        aligned = align(image, anchors)
        dst = out_dir / src.name
        aligned.save(dst)
        print(f'{src.name}: {anchors} -> {dst}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
