"""Проверка кадра ролика сна: что из него будет видно сквозь облако.

Запуск: python3 tool/check_dream_frame.py <кадр.jpg|png> [выход.jpg]

Слева — кадр целиком, справа — то, что покажет облако мыслей в спальне
(`lib/widgets/sleep_thought.dart`, контур `cloudPath`). Сетка отступов и
формат ролика — `docs/living-scene.md`, раздел 6, и `CLAUDE.md`.
Герои должны быть внутри 15 % от каждого края; у нижних углов пусто.
"""
import sys

from PIL import Image, ImageDraw

# Границы контура облака в долях его рамки (растр `cloudPath`, см. памятку).
BX0, BX1, BY0, BY1 = -0.083, 1.067, -0.160, 1.059
# Окно ролика = границы контура; пропорция ширины к высоте.
ASPECT = (BX1 - BX0) * 1.28 / (BY1 - BY0)  # ≈ 1.208
# Контур: скруглённый прямоугольник и горбы (центр в долях рамки,
# радиус в долях её высоты) — один в один с Dart.
CORE = (0.06, 0.28, 0.88, 0.52, 0.26)
BUMPS = [
    (0.22, 0.30, 0.30), (0.45, 0.20, 0.36), (0.70, 0.27, 0.32),
    (0.88, 0.45, 0.24), (0.12, 0.55, 0.26), (0.30, 0.76, 0.24),
    (0.58, 0.80, 0.26), (0.82, 0.72, 0.22),
]
WALL = (58, 76, 104)


def cloud_mask(w, h):
    rect_h = h / (BY1 - BY0)

    def x(v):
        return (v - BX0) / (BX1 - BX0) * w

    def y(v):
        return (v - BY0) / (BY1 - BY0) * h

    mask = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(mask)
    l, t, cw, ch, r = CORE
    d.rounded_rectangle((x(l), y(t), x(l + cw), y(t + ch)),
                        radius=r * rect_h, fill=255)
    for cx, cy, r in BUMPS:
        rr = r * rect_h
        d.ellipse((x(cx) - rr, y(cy) - rr, x(cx) + rr, y(cy) + rr), fill=255)
    return mask


def main(src, dst):
    im = Image.open(src).convert('RGB')
    W, H = im.size
    # BoxFit.cover: кадр обрезается до пропорции окна по центру.
    if W / H > ASPECT:
        tw = int(H * ASPECT)
        crop = im.crop(((W - tw) // 2, 0, (W - tw) // 2 + tw, H))
    else:
        th = int(W / ASPECT)
        crop = im.crop((0, (H - th) // 2, W, (H - th) // 2 + th))
    w, h = crop.size
    shown = Image.composite(crop, Image.new('RGB', (w, h), WALL),
                            cloud_mask(w, h))
    out = Image.new('RGB', (W + w + 20, max(H, h)), (30, 30, 30))
    out.paste(im, (0, 0))
    out.paste(shown, (W + 20, 0))
    out.save(dst, quality=88)
    print(f'{dst}: окно {w}×{h}, кадр {W}×{H}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'frame_check.jpg')
