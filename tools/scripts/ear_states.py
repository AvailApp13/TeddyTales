#!/usr/bin/env python3
"""
Положения ушей (D24): кадры утверждённой головы, где Higgsfield перерисовал только
уши (handoff/ears_src/ears_<n>.webp, фон — запечённая «шахматка»), режутся в слои
рига ear_<сторона>_<состояние>.png в кадре слоёв 1333×2000.

    python3 tools/scripts/ear_states.py handoff/ears_src handoff/layers_v2 cup=ears_11 droop=ears_31

Для каждого кадра:
  1) фон-шахматка -> прозрачность (нейтрально-серые светлые пиксели, связные с краем);
  2) совмещение с утверждённой головой (face_base, SIFT по капюшону и лицу, уши
     исключены) -> кадр слоёв: (голова + (520, 480)) × 1333/2336;
  3) ухо = мех (не голубой) снаружи капюшона и лица, связный с ухом рига;
     продолжается под капюшон (заливка мехом), цвет подгоняется к уху рига;
  4) метаданные для перехода: угол и масштаб нового уха относительно уха рига вокруг
     оси уха (layers.json → ear_pivots.pivot) — по моментам масок.
Слои кладутся в группу уха над ухом рига; переход — tools/scripts/idle_life.mjs.
"""
import json, os, sys
import numpy as np, cv2
from PIL import Image
from scipy import ndimage

SRC, OUT = sys.argv[1], sys.argv[2]
STATES = dict(a.split('=') for a in sys.argv[3:])
FX, FY, FS = 520, 480, 1333 / 2336
W, H = 1333, 2000
meta = json.load(open(f'{OUT}/layers.json'))
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

base = np.asarray(Image.open(f'{R}/handoff/faces_src/face_base.webp').convert('RGBA'))
hood_a = np.asarray(Image.open(f'{OUT}/hood.png'))[..., 3]
lay = {n: np.asarray(Image.open(f'{OUT}/{n}.png'))[..., 3] > 128 for n in ('ear_left', 'ear_right', 'hood', 'face', 'hood_lining')}
ear_rgba = {n: np.asarray(Image.open(f'{OUT}/{n}.png').convert('RGBA')) for n in ('ear_left', 'ear_right')}


def to_head(m):
    """маска кадра слоёв -> координаты головы (face_base)"""
    Mi = np.float32([[1 / FS, 0, -FX], [0, 1 / FS, -FY]])
    return cv2.warpAffine(m.astype(np.uint8), Mi, (base.shape[1], base.shape[0]), flags=cv2.INTER_NEAREST) > 0


def unchecker(rgb):
    """прозрачность вместо шахматки: нейтральные светлые пиксели, связные с краем кадра"""
    a = rgb.astype(np.int16)
    neutral = (a.max(-1) - a.min(-1) <= 4) & (a.min(-1) >= 226)
    lab, _ = ndimage.label(neutral)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, edge[edge > 0])
    bg = ndimage.binary_opening(bg, iterations=1)
    alpha = 1 - ndimage.gaussian_filter(bg.astype(np.float32), 0.8)
    return np.dstack([rgb, (alpha * 255).clip(0, 255).astype(np.uint8)])


def align(gen):
    """подобие gen -> голова (face_base) по капюшону и лицу, уши исключены"""
    ears_h = ndimage.binary_dilation(to_head(lay['ear_left'] | lay['ear_right']), iterations=60)
    g0 = cv2.cvtColor(base[..., :3], cv2.COLOR_RGB2GRAY); g1 = cv2.cvtColor(gen[..., :3], cv2.COLOR_RGB2GRAY)
    m0 = ((base[..., 3] > 200) & ~ears_h).astype(np.uint8) * 255
    sift = cv2.SIFT_create(8000)
    k0, d0 = sift.detectAndCompute(g0, m0); k1, d1 = sift.detectAndCompute(g1, (gen[..., 3] > 200).astype(np.uint8) * 255)
    good = [p for p, q in cv2.BFMatcher().knnMatch(d1, d0, k=2) if p.distance < 0.7 * q.distance]
    src = np.float32([k1[p.queryIdx].pt for p in good]); dst = np.float32([k0[p.trainIdx].pt for p in good])
    # только точки вне ушей рига (в голове)
    keep = ~ears_h[np.clip(dst[:, 1].astype(int), 0, base.shape[0] - 1), np.clip(dst[:, 0].astype(int), 0, base.shape[1] - 1)]
    M, inl = cv2.estimateAffinePartial2D(src[keep], dst[keep], method=cv2.RANSAC, ransacReprojThreshold=2.0, maxIters=8000)
    return M, int(inl.sum()), len(good)


def moments(mask, pivot):
    ys, xs = np.nonzero(mask)
    c = np.array([xs.mean(), ys.mean()])
    d = c - pivot
    return np.degrees(np.arctan2(d[1], d[0])), np.hypot(*d), c


out = {}
for state, name in STATES.items():
    f = next(f'{SRC}/{name}.{e}' for e in ('png', 'webp') if os.path.exists(f'{SRC}/{name}.{e}'))
    gen = unchecker(np.asarray(Image.open(f).convert('RGB')))
    M, inl, n = align(gen)
    # gen -> кадр слоёв
    A = np.vstack([M, [0, 0, 1]]); F = np.array([[FS, 0, FX * FS], [0, FS, FY * FS], [0, 0, 1]]) @ A
    g = cv2.warpAffine(gen, F[:2], (W, H), flags=cv2.INTER_LANCZOS4, borderValue=0)
    hsv = cv2.cvtColor(g[..., :3], cv2.COLOR_RGB2HSV)
    blue = (hsv[..., 0] > 85) & (hsv[..., 0] < 125) & (hsv[..., 1] > 35)
    # мех — бежевый (серые тени капюшона и остатки шахматки сюда не попадают)
    fur = (g[..., 3] > 40) & ~ndimage.binary_dilation(blue, iterations=2) & (hsv[..., 1] > 22) & (hsv[..., 0] < 40)
    inner = ndimage.binary_dilation(lay['face'] | lay['hood_lining'], iterations=6)   # лицо в проёме капюшона
    res = {'source': name, 'sift_inliers': inl, 'sift_matches': n, 'scale': round(float(np.hypot(*M[:, 0]) * 1), 4)}
    for side in ('left', 'right'):
        en = f'ear_{side}'
        zone = ndimage.binary_dilation(lay[en], iterations=90) & ~inner
        lab, _ = ndimage.label(fur & zone)
        ids = np.unique(lab[lay[en] & (lab > 0)])
        ear = np.isin(lab, ids[ids > 0]) if len(ids) else np.zeros_like(fur)
        ear = ndimage.binary_fill_holes(ndimage.binary_closing(ear, iterations=3))
        ear = ndimage.binary_opening(ear, iterations=3)                 # без волосков-осколков
        lab2, n2 = ndimage.label(ear)
        if n2 > 1: ear = lab2 == 1 + np.argmax(ndimage.sum(ear, lab2, range(1, n2 + 1)))
        # край: на 2 px внутрь (там мех смешан с шахматкой — светлый ореол), мягкий спад;
        # цвет края — ближайшего «чистого» меха изнутри
        # пушистая кайма, как у уха рига: плотное ядро + мягкий спад наружу
        core = ndimage.binary_erosion(ear, iterations=2)
        a = np.maximum(ndimage.gaussian_filter(core.astype(np.float32), 1.3),
                       0.85 * ndimage.gaussian_filter(ear.astype(np.float32), 3.2))
        clean = ndimage.binary_erosion(ear, iterations=5)
        _, (iy, ix) = ndimage.distance_transform_edt(~clean, return_indices=True)
        rgb = g[..., :3].copy()
        rgb = np.where(clean[..., None], rgb, rgb[iy, ix])
        # продолжение под капюшон: заливка мехом из уха (под капюшоном рига не видно,
        # но у края капюшона новое ухо не оставляет щели)
        P = meta['ear_pivots'][en]
        (cx, cy), rr = cv2.minEnclosingCircle(np.argwhere(lay[en])[:, ::-1].astype(np.float32))
        Y, X = np.mgrid[0:H, 0:W]
        # под капюшоном: где он плотный — заливка мехом из уха (не видна, но у края
        # капюшона новое ухо не оставляет щели); где кромка капюшона полупрозрачная —
        # ровно пиксели уха рига, как в покое (иначе сквозь светлую кромку виден фон
        # или пятно заливки)
        hidden = hood_a > 250
        under = hidden & ((X - cx) ** 2 + (Y - cy) ** 2 <= (rr + 2) ** 2) & ~ear
        under &= ndimage.binary_dilation(ear, iterations=45) | ndimage.binary_dilation(lay[en], iterations=4)
        fill = cv2.inpaint(np.ascontiguousarray(rgb[..., ::-1]), under.astype(np.uint8), 9, cv2.INPAINT_TELEA)[..., ::-1]
        rgb = np.where(under[..., None], fill, rgb)
        a = np.maximum(a, under.astype(np.float32))
        rim = (hood_a > 5) & ~hidden & ndimage.binary_dilation(ear_rgba[en][..., 3] > 5, iterations=10) & (a < 0.9)
        old_a = ear_rgba[en][..., 3].astype(np.float32) / 255
        rgb = np.where(rim[..., None], ear_rgba[en][..., :3], rgb)
        a = np.where(rim, np.maximum(a, old_a), a)
        # цвет — к уху рига (по видимой части, вне капюшона)
        vis_old = lay[en] & ~lay['hood']; vis_new = (a > 0.9) & ~lay['hood']
        k = ear_rgba[en][..., :3][vis_old].mean(0) / np.maximum(rgb[vis_new].mean(0), 1)
        rgb = (rgb.astype(np.float32) * np.clip(k, 0.85, 1.15)).clip(0, 255).astype(np.uint8)
        img = np.dstack([rgb, (a * 255).round().clip(0, 255).astype(np.uint8)])
        fn = f'{en}_{state}'
        Image.fromarray(img, 'RGBA').save(f'{OUT}/{fn}.png', optimize=True)
        # переход: угол и масштаб видимой части уха вокруг оси
        piv = np.array(P['pivot'])
        a0, r0, c0 = moments(vis_old, piv); a1, r1, c1 = moments(vis_new, piv)
        res[side] = {'file': f'{fn}.png', 'angle': round(float((a1 - a0 + 180) % 360 - 180), 2), 'scale': round(float(r1 / r0), 3),
                     'area': round(float(vis_new.sum() / vis_old.sum()), 3), 'center': [round(float(v), 1) for v in c1]}
    out[state] = res
    print(state, json.dumps(res, ensure_ascii=False))
# кромка капюшона у основания острия: при нарезке в неё вмешался цвет меха уха (в покое
# её прятал мех), в новых положениях ухо там фон — светлый зубчик. Кромка, которая
# граничит с фоном хотя бы в одном положении, перекрашивается в ткань капюшона рядом.
hood_img = np.asarray(Image.open(f'{OUT}/hood.png').convert('RGBA')).copy()
ha = hood_img[..., 3]
empty = np.ones((H, W), bool)
for n in meta['order_back_to_front']:
    if n != 'hood' and not n.startswith('ear_') and not n.endswith('_shade'):
        empty &= np.asarray(Image.open(f'{OUT}/{n}.png'))[..., 3] < 20
open_any = np.zeros((H, W), bool)
for state, res in out.items():
    ears = np.zeros((H, W), bool)
    for side in ('left', 'right'): ears |= np.asarray(Image.open(f"{OUT}/{res[side]['file']}"))[..., 3] > 60
    open_any |= empty & ~ears
near_ear = ndimage.binary_dilation(lay['ear_left'] | lay['ear_right'], iterations=12)
Yg, Xg = np.mgrid[0:H, 0:W]
peak = np.zeros((H, W), bool)                       # только у верхнего конца стыка уха с капюшоном
for en in ('ear_left', 'ear_right'):
    tx, ty = meta['ear_pivots'][en]['contact'][0]; peak |= (Xg - tx) ** 2 + (Yg - ty) ** 2 < 45 ** 2
rim = (ha > 0) & near_ear & peak & ndimage.binary_dilation(open_any & (ha < 20), iterations=7)
core = (ha > 250) & ~ndimage.binary_dilation(lay['ear_left'] | lay['ear_right'] | rim, iterations=10)
_, (iy, ix) = ndimage.distance_transform_edt(~core, return_indices=True)
hood_img[..., :3] = np.where(rim[..., None], hood_img[iy, ix, :3], hood_img[..., :3])
Image.fromarray(hood_img, 'RGBA').save(f'{OUT}/hood.png', optimize=True)
print('кромка капюшона перекрашена:', int(rim.sum()), 'px')
meta['ear_states'] = out
json.dump(meta, open(f'{OUT}/layers.json', 'w'), indent=1, ensure_ascii=False)
