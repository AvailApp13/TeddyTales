#!/usr/bin/env python3
"""
Офлайн-проверка поз без редактора: слои handoff/layers_v2 ставятся так, как их
поставит Rive. Жёсткие слои поворачиваются вокруг оси своей кости; слои-сетки
(рукава, капюшон, шорты) деформируются по весам из tools/lib/bear_weights.mjs
(линейное смешивание костей по вершинам, треугольники — аффинно, как в Rive).
Складываются в порядке отрисовки (layers.json).

    python3 tools/scripts/simulate_pose.py out.png head=8 arm_left=40 arm_right=-40 leg_left=12 ...

Оси — в координатах артборда (как в teddy mcp:bones), переводятся в кадр
слоёв через общий трансформ слоёв (bear_proportions.photo + AB).
"""
import json, os, subprocess, sys, tempfile
import numpy as np
import cv2
from PIL import Image

R = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
D = f'{R}/handoff/layers_v2'
P = json.load(open(f'{R}/rig/bear_proportions.json'))['photo']
S = 760 / P['bodyHeightPx']
CX, CY = 512 + (666.5 - P['axisX']) * S, 985 - (P['groundY'] - 1000) * S   # центр кадра в артборде
to_full = lambda xa, ya: (666.5 + (xa - CX) / S, 1000 + (ya - CY) / S)
PIVOT = {  # поза: ось в артборде
    'head': (524.0, 554.0), 'arm_left': (381, 577), 'arm_right': (658, 577),
    'leg_left': (453, 812), 'leg_right': (582, 812),
    'body': (517.5, 810.8),   # начало кости root (таз)
}
BONE = {'root_ear_left': 'ear_left', 'root_ear_right': 'ear_right', 'root_body': 'head', 'root_arm_left': 'arm_left', 'root_arm_right': 'arm_right',
        'root_leg_left': 'leg_left', 'root_leg_right': 'leg_right'}           # кость рига -> поза
RIGID = {'face': 'head', 'hood_lining': 'head', 'paw_left': 'arm_left', 'paw_right': 'arm_right',
         'foot_left': 'leg_left', 'foot_right': 'leg_right'}
SKINNED = ('sleeve_left', 'sleeve_right', 'hood', 'shorts', 'ear_left', 'ear_right')
MESH_STEP = 6


def _rot(pivot, deg):
    px, py = to_full(*pivot); t = np.radians(deg); c, s = np.cos(t), np.sin(t)
    return np.array([[c, -s, px - c * px + s * py], [s, c, py - s * px - c * py], [0, 0, 1]])


# оси ушей — середина линии стыка с капюшоном (layers.json, split_full_bear.py, кадр) -> артборд
to_art = lambda xf, yf: (CX + (xf - 666.5) * S, CY + (yf - 1000) * S)
for _e, _p in json.load(open(f'{D}/layers.json')).get('ear_pivots', {}).items():
    PIVOT[_e] = to_art(*_p['pivot'])
# кость уха — дочерняя головы: сначала изгиб уха, затем голова
PARENT = {'ear_left': ['head', 'ear_left'], 'ear_right': ['head', 'ear_right']}


def bone_affine(pose, ang):
    """2×3: поворот вокруг оси позы на угол (Rive: + по часовой при y вниз).
    body=… — наклон кости root от таза: все кости — её дети, поворот внешний."""
    M = np.eye(3)
    if pose in PARENT:
        for q in PARENT[pose]:
            if ang.get(q): M = M @ _rot(PIVOT[q], ang[q])
    elif pose and ang.get(pose): M = _rot(PIVOT[pose], ang[pose])
    if ang.get('body'): M = _rot(PIVOT['body'], ang['body']) @ M
    return M[:2]


def warp_mesh(L, weights, ang, step):
    """Деформирует слой L (H×W×4) сеткой с шагом step по весам костей."""
    H, W = L.shape[:2]
    a = L[..., 3] > 0
    ys, xs = np.where(cv2.dilate(a.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0)
    x0, x1 = max(xs.min() - step, 0) // step * step, min(xs.max() + 2 * step, W - 1)
    y0, y1 = max(ys.min() - step, 0) // step * step, min(ys.max() + 2 * step, H - 1)
    gx, gy = np.arange(x0, x1 + 1, step), np.arange(y0, y1 + 1, step)
    VX, VY = np.meshgrid(gx.astype(np.float64), gy.astype(np.float64))
    g = weights['step']
    dx, dy = VX.copy(), VY.copy()
    tot = np.zeros_like(VX)
    for bone, grid in weights['bones'].items():
        wgrid = np.asarray(grid, np.float32)
        w = cv2.remap(wgrid, (VX / g).astype(np.float32), (VY / g).astype(np.float32), cv2.INTER_LINEAR)
        M = bone_affine(BONE.get(bone), ang)
        tx, ty = M[0, 0] * VX + M[0, 1] * VY + M[0, 2], M[1, 0] * VX + M[1, 1] * VY + M[1, 2]
        if bone == list(weights['bones'])[0]:
            dx, dy = w * tx, w * ty
        else:
            dx, dy = dx + w * tx, dy + w * ty
        tot += w
    dx, dy = dx / np.maximum(tot, 1e-6), dy / np.maximum(tot, 1e-6)
    # треугольники ячеек; рисуем только те, где есть непрозрачные пиксели
    idx = np.arange(VX.size).reshape(VX.shape)
    tri = np.concatenate([np.stack([idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:]], -1).reshape(-1, 3),
                          np.stack([idx[:-1, :-1], idx[1:, 1:], idx[1:, :-1]], -1).reshape(-1, 3)])
    sx, sy, fx, fy = VX.ravel(), VY.ravel(), dx.ravel(), dy.ravel()
    cxs, cys = sx[tri].mean(1).astype(int), sy[tri].mean(1).astype(int)
    keep = cv2.dilate(a.astype(np.uint8), np.ones((2 * step + 1, 2 * step + 1), np.uint8))[np.clip(cys, 0, H - 1), np.clip(cxs, 0, W - 1)] > 0
    tri = tri[keep]
    tid = np.full((H, W), -1, np.int32)
    for k, t in enumerate(tri):
        pts = np.rint(np.stack([fx[t], fy[t]], 1) * 16).astype(np.int32)
        cv2.fillConvexPoly(tid, pts, k, lineType=cv2.LINE_8, shift=4)
        cv2.polylines(tid, [pts], True, k, 1, cv2.LINE_8, shift=4)   # без волосяных щелей между треугольниками (в Rive их нет)
    yy, xx = np.where(tid >= 0)
    t = tri[tid[yy, xx]]
    # барицентрические координаты в деформированном треугольнике -> точка в исходном
    ax, ay, bx, by, qx, qy = fx[t[:, 0]], fy[t[:, 0]], fx[t[:, 1]], fy[t[:, 1]], fx[t[:, 2]], fy[t[:, 2]]
    det = (by - qy) * (ax - qx) + (qx - bx) * (ay - qy)
    det = np.where(np.abs(det) < 1e-9, 1e-9, det)
    l1 = ((by - qy) * (xx - qx) + (qx - bx) * (yy - qy)) / det
    l2 = ((qy - ay) * (xx - qx) + (ax - qx) * (yy - qy)) / det
    l3 = 1 - l1 - l2
    mx = l1 * sx[t[:, 0]] + l2 * sx[t[:, 1]] + l3 * sx[t[:, 2]]
    my = l1 * sy[t[:, 0]] + l2 * sy[t[:, 1]] + l3 * sy[t[:, 2]]
    map_x = np.full((H, W), -10, np.float32); map_y = np.full((H, W), -10, np.float32)
    map_x[yy, xx], map_y[yy, xx] = mx, my
    return cv2.remap(L, map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def main():
    out = sys.argv[1]
    ang = {k: float(v) for k, v in (a.split('=') for a in sys.argv[2:])}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        subprocess.run(["node", f"{R}/tools/scripts/dump_weights.mjs", tf.name, "4"], check=True)
        dump = json.load(open(tf.name))
    order = json.load(open(f'{D}/layers.json'))['order_back_to_front']
    canvas = np.zeros((2000, 1333, 4), np.float64); canvas[..., :3] = (40, 40, 46); canvas[..., 3] = 255
    skip = set(filter(None, os.environ.get('SIM_SKIP', '').split(',')))   # отладка: без этих слоёв
    for n in order:
        if n in skip: continue
        L = np.asarray(Image.open(f'{D}/{n}.png').convert('RGBA')).astype(np.float32)
        L[..., :3] *= L[..., 3:4] / 255   # премультиплицированная альфа (как в Rive): иначе интерполяция у краёв тянет чёрный из прозрачных пикселей
        if n in SKINNED:
            L = warp_mesh(L, {'step': dump['step'], 'bones': dump['layers'][n]}, ang, MESH_STEP)
        elif (RIGID.get(n) and (ang.get(RIGID[n]) or any(ang.get(q) for q in PARENT.get(RIGID[n], [])))) or (ang.get('body') and n not in SKINNED):
            M = bone_affine(RIGID.get(n), ang)
            L = cv2.warpAffine(L, M, (L.shape[1], L.shape[0]), flags=cv2.INTER_LINEAR, borderValue=0)
        la = L[..., 3:4].astype(np.float64) / 255
        canvas[..., :3] = L[..., :3] + canvas[..., :3] * (1 - la)
    Image.fromarray(canvas[..., :3].clip(0, 255).astype(np.uint8)).save(out)


if __name__ == '__main__':
    main()
