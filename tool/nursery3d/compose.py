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

    def floor_layer(self, albedo_fn):
        acc = 0
        for su, sv in ((-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)):
            x, y = self.floor_xy(su, sv)
            acc = acc + albedo_fn(x, y)
        albedo = acc / 4
        lin = albedo * self.light * self.exposure
        # Солнце на светлом полу не выгорает в белое: верх мягко прижат.
        knee, top = 0.68, 0.30
        over = lin > knee
        lin[over] = knee + top * np.tanh((lin[over] - knee) / top)
        rgb = lin_to_srgb8(lin)
        cov = self.mask['floor']
        alpha = np.clip(cov / np.maximum(1 - self.above_floor(), 1e-3), 0, 1)
        alpha[cov < 0.002] = 0
        return Image.fromarray(np.dstack([rgb, (alpha * 255 + 0.5).astype(np.uint8)]), 'RGBA')

    def trim_layer(self):
        """Отделка, потолок и вид за окном — из рендера как есть.

        Редкие тёмные точки на стыках брусков рамы (куда свет не доходит)
        заменяются средним из соседних светлых пикселей."""
        cov = self.above_floor()
        lin = self.rgb * self.exposure
        dark = (room_lum(lin) < 0.08) & (self.mask['trim'] > 0.5)
        if dark.any():
            ys, xs = np.nonzero(dark)
            fixed = lin.copy()
            for y, x in zip(ys, xs):
                y0, y1 = max(y - 3, 0), min(y + 4, self.h)
                x0, x1 = max(x - 3, 0), min(x + 4, self.w)
                patch = lin[y0:y1, x0:x1].reshape(-1, 3)
                ok = room_lum(patch) >= 0.08
                if ok.any():
                    fixed[y, x] = patch[ok].mean(axis=0)
            lin = fixed
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


def wood_planks(albedo, plank=0.19, length=2.4, seed=7, grain_amp=1.0,
                seam_dark=0.15, tint_sd=0.025):
    """Доски: стыки вразбежку, мягкие волокна, тонкие швы. albedo — линейный."""
    base = np.asarray(albedo, dtype=np.float64)
    rng = np.random.default_rng(seed)
    offs = rng.uniform(0, length, 512)
    tint = rng.normal(0, tint_sd * 0.3, (512, 3)) + rng.normal(0, tint_sd, (512, 1))

    def fn(x, y):
        i = np.floor(x / plank).astype(int)
        k = np.mod(i, 512)
        fx = x / plank - i
        o = offs[k]
        fy = np.mod(y + o, length) / length
        grain = grain_amp * (
            0.016 * np.sin(2 * np.pi * (fx * 7.0 + 0.35 * np.sin(y * 2.1 + i)))
            + 0.010 * np.sin(2 * np.pi * (fx * 19.0 + y * 0.9 + i * 0.37)))
        # Вдали волокна сливаются — гасим их, чтобы не было ряби.
        grain = grain * np.clip(1.6 - y / 3.0, 0.15, 1.0)
        shade = 1 + tint[k] + grain[..., None]
        # Швы — мягкие: тонкая тень, а не чёрная линия.
        seam = np.exp(-np.minimum(fx, 1 - fx) * plank / 0.0015)
        joint = np.exp(-np.minimum(fy, 1 - fy) * length / 0.0012)
        dark = (1 - seam_dark * np.maximum(seam, joint))[..., None]
        return base * shade * dark
    return fn


def checker(a1, a2, size=0.30, grout=0.0035, grout_albedo=None):
    """Плитка «шахматка»: квадраты двух цветов, тонкие швы."""
    a1, a2 = np.asarray(a1), np.asarray(a2)
    g = np.asarray(grout_albedo) if grout_albedo is not None else (a1 + a2) / 2 * 0.93

    def fn(x, y):
        i = np.floor(x / size).astype(int)
        j = np.floor(y / size).astype(int)
        fx = x / size - i
        fy = y / size - j
        col = np.where(((i + j) % 2 == 0)[..., None], a1, a2)
        d = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)) * size
        line = np.clip(1 - d / grout, 0, 1)[..., None]
        return col * (1 - line) + g * line
    return fn


def carpet(albedo, seed=11):
    """Ковролин: ровный цвет, мелкий ворс и едва заметные разводы."""
    base = np.asarray(albedo, dtype=np.float64)
    rng = np.random.default_rng(seed)
    noise = rng.normal(0, 1, (256, 256))

    def fn(x, y):
        # Ворс — мелкое зерно, вдали сливается в ровный цвет.
        ix = (np.floor(x / 0.004).astype(int)) % 256
        iy = (np.floor(y / 0.004).astype(int)) % 256
        fade = np.clip(1.5 - y / 2.5, 0.0, 1.0)
        fibre = 0.035 * noise[iy, ix] * fade
        mottle = 0.012 * np.sin(x * 3.1 + np.sin(y * 1.7)) * np.sin(y * 2.3)
        return base * (1 + fibre + mottle)[..., None]
    return fn


def puzzle(albedos, size=0.6, seam=0.003, seed=3):
    """Мягкий пол-пазл: квадраты 60 см с замками-выступами, пастельные цвета."""
    cols = np.stack([np.asarray(c, dtype=np.float64) for c in albedos])
    rng = np.random.default_rng(seed)
    foam = rng.normal(0, 1, (256, 256))
    r2, dl = 0.075 ** 2, 0.05      # выступ: радиус и вынос за грань, доли стороны

    def own(X, Y):
        """Чей кусок под точкой (в долях стороны) — с учётом выступов."""
        i, j = np.floor(X).astype(int), np.floor(Y).astype(int)
        oi, oj = i.copy(), j.copy()
        # Правая грань плитки i; направление выступа чередуется.
        sgn = np.where((i + j) % 2 == 0, 1, -1)
        c = (X - (i + 1 + sgn * dl)) ** 2 + (Y - (j + 0.5)) ** 2 < r2
        oi = np.where(c, np.where(sgn > 0, i, i + 1), oi)
        oj = np.where(c, j, oj)
        # Левая грань — это правая грань плитки i − 1.
        sgn = np.where((i - 1 + j) % 2 == 0, 1, -1)
        c = (X - (i + sgn * dl)) ** 2 + (Y - (j + 0.5)) ** 2 < r2
        oi = np.where(c, np.where(sgn > 0, i - 1, i), oi)
        oj = np.where(c, j, oj)
        # Дальняя грань плитки j и ближняя (дальняя у j − 1).
        sgn = np.where((i + j) % 2 == 1, 1, -1)
        c = (X - (i + 0.5)) ** 2 + (Y - (j + 1 + sgn * dl)) ** 2 < r2
        oj = np.where(c, np.where(sgn > 0, j, j + 1), oj)
        oi = np.where(c, i, oi)
        sgn = np.where((i + j - 1) % 2 == 1, 1, -1)
        c = (X - (i + 0.5)) ** 2 + (Y - (j + sgn * dl)) ** 2 < r2
        oj = np.where(c, np.where(sgn > 0, j - 1, j), oj)
        oi = np.where(c, i, oi)
        return oi, oj

    def fn(x, y):
        X, Y = x / size, y / size
        oi, oj = own(X, Y)
        col = cols[np.mod(oi + 2 * oj, len(cols))]
        e = seam / size
        ai, aj = own(X + e, Y)
        bi, bj = own(X, Y + e)
        edge = (ai != oi) | (aj != oj) | (bi != oi) | (bj != oj)
        ix = (np.floor(x / 0.003).astype(int)) % 256
        iy = (np.floor(y / 0.003).astype(int)) % 256
        fade = np.clip(1.5 - y / 2.5, 0.0, 1.0)
        tex = 1 + 0.02 * foam[iy, ix] * fade
        return col * tex[..., None] * np.where(edge, 0.84, 1.0)[..., None]
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


# --- 10 стен и 10 полов (docs/room-surfaces-answers.md) -----------------------
# id — как в lib/game/shop_items.dart. Цвет — каким вариант выглядит в
# обычном свете комнаты (код палитры из анкеты); узор — образец из
# tool/surface_tiles и сторона его плитки на стене в метрах.

def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


WALLS = {
    'wall_rose': ('flat', '#E2A393'),       # С1, нынешняя
    'wall_cream': ('flat', '#EFE0C8'),      # С5
    'wall_mint': ('flat', '#BFDCCF'),       # С7
    'wall_dots': ('tile', 'wall-dots.webp', 0.80),
    'wall_forest': ('tile', 'wall-forest.webp', 1.60),
    'wall_clouds': ('tile', 'wall-clouds.webp', 1.15),
    'wall_sprigs': ('tile', 'wall-sprigs.webp', 0.70),
    'wall_bunnies': ('tile', 'wall-bunnies.webp', 0.75),
    'wall_lavender': ('flat', '#CBBFDD'),   # С6
    'wall_sky': ('flat', '#B8CCE0'),        # С3
}

FLOORS = {
    'floor_wood': ('planks', '#EABA95', {}),           # П1, нынешний
    'floor_honey': ('planks', '#D9B48C', {}),          # П3
    'floor_greige': ('planks', '#E6D6C3', {}),         # П5
    # Ламинат широкой доской — светлый, «дорогое дерево».
    'floor_laminate': ('planks', '#E8D3B4', dict(plank=0.27, length=2.2, grain_amp=1.6,
                                                 seam_dark=0.20, tint_sd=0.015)),
    'floor_dark_oak': ('planks', '#9C7656', dict(grain_amp=2.0, seam_dark=0.25, tint_sd=0.035)),  # П6
    'floor_checker': ('checker', '#F3EBDD', '#EBCFCB'),  # кремовая с пудровой
    'floor_carpet': ('carpet', '#E3D8CA'),
    'floor_puzzle': ('puzzle', ['#BFE3D0', '#F3C9D0', '#F6E3A6', '#BFD9F0']),
    'floor_powder': ('planks', '#EBD8D2', {}),         # П7
    'floor_light': ('planks', '#F1E3CD', {}),          # П2, беленый дуб
}


def wall_material(spec, tiles):
    if spec[0] == 'flat':
        return flat(hexrgb(spec[1]))
    return tile(tiles / spec[1], spec[2])


def floor_material(spec, fl):
    """Альбедо пола — так, чтобы в обычном свете пол был цвета палитры."""
    def cal(h):
        return srgb_to_lin(hexrgb(h)) / fl
    kind = spec[0]
    if kind == 'planks':
        return wood_planks(cal(spec[1]), **spec[2])
    if kind == 'checker':
        return checker(cal(spec[1]), cal(spec[2]))
    if kind == 'carpet':
        return carpet(cal(spec[1]))
    return puzzle([cal(h) for h in spec[1]])


def build(r, root):
    """Все слои игровой — в assets/rooms/nursery/ — и картинка по умолчанию."""
    from PIL import ImageFilter
    base = root / 'assets/rooms/nursery'
    tiles = root / 'tool/surface_tiles'
    for d in ('walls', 'floors', 'swatches'):
        (base / d).mkdir(parents=True, exist_ok=True)
    trim = r.trim_layer()
    trim.save(base / 'trim.webp', quality=90, method=6)
    curt = r.curtain_layer()
    curt.save(base / 'curtains.webp', quality=90, method=6)
    fl = r.median_floor_light()

    # Стена непрозрачная, но вне стен (под полом, потолком, окном) её не
    # видно — там ровная заливка: файл в разы меньше.
    near = Image.fromarray(((r.mask['walls'] > 0.002) * 255).astype(np.uint8))
    near = np.asarray(near.filter(ImageFilter.MaxFilter(9))) > 0
    walls, floors = {}, {}
    for wid, spec in WALLS.items():
        a = np.asarray(r.wall_layer(wall_material(spec, tiles)))[..., :3].copy()
        a[~near] = np.median(a[r.mask['walls'] > 0.99], axis=0).astype(np.uint8)
        img = Image.fromarray(a, 'RGB')
        img.save(base / 'walls' / f'{wid}.webp', quality=88, method=6)
        walls[wid] = img.convert('RGBA')
        print(f'{wid:16s} {(base / "walls" / f"{wid}.webp").stat().st_size // 1024:5d} КБ')
    for fid, spec in FLOORS.items():
        lay = r.floor_layer(floor_material(spec, fl))
        lay.save(base / 'floors' / f'{fid}.webp', quality=88, method=6)
        floors[fid] = lay
        print(f'{fid:16s} {(base / "floors" / f"{fid}.webp").stat().st_size // 1024:5d} КБ')

    default = stack([walls['wall_rose'], floors['floor_wood'], trim, curt])
    default.save(root / 'assets/rooms/nursery3d.jpg', quality=92, optimize=True,
                 progressive=True)

    shots = []
    for wid in WALLS:
        comp = stack([walls[wid], floors['floor_wood'], trim, curt])
        comp.crop((520, 360, 840, 680)).resize((160, 160), Image.LANCZOS).save(
            base / 'swatches' / f'{wid}.webp', quality=88)
        shots.append(comp)
    for fid in FLOORS:
        comp = stack([walls['wall_rose'], floors[fid], trim, curt])
        comp.crop((620, 1280, 940, 1600)).resize((160, 160), Image.LANCZOS).save(
            base / 'swatches' / f'{fid}.webp', quality=88)
        shots.append(comp)
    return shots


def contact_sheet(shots, path, cols=5, w=235):
    h = int(w * shots[0].height / shots[0].width)
    rows = (len(shots) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * (w + 8), rows * (h + 8)), 'white')
    for k, im in enumerate(shots):
        sheet.paste(im.resize((w, h), Image.LANCZOS), ((k % cols) * (w + 8), (k // cols) * (h + 8)))
    sheet.save(path, quality=88)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--render', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--trial', action='store_true')
    ap.add_argument('--flat', help='куда сохранить собранную комнату (jpg) для приложения')
    ap.add_argument('--demo', action='store_true',
                    help='несколько стен и полов на одних слоях — для показа')
    ap.add_argument('--build', action='store_true',
                    help='все 10 стен и 10 полов, отделка и тюль — в assets/rooms/nursery')
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
        floor = r.floor_layer(wood_planks(srgb_to_lin(floor_t) / fl))
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

    if args.build:
        shots = build(r, pathlib.Path(__file__).resolve().parents[2])
        contact_sheet(shots, out / 'all.jpg')


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
        return r.floor_layer(wood_planks(srgb_to_lin(color) / fl))

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
