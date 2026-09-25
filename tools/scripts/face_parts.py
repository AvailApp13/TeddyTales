#!/usr/bin/env python3
"""
Мимика мишки v2: из выражений лица (правки утверждённого кадра в Higgsfield,
tools/scripts/mac_fetch_faces.sh) режет накладки для рига — глаза, рот, румянец —
и отдельно бусины глаз с «пустой» глазницей под ними (для взгляда).

    python3 tools/scripts/face_parts.py handoff/faces_src handoff/face_v2

Входные face_<имя>.png — голова, вырезанная из кадра 2336×3504 со смещением
(520, 480); кадр рига 1333×2000 — тот же кадр ×0.5706. Каждое выражение:
  1) совмещается с основой по капюшону и ушам (SIFT + подобие) — генератор
     иногда рисует мишку на 3–5 % меньше;
  2) черты лица генератор мог нарисовать чуть выше/ниже — поэтому глаза и рот
     переносятся отдельными накладками: рот ставится по носу (нос всегда
     остаётся от основы), глаза — по центру глазниц основы;
  3) мех накладки подгоняется по цвету к основе (по кромке растушёвки).
Накладки кладутся поверх лица основы; в покое их нет — лицо как утверждено.
"""
import json, os, sys
import numpy as np, cv2
from PIL import Image
from scipy import ndimage

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
FX, FY, FS = 520, 480, 1333 / 2336          # голова -> кадр рига: (x + FX) * FS

def load(n):
    f = next(f'{SRC}/face_{n}.{e}' for e in ('png', 'webp') if os.path.exists(f'{SRC}/face_{n}.{e}'))
    return np.asarray(Image.open(f).convert('RGBA'))

base = load('base'); H, W = base.shape[:2]
gb = cv2.cvtColor(base[..., :3], cv2.COLOR_RGB2GRAY)
hsv_b = cv2.cvtColor(base[..., :3], cv2.COLOR_RGB2HSV)
# мех лица (не капюшон). Тёмные бусины с синим бликом — тоже «лицо», иначе накладка
# глаз над ними прозрачна и бусина основы просвечивает сквозь закрытые глаза
fur = (base[..., 3] > 200) & ~((hsv_b[..., 0] > 90) & (hsv_b[..., 0] < 130) & (hsv_b[..., 1] > 40) & (hsv_b[..., 2] > 110))
fur = ndimage.binary_fill_holes(ndimage.binary_opening(fur, iterations=3))
fur = ndimage.binary_erosion(fur, iterations=6)

EYE = {'l': (510, 1090), 'r': (820, 1090)}      # центры бусин основы
NOSE = (667, 1238)                               # центр носа основы
NOSE_T = gb[1180:1300, 605:735]
BEAD_T = gb[1035:1145, 455:565]

def align(a):
    """Подобие по капюшону/ушам (центр лица исключён)."""
    g = cv2.cvtColor(a[..., :3], cv2.COLOR_RGB2GRAY)
    sift = cv2.SIFT_create(6000)
    def feats(img):
        m = np.full(img.shape, 255, np.uint8)
        cv2.ellipse(m, (int(660 * img.shape[1] / W), int(1080 * img.shape[0] / H)), (420, 360), 0, 0, 360, 0, -1)
        return sift.detectAndCompute(img, m)
    k0, d0 = feats(gb); k1, d1 = feats(g)
    good = [p for p, q in cv2.BFMatcher().knnMatch(d1, d0, k=2) if p.distance < 0.7 * q.distance]
    src = np.float32([k1[p.queryIdx].pt for p in good]); dst = np.float32([k0[p.trainIdx].pt for p in good])
    M, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.RANSAC, ransacReprojThreshold=2.0, maxIters=5000)
    return cv2.warpAffine(a, M, (W, H), flags=cv2.INTER_LANCZOS4, borderValue=0)

def locate(a):
    g = cv2.cvtColor(a[..., :3], cv2.COLOR_RGB2GRAY); hsv = cv2.cvtColor(a[..., :3], cv2.COLOR_RGB2HSV)
    r = cv2.matchTemplate(g[900:1400, 480:860], NOSE_T, cv2.TM_CCOEFF_NORMED); _, _, _, lc = cv2.minMaxLoc(r)
    nose = (480 + lc[0] + 62, 900 + lc[1] + 58)
    eyes = {}
    for k, (x0, x1) in {'l': (360, 650), 'r': (680, 980)}.items():
        rr = cv2.matchTemplate(g[950:nose[1] - 30, x0:x1], BEAD_T, cv2.TM_CCOEFF_NORMED); _, ev, _, el = cv2.minMaxLoc(rr)
        if ev > 0.75:                                      # бусина
            eyes[k] = (x0 + el[0] + 55, 950 + el[1] + 55, 'bead')
        else:                                              # вышитые дуги
            dark = (hsv[..., 2] < 110) & (a[..., 3] > 200); m = np.zeros_like(dark)
            m[950:nose[1] - 40, x0:x1] = dark[950:nose[1] - 40, x0:x1]
            ys, xs = np.where(m); eyes[k] = (int(xs.mean()), int(ys.mean()), 'arc')
    return nose, eyes

def feather(mask, r):
    return np.clip(ndimage.gaussian_filter(mask.astype(np.float32), r / 2), 0, 1)

def ellipse(cx, cy, rx, ry):
    m = np.zeros((H, W), np.uint8); cv2.ellipse(m, (int(cx), int(cy)), (int(rx), int(ry)), 0, 0, 360, 1, -1); return m > 0

def moved(a, dx, dy, s=1.0, c=(0, 0)):
    M = np.float32([[s, 0, dx + c[0] * (1 - s)], [0, s, dy + c[1] * (1 - s)]])
    return cv2.warpAffine(a, M, (W, H), flags=cv2.INTER_LANCZOS4, borderValue=0)

def color_match(src, alpha):
    ring = (alpha > 0.05) & (alpha < 0.6) & fur & (src[..., 3] > 200)
    if ring.sum() < 50: return src
    g = base[..., :3][ring].mean(0) / np.maximum(src[..., :3][ring].mean(0), 1)
    out = src.astype(np.float32); out[..., :3] *= np.clip(g, 0.85, 1.15); return out.clip(0, 255).astype(np.uint8)

def patch(src, alpha, name):
    """Накладка = src с прозрачностью alpha; обрезка по границам, запись + метаданные."""
    alpha = alpha * fur_soft * (src[..., 3] / 255.0)
    ys, xs = np.where(alpha > 0.003)
    if not len(ys): return None
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    img = np.dstack([src[y0:y1, x0:x1, :3], (alpha[y0:y1, x0:x1] * 255).round().astype(np.uint8)])
    # в разрешении кадра рига (как остальные слои): мельче не видно на экране,
    # а .riv с накладками в разрешении головы выходил за 9 МБ
    im = Image.fromarray(img, 'RGBA')
    im = im.resize((max(1, round(im.width * FS)), max(1, round(im.height * FS))), Image.LANCZOS)
    im.save(f'{OUT}/{name}.png', optimize=True)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return {'file': f'{name}.png', 'size': [im.width, im.height],
            'center_frame': [round((cx + FX) * FS, 2), round((cy + FY) * FS, 2)], 'px_scale': round(im.width and (x1 - x0) * FS / im.width, 6)}

fur_soft = feather(fur, 16)
nose_mask = feather(ellipse(NOSE[0], NOSE[1] - 4, 100, 70), 8)   # с запасом: край носа выражения не лезет из-под носа основы

# --- параметры выражений: смещения меряются, мелкие правки — здесь
MOUTH_SCALE = {"yawn": 0.66, "lick": 0.92}
MOUTH_DY = {"yawn": -34}                        # рот зевка — выше, иначе уходит под капюшон      # крупный рот: чуть меньше, чтобы не уходил под капюшон
NO_MOUTH = {'blink_half', 'eyes_closed'}         # рот как у основы
NO_EYES = {'chew', 'lick', 'smile', 'tongue'}              # глаза как у основы (бусины на месте)
BLUSH = {'love'}

parts = {'frame': [1333, 2000], 'face_crop_offset': [FX, FY], 'expressions': {}}
closed_eye = {}   # закрытые глаза, уже в глазницах основы и в цвет меха — из них глазница для взгляда
names = sorted(os.path.splitext(f)[0][5:] for f in os.listdir(SRC) if f.startswith('face_') and f.endswith(('.png', '.webp')))
for n in [x for x in names if x != 'base']:
    a = align(load(n)); nose, eyes = locate(a)
    e = {'found': {'nose': nose, 'eyes': {k: v for k, v in eyes.items()}}}
    # рот: по носу; нос остаётся от основы
    if n not in NO_MOUTH:
        s = MOUTH_SCALE.get(n, 1.0)
        m = moved(a, NOSE[0] - nose[0], NOSE[1] - nose[1] + MOUTH_DY.get(n, 0), s, NOSE)
        area = ellipse(NOSE[0], NOSE[1] + 100, 185, 150) & (np.arange(H)[:, None] > NOSE[1] - 40)
        al = feather(area, 30) * (1 - nose_mask)
        e['mouth'] = patch(color_match(m, al), al, f'{n}_mouth')
    # глаза: каждый — в свою глазницу основы
    if n not in NO_EYES:
        for k, (bx, by) in EYE.items():
            ex, ey, kind = eyes[k]
            ty = by - 8 if kind == 'arc' and n in ('laugh', 'love', 'yawn') else by   # «улыбающиеся» дуги чуть выше центра
            m = moved(a, bx - ex, (ty - ey) if kind == 'bead' or n in ('laugh', 'love', 'yawn', 'surprised') else 0)
            al = feather(ellipse(bx, by - 25, 135, 140), 30)
            e[f'eye_{k}'] = patch(color_match(m, al), al, f'{n}_eye_{k}')
            if n == 'eyes_closed': closed_eye[k] = color_match(m, al)
    if n in BLUSH:
        # румянец отдельным слоем: только «розовость» сверх основы
        m = moved(a, 0, NOSE[1] - nose[1])
        red = lambda x: x[..., 0].astype(np.float32) - (x[..., 1].astype(np.float32) + x[..., 2]) / 2
        extra = np.clip((red(m) - red(base) - 6) / 30, 0, 1) * (m[..., 3] > 200)
        extra = ndimage.gaussian_filter(extra, 3) * (1 - nose_mask)
        extra[:1150] = 0; extra[1340:] = 0              # только щёки
        pink = np.zeros_like(m); pink[..., :3] = (236, 150, 150); pink[..., 3] = 255
        e['blush'] = patch(pink, extra * 0.9, f'{n}_blush')
    parts['expressions'][n] = e
    print(n, {k: (v['size'] if isinstance(v, dict) and 'size' in v else v) for k, v in e.items()})

# --- взгляд: бусины основы отдельно + глазница без бусины. Глазница — мех закрытого
# глаза из того же кадра (Higgsfield) без линии ресниц: при моргании бусина сплющивается
# и открывает глазницу, поэтому мех там должен быть настоящим — дорисовка по краям
# (inpaint) давала светлое размытое пятно. Ресницы (тонкая линия) закрываются мехом века.
bead_dark = cv2.cvtColor(base[..., :3], cv2.COLOR_RGB2HSV)[..., 2] < 80
gaze = {}
for k, (bx, by) in EYE.items():
    m = ndimage.binary_fill_holes(bead_dark & ellipse(bx, by, 70, 65))
    m = ndimage.binary_dilation(ndimage.binary_opening(m, iterations=2), iterations=4)
    src = closed_eye[k].copy()
    hsv = cv2.cvtColor(src[..., :3], cv2.COLOR_RGB2HSV)
    lash = (hsv[..., 2] < 150) & ellipse(bx, by, 95, 80)
    lash = ndimage.binary_dilation(lash, iterations=4)
    # ресницы закрываются мехом века: тот же столбец на LID px выше (фактура сохраняется;
    # дорисовка inpaint давала гладкое светлое пятно), край — мягкий
    LID = 26
    lid = np.roll(src[..., :3], LID, axis=0)
    wl = feather(lash, 4)[..., None]
    src[..., :3] = (src[..., :3] * (1 - wl) + lid * wl).round().astype(np.uint8)
    ab = feather(m, 3)
    gaze[f'bead_{k}'] = patch(base, ab, f'gaze_bead_{k}')
    gaze[f'socket_{k}'] = patch(src, feather(ndimage.binary_dilation(m, iterations=10), 8), f'gaze_socket_{k}')
parts['gaze'] = gaze
json.dump(parts, open(f'{OUT}/face_parts.json', 'w'), indent=1, ensure_ascii=False)
print('ok', len(parts['expressions']), 'выражений')
