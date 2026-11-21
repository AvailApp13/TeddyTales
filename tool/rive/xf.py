"""Мировые трансформы узлов Rive-сцены из RML (поза покоя)."""
import math, xml.etree.ElementTree as ET

class M:
    # Mat2D(xx, xy, yx, yy, tx, ty): x-ось (xx, xy), y-ось (yx, yy)
    def __init__(s, xx=1, xy=0, yx=0, yy=1, tx=0, ty=0):
        s.v = [xx, xy, yx, yy, tx, ty]
    def __mul__(a, b):
        A, B = a.v, b.v
        return M(A[0]*B[0] + A[2]*B[1], A[1]*B[0] + A[3]*B[1],
                 A[0]*B[2] + A[2]*B[3], A[1]*B[2] + A[3]*B[3],
                 A[0]*B[4] + A[2]*B[5] + A[4], A[1]*B[4] + A[3]*B[5] + A[5])
    def apply(s, x, y):
        a = s.v
        return (a[0]*x + a[2]*y + a[4], a[1]*x + a[3]*y + a[5])
    def inv(s):
        a, b, c, d, tx, ty = s.v
        det = a*d - b*c
        ia, ib, ic, id_ = d/det, -b/det, -c/det, a/det
        return M(ia, ib, ic, id_, -(ia*tx + ic*ty), -(ib*tx + id_*ty))
    @staticmethod
    def trs(x, y, r, sx=1, sy=1):
        c, s_ = math.cos(r), math.sin(r)
        return M(c*sx, s_*sx, -s_*sy, c*sy, x, y)
    def angle(s):
        return math.atan2(s.v[1], s.v[0])

def f(e, k, d=0.0):
    return float(e.attrib.get(k, d))

TRANSFORMS = {'Node', 'RootBone', 'Bone', 'Image', 'Shape', 'Solo'}

def world_map(ab):
    """{element: world M} для всех трансформируемых узлов артборда."""
    out = {}
    def walk(e, parent_w, parent_e):
        w = parent_w
        if e.tag in TRANSFORMS:
            if e.tag == 'Bone':
                x, y = f(parent_e, 'length'), 0.0
            else:
                x, y = f(e, 'x'), f(e, 'y')
            w = parent_w * M.trs(x, y, f(e, 'rotation'), f(e, 'scaleX', 1), f(e, 'scaleY', 1))
            out[e] = w
            parent_e = e
        for c in e:
            walk(c, w, parent_e if e.tag in TRANSFORMS else parent_e)
    for c in ab:
        walk(c, M(), None)
    return out
