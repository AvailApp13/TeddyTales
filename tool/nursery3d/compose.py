"""Слои игровой из рендера Blender (tool/nursery3d/scene.py).

Свет стен и пола посчитан с белым альбедо, поэтому любой цвет или узор —
это цвет × свет. Отделка, потолок, вид за окном и тюль берутся из рендера
как есть и лежат поверх. Порядок в приложении (снизу вверх):

    стена (непрозрачная, на весь кадр) → пол → отделка → тюль → мебель.

Альфа пола делится на «сколько осталось после отделки»: в пикселе на краю
плинтуса пол и плинтус делят его ровно по покрытию, без серой каймы.

Запуск:  python tool/nursery3d/compose.py --render <папка рендера>
             --out <папка> [--trial]
--trial — пробная сборка «как сейчас»: розовые стены и светлое дерево, плюс
кадр сравнения с нынешней картинкой.
"""

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import exr  # noqa: E402
import scene as room  # noqa: E402

CORNER_U = 279.0


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb8(lin):
    # Мягкое плечо вместо обрезки: солнечные пятна не выгорают пятном.
    knee = 0.85
    x = np.clip(lin, 0, None)
    over = x > knee
    x = x.copy()
    x[over] = knee + (1 - knee) * np.tanh((x[over] - knee) / (1 - knee))
    return (np.clip(exr.to_srgb(x), 0, 1) * 255 + 0.5).astype(np.uint8)


def load_mask(path, shape):
    im = Image.open(path)
    a = np.asarray(im, dtype=np.float64)
    alpha = a[..., 3] / (65535.0 if a.max() > 255 else 255.0)
    if alpha.shape != shape:
        alpha = np.asarray(Image.fromarray(alpha.astype(np.float32)).resize(
            (shape[1], shape[0]), Image.BILINEAR))
    return alpha


class Room:
    def __init__(self, render_dir):
        d = pathlib.Path(render_dir)
        light = exr.load(d / 'light.exr')
        self.h, self.w = light.shape[:2]
        self.scale = self.w / room.W_PX
        self.rgb = light[..., :3].astype(np.float64)
        self.mask = {c: load_mask(d / f'mask_{c}.png', (self.h, self.w))
                     for c in ('walls', 'floor', 'trim', 'ceiling', 'view')}
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        self.u = (xx + 0.5) / self.scale
        self.v = (yy + 0.5) / self.scale
        back = (self.mask['walls'] > 0.99) & (self.u > CORNER_U + 4)
        # Баланс белого: обычный свет на задней стене — нейтральный, чтобы
        # белая отделка была белой, а стена — ровно выбранного цвета. Тепло
        # остаётся там, где свет теплее среднего, — в солнечных пятнах.
        m = np.median(self.rgb[back], axis=0)
        self.wb = room_lum(m[None, :])[0] / m
        self.rgb = self.rgb * self.wb
        # Свет на белом (альбедо 1): рендер считался с NEUTRAL.
        self.light = self.rgb / room.NEUTRAL
        # Экспозиция: белая стена при обычном свете задней стены — белая.
        self.exposure = 1.0 / np.median(room_lum(self.light[back]))
        self.curtains = exr.load(d / 'curtains.exr') if (d / 'curtains.exr').exists() else None

    # --- координаты на поверхностях (метры) -------------------------------

    def floor_xy(self, su=0.0, sv=0.0):
        """Точка пола под пикселем: X поперёк, Y вглубь от камеры."""
        u = self.u + su / self.scale
        v = self.v + sv / self.scale
        dv = np.maximum(v - room.VP[1], 0.5)
        y = room.F_PX * room.EYE / dv
        x = (u - room.VP[0]) * y / room.F_PX
        return x, y

    def wall_uv(self, su=0.0, sv=0.0):
        """Точка стены: s — по стене, z — высота. Задняя стена: s = X,
        левая: s = D − Y (от угла к окну)."""
        u = self.u + su / self.scale
        v = self.v + sv / self.scale
        left = u < CORNER_U
        # Задняя стена на глубине D.
        s_back = (u - room.VP[0]) * room.D / room.F_PX
        z_back = room.EYE + (room.VP[1] - v) * room.D / room.F_PX
        # Левая стена x = −WL: глубина по столбцу.
        y_left = room.F_PX * room.WL / np.maximum(room.VP[0] - u, 1e-3)
        z_left = room.EYE + (room.VP[1] - v) * y_left / room.F_PX
        s = np.where(left, -room.WL - (room.D - y_left), s_back)
        z = np.where(left, z_left, z_back)
        return s, z

    # --- слои --------------------------------------------------------------

    def above_floor(self):
        return np.clip(self.mask['trim'] + self.mask['ceiling'] + self.mask['view'], 0, 1)

    def wall_layer(self, albedo_fn):
        """Непрозрачная стена на весь кадр: альбедо × свет."""
        acc = 0
        for su, sv in ((-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)):
            s, z = self.wall_uv(su, sv)
            acc = acc + albedo_fn(s, z)
        albedo = acc / 4
        lin = albedo * self.light * self.exposure
        rgb = lin_to_srgb8(lin)
        return Image.fromarray(np.dstack([rgb, np.full(rgb.shape[:2], 255, np.uint8)]), 'RGBA')

    def floor_layer(self, albedo_fn, target=None):
        acc = 0
        for su, sv in ((-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)):
            x, y = self.floor_xy(su, sv)
            acc = acc + albedo_fn(x, y)
        albedo = acc / 4
        lin = albedo * self.light * self.exposure
        rgb = lin_to_srgb8(lin)
        cov = self.mask['floor']
        alpha = np.clip(cov / np.maximum(1 - self.above_floor(), 1e-3), 0, 1)
        alpha[cov < 0.002] = 0
        return Image.fromarray(np.dstack([rgb, (alpha * 255 + 0.5).astype(np.uint8)]), 'RGBA')

    def trim_layer(self):
        """Отделка, потолок и вид за окном — из рендера как есть."""
        cov = self.above_floor()
        lin = self.rgb * self.exposure
        rgb = lin_to_srgb8(lin)
        return Image.fromarray(np.dstack([rgb, (cov * 255 + 0.5).astype(np.uint8)]), 'RGBA')

    def curtain_layer(self):
        c = self.curtains
        a = np.clip(c[..., 3], 0, 1)
        lin = c[..., :3] / np.maximum(a, 1e-4)[..., None] * self.exposure * self.wb
        rgb = lin_to_srgb8(lin)
        return Image.fromarray(np.dstack([rgb, (a * 255 + 0.5).astype(np.uint8)]), 'RGBA')

    def median_floor_light(self):
        f = (self.mask['floor'] > 0.99)
        lum = room_lum(self.light[f] * self.exposure)
        return np.median(lum)


def room_lum(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


# --- материалы ---------------------------------------------------------------

def flat(color_srgb):
    lin = srgb_to_lin(color_srgb)

    def fn(s, z):
        return np.broadcast_to(lin, s.shape + (3,))
    return fn


def wood_planks(color_srgb, plank=0.19, length=2.4, seed=7):
    """Доски светлого дерева: стыки вразбежку, мягкие волокна, тонкие швы."""
    base = srgb_to_lin(color_srgb)
    rng = np.random.default_rng(seed)
    offs = rng.uniform(0, length, 512)
    tint = rng.normal(0, 0.008, (512, 3)) + rng.normal(0, 0.025, (512, 1))

    def fn(x, y):
        i = np.floor(x / plank).astype(int)
        k = np.mod(i, 512)
        fx = x / plank - i
        o = offs[k]
        fy = np.mod(y + o, length) / length
        grain = (0.016 * np.sin(2 * np.pi * (fx * 7.0 + 0.35 * np.sin(y * 2.1 + i)))
                 + 0.010 * np.sin(2 * np.pi * (fx * 19.0 + y * 0.9 + i * 0.37)))
        # Вдали волокна сливаются — гасим их, чтобы не было ряби.
        grain = grain * np.clip(1.6 - y / 3.0, 0.15, 1.0)
        shade = 1 + tint[k] + grain[..., None]
        # Швы — мягкие: тонкая тень, а не чёрная линия.
        seam = np.exp(-np.minimum(fx, 1 - fx) / 0.008)
        joint = np.exp(-np.minimum(fy, 1 - fy) * length / 0.006)
        dark = (1 - 0.15 * np.maximum(seam, joint))[..., None]
        return base * shade * dark
    return fn


def tile(path, metres):
    """Бесшовный образец (обои, особый пол): плитка `metres` м по стороне."""
    img = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)
    lin = srgb_to_lin(img)
    h, w = lin.shape[:2]

    def fn(s, z):
        fx = np.mod(s / metres, 1.0) * w
        fy = np.mod(-z / metres, 1.0) * h
        x0 = np.floor(fx).astype(int) % w
        y0 = np.floor(fy).astype(int) % h
        x1 = (x0 + 1) % w
        y1 = (y0 + 1) % h
        ax = (fx - np.floor(fx))[..., None]
        ay = (fy - np.floor(fy))[..., None]
        return ((lin[y0, x0] * (1 - ax) + lin[y0, x1] * ax) * (1 - ay)
                + (lin[y1, x0] * (1 - ax) + lin[y1, x1] * ax) * ay)
    return fn


def stack(layers):
    comp = layers[0]
    for lay in layers[1:]:
        comp = Image.alpha_composite(comp, lay)
    return comp.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--render', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--trial', action='store_true')
    ap.add_argument('--flat', help='куда сохранить собранную комнату (jpg) для приложения')
    ap.add_argument('--demo', action='store_true',
                    help='несколько стен и полов на одних слоях — для показа')
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    r = Room(args.render)
    print(f'экспозиция {r.exposure:.3f}, свет пола {r.median_floor_light():.3f}')

    if args.trial:
        # Цвета «как сейчас» — медианы нынешней картинки.
        old = np.asarray(Image.open(room_image()).convert('RGB'), dtype=np.float64)
        wall_t = np.median(old[300:820, 350:900].reshape(-1, 3), axis=0)
        floor_px = old[1100:1600, 650:930].reshape(-1, 3)
        floor_t = np.median(floor_px, axis=0)
        print('цвет стены', wall_t, 'цвет пола', floor_t)
        wall = r.wall_layer(flat(wall_t))
        # Альбедо пола — так, чтобы в обычном свете пол был цвета картинки.
        fl = r.median_floor_light()
        floor = r.floor_layer(wood_planks(srgb_lin_to_srgb8(srgb_to_lin(floor_t) / fl)))
        trim = r.trim_layer()
        layers = [wall, floor, trim]
        if r.curtains is not None:
            layers.append(r.curtain_layer())
        comp = layers[0]
        for lay in layers[1:]:
            comp = Image.alpha_composite(comp, lay)
        comp = comp.convert('RGB')
        comp.save(out / 'trial.png')
        if args.flat:
            comp.save(args.flat, quality=92, optimize=True, progressive=True)
            top = np.asarray(comp, dtype=np.float64)[:6].reshape(-1, 3).mean(axis=0)
            print('верх кадра (для RoomCeiling):', '0xFF%02X%02X%02X' % tuple(int(round(c)) for c in top))
        for name, lay in zip(('wall', 'floor', 'trim', 'curtains'), layers):
            lay.save(out / f'layer_{name}.png')
        oldim = Image.open(room_image()).convert('RGB').resize(comp.size)
        sheet = Image.new('RGB', (comp.width * 2 + 20, comp.height), 'white')
        sheet.paste(oldim, (0, 0))
        sheet.paste(comp, (comp.width + 20, 0))
        sheet.save(out / 'compare.jpg', quality=90)

    if args.demo:
        demo(r, out)


def srgb_lin_to_srgb8(lin):
    return lin_to_srgb8(np.asarray(lin, dtype=np.float64))


def room_image():
    return pathlib.Path(__file__).resolve().parents[2] / 'assets/rooms/nursery.jpg'


def demo(r, out):
    root = pathlib.Path(__file__).resolve().parents[2]
    tiles = root / 'tool/surface_tiles'
    trim = r.trim_layer()
    curtains = r.curtain_layer() if r.curtains is not None else None
    fl = r.median_floor_light()

    def floor(color):
        return r.floor_layer(wood_planks(srgb_lin_to_srgb8(srgb_to_lin(color) / fl)))

    variants = [
        ('Мятная + медовое дерево', r.wall_layer(flat((191, 220, 207))), floor((217, 180, 140))),
        ('Обои «Облака» + тёмный дуб', r.wall_layer(tile(tiles / 'wall-clouds.webp', 0.95)),
         floor((156, 118, 86))),
        ('Лавандовая + беленый дуб', r.wall_layer(flat((203, 191, 221))), floor((241, 227, 205))),
        ('Обои «Лесные звери» + светлое дерево', r.wall_layer(tile(tiles / 'wall-forest.webp', 1.15)),
         floor((236, 186, 148))),
    ]
    shots = []
    for name, wall, fl_layer in variants:
        layers = [wall, fl_layer, trim] + ([curtains] if curtains else [])
        img = stack(layers)
        img.save(out / f'demo_{len(shots)}.jpg', quality=90)
        shots.append(img)
    w, h = shots[0].size
    sheet = Image.new('RGB', (w * len(shots) + 20 * (len(shots) - 1), h), 'white')
    for i, im in enumerate(shots):
        sheet.paste(im, (i * (w + 20), 0))
    sheet.save(out / 'demo.jpg', quality=88)


if __name__ == '__main__':
    main()
