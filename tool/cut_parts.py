#!/usr/bin/env python3
"""Нарезка деталей героя из эталона + подготовка сгенерированных кусков.

Видимые детали режутся из docs/reference/bear-etalon-2048.png (пиксели фото,
координаты сняты вручную по сетке); чистая голова — из bear-etalon-clean-face;
скрытые зоны и согнутые руки — из docs/reference/parts-gen/* с приведением
цвета к эталону (перенос статистик LAB по зонам мех→мех, шорты→шорты);
веки — донорский мех эталона; открытый рот и язык — процедурно в палитре носа.

Выход: docs/reference/parts/<имя>.png (RGBA) и общий контрольный лист
docs/reference/parts-contact-sheet.png для утверждения.
"""

from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'docs/reference'
OUT = REF / 'parts'
GREY = 128

et = cv2.imread(str(REF / 'bear-etalon-2048.png'))
clean = cv2.imread(str(REF / 'bear-etalon-clean-face.png'))
hsv = cv2.cvtColor(et, cv2.COLOR_BGR2HSV)
HUE, SAT, VAL = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]

# Силуэт мишки на канве эталона: всё, что не ровный фон.
sil = (np.abs(et.astype(int) - GREY).sum(axis=2) > 12).astype(np.uint8) * 255
sil = cv2.morphologyEx(sil, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))

FUR = (HUE < 30) & (SAT > 15) & (VAL > 110)   # мех, включая затенённый ворс
BLUE = (HUE > 85) & (HUE < 125) & (SAT > 25)   # кофта и капюшон
YELLOW = (HUE >= 15) & (HUE <= 35) & (SAT > 45) & (VAL > 170)  # шорты


def solid(mask, k=9):
    """Закрыть дыры и оставить одну крупнейшую компоненту."""
    m = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((k, k), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    if n <= 1:
        return m
    big = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    return np.where(lab == big, 255, 0).astype(np.uint8)


def save_rgba(name, bgr, alpha, feather=2.0):
    a = cv2.GaussianBlur(alpha, (0, 0), feather)
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        raise RuntimeError(f'{name}: пустая деталь')
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rgba = np.dstack([bgr[y0:y1, x0:x1], a[y0:y1, x0:x1]])
    cv2.imwrite(str(OUT / f'{name}.png'), rgba)
    return name


def region_mask(x0, y0, x1, y1, cond=None):
    m = np.zeros(sil.shape, np.uint8)
    m[y0:y1, x0:x1] = sil[y0:y1, x0:x1]
    if cond is not None:
        m[~cond] = 0
    return m


def lab_transfer(src_bgr, src_mask, tgt_stats):
    """Перенос mean/std LAB на пиксели src под маской."""
    lab = cv2.cvtColor(src_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    out = lab.copy()
    sm, ss = lab[src_mask].mean(axis=0), lab[src_mask].std(axis=0) + 1e-3
    tm, ts = tgt_stats
    out[src_mask] = (lab[src_mask] - sm) / ss * ts + tm
    out = np.clip(out, 0, 255).astype(np.uint8)
    return cv2.cvtColor(out, cv2.COLOR_LAB2BGR)


def stats_of(bgr, mask):
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    return lab[mask].mean(axis=0), lab[mask].std(axis=0) + 1e-3


def ellipse_mask(cx, cy, rx, ry):
    m = np.zeros(sil.shape, np.uint8)
    cv2.ellipse(m, (cx, cy), (rx, ry), 0, 0, 360, 255, -1)
    return m


def main():
    OUT.mkdir(exist_ok=True)
    made = []

    # --- Уши: мех в верхних боковых зонах ---
    made.append(save_rgba('ear-left', et,
                          solid(region_mask(540, 470, 790, 720, FUR))))
    made.append(save_rgba('ear-right', et,
                          solid(region_mask(1215, 470, 1470, 720, FUR))))

    # --- Голова в капюшоне, чистое лицо, без ушей ---
    head = region_mask(500, 200, 1550, 1230)
    # Ниже линии подбородка оставляем только ворот под головой, без плеч.
    below = np.zeros(sil.shape, bool)
    below[1080:, :640] = True
    below[1080:, 1400:] = True
    head[below] = 0
    ear_zone = np.zeros(sil.shape, bool)
    ear_zone[470:720, 540:790] = True
    ear_zone[470:720, 1215:1470] = True
    # В зоне ушей на голове может остаться только ткань капюшона: сам мех
    # уха и его полупрозрачный край против фона уходят в деталь «ухо».
    head[ear_zone & ~BLUE] = 0
    made.append(save_rgba('head-hood-clean', clean, head))

    # --- Лицо: глаза, нос, нейтральный рот-стежок ---
    made.append(save_rgba('eye-left', et, ellipse_mask(918, 860, 42, 43), 1.2))
    made.append(save_rgba('eye-right', et, ellipse_mask(1113, 860, 42, 43), 1.2))
    made.append(save_rgba('nose', et, ellipse_mask(1018, 953, 52, 40), 1.5))
    made.append(save_rgba('mouth-stitch', et,
                          ellipse_mask(1018, 1022, 30, 42), 1.5))

    # --- Торс: кофта (синяя ткань) ниже капюшона + пуговица ---
    torso = region_mask(400, 1130, 1650, 1580, BLUE)
    torso = cv2.morphologyEx(torso, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    torso[sil == 0] = 0
    made.append(save_rgba('torso-hoodie', et, torso))

    # --- Видимые лапы рук (фото) ---
    made.append(save_rgba('paw-left', et,
                          solid(region_mask(460, 1180, 700, 1370, FUR))))
    made.append(save_rgba('paw-right', et,
                          solid(region_mask(1340, 1180, 1560, 1370, FUR))))

    # --- Ноги: шорты + ступни (фото), без нависающего подола кофты ---
    legs = region_mask(600, 1415, 1420, 1760)
    blue_wide = cv2.dilate(BLUE.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    legs[blue_wide] = 0
    legs = solid(legs, 5)
    made.append(save_rgba('legs-shorts-feet', et, legs))

    # --- Целевые статистики для цветокоррекции генерата ---
    fur_ref = np.zeros(sil.shape, bool)
    fur_ref[1200:1340, 480:680] = True   # лапа
    fur_ref[1600:1740, 700:1200] = True  # ступни
    fur_stats = stats_of(et, fur_ref & FUR & (sil > 0))
    yellow_stats = stats_of(et, YELLOW & (sil > 0))

    # --- Генерат: скрытые зоны (цвет к эталону) ---
    gen = cv2.imread(str(REF / 'parts-gen/gen-hidden-zones.png'))
    gh = cv2.cvtColor(gen, cv2.COLOR_BGR2HSV)
    g_sil = (np.abs(gen.astype(int) - 126).sum(axis=2) > 14)
    g_fur = g_sil & (gh[:, :, 0] < 30) & (gh[:, :, 1] > 25)
    g_yel = g_sil & (gh[:, :, 0] >= 15) & (gh[:, :, 0] <= 35) & \
        (gh[:, :, 1] > 80)
    g_yel &= ~g_fur
    fixed = lab_transfer(gen, g_fur & ~g_yel, fur_stats)
    fixed = lab_transfer(fixed, g_yel, yellow_stats)
    galpha = (g_sil.astype(np.uint8)) * 255
    h, w = gen.shape[:2]
    made.append(save_rgba('gen-legs-extended', fixed,
                          np.where(np.arange(w)[None, :] < w // 2, galpha, 0
                                   ).astype(np.uint8)))
    made.append(save_rgba('gen-arm-roots', fixed,
                          np.where(np.arange(w)[None, :] >= w // 2, galpha, 0
                                   ).astype(np.uint8)))

    # --- Генерат: согнутые руки (цвет к эталону) ---
    arms = cv2.imread(str(REF / 'parts-gen/gen-giggle-arms.png'))
    ah = cv2.cvtColor(arms, cv2.COLOR_BGR2HSV)
    a_sil = (np.abs(arms.astype(int) - 125).sum(axis=2) > 14)
    a_fur = a_sil & (ah[:, :, 1] > 25)
    arms_fixed = lab_transfer(arms, a_fur, fur_stats)
    aalpha = a_sil.astype(np.uint8) * 255
    aw = arms.shape[1]
    made.append(save_rgba('giggle-arm-left', arms_fixed,
                          np.where(np.arange(aw)[None, :] < aw // 2, aalpha, 0
                                   ).astype(np.uint8)))
    made.append(save_rgba('giggle-arm-right', arms_fixed,
                          np.where(np.arange(aw)[None, :] >= aw // 2, aalpha, 0
                                   ).astype(np.uint8)))

    # --- Веки из донорского меха лба (чистая зона без носа и глаз) ---
    donor = et[690:790, 920:1130]
    for name, ry, crop_top in [('eyelid-upper', 46, False),
                               ('eyelid-lower', 18, True)]:
        tile = cv2.resize(donor, (240, 140))
        lid = np.zeros((140, 240, 3), np.uint8)
        lida = np.zeros((140, 240), np.uint8)
        cv2.ellipse(lida, (60, 70), (44, ry), 0, 0, 360, 255, -1)
        cv2.ellipse(lida, (180, 70), (44, ry), 0, 0, 360, 255, -1)
        if crop_top:
            lida[:70, :] = 0  # нижнее веко — только нижняя половина
        lid[lida > 0] = tile[lida > 0]
        made.append(save_rgba(name, lid, lida, 1.5))

    # --- Открытый рот и язык, палитра от носа ---
    nose_bgr = et[ellipse_mask(1018, 953, 30, 22) > 0].mean(axis=0)
    mouth = np.zeros((160, 220, 3), np.uint8)
    ma = np.zeros((160, 220), np.uint8)
    cv2.ellipse(ma, (110, 75), (85, 62), 0, 0, 360, 255, -1)
    dark = (nose_bgr * 0.45).astype(np.uint8)
    mouth[:] = dark
    inner = np.zeros_like(ma)
    cv2.ellipse(inner, (110, 82), (62, 42), 0, 0, 360, 255, -1)
    mouth[inner > 0] = (nose_bgr * 0.28).astype(np.uint8)
    made.append(save_rgba('mouth-open', mouth, ma, 4.0))

    tongue = np.zeros((90, 130, 3), np.uint8)
    ta = np.zeros((90, 130), np.uint8)
    cv2.ellipse(ta, (65, 40), (48, 34), 0, 0, 360, 255, -1)
    tongue[:] = (150, 138, 224)  # мягкий плюшевый розовый (BGR)
    cv2.line(tongue, (65, 18), (65, 62), (128, 112, 204), 5)
    made.append(save_rgba('tongue', tongue, ta, 2.0))

    contact_sheet(made)
    print(f'OK: {len(made)} деталей → docs/reference/parts/ + контрольный лист')


def contact_sheet(names):
    """Все детали на одном листе с подписями."""
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 22)
    cols = 5
    cell = 360
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell, rows * (cell + 40)),
                      (GREY, GREY, GREY))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        img = Image.open(OUT / f'{name}.png')
        img.thumbnail((cell - 30, cell - 30))
        cx = (i % cols) * cell + (cell - img.width) // 2
        cy = (i // cols) * (cell + 40) + (cell - img.height) // 2
        sheet.paste(img, (cx, cy), img)
        d.text(((i % cols) * cell + cell // 2, (i // cols) * (cell + 40) + cell + 8),
               name, font=font, fill=(30, 25, 20), anchor='ma')
    sheet.save(REF / 'parts-contact-sheet.png')


if __name__ == '__main__':
    main()
