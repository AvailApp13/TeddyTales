#!/usr/bin/env python3
"""
Референсы мимики из видео заказчика: кадры по эмоциям для согласования.

Шаг 1 — обзор: каждое видео раскладывается на кадры, по нему собирается лист миниатюр
с номерами кадров и секундами (по нему эмоции размечаются вручную или глазами модели):

    python3 -I tools/scripts/emotion_refs.py sheets <папка_с_видео> <папка_вывода>

Шаг 2 — сборка: по разметке labels.json раскладывает выбранные кадры по папкам эмоций,
подписывает каждый кадр (эмоция, пункт КП, видео, секунда) и собирает по эмоции лист
и общий обзор для согласования:

    python3 -I tools/scripts/emotion_refs.py build <папка_с_видео> <labels.json> <папка_вывода>

labels.json:
    {"emotions": [{"id": "joy", "title": "Радость", "kp": "4.8 emote_joy",
                   "frames": [["video_01.mp4", 118, [x0, y0, x1, y1]], ["video_07.mp4", 52], ...]}, ...]}
    четвёртый (необязательный) — пометка к кадру, например «девочка».
    третий элемент кадра (необязательный) — рамка лица в пикселях кадра: на карточке лицо
    показывается крупно рядом с полным кадром.
"""
import json
import os
import sys

import cv2
from PIL import Image, ImageDraw, ImageFont

VIDEO_EXT = ('.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi')
FONT_DIR = '/usr/share/fonts/truetype/liberation'


def font(size, bold=False):
    try:
        return ImageFont.truetype(f'{FONT_DIR}/LiberationSans-{"Bold" if bold else "Regular"}.ttf', size)
    except OSError:
        return ImageFont.load_default()


def videos(folder):
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(VIDEO_EXT))


def read_frame(path, idx):
    cap = cv2.VideoCapture(path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
    ok, fr = cap.read()
    cap.release()
    if not ok:
        raise ValueError(f'{path}: нет кадра {idx}')
    return Image.fromarray(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB))


def info(path):
    cap = cv2.VideoCapture(path)
    fps, n = cap.get(cv2.CAP_PROP_FPS) or 24.0, int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    return fps, n


def sheets(src, out, step_s=0.25, cols=8, tw=200):
    """Лист миниатюр на каждое видео: кадр каждые step_s секунд, подписи «кадр · секунда»."""
    os.makedirs(out, exist_ok=True)
    f12 = font(13)
    index = []
    for name in videos(src):
        path = os.path.join(src, name)
        fps, n = info(path)
        step = max(1, round(fps * step_s))
        idx = list(range(0, n, step))
        first = read_frame(path, 0)
        th = round(tw * first.height / first.width)
        sheet = Image.new('RGB', (cols * tw, ((len(idx) + cols - 1) // cols) * th), (0, 0, 0))
        d = ImageDraw.Draw(sheet)
        cap = cv2.VideoCapture(path)
        for k, i in enumerate(idx):
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ok, fr = cap.read()
            if not ok:
                break
            im = Image.fromarray(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)).resize((tw, th), Image.LANCZOS)
            x, y = tw * (k % cols), th * (k // cols)
            sheet.paste(im, (x, y))
            d.text((x + 4, y + 3), f'{i} · {i / fps:.2f}s', fill=(255, 255, 0), font=f12)
        cap.release()
        base = os.path.splitext(name)[0]
        sheet.save(os.path.join(out, f'{base}_sheet.jpg'), quality=88)
        index.append({'video': name, 'fps': round(fps, 3), 'frames': n, 'seconds': round(n / fps, 2),
                      'size': [first.width, first.height], 'sheet': f'{base}_sheet.jpg'})
        print(f'{name}: {n} кадров, {n / fps:.1f} с, {first.width}×{first.height}')
    json.dump(index, open(os.path.join(out, 'videos.json'), 'w'), ensure_ascii=False, indent=1)


def caption(im, lines):
    """Кадр с подписью снизу (две строки); шрифт — от ширины кадра, чтобы читался и на листе."""
    k = max(1.0, im.width / 360)
    pad = round(46 * k)
    out = Image.new('RGB', (im.width, im.height + pad), (24, 24, 28))
    out.paste(im, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((round(8 * k), im.height + round(4 * k)), lines[0], fill=(255, 255, 255), font=font(round(15 * k), True))
    d.text((round(8 * k), im.height + round(24 * k)), lines[1], fill=(190, 190, 200), font=font(round(13 * k)))
    return out


def build(src, labels_path, out):
    labels = json.load(open(labels_path))
    os.makedirs(out, exist_ok=True)
    overview = []
    for n, e in enumerate(labels['emotions'], 1):
        folder = os.path.join(out, f'{n:02d}_{e["id"]}')
        os.makedirs(folder, exist_ok=True)
        cells = []
        for k, fr in enumerate(e['frames'], 1):
            video, idx = fr[0], fr[1]
            path = os.path.join(src, video)
            fps, _ = info(path)
            im = read_frame(path, idx)
            if len(fr) > 2:
                # лицо крупно рядом с полным кадром: в полный рост мимика мелкая
                x0, y0, x1, y1 = fr[2]
                face = im.crop((x0, y0, x1, y1))
                fh = 640; full = im.resize((round(fh * im.width / im.height), fh), Image.LANCZOS)
                face = face.resize((round(fh * face.width / face.height), fh), Image.LANCZOS)
                im = Image.new('RGB', (full.width + 8 + face.width, fh), (24, 24, 28))
                im.paste(full, (0, 0)); im.paste(face, (full.width + 8, 0))
            if im.width > 1100:
                im = im.resize((1100, round(1100 * im.height / im.width)), Image.LANCZOS)
            note = f' · {fr[3]}' if len(fr) > 3 else ''
            card = caption(im, [f'{e["title"]} — {k}', f'КП {e["kp"]} · {video} · {idx / fps:.2f} с{note}'])
            card.save(os.path.join(folder, f'{e["id"]}_{k}.jpg'), quality=92)
            cells.append(card)
        # лист эмоции: все её кадры в ряд (до 3 в строке)
        cw = 360 if all(c.width < c.height for c in cells) else 540
        thumbs = [c.resize((cw, round(cw * c.height / c.width)), Image.LANCZOS) for c in cells]
        ch = max(t.height for t in thumbs)
        cols = min(3, len(thumbs))
        sheet = Image.new('RGB', (cols * (cw + 10) + 10, 56 + ((len(thumbs) + cols - 1) // cols) * (ch + 10)), (30, 30, 36))
        d = ImageDraw.Draw(sheet)
        d.text((12, 12), f'{n}. {e["title"]}', fill=(255, 255, 255), font=font(22, True))
        d.text((12, 38), f'КП {e["kp"]}', fill=(170, 200, 255), font=font(14))
        for k, t in enumerate(thumbs):
            sheet.paste(t, (10 + (k % cols) * (cw + 10), 56 + (k // cols) * (ch + 10)))
        sheet.save(os.path.join(folder, f'_{e["id"]}_лист.jpg'), quality=90)
        overview.append(sheet)
        print(f'{n:02d} {e["title"]}: {len(cells)} кадров')
    # общий обзор для согласования — все листы эмоций подряд (PDF, по эмоции на страницу)
    if overview:
        overview[0].save(os.path.join(out, 'эмоции_на_согласование.pdf'), save_all=True,
                         append_images=overview[1:], resolution=110)


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'sheets' and len(sys.argv) == 4:
        sheets(sys.argv[2], sys.argv[3])
    elif cmd == 'build' and len(sys.argv) == 5:
        build(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)
