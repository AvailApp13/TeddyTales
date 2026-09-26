"""Убирает с вырезанной картинки всё, что не является самой вещью.

Нарезка листа (`tool/cut_shop.py`) делит кадр прямоугольниками, а вещи в
кадре не прямоугольные: в угол куска попадает лист соседнего растения,
камешек от соседа, полоска непрозрачного фона. В карточке магазина это
незаметно, а в полноэкранном просмотре бросается в глаза — заказчик 20.09:
«вырезано не аккуратно».

Отсюда правило: на картинке остаётся одна вещь — самая крупная связная
область непрозрачных пикселей — и те куски, которые к ней относятся.
Относятся, если лежат внутри её habitat: свисающая лиана отрывается от
кашпо и сама по себе мала, но висит прямо под ним, а чужой лист лежит с
краю, за пределами вещи.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def clean(
    path: Path,
    target: Path,
    keep: float = 0.01,
    reach: float = 0.005,
    solid_floor: int = 128,
) -> tuple[int, int]:
    image, pieces, dropped = cleaned_image(
        Image.open(path), keep, reach, solid_floor,
    )
    image.save(target)
    return (pieces, dropped)


def cleaned_image(
    source: Image.Image,
    keep: float = 0.01,
    reach: float = 0.005,
    solid_floor: int = 128,
) -> tuple[Image.Image, int, int]:
    image = source.convert('RGBA')
    data = np.array(image)
    solid = data[..., 3] > solid_floor

    labels, count = ndimage.label(solid)
    if count <= 1:
        # Убирать нечего, но обрезать поля всё равно надо: край картинки —
        # это край вещи, по нему комната считает её размер.
        return (_cropped(image), count, 0)

    sizes = ndimage.sum_labels(solid, labels, range(1, count + 1))
    main = int(np.argmax(sizes)) + 1
    boxes = ndimage.find_objects(labels)

    # Что считать «той же вещью»: кусок, лежащий вплотную к главному.
    # Свисающая лиана отрывается от кашпо на считанные пиксели, а чужой
    # лист с соседнего горшка лежит поодаль — расстояние их и разводит.
    span = max(solid.shape)
    near = ndimage.binary_dilation(
        labels == main,
        iterations=max(2, round(reach * span)),
    )

    keep_labels = {main}
    for index in range(1, count + 1):
        if index == main:
            continue
        if sizes[index - 1] < keep * sizes[main - 1]:
            continue
        if np.any(near & (labels == index)):
            keep_labels.add(index)

    mask = np.isin(labels, list(keep_labels))
    # Полупрозрачную кромку оставляем той же вещи: она лежит вплотную к
    # ней, и без неё край становится рубленым.
    edge = ndimage.binary_dilation(mask, iterations=2)
    data[..., 3] = np.where(edge, data[..., 3], 0)

    result = _cropped(Image.fromarray(data))

    return (result, count, count - len(keep_labels))


def _cropped(image: Image.Image) -> Image.Image:
    """Обрезает прозрачные поля до самой вещи."""
    box = image.split()[-1].point(lambda v: 255 if v > 8 else 0).getbbox()
    return image.crop(box) if box else image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sources', nargs='+', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    for source in args.sources:
        pieces, dropped = clean(source, args.out / source.name)
        if dropped:
            print(f'{source.name}: было кусков {pieces}, убрано {dropped}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
