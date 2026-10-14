"""Сборка девочки (JOY): риг мальчика с её слоями и мордочкой.

    python3 tool/rive/build_girl.py        # → assets/rive/bear_girl.riv

Заказчик 14.10: «второго героя нужно тоже так же анимировать». Исходник
Rive, скелет, веса и все движения — те же, что у мальчика (`build_bear.py`,
`rebuild_rig.py`): девочка совмещена с ним по глазам (`girl_face.py`), её
12 слоёв (`girl_layers.py`) встают на места его картинок (`girl_rig.py`).

Своё у девочки (здесь — поправки к модулям мальчика до сборки):
- уши на голове, капюшона нет: кости ушей — по её ушам, стыка с капюшоном
  нет (`pin`), из «сварок» швов остались только подмышки;
- бант — две кости петель от узла (`bow_lo`, `bow_up`), лента на макушке
  держится за голову; петли покачиваются с запаздыванием;
- юбка — подол на двух костях (`skirt_l`, `skirt_r`), чуть ходит за ногами;
- мордочка: нос на 8 px и рот на 13 px выше, чем у мальчика (глаза
  совпадают) — зоны мимики, кости рта и носа, ротик покоя — по её мордочке;
- выражения: её плитки Higgsfield (смех, зевок, закрытые глаза), где их ещё
  нет — плитки мальчика, сдвинутые к её носу (рты-линии — в цвет её
  стежка); удивление — пока её лицо покоя (⚠ ждёт плитки Higgsfield);
- ткань под капюшоном и расправленная складка кофты мальчика не нужны:
  её слои уже дорисованы с запасом.

Нужен Rive CLI (`docs/rive-bear.md`), numpy, scipy, Pillow, opencv, triangle.
"""
import math
import os
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))
GIRL = os.path.join(ROOT, 'assets_src/rive/girl')
OUT = os.path.join(ROOT, 'assets/rive/bear_girl.riv')

import faces  # noqa: E402
import mouth  # noqa: E402

# --- Плитки выражений -------------------------------------------------------
# Сдвиг плиток к её носу, px плитки. Мальчика — от его носа к её (по
# текстурам: середина носа x 166 → 171, низ носа 195 → 173). Её — от носа на
# плитке к носу на текстуре: Higgsfield в смехе и зевке поднимал лицо.
BOY_SHIFT = (5, -22)
GIRL_SHIFT = {'laugh': (1, 11), 'yawn': (1, 41), 'eyes_closed': (0, 0)}
LINES = ('sad', 'upset', 'sleepy', 'chew_closed')    # рты-линии мальчика
REST_MOUTH = (683, 1030, 25, 30)    # стёжка и «ножки» рта: эллипс для стирания
REST_Y = 1023                       # середина её ротика, px текстуры


def _shift(rgb, dx, dy):
    return ndimage.shift(rgb, (dy, dx, 0), order=1, mode='nearest')


def tiles_dir():
    """Папка плиток для `faces.py` и `mouth.py` (вместо `assets_src/rive/faces`)."""
    d = tempfile.mkdtemp(prefix='girl_faces_')
    for fn in os.listdir(faces.SRC):
        name = fn.rsplit('.', 1)[0]
        rgb = np.asarray(Image.open(os.path.join(faces.SRC, fn)).convert('RGB'), np.float64)
        rgb = _shift(rgb, *BOY_SHIFT)
        if name in LINES:      # коричневая линия мальчика → серый стежок девочки
            rgb = np.repeat(rgb.mean(2, keepdims=True), 3, 2)
        Image.fromarray(rgb.clip(0, 255).round().astype(np.uint8)).save(os.path.join(d, fn), quality=95)
    for name, (dx, dy) in GIRL_SHIFT.items():
        rgb = np.asarray(Image.open(os.path.join(GIRL, 'faces', f'{name}.webp')).convert('RGB'), np.float64)
        Image.fromarray(_shift(rgb, dx, dy).clip(0, 255).round().astype(np.uint8)).save(
            os.path.join(d, f'{name}.webp'), quality=95)
    # ⚠ ждёт плитки Higgsfield (дневной лимит 14.10): удивление — её лицо покоя
    head = Image.open(os.path.join(GIRL, 'layers', 'head.png')).convert('RGB')
    x0, y0 = faces.FRAME[0] + faces.BOX[0], faces.FRAME[1] + faces.BOX[1]
    head.crop((x0, y0, x0 + faces.BOX[2] - faces.BOX[0], y0 + faces.BOX[3] - faces.BOX[1])).save(
        os.path.join(d, 'surprised.webp'), quality=95)
    return d


TILES = tiles_dir()
faces.SRC = mouth.SRC = TILES
faces.OVERLAYS = [('blink', 'eyes_closed', faces.EYES),
                  ('surprised', 'surprised', faces.EYES)]
DY = BOY_SHIFT[1]
mouth.CAVITIES = {k: (pic, y0 + DY, y1 + DY, sig, shut)
                  for k, (pic, y0, y1, sig, shut) in mouth.CAVITIES.items()}
mouth.SHAPE_ROWS = (mouth.SHAPE_ROWS[0] + DY, mouth.SHAPE_ROWS[1] + DY)
mouth.REST = REST_MOUTH
mouth.CENTER_Y = round(mouth.TEX_O[1] + (REST_Y - mouth.TEX_O[3]) * mouth.TEX_K, 1)

import build_bear  # noqa: E402  (после поправок: скелет считает рты при импорте)
import crease  # noqa: E402
import girl_rig  # noqa: E402
import rebuild_rig as rr  # noqa: E402
import underpaint  # noqa: E402

# --- Скелет -------------------------------------------------------------------
# (родитель, начало, конец) в мире; None — от конца родителя
GIRL_BONES = {
    # уши на голове: от основания (чуть внутри головы) к кончику
    'ear_l1': ('head', (396, 292), (374, 279)),
    'ear_l2': ('ear_l1', None, (351, 265)),
    'ear_l3': ('ear_l2', None, (318, 245)),
    'ear_r1': ('head', (626, 258), (650, 249)),
    'ear_r2': ('ear_r1', None, (675, 239)),
    'ear_r3': ('ear_r2', None, (703, 228)),
    # нос и рот — по её мордочке
    'mouth': ('face', (516, 495), (516, 485)),
    'mouth_l': ('face', (507, 506), (507, 496)),
    'mouth_r': ('face', (525, 506), (525, 496)),
    'chin': ('face', (516, 516), (516, 506)),
    'muzzle': ('face', (516, 460), (516, 450)),
    'nose': ('face', (516, 460), (516, 450)),
    'jaw': ('face', (516, 530), (516, 520)),
}
KNOT = (628, 272)                       # узел банта
rr.CHAIN = [(n, *GIRL_BONES[n]) if n in GIRL_BONES else (n, p, s, e) for n, p, s, e in rr.CHAIN]
rr.CHAIN += [
    ('bow_lo', 'head', KNOT, (733, 373)),       # нижняя петля и хвост
    ('bow_up', 'head', KNOT, (565, 176)),       # верхняя петля
    ('skirt_l', 'hips', (470, 752), (330, 925)),
    ('skirt_r', 'hips', (566, 752), (706, 925)),
]

ZONES = {'muzzle': (516, 462, 34, 26), 'nose': (516, 460, 26, 18),
         'mouth': (516, 495, 11, 10), 'mouth_l': (507, 506, 11, 10), 'mouth_r': (525, 506, 11, 10),
         'chin': (516, 516, 40, 18), 'jaw': (516, 532, 90, 24)}
rr.FACE_ZONES = [(b, *ZONES[b]) if b in ZONES else (b, x, y, rx, ry) for b, x, y, rx, ry in rr.FACE_ZONES]
rr.FACE_REFINE = [(516, 497, 20, 2), (516, 512, 12, 1), (516, 462, 30, 1),
                  (457, 441, 26, 1), (568, 441, 26, 1), (457, 391, 26, 1), (568, 391, 26, 1)]

# швы: только подмышки (рукав с кофтой); ушей с капюшоном нет
rr.SEAMS = [
    ([(349, 694), (349, 708)], rr._SHIRT + ('sleeve_left_img',), ('shirt_img', 'sleeve_left_img')),
    ([(682, 692), (682, 706)], rr._SHIRT + ('sleeve_right_img',), ('shirt_img', 'sleeve_right_img')),
]
rr.pin = lambda w, layer, x, y, r0=4, r1=62: w
# шов реглана: половина ширины кофты от оси по высоте (замер по рукавам;
# выше 540 — под головой, продолжение к шее)
rr.SEAM = [(480, 92), (500, 98), (520, 104), (540, 113), (560, 126), (580, 138), (600, 141),
           (620, 143), (640, 146), (660, 149), (680, 157), (700, 167)]
# низ головы над кофтой (воротник): чем ниже, тем ближе к середине
_COLLAR_X = [330, 360, 390, 420, 450, 480, 510, 540, 570, 600, 630, 660, 690]
_COLLAR_Y = [470, 484.3, 512.6, 530.9, 539.1, 544.1, 546.6, 547.9, 542.2, 533.4, 519.6, 488.1, 470]
rr.collar_y = lambda x: float(np.interp(x, _COLLAR_X, _COLLAR_Y))


def bow_weights(x, y, B):
    """Лента на макушке и узел — за головой; петли — за своими костями,
    тем сильнее, чем дальше от узла."""
    if x < 535:
        return {'head': 1.0}

    def seg(name):
        a, b = B[name]['start'], B[name]['end']
        t = min(1.0, max(0.0, rr.along((x, y), a, b)))
        return math.hypot(x - a[0] - t * (b[0] - a[0]), y - a[1] - t * (b[1] - a[1])), rr.along((x, y), a, b)

    d_lo, t_lo = seg('bow_lo')
    d_up, t_up = seg('bow_up')
    if d_lo <= d_up:
        bone, k = 'bow_lo', rr.smooth(0.12, 0.7, t_lo)
    else:
        bone, k = 'bow_up', rr.smooth(0.15, 0.7, t_up) * rr.smooth(535, 565, x)
    if k <= 0:
        return {'head': 1.0}
    return {b: v for b, v in (('head', 1 - k), (bone, k)) if v > 1e-4}


def skirt_weights(x, y):
    """Пояс — за тазом, подол — на своих костях, немного — за ногами (топот
    приподнимает подол). Не больше четырёх костей на точку."""
    k = rr.smooth(748, 905, y)
    s = rr.smooth(445, 590, x)
    leg_l = 0.25 * k * (1 - rr.smooth(0.2, 0.45, s))
    leg_r = 0.25 * k * rr.smooth(0.55, 0.8, s)
    w = {'hips': 1 - 0.75 * k - leg_l - leg_r, 'skirt_l': 0.75 * k * (1 - s), 'skirt_r': 0.75 * k * s,
         'leg_l': leg_l, 'leg_r': leg_r}
    return {b: v for b, v in w.items() if v > 1e-4}


_weights_for = rr._weights_for


def girl_weights(layer, x, y, B):
    if layer == 'bow_img':
        return bow_weights(x, y, B)
    if layer == 'shorts_img':
        return skirt_weights(x, y)
    return _weights_for(layer, x, y, B)


rr._weights_for = girl_weights

_breathing = rr.breathing


def girl_breathing(B, rest, period=rr.PERIOD, amp=1.0):
    """Покой мальчика + петли банта догоняют голову, подол дышит с тазом."""
    ch = _breathing(B, rest, period, amp)

    def wv(t, lag=0.0):
        return amp * rr.wave(t, lag, period)

    def look(t):
        return [sum(v[i] * rr.pulse(t, a, b, 40) for a, b, *v in rr.LOOKS) for i in range(3)]

    def add(bone, fn):
        ch[(bone, 15)] = [(t, rest[bone]['rotation'] + fn(t)) for t in range(0, rr.DUR + 1, 4)]

    add('bow_lo', lambda t: 0.035 * wv(t, 30) + 0.025 * math.sin(2 * math.pi * (t - 40) / rr.SWAY)
        + 0.05 * look(t - 14)[2])
    add('bow_up', lambda t: -0.03 * wv(t, 36) - 0.02 * math.sin(2 * math.pi * (t - 50) / rr.SWAY)
        - 0.04 * look(t - 16)[2])
    add('skirt_l', lambda t: 0.012 * wv(t, 16))
    add('skirt_r', lambda t: -0.012 * wv(t, 16))
    return ch


rr.breathing = girl_breathing
underpaint.build = lambda project, rive_root, byname: 0
crease.flatten = lambda rgba: {s: np.zeros_like(rgba) for s in ('l', 'r')}


def prepare(project):
    """Картинки, сетки и бант девочки в проекте мальчика; артборд — Bear_Girl."""
    path = os.path.join(project, 'scene.rml')
    tree = ET.parse(path)
    root = tree.getroot()
    ab = root.find('Artboard')
    ab.set('name', 'Bear_Girl')
    ids = iter(range(10 ** 6, 10 ** 7))
    stats = girl_rig.swap(project, root, ab, lambda: f'8:{next(ids)}')
    for name, (nv, nt) in stats.items():
        print(f'сетка {name}: {nv} точек, {nt} треугольников')
    tree.write(path, encoding='unicode')
    yaml = os.path.join(project, 'rive.yaml')
    text = open(yaml, encoding='utf-8').read()
    assert 'main: "Bear_Boy"' in text, 'в rive.yaml нет артборда мальчика'
    open(yaml, 'w', encoding='utf-8').write(text.replace('main: "Bear_Boy"', 'main: "Bear_Girl"'))


def main():
    try:
        build_bear.main(out=OUT, prepare=prepare)
    finally:
        shutil.rmtree(TILES, ignore_errors=True)


if __name__ == '__main__':
    main()
