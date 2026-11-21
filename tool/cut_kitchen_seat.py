"""Тело прежнего мишка за кухонным столом — под голову нынешнего.

    python3 tool/cut_kitchen_seat.py

Заказчик 11.10: «возьми предыдущего мишку, его одежду, сопоставь цвет и
наложи на него… идеально ровный вид, как был ранее. Расположение рук».
За столом у Rive-мишка видна только голова в капюшоне (риг прячет своё
тело позой `pose_body_off`), а кофта, рукава и лапы — части прежнего
нарисованного мишка (`cut_kitchen_parts.py`) ровно на их прежних местах.

- Кофта и рукава — одна картинка `seat_body.png`: рукава, поверх них
  туловище, как стояли у прежнего. Бежевый овал наверху туловища (место
  прежней шеи) закрашен тканью кофты: его прячет капюшон, но при вдохе и
  кивке край капюшона ходит.
- Лапы — отдельно (`seat_paw_*.png`): лежат под рукавами и похлопывают
  по столу, пока мишка жуёт.
- Изнанка рукавов (`seat_cuffs.png`, та же рамка, что у кофты) — под
  лапами (заказчик 11.10: «когда лапками двигает — проблески, как будто
  рукава обрезаны»). Проём рукава (выпуклая оболочка рукава без самой
  ткани и туловища) прозрачен, в покое его закрывает лапа; приподнялась —
  был виден стул. Изнанка — тёмная ткань ровно там, где в проёме лежит
  лапа: в покое вид прежний, при хлопке — глубина рукава.
- Цвет: ткань прежней кофты насыщеннее и темнее нашей — множитель по
  каналам к средней ткани нашей кофты под светом кухни (замер 11.10:
  прежняя 113 / 155 / 190, наша 138 / 177 / 201); мех лап — к меху нашей
  мордочки (прежний 208 / 173 / 144, наш 203 / 172 / 146).

Картинки — в удвоенном разрешении кадра (941 × 1672 → ×2). Печатает
прямоугольники в долях кадра для `KitchenBear`.
"""
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import ConvexHull

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, 'assets/rooms/kitchen')
W, H = 941, 1672
UP = 2

# прежние места частей — доли кадра (KitchenScene)
RECTS = {
    'paw_left': (0.335648, 0.579427, 0.092593, 0.037760),
    'paw_right': (0.562500, 0.579427, 0.086806, 0.037760),
    'sleeve_left': (0.340278, 0.554688, 0.096065, 0.052734),
    'sleeve_right': (0.554398, 0.554688, 0.091435, 0.050130),
    'torso': (0.406250, 0.541016, 0.178241, 0.067057),
}
JACKET_GAIN = np.array([138.1 / 113.0, 176.9 / 155.3, 201.3 / 190.1])
FUR_GAIN = np.array([203.2 / 208.2, 172.4 / 173.2, 145.9 / 143.8])


def box(name):
    l, t, w, h = RECTS[name]
    return l * W, t * H, (l + w) * W, (t + h) * H


def recolor(rgba):
    """Ткань — к нашей кофте, мех — к нашему меху; белая пуговица почти не
    меняется (вес по синеве)."""
    rgb, a = rgba[..., :3], rgba[..., 3:]
    r, b = rgb[..., 0], rgb[..., 2]
    blue = np.clip((b - r - 10) / 30, 0, 1)[..., None]
    fur = np.clip((r - b - 15) / 30, 0, 1)[..., None]
    gain = 1 + blue * (JACKET_GAIN - 1) + fur * (FUR_GAIN - 1)
    return np.concatenate([np.clip(rgb * gain, 0, 255), a], axis=-1)


def paste(canvas, origin, name):
    """Часть на своё место в холсте с началом origin (px кадра)."""
    x0, y0, x1, y1 = box(name)
    im = Image.open(os.path.join(DIR, f'{name}.png')).convert('RGBA')
    size = (round((x1 - x0) * UP), round((y1 - y0) * UP))
    canvas.alpha_composite(im.resize(size, Image.LANCZOS),
                           (round((x0 - origin[0]) * UP), round((y0 - origin[1]) * UP)))


def fill_neck(rgba):
    """Бежевый овал наверху туловища — тканью кофты: средний цвет ткани
    вокруг, растушёвка на 2 px."""
    rgb, a = rgba[..., :3], rgba[..., 3]
    r, b = rgb[..., 0], rgb[..., 2]
    beige = (a > 10) & (r > b + 10)
    beige = ndimage.binary_dilation(beige, iterations=2 * UP)
    cloth = (a > 200) & ~beige & (b > r + 30)
    color = np.median(rgb[cloth], axis=0)
    w = ndimage.gaussian_filter(beige.astype(np.float64), UP)[..., None]
    rgba[..., :3] = rgb * (1 - w) + color * w
    return rgba


def part_mask(size, origin, name):
    """Где непрозрачна часть в холсте кофты."""
    t = Image.new('RGBA', size)
    paste(t, origin, name)
    return np.asarray(t)[..., 3] > 128


def cuffs(size, origin, body):
    """Изнанка рукавов: тёмная ткань в проёме рукава под лапой в покое.
    Цвет — тень складок той же кофты (тёмная десятая доля ткани), к
    глубине рукава темнее."""
    torso = part_mask(size, origin, 'torso')
    out = np.zeros(size[::-1] + (4,))
    rgb = body[..., :3]
    cloth = (body[..., 3] > 200) & (rgb[..., 2] > rgb[..., 0] + 30)
    lum = rgb.mean(2)
    deep = np.percentile(lum[cloth], 10)
    shade = np.median(rgb[cloth & (lum <= deep)], axis=0)
    for side in ('left', 'right'):
        sleeve = part_mask(size, origin, f'sleeve_{side}')
        paw = part_mask(size, origin, f'paw_{side}')
        ys, xs = np.where(sleeve)
        hull = ConvexHull(np.c_[xs, ys])
        poly = Image.new('L', size)
        ImageDraw.Draw(poly).polygon([(float(xs[i]), float(ys[i])) for i in hull.vertices], fill=255)
        opening = (np.asarray(poly) > 0) & ~sleeve & ~torso
        inner = opening & ndimage.binary_dilation(paw, iterations=UP)
        rows = np.where(inner.any(1))[0]
        depth = np.clip((np.arange(size[1]) - rows.min()) / max(1, rows.max() - rows.min()), 0, 1)
        tone = (0.78 + 0.22 * depth)[:, None, None]       # глубже — темнее
        a = ndimage.gaussian_filter(inner.astype(np.float64), 0.7)
        out[..., :3] += shade * tone * a[..., None]
        out[..., 3] = np.maximum(out[..., 3], a)
    rgba = np.dstack([out[..., :3] / np.maximum(out[..., 3:], 1e-6), out[..., 3] * 255])
    Image.fromarray(rgba.clip(0, 255).astype(np.uint8), 'RGBA').save(
        os.path.join(DIR, 'seat_cuffs.png'), optimize=True)
    print('cuffs — та же рамка, что body; тень ткани', shade.round(1))


def main():
    names = ('sleeve_left', 'sleeve_right', 'torso')
    x0 = min(box(n)[0] for n in names)
    y0 = min(box(n)[1] for n in names)
    x1 = max(box(n)[2] for n in names)
    y1 = max(box(n)[3] for n in names)
    x0, y0, x1, y1 = np.floor(x0), np.floor(y0), np.ceil(x1), np.ceil(y1)
    canvas = Image.new('RGBA', (int((x1 - x0) * UP), int((y1 - y0) * UP)))
    for name in names:                      # туловище поверх рукавов
        if name == 'torso':
            t = Image.new('RGBA', canvas.size)
            paste(t, (x0, y0), name)
            t = fill_neck(np.asarray(t).astype(np.float64))
            canvas.alpha_composite(Image.fromarray(t.clip(0, 255).astype(np.uint8), 'RGBA'))
        else:
            paste(canvas, (x0, y0), name)
    body = recolor(np.asarray(canvas).astype(np.float64))
    Image.fromarray(body.clip(0, 255).astype(np.uint8), 'RGBA').save(
        os.path.join(DIR, 'seat_body.png'), optimize=True)
    print(f'body  Rect.fromLTWH({x0 / W:.6f}, {y0 / H:.6f}, {(x1 - x0) / W:.6f}, {(y1 - y0) / H:.6f})')
    cuffs(canvas.size, (x0, y0), body)
    for side in ('left', 'right'):
        name = f'paw_{side}'
        px0, py0, px1, py1 = box(name)
        im = Image.open(os.path.join(DIR, f'{name}.png')).convert('RGBA')
        im = im.resize((round((px1 - px0) * UP), round((py1 - py0) * UP)), Image.LANCZOS)
        paw = recolor(np.asarray(im).astype(np.float64))
        Image.fromarray(paw.clip(0, 255).astype(np.uint8), 'RGBA').save(
            os.path.join(DIR, f'seat_paw_{side}.png'), optimize=True)
        print(f'{name:9s} Rect.fromLTWH({px0 / W:.6f}, {py0 / H:.6f}, {(px1 - px0) / W:.6f}, {(py1 - py0) / H:.6f})')


if __name__ == '__main__':
    main()
