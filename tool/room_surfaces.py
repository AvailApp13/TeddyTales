#!/usr/bin/env python3
"""Стены и пол игровой: сменные слои поверх assets/rooms/nursery.jpg.

Заказчик 09.10 (docs/room-surfaces-answers.md): 10 стен и 10 полов. Нынешние
стена (С1) и пол (П1) — сама картинка комнаты, слой не нужен. Остальные —
прозрачные слои 941×1672 в тех же координатах, что и фон:

  assets/rooms/nursery/walls/<id>.webp
  assets/rooms/nursery/floors/<id>.webp
  assets/rooms/nursery/swatches/<id>.webp   — образцы для выбора, 160 px

Цвет — перекраска: новый цвет × яркость исходной стены или пола, поэтому
свет из окна, тени и волокна дерева остаются. Узор (обои, особые полы) —
бесшовный образец из tool/surface_tiles/, разложенный в перспективе комнаты
(задняя стена прямо, левая — под углом, пол уходит к горизонту), сверху свет
комнаты.

Геометрия снята с картинки (пиксели 941×1672):
  угол стен x = 279; задняя стена y 250…860, плинтус до 892;
  левая стена: верх по линии карниза через (279, 247) и (195, 165),
  низ — по плинтусу через (279, 862) с наклоном 0,31;
  пол — ниже плинтусов: задний y = 892, левый через (279, 894,6), наклон 0,371;
  точка схода глубины (757, 715). Фокус камеры F подобран на глаз.

Запуск: python3 tool/room_surfaces.py [--preview папка]
"""

import argparse
import pathlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / 'assets/rooms/nursery.jpg'
TILES = ROOT / 'tool/surface_tiles'
OUT = ROOT / 'assets/rooms/nursery'

W, H = 941, 1672
CORNER_X = 279
WALL_TOP = 250          # низ карниза над задней стеной
WALL_BOTTOM = 861       # верх заднего плинтуса
FLOOR_TOP = 892         # низ заднего плинтуса
VP = (757.0, 715.0)     # точка схода линий глубины
F = 1300.0              # фокус камеры, px


def left_top(x):
    """Карниз над левой стеной."""
    return 247.0 - 0.976 * (CORNER_X - x)


def left_bottom(x):
    """Верх левого плинтуса."""
    return 862.0 + 0.31 * (CORNER_X - x)


def left_floor(x):
    """Низ левого плинтуса — край пола."""
    return 894.6 + 0.371 * (CORNER_X - x)


# --- Варианты (docs/room-surfaces-answers.md) -----------------------------

# id → ('color', '#RRGGBB') или ('tile', файл, размер плитки в px у угла)
WALLS = {
    'wall_cream': ('color', '#EFE0C8'),
    'wall_mint': ('color', '#BFDCCF'),
    'wall_lavender': ('color', '#CBBFDD'),
    'wall_sky': ('color', '#B8CCE0'),
    'wall_dots': ('tile', 'wall-dots', 300),
    'wall_forest': ('tile', 'wall-forest', 520),
    'wall_clouds': ('tile', 'wall-clouds', 440),
    'wall_sprigs': ('tile', 'wall-sprigs', 230),
    'wall_bunnies': ('tile', 'wall-bunnies', 210),
}

FLOORS = {
    'floor_honey': ('color', '#D9B48C'),
    'floor_greige': ('color', '#E6D6C3'),
    'floor_dark_oak': ('color', '#9C7656'),
    'floor_powder': ('color', '#EBD8D2'),
    'floor_light': ('color', '#F1E3CD'),
    'floor_laminate': ('tile', 'floor-laminate', 420),
    'floor_checker': ('tile', 'floor-checker', 360),
    'floor_carpet': ('tile', 'floor-carpet', 400),
    'floor_puzzle': ('tile', 'floor-puzzle', 380),
}

# Нынешние — образцы для выбора тоже нужны, слоя нет.
CURRENT = {'wall_rose': 'wall', 'floor_wood': 'floor'}


# --- Маски ----------------------------------------------------------------

def polygon_mask(points, scale=4):
    """Многоугольник со сглаженным краем (рисуем крупнее и уменьшаем)."""
    img = Image.new('L', (W * scale, H * scale), 0)
    ImageDraw.Draw(img).polygon([(x * scale, y * scale) for x, y in points],
                                fill=255)
    img = img.resize((W, H), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64) / 255.0


def masks(rgb):
    """Для стены и пола: (многоугольник, видимость). Видимость 1 — чистая
    поверхность, 0 — не она (карниз, рама, листва), между — тюль, сквозь
    который поверхность просвечивает."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    sat = (r - b) / np.maximum(r, 1)
    warm = ((g < r * 0.8) & (b < r)).astype(np.float64)  # не небо, не листва
    yy, xx = np.mgrid[0:H, 0:W]

    def ramp(lo, hi):
        return np.clip((sat - lo) / (hi - lo), 0, 1)

    # Стена: насыщенность 0,37–0,43; карниз, потолок у угла и плинтус ≤ 0,32.
    # Тюль белёсый (0,18–0,30), в складках стена видна сильнее.
    back = polygon_mask([(CORNER_X, WALL_TOP - 6), (W, WALL_TOP - 6),
                         (W, WALL_BOTTOM + 2), (CORNER_X, WALL_BOTTOM + 2)])
    x0 = CORNER_X - 253.0 / 0.976  # где карниз уходит за верх кадра
    left = polygon_mask([(0, 0), (x0, 0), (CORNER_X, 241),
                         (CORNER_X, left_bottom(CORNER_X) + 2),
                         (0, left_bottom(0) + 2)])
    wall_poly = np.maximum(back, left * (xx < CORNER_X + 2))
    curtain = ((xx >= 88) & (xx < 234)) | (xx < 22)
    # Внутри задней стены — вся стена (у правого края она бледнее, 0,34);
    # строгий порог только у карниза и плинтуса, у левой стены — у карниза.
    back_inner = ((xx >= CORNER_X + 3) & (yy > WALL_TOP + 3)
                  & (yy < WALL_BOTTOM - 3))
    near_top = yy < left_top(xx) + 12
    edge = np.where(near_top, ramp(0.31, 0.36), ramp(0.27, 0.33))
    wall_vis = np.where(back_inner, 1.0,
                        np.where(curtain & ~near_top, ramp(0.17, 0.38), edge)) * warm
    wall_vis = ndimage.gaussian_filter(wall_vis, 1.0)

    floor_poly = polygon_mask([(0, left_floor(0)), (CORNER_X, left_floor(CORNER_X)),
                               (CORNER_X, FLOOR_TOP), (W, FLOOR_TOP),
                               (W, H), (0, H)])
    # Подол тюля лежит на полу слева; дальше (солнечные пятна) — весь пол.
    hem = (xx < 236) & (yy < 1045)
    floor_vis = np.where(hem, ramp(0.20, 0.30), 1.0)
    floor_vis = ndimage.gaussian_filter(floor_vis, 1.0)
    return {'wall': (wall_poly, wall_vis), 'floor': (floor_poly, floor_vis)}


# --- Свет -----------------------------------------------------------------

def luminance(rgb):
    return rgb @ np.array([0.299, 0.587, 0.114])


def masked_blur(values, mask, sigma):
    """Размытие только внутри маски: плинтус и штора не просачиваются."""
    num = ndimage.gaussian_filter(values * mask, sigma)
    den = ndimage.gaussian_filter(mask, sigma)
    return num / np.maximum(den, 1e-4)


def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


# --- Узор в перспективе -----------------------------------------------------

def wall_uv():
    """Координаты стен в пикселях «у угла»: задняя прямо, левая под углом."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    u, v = xx.copy(), yy.copy()
    left = xx < CORNER_X
    h0 = left_bottom(CORNER_X) - 247.0
    h = left_bottom(xx) - left_top(xx)
    u[left] = CORNER_X - F * (1 - h0 / h[left])
    v[left] = 247.0 + (yy[left] - left_top(xx[left])) / h[left] * h0
    # Сколько пикселей узора приходится на пиксель экрана — для размытия вдали.
    foot = np.ones_like(u)
    foot[left] = np.maximum(h0 / h[left], F * h0 * 1.286 / h[left] ** 2)
    return u, v, foot


def floor_uv():
    """Координаты пола: X поперёк, Z вглубь, в пикселях у заднего плинтуса."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    dy = np.maximum(yy - VP[1], 1.0)
    k = (FLOOR_TOP - VP[1]) / dy
    x = (xx - VP[0]) * k
    z = F * (1 - k)
    foot = np.maximum(k, F * (FLOOR_TOP - VP[1]) / dy ** 2)
    return x, z, foot


def sample(tile, u, v, size, foot):
    """Бесшовный узор по координатам u, v; плитка size px. Вдали — размытее
    (пирамида уровней), чтобы не было ряби."""
    t = Image.fromarray(tile).resize((size, size), Image.LANCZOS)
    base = np.asarray(t, dtype=np.float64)
    levels = [base] + [ndimage.gaussian_filter(base, (0.5 * 2 ** i,) * 2 + (0,),
                                               mode='wrap') for i in range(1, 7)]
    lod = np.clip(np.log2(np.maximum(foot, 1.0)), 0, len(levels) - 1)

    def bilinear(img, uu, vv):
        n = img.shape[0]
        uu = np.mod(uu, n)
        vv = np.mod(vv, n)
        x0 = np.floor(uu).astype(int)
        y0 = np.floor(vv).astype(int)
        fx = (uu - x0)[..., None]
        fy = (vv - y0)[..., None]
        x1 = (x0 + 1) % n
        y1 = (y0 + 1) % n
        return ((img[y0, x0] * (1 - fx) + img[y0, x1] * fx) * (1 - fy)
                + (img[y1, x0] * (1 - fx) + img[y1, x1] * fx) * fy)

    lo = np.floor(lod).astype(int)
    hi = np.minimum(lo + 1, len(levels) - 1)
    frac = (lod - lo)[..., None]
    out = np.zeros(u.shape + (3,))
    for lvl in range(len(levels)):
        w = np.where(lo == lvl, 1 - frac[..., 0], 0) + np.where(hi == lvl, frac[..., 0], 0)
        if not w.any():
            continue
        out += bilinear(levels[lvl], u, v) * w[..., None]
    return out


def load_tile(name):
    path = TILES / f'{name}.webp'
    if not path.exists():
        return None
    return np.asarray(Image.open(path).convert('RGB'))


# --- Сборка ---------------------------------------------------------------

def smooth_light(lum, conf, sigma):
    """Свет поверхности без мелочей; за тюлем — продолжение соседнего."""
    near = masked_blur(lum, conf, sigma)
    far = masked_blur(lum, conf, 40)
    den = ndimage.gaussian_filter(conf, sigma)
    return np.where(den > 0.3, near, far)


def soft_clip(x):
    knee = 232.0
    over = x > knee
    x = x.copy()
    x[over] = knee + (255 - knee) * np.tanh((x[over] - knee) / (255 - knee))
    return x


def render(rgb, region_masks, region, spec, uv):
    """Слой поверхности.

    Было: old = цвет поверхности × свет. Станет: new = цвет или узор × свет.
    Пиксель = исходный + видимость × (new − old): чистая стена получает новый
    цвет со всеми своими оттенками и волокнами, тюль — новый оттенок сквозь
    себя, рама и карниз не меняются. У узора исходная фактура (волокна, швы
    досок) убирается — остаётся только свет."""
    poly, vis = region_masks[region]
    lum = luminance(rgb)
    conf = ((poly > 0.99) & (vis > 0.95)).astype(np.float64)
    ref_rgb = np.median(rgb[conf > 0], axis=0)
    ref = luminance(ref_rgb[None, :])[0]
    light = smooth_light(lum, conf, 6 if region == 'floor' else 3) / ref
    old = ref_rgb[None, None, :] * light[..., None]
    solid = np.clip((vis - 0.7) / 0.3, 0, 1)[..., None]
    if spec[0] == 'color':
        color = hex_rgb(spec[1])[None, None, :]
        new = color * light[..., None]
        # Чистая поверхность: новый цвет × яркость пикселя — волокна, тени и
        # пятна солнца остаются, но уже в новом цвете.
        opaque = color * (lum / ref)[..., None]
    else:
        tile = load_tile(spec[1])
        if tile is None:
            return None
        u, v, foot = uv
        new = sample(tile, u, v, spec[2], foot) * light[..., None]
        opaque = new
    # Тюль: исходный пиксель + разница «стало − было» по мере видимости.
    sheer = rgb + vis[..., None] * (new - old)
    out = solid * opaque + (1 - solid) * sheer
    out = soft_clip(out)
    alpha = (poly * np.clip(vis * 4, 0, 1) * 255).round().astype(np.uint8)
    layer = np.dstack([np.clip(out, 0, 255).round().astype(np.uint8), alpha])
    return Image.fromarray(layer, 'RGBA')


def swatch(spec, size=160):
    if spec[0] == 'color':
        return Image.new('RGB', (size, size), tuple(int(c) for c in hex_rgb(spec[1])))
    tile = load_tile(spec[1])
    if tile is None:
        return None
    n = tile.shape[0]
    # Образец — кусок плитки примерно в том масштабе, что на стене.
    crop = Image.fromarray(tile).crop((0, 0, n // 2, n // 2))
    return crop.resize((size, size), Image.LANCZOS)


def current_swatch(rgb, mask, size=160):
    """Образец нынешней стены или пола — кусок самой картинки."""
    ys, xs = np.nonzero(mask > 0.99)
    cy, cx = int(np.median(ys)), int(np.median(xs))
    if cx + size > W:
        cx = W - size
    crop = rgb[cy:cy + size, cx:cx + size].astype(np.uint8)
    return Image.fromarray(crop).resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview', help='папка для полных кадров с наложением')
    ap.add_argument('--only', help='только эти id через запятую')
    args = ap.parse_args()
    only = set(args.only.split(',')) if args.only else None

    rgb = np.asarray(Image.open(BASE).convert('RGB'), dtype=np.float64)
    region_masks = masks(rgb)
    wall = region_masks['wall'][0] * region_masks['wall'][1]
    floor = region_masks['floor'][0] * region_masks['floor'][1]
    uv = {'wall': wall_uv(), 'floor': floor_uv()}
    for d in ('walls', 'floors', 'swatches'):
        (OUT / d).mkdir(parents=True, exist_ok=True)
    preview = pathlib.Path(args.preview) if args.preview else None
    if preview:
        preview.mkdir(parents=True, exist_ok=True)
        Image.fromarray(np.dstack([rgb.astype(np.uint8),
                                   (np.maximum(wall, floor) * 255).astype(np.uint8)]),
                        'RGBA').save(preview / 'masks.png')

    for item, region in CURRENT.items():
        if only and item not in only:
            continue
        current_swatch(rgb, wall if region == 'wall' else floor).save(
            OUT / 'swatches' / f'{item}.webp', quality=88)

    base_img = Image.fromarray(rgb.astype(np.uint8)).convert('RGBA')
    for region, table, mask, folder in (('wall', WALLS, wall, 'walls'),
                                        ('floor', FLOORS, floor, 'floors')):
        for item, spec in table.items():
            if only and item not in only:
                continue
            layer = render(rgb, region_masks, region, spec, uv[region])
            if layer is None:
                print(f'{item:16s} нет образца {spec[1]} — пропуск')
                continue
            path = OUT / folder / f'{item}.webp'
            layer.save(path, quality=86, method=6)
            swatch(spec).save(OUT / 'swatches' / f'{item}.webp', quality=88)
            print(f'{item:16s} {path.stat().st_size / 1024:6.0f} КБ')
            if preview:
                Image.alpha_composite(base_img, layer).convert('RGB').save(
                    preview / f'{item}.jpg', quality=88)


if __name__ == '__main__':
    main()
