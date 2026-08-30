#!/usr/bin/env python3
"""Нарезка рига v4 из нового студийного кадра — целиком из одного фото.

Вход:  docs/reference/bear-source-v2.png — герой с открытым смеющимся ртом
       на ровном светло-сером фоне (кадр-эталон, утверждён заказчиком).
Выход: docs/reference/parts-v4/{head,ear_left,ear_right,paw_left,paw_right,
       torso,legs}.png + placements.json с посадкой в координатах артборда.

Чем v4 отличается от v2: лицо больше не собирается из кусочков. Моргание
убрано решением заказчика, поэтому глаза, веки, нос и рот остаются
нарисованными прямо на голове — швов на лице нет вовсе. Деталей семь, и все
резы либо идут по настоящим краям ткани (подол кофты), либо прячутся под
перекрытиями (низ капюшона уходит под голову с запасом, верх шорт — под
подол).

Геометрия посадки: новый мишка вписывается ровно в габарит нынешнего героя
на артборде (высота 1310, ступни на нижней кромке 1350, центр по x=540) —
размер героя на экране зафиксирован заказчиком и не меняется.

ВНИМАНИЕ: пороги и прямоугольники подобраны под конкретный кадр v2.
Новое фото — пересмотреть числа.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'docs/reference/bear-source-v2.png'
OUT = ROOT / 'docs/reference/parts-v4'

# Габарит героя на артборде 1080x1350 (снят с рига v3, менять нельзя).
ART_HEIGHT, ART_BOTTOM, ART_CX = 1310.0, 1350.0, 540.0

# Все координаты ниже — в пространстве фото 1024x1024 (до апскейла).
# Прямоугольники режущих зон: (x0, x1, y0, y1).
REGIONS = {
    # Голова: капюшон целиком + лицо + низ капюшона до груди. Нижний срез
    # прямой, но растушёван и лежит на синей ткани поверх такой же синей
    # ткани торса — шва не видно.
    'head':      (300, 730, 130, 640),
    # Уши торчат из прорезей капюшона; рисуются ПОЗАДИ головы, так что
    # захваченные с запасом куски меха прячутся за капюшоном.
    'ear_left':  (320, 450, 270, 415),
    'ear_right': (570, 700, 260, 405),
    # Лапки — только мех по бокам под рукавами.
    'paw_left':  (255, 345, 630, 770),
    'paw_right': (700, 778, 620, 760),
    # Торс — вся синяя ткань; верх дублирует низ капюшона (запас под подъём
    # головы на вдохе), низ идёт по настоящему подолу.
    'torso':     (280, 760, 555, 915),
    # Ноги: шорты и ступни; верх прячется под подолом кофты.
    'legs':      (315, 725, 700, 975),
}

# Ярлычок на правом бедре шорт торчит за контур — заказчик читает его как
# мусор у ноги. Полоса строк (в координатах фото 1024), где правый край шорт
# восстанавливается интерполяцией между чистыми строками выше и ниже: всё,
# что правее восстановленного контура, срезается вместе с ярлычком.
TAG_ROWS = (788, 897)

# Цветовой фильтр внутри зоны: у торса — только синяя ткань (иначе в кусок
# попадают шорты и лапы, торс рисуется поверх ног и двоит их), у ушей и лап —
# только мех (иначе прихватывается скат капюшона, и при повороте уха его
# запечённая копия края вылезает из-за головы). 'legs' — всё, КРОМЕ синего:
# верх шорт прячется под подолом кофты. None — без фильтра.
FILTERS = {
    'head': None,
    'ear_left': 'fur', 'ear_right': 'fur',
    'paw_left': 'fur', 'paw_right': 'fur',
    'torso': 'blue',
    'legs': 'warm',
}

FEATHER_CUT = 6.0     # растушёвка внутренних (прямых) срезов
FEATHER_EDGE = 0.8    # растушёвка силуэта после подрезки
MAX_TRIM, DARKER = 4, 12


def colour_mask(image: np.ndarray, kind: str | None) -> np.ndarray:
    """Маска цвета детали. Морфология срастила бы дырки (кнопка на кофте)."""
    if kind is None:
        return np.full(image.shape[:2], 255, np.uint8)
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, s = hsv[:, :, 0], hsv[:, :, 1]
    blue = (h > 85) & (h < 130) & (s > 15)
    fur = (h < 60) & (s > 28)
    # «Тёплое» — мех и жёлтые шорты разом; отсекает синь И тёмную тень под
    # подолом кофты, которая иначе торчит серыми клочками над шортами.
    warm = (h < 45) & (s > 25)
    m = {'blue': blue, 'fur': fur, 'not_blue': ~blue, 'warm': warm}[kind]
    m = m.astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((13, 13), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    return m


def build_mask(image: np.ndarray) -> np.ndarray:
    """Силуэт героя: GrabCut + чистка тени под ступнями."""
    h, w = image.shape[:2]
    mask = np.zeros((h, w), np.uint8)
    rect = (int(w * 0.22), int(h * 0.10), int(w * 0.58), int(h * 0.85))
    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(image, mask, rect, bgd, fgd, 8, cv2.GC_INIT_WITH_RECT)
    m = np.where((mask == 2) | (mask == 0), 0, 255).astype(np.uint8)

    def largest(binary: np.ndarray) -> np.ndarray:
        n, lab, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
        keep = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        return np.where(lab == keep, 255, 0).astype(np.uint8)

    m = largest(m)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    s, v = hsv[:, :, 1], hsv[:, :, 2]
    band = np.zeros((h, w), bool)
    band[880:, :] = True
    m[band & (s < 25) & (v > 200)] = 0   # тень и фон под ступнями
    return cv2.medianBlur(largest(m), 5)


def trim_and_defringe(piece: np.ndarray) -> np.ndarray:
    """Адаптивная подрезка тёмной кромки + перекраска полупрозрачной юбки.

    Та же пара приёмов, что в `riv_rig.py clean`: тень контура с фото
    срезается, а цвет старого края не просвечивает сквозь растушёвку.
    """
    alpha = piece[:, :, 3]
    value = cv2.cvtColor(piece[:, :, :3],
                         cv2.COLOR_BGR2HSV)[:, :, 2].astype(np.float32)
    solid = (alpha > 200).astype(np.uint8)
    deep_mask = cv2.erode(solid, np.ones((15, 15), np.uint8)) > 0
    if deep_mask.any():
        deep = float(np.median(value[deep_mask]))
        work = alpha.copy()
        trimmed = 0
        for _ in range(MAX_TRIM):
            shell = (work > 200).astype(np.uint8)
            rim = (shell > 0) & (cv2.erode(shell,
                                           np.ones((3, 3), np.uint8)) == 0)
            if not rim.any():
                break
            if deep - float(np.median(value[rim])) < DARKER:
                break
            work = cv2.erode(work, np.ones((3, 3), np.uint8))
            trimmed += 1
        if trimmed:
            piece[:, :, 3] = cv2.GaussianBlur(work, (0, 0), FEATHER_EDGE)

    shell = (piece[:, :, 3] > 200).astype(np.uint8)
    if shell.any() and (shell == 0).any():
        _, labels = cv2.distanceTransformWithLabels(
            1 - shell, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
        ys, xs = np.nonzero(shell)
        lut_y = np.zeros(int(labels.max()) + 1, np.int32)
        lut_x = np.zeros_like(lut_y)
        lut_y[labels[ys, xs]] = ys
        lut_x[labels[ys, xs]] = xs
        donor = piece[lut_y[labels], lut_x[labels], :3]
        piece[:, :, :3] = np.where((shell == 0)[..., None],
                                   donor, piece[:, :, :3])
    return piece


def shear_tag(piece: np.ndarray, piece_top: int) -> None:
    """Срезает ярлычок: контур шорт продолжается по прямой между опорами."""
    top, bottom = TAG_ROWS[0] * 2 - piece_top, TAG_ROWS[1] * 2 - piece_top
    alpha = piece[:, :, 3]

    def rightmost(start: int, step: int) -> float:
        """Медиана правого края по первым восьми непустым строкам."""
        edges: list[int] = []
        row = start
        while 0 <= row < alpha.shape[0] and len(edges) < 8:
            solid = np.nonzero(alpha[row] > 128)[0]
            if solid.size:
                edges.append(int(solid.max()))
            row += step
        if not edges:
            raise SystemExit('shear_tag: не нашёл опорных строк контура')
        return float(np.median(edges))

    above = rightmost(top - 1, -1)
    below = rightmost(bottom, 1)
    for row in range(max(0, top), min(alpha.shape[0], bottom)):
        edge = above + (below - above) * (row - top) / (bottom - top)
        alpha[row, int(edge) + 2:] = 0


def main() -> int:
    image = cv2.imread(str(SRC))
    mask = build_mask(image)


    # Апскейл x2: артбордный масштаб получается ~0.8, как у прежнего рига,
    # и детали не тянутся вверх из «родного» размера.
    image = cv2.resize(image, None, fx=2, fy=2, interpolation=cv2.INTER_LANCZOS4)
    mask = cv2.resize(mask, None, fx=2, fy=2, interpolation=cv2.INTER_NEAREST)

    ys, xs = np.where(mask > 0)
    top, bottom = ys.min(), ys.max()
    cx = (xs.min() + xs.max()) / 2
    scale = ART_HEIGHT / (bottom - top + 1)
    print(f'герой на фото: {xs.max() - xs.min() + 1}x{bottom - top + 1}, '
          f'масштаб к артборду {scale:.4f}')

    OUT.mkdir(parents=True, exist_ok=True)
    placements: dict[str, dict[str, float]] = {}
    for name, (rx0, rx1, ry0, ry1) in REGIONS.items():
        rx0, rx1, ry0, ry1 = rx0 * 2, rx1 * 2, ry0 * 2, ry1 * 2
        region = np.zeros_like(mask, np.float32)
        region[ry0:ry1, rx0:rx1] = 255.0
        # Прямые срезы растушёвываются, чтобы не читались линией.
        region = cv2.GaussianBlur(region, (0, 0), FEATHER_CUT)
        colour = colour_mask(image, FILTERS[name]).astype(np.float32)
        colour = cv2.GaussianBlur(colour, (0, 0), 2.0)
        alpha = (mask.astype(np.float32) * region * colour / 255.0 / 255.0)

        # Клочки-сироты (кусочек лапы в углу зоны ног) — вон.
        blobs = (alpha > 60).astype(np.uint8)
        n, lab, stats, _ = cv2.connectedComponentsWithStats(blobs, 8)
        for i in range(1, n):
            if stats[i, cv2.CC_STAT_AREA] < 6000:
                alpha[lab == i] = 0

        pys, pxs = np.where(alpha > 8)
        pad = 4
        py0, py1 = max(0, pys.min() - pad), min(mask.shape[0], pys.max() + pad)
        px0, px1 = max(0, pxs.min() - pad), min(mask.shape[1], pxs.max() + pad)
        piece = np.dstack([image[py0:py1, px0:px1],
                           alpha[py0:py1, px0:px1].astype(np.uint8)])
        if name == 'legs':
            shear_tag(piece, py0)
        piece = trim_and_defringe(piece)
        cv2.imwrite(str(OUT / f'{name}.png'), piece)

        centre_x = (px0 + px1) / 2
        centre_y = (py0 + py1) / 2
        placements[name] = {
            'x': round(ART_CX + (centre_x - cx) * scale, 2),
            'y': round(ART_BOTTOM - (bottom - centre_y) * scale, 2),
            'scale': round(scale, 5),
            'w': piece.shape[1], 'h': piece.shape[0],
        }
        print(f'  {name:10s} {piece.shape[1]}x{piece.shape[0]} '
              f'-> артборд ({placements[name]["x"]}, {placements[name]["y"]})')

    (OUT / 'placements.json').write_text(
        json.dumps(placements, ensure_ascii=False, indent=2))
    print(f'Готово: {OUT}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
