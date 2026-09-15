#!/usr/bin/env python3
"""Снимает ровный серый фон с листа и возвращает честную альфу.

Почему не «вырезать по порогу». Мех по краю силуэта распадается на
отдельные ворсинки, и пиксель там — это смесь шерсти и фона. Порог такую
кромку либо съедает (силуэт становится стриженым), либо оставляет вместе с
примесью фона — и тогда вокруг мишки идёт серая кайма, которая на светлой
сцене приложения читается обводкой.

Правильно тут не резать, а **расшивать смесь**. Пиксель кромки описывается
как `C = a·F + (1-a)·B`, где `B` — цвет фона, `F` — цвет шерсти, `a` —
сколько в пикселе шерсти. Фон мы знаем точно: он ровный и снят по ТЗ 2.2.
Значит по `C` и `B` можно восстановить и `a`, и чистый цвет `F` — без следа
фона внутри полупрозрачных пикселей.

Тень на фоне отсекается отдельно: это тоже «не фон», но к мишке она не
относится. Берём самую большую связную область и всё, что вне её, гасим.

    python3 tool/unbackground.py out/ sheets/*.png
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

CORNER = 64
"""Сторона квадрата в углу листа, по которому замеряется цвет фона."""

FLOOR = 0.22
"""Ниже этой доли шерсти пиксель считается чистым фоном.

Не ноль и не десятая: сенсорный шум и слабая тень дают проценты примеси, и
при низком пороге вокруг мишки остаётся дымка из почти прозрачных пикселей.
Она незаметна на целом листе, но стоит нарезать его на части — и каждая
рамка проявляется светлым прямоугольником на тёмном фоне.
"""

CEIL = 0.92
"""Выше этой доли пиксель считается полностью непрозрачным."""

KEEP = 0.004
"""Доля площади листа, ниже которой связная область считается мусором."""


def background_colour(image: np.ndarray) -> np.ndarray:
    """Цвет фона по четырём углам листа."""
    h, w = image.shape[:2]
    patches = [
        image[:CORNER, :CORNER], image[:CORNER, w - CORNER:],
        image[h - CORNER:, :CORNER], image[h - CORNER:, w - CORNER:],
    ]
    return np.median(np.concatenate([p.reshape(-1, 3) for p in patches]),
                     axis=0)


def coverage(image: np.ndarray, back: np.ndarray) -> np.ndarray:
    """Доля шерсти в каждом пикселе, 0…1.

    Считается по тому, насколько цвет ушёл от фона в сравнении с тем,
    насколько ушла бы чистая шерсть. По каналам берём максимум: на канале,
    где шерсть и фон ближе всего, отношение шумит сильнее всего.
    """
    pixels = image.astype(np.float32)
    delta = pixels - back
    fur = np.percentile(pixels[np.linalg.norm(delta, axis=2) > 60], 70, axis=0)
    spread = np.abs(fur - back)
    spread[spread < 8] = 8
    alpha = np.max(np.abs(delta) / spread, axis=2)
    return np.clip((alpha - FLOOR) / (CEIL - FLOOR), 0.0, 1.0)


def unmix(image: np.ndarray, back: np.ndarray,
          alpha: np.ndarray) -> np.ndarray:
    """Чистый цвет шерсти: вычитает из пикселя вклад фона.

    Считается ПОСЛЕ того, как альфа окончательна. Порядок здесь не
    формальность: делить на промежуточную альфу, а потом поднимать её до
    единицы — значит завысить яркость ровно во столько раз, во сколько
    альфа подросла. На мехе это вылезает пересветом и рыжими точками по
    складкам.

    Там, где пиксель непрозрачен, формула вырождается в тождество и цвет
    остаётся ровно таким, каким его снял объектив.
    """
    pixels = image.astype(np.float32)
    safe = np.maximum(alpha, 1e-3)[..., None]
    colour = (pixels - (1.0 - safe) * back) / safe
    return np.clip(colour, 0, 255)


def solidify(alpha: np.ndarray) -> np.ndarray:
    """Делает внутренность силуэта полностью непрозрачной.

    Расшивка смеси оценивает долю шерсти по тому, насколько цвет ушёл от
    фона. Для кромки это работает, а вот внутри тела подводит: затенённые
    складки меха по яркости близки к серому фону, и альфа там выходит
    заниженной — 0,5 вместо единицы. На целом листе этого не видно, потому
    что под полупрозрачным пикселем ничего нет. Но стоит наложить детали
    друг на друга, и в местах перехлёста проступают светлые полосы.

    Поэтому полупрозрачность оставляем только там, где ей место — на кромке
    шириной в несколько пикселей. Всё, что глубже, непрозрачно.
    """
    body = (alpha > 0.30).astype(np.uint8)
    # Закрываем дыры, которые дали тёмные складки.
    body = cv2.morphologyEx(body, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    inner = cv2.erode(body, np.ones((7, 7), np.uint8))
    return np.where(inner > 0, 1.0, alpha)


def largest_island(alpha: np.ndarray) -> np.ndarray:
    """Оставляет самую большую связную область, остальное гасит.

    Отсекает тень на фоне и одиночный мусор: они тоже отличаются от фона,
    но к силуэту не относятся.
    """
    solid = (alpha > 0.35).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
    if count <= 1:
        return alpha
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = {index + 1 for index, area in enumerate(areas)
            if area >= alpha.size * KEEP}
    if not keep:
        keep = {int(np.argmax(areas)) + 1}
    mask = np.isin(labels, list(keep)).astype(np.uint8)
    # Возвращаем кромку: она тоньше порога и в компоненту не попала.
    # Расширение узкое — широкое втягивает обратно дымку вокруг силуэта.
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    return alpha * mask


def strip(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise SystemExit(f'Не читается: {path}')
    back = background_colour(image)
    alpha = coverage(image, back)
    alpha = largest_island(alpha)
    alpha = solidify(alpha)
    colour = unmix(image, back, alpha)
    out = np.dstack([colour, alpha * 255]).astype(np.uint8)
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    for raw in argv[2:]:
        src = Path(raw)
        rgba = strip(src)
        dst = out_dir / f'{src.stem}.png'
        cv2.imwrite(str(dst), rgba)
        solid = (rgba[:, :, 3] > 200).sum()
        edge = ((rgba[:, :, 3] > 10) & (rgba[:, :, 3] <= 200)).sum()
        print(f'{src.stem:14s} плотных {solid / 1e6:5.2f} Мп, '
              f'кромка {edge / 1e3:6.1f} тыс. px -> {dst.name}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
