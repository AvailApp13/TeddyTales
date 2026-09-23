"""Спрайты лица кухни — в один стиль со спальней.

Заказчик 23.09: «когда он закрывает глазки, получается дуга… чтобы мишка
везде был похож». В спальне закрытые глаза — вышитые дуги с ресничками
(GPT), на кухне GPT нарисовал тонкие фиолетовые линии с цветной каймой.
Скрипт:

1. вырезает дуги закрытых глаз из спальни (`bear_closed.png` минус мех)
   и ставит их на кухонный спрайт по центрам бусин — `eyes_closed.png`;
2. из тех же дуг, перевёрнутых, делает глаза-улыбку — `eyes_happy.png`;
3. смягчает край спрайтов с мехом (`eyes_open.png`, `mouth_neutral.png`):
   жёсткий срез читался кольцом вокруг бусин и носа;
4. убирает светлую кайму с ушей.

Исходники GPT сохраняются один раз в `tool/kitchen_gpt_originals/` (не в
ассеты — иначе попадут в сборку).

    python3 tool/fix_kitchen_sprites.py            # правит ассеты
    python3 tool/fix_kitchen_sprites.py --preview  # только картинка проверки
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
K = ROOT / 'assets/rooms/kitchen'
B = ROOT / 'assets/rooms/bedroom'
PREVIEW = Path('/tmp/claude-0/-home-user-TeddyTales/80e45046-6c08-58de-a596-b9d2149c09f8/scratchpad/kitchenshot/sprites_fix.png')


def load(path):
    return np.asarray(Image.open(path).convert('RGBA')).astype(float)


ORIGINALS = ROOT / 'tool/kitchen_gpt_originals'


def keep_original(path: Path):
    backup = ORIGINALS / path.name
    if not backup.exists():
        ORIGINALS.mkdir(parents=True, exist_ok=True)
        Image.open(path).save(backup)


def dark_blobs(rgba, thr=110, min_area=40):
    """Тёмные пятна (бусины, нитки) на меху: маска и центроиды."""
    lum = rgba[..., :3] @ [0.299, 0.587, 0.114]
    mask = (lum < thr) & (rgba[..., 3] > 128)
    mask = ndimage.binary_opening(mask, iterations=1)
    labels, n = ndimage.label(mask)
    blobs = []
    for i in range(1, n + 1):
        area = (labels == i).sum()
        if area < min_area:
            continue
        cy, cx = ndimage.center_of_mass(labels == i)
        ys, xs = np.where(labels == i)
        blobs.append(dict(cx=cx, cy=cy, area=area, x0=xs.min(), x1=xs.max(), y0=ys.min(), y1=ys.max(), mask=labels == i))
    return sorted(blobs, key=lambda b: b['cx'])


def two_eyes(blobs):
    """Две самые крупные — левый и правый глаз."""
    top = sorted(blobs, key=lambda b: -b['area'])[:2]
    return sorted(top, key=lambda b: b['cx'])


def thread_sprite(rgba, blob, pad=6):
    """Вырезка нитки: цвет — из картинки, альфа — по темноте, мягко."""
    x0, x1, y0, y1 = blob['x0'] - pad, blob['x1'] + pad, blob['y0'] - pad, blob['y1'] + pad
    crop = rgba[y0:y1 + 1, x0:x1 + 1].copy()
    lum = crop[..., :3] @ [0.299, 0.587, 0.114]
    # Мех ~ 200+, нитка ~ 60–120: альфа растёт к тёмному.
    alpha = np.clip((175 - lum) / 70, 0, 1)
    alpha *= crop[..., 3] / 255
    # Только сама нитка, без случайных тёмных ворсинок вокруг.
    near = ndimage.binary_dilation(blob['mask'][y0:y1 + 1, x0:x1 + 1], iterations=3)
    alpha *= near
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    crop[..., 3] = alpha * 255
    return crop, (blob['cx'] - x0, blob['cy'] - y0)


def paste(canvas, sprite, center, scale, flip=False):
    """Поставить спрайт центром в [center] с масштабом [scale]."""
    im = Image.fromarray(sprite.astype(np.uint8))
    if flip:
        im = im.transpose(Image.FLIP_TOP_BOTTOM)
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    im = im.resize((w, h), Image.LANCZOS)
    x = round(center[0] - w / 2)
    y = round(center[1] - h / 2)
    canvas.alpha_composite(im, (x, y))


def build_eyes():
    b_open, b_closed = load(B / 'bear_open.png'), load(B / 'bear_closed.png')
    k_open = load(K / 'eyes_open.png')
    # Зона глаз спальни — где открытая и закрытая картинки различаются;
    # вне её тёмные пятна (тени, нос) сбивают поиск бусин.
    diff = np.abs(b_open[..., :3] - b_closed[..., :3]).sum(-1)
    ys, xs = np.where(diff > 40)
    zone = np.zeros(diff.shape, bool)
    zone[ys.min() - 5:ys.max() + 6, xs.min() - 5:xs.max() + 6] = True
    masked = lambda img: np.where(zone[..., None], img, [0, 0, 0, 0])
    # Бусины: спальня и кухня.
    b_beads = two_eyes(dark_blobs(masked(b_open), thr=90, min_area=200))
    k_beads = two_eyes(dark_blobs(k_open, thr=90, min_area=60))
    # Дуги закрытых глаз в спальне — тонкие тёмные нитки (шире, чем выше)
    # ближе всего к каждой бусине; тени и нос отсеиваются формой.
    threads = [a for a in dark_blobs(masked(b_closed), thr=140, min_area=80)
               if (a['y1'] - a['y0']) < 0.7 * (a['x1'] - a['x0']) and 20 <= a['x1'] - a['x0'] <= 80]
    arcs = [min(threads, key=lambda a: (a['cx'] - e['cx']) ** 2 + (a['cy'] - e['cy']) ** 2)
            for e in b_beads]
    print('дуги спальни:', [(round(a['cx']), round(a['cy']), a['x1'] - a['x0'], a['y1'] - a['y0']) for a in arcs])
    b_d = np.mean([e['x1'] - e['x0'] for e in b_beads])
    k_d = np.mean([e['x1'] - e['x0'] for e in k_beads])
    scale = k_d / b_d
    print(f'бусины: спальня {b_d:.0f} px, кухня {k_d:.0f} px, масштаб {scale:.3f}')
    h, w = k_open.shape[:2]
    closed = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    happy = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for arc, b_eye, k_eye in zip(arcs, b_beads, k_beads):
        sprite, (acx, acy) = thread_sprite(b_closed, arc)
        # Смещение дуги относительно бусины — как в спальне, в масштабе.
        dx = (arc['cx'] - b_eye['cx']) * scale
        dy = (arc['cy'] - b_eye['cy']) * scale
        paste(closed, sprite, (k_eye['cx'] + dx, k_eye['cy'] + dy), scale)
        # Улыбка: та же нитка вверх ногами, чуть выше центра бусины.
        paste(happy, sprite, (k_eye['cx'] + dx, k_eye['cy'] - dy * 0.3), scale, flip=True)
    return closed, happy


def feather(path: Path, px: float):
    """Мягкий край у спрайта с мехом: альфа сходит на нет за [px] от среза."""
    rgba = load(path)
    alpha = rgba[..., 3] / 255
    inside = alpha > 0.5
    dist = ndimage.distance_transform_edt(inside)
    soft = np.clip(dist / px, 0, 1)
    rgba[..., 3] = np.minimum(alpha, soft) * 255
    return Image.fromarray(rgba.astype(np.uint8))


def defringe(path: Path):
    """Ухо: светлая кайма от вырезки — сжать альфу на пиксель и смягчить."""
    im = Image.open(path).convert('RGBA')
    a = np.asarray(im).astype(float)
    alpha = a[..., 3]
    eroded = ndimage.grey_erosion(alpha, size=(3, 3))
    alpha = np.minimum(alpha, ndimage.gaussian_filter(eroded, 0.7))
    a[..., 3] = alpha
    return Image.fromarray(a.astype(np.uint8))


def main():
    preview = '--preview' in sys.argv
    closed, happy = build_eyes()
    outputs = {
        'eyes_closed.png': closed,
        'eyes_happy.png': happy,
        'eyes_open.png': feather(K / 'eyes_open.png', 7),
        'mouth_neutral.png': feather(K / 'mouth_neutral.png', 5),
        'ear_left.png': defringe(K / 'ear_left.png'),
        'ear_right.png': defringe(K / 'ear_right.png'),
    }
    if not preview:
        for name, im in outputs.items():
            keep_original(K / name)
            im.save(K / name)
    # Проверка: голова с новыми спрайтами, три состояния.
    head = Image.open(K / 'head.png').convert('RGBA')
    HEAD = (0.357639, 0.382161, 0.275463, 0.185547)
    EY = (0.430556, 0.505208, 0.129630, 0.033854)
    MO = (0.458333, 0.536458, 0.071759, 0.023438)

    def put(canvas, im, box):
        x = (box[0] - HEAD[0]) / HEAD[2] * canvas.width
        y = (box[1] - HEAD[1]) / HEAD[3] * canvas.height
        w = box[2] / HEAD[2] * canvas.width
        h = box[3] / HEAD[3] * canvas.height
        canvas.alpha_composite(im.resize((round(w), round(h)), Image.LANCZOS), (round(x), round(y)))

    tiles = []
    for eyes in ['eyes_open.png', 'eyes_closed.png', 'eyes_happy.png']:
        c = head.copy()
        put(c, outputs[eyes], EY)
        put(c, outputs['mouth_neutral.png'], MO)
        ex = (EY[0] - HEAD[0]) / HEAD[2] * c.width
        ey = (EY[1] - HEAD[1]) / HEAD[3] * c.height
        tiles.append(c.crop((int(ex - 30), int(ey - 40), int(ex + 100), int(ey + 60))).resize((390, 300), Image.LANCZOS))
    sheet = Image.new('RGBA', (sum(t.width + 10 for t in tiles), 300), (255, 0, 255, 255))
    x = 0
    for t in tiles:
        sheet.alpha_composite(t, (x, 0))
        x += t.width + 10
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print('preview', PREVIEW)


if __name__ == '__main__':
    main()
