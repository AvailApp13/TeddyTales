"""Мимика v2 мальчика — лицо как в видео Ирины.

    PYTHONHASHSEED=0 python3 tool/rive/face_v2.py   # → assets/rive/bear_boy_v3.riv

Заказчик 26.10: «всё, что я прислал, нужно полностью один в один
реализовать на нашего мишку… глазки, всё»; разбор кадров, замеры и этапы —
`docs/mimika-v2.md`. Риг тот же, что у мальчика (`build_bear.py`,
`rebuild_rig.py`), поверх — новое лицо; нынешний файл мальчика
(`bear_boy_v2.riv`) не меняется, пока заказчик не скажет «да» новому.

Сделано:
- рот — вышитый шов своим рисунком на костях (`vec.py`) вместо картинки
  ротика покоя: стежок от носа вниз и «домик» ∧ (замеры кадров «Спокойствие»:
  стежок 19–29 px, ножки 13–17 px под 30–45° вниз, ширина 27–34 px, цвет —
  тёмный шоколад, толщина ~2,2 px). Стежок от носа виден всегда, «домик» —
  ротик покоя: гаснет, когда раскрывается любой рот эмоции (`MOUTH_SWAP`);
- рты-линии мальчика (довольный, грусть, обида, сонный) — не картинки, а
  позы того же шва: у ножек по пять костей (`SEAM_BONES`), поза — их сдвиг
  от покоя (`POSES`). Все готовые клипы и петли зовут прежние
  `mouth_open(kind=...)` и `_mood_mouth(...)` — сюда они приходят позой шва,
  датчики `mh_<вид>` для приложения те же. Картинки ртов-линий не
  строятся; их прозрачности в приложении (`mop_<вид>`) — прозрачность шва.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_bear  # noqa: E402
import rebuild_rig as rr  # noqa: E402
import vec  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets/rive/bear_boy_v3.riv')

# --- Рот-шов -------------------------------------------------------------------
SEAM_RGB = '#4a2610'        # тёмный шоколад (кадры видео: #3e2111–#58300d)
SEAM_W = 2.2                # толщина, px мира
NOSE_TIP = (513.5, 484.0)   # стежок начинается внутри низа носа
JUNCTION = (513.5, 503.0)   # развилка «домика»
LEG = 17.0                  # длина ножки
LEG_ANGLE = 35              # градусов вниз от горизонтали


LEG_T = (0.2, 0.4, 0.6, 0.8, 1.0)      # кости ножки — доли её длины
LEG_STEPS = 15                          # точек на ножку (линия гладкая)


def _rest_leg(s, t):
    """Ножка «домика» в покое, от развилки: s = −1 левая, +1 правая; конец
    чуть загибается вниз (кадры «Спокойствие 1–6»)."""
    a = math.radians(LEG_ANGLE)
    return s * LEG * t * math.cos(a), LEG * t * math.sin(a) + 1.6 * t * t


# Позы шва (замеры кадров, docs/mimika-v2.md; МГ = 112 px): сдвиг развилки и
# ножка от развилки как функция доли длины t.
POSES = {
    # «Спокойствие»: домик ∧
    'rest': ((0.0, 0.0), _rest_leg),
    # «Улыбка 1, 3»: сомкнутая «ω» шириной 0,40 МГ — от развилки ножка
    # уходит вниз (прогиб 0,07 МГ) и загибается вверх, уголок выше
    # развилки; стежок от носа короче
    'smile': ((0.0, -2.0), lambda s, t: (s * 22.5 * t, 8.5 * math.sin(math.pi * t) - 4.0 * t * t)),
    # «Улыбка 2, 4», «Радость 3»: широкая «ω» 0,80–0,85 МГ
    'smile_wide': ((0.0, -3.0), lambda s, t: (s * 46.0 * t, 7.0 * math.sin(math.pi * t) - 6.0 * t * t)),
    # «Грусть 1, 2, 4»: узкий домик 0,20–0,24 МГ, ножки загибаются вниз
    'sad': ((0.0, 1.0), lambda s, t: (s * 11.5 * t, 9.0 * t + 3.5 * t * t)),
    # «Обида 3»: крошечный домик 0,18–0,22 МГ, уголки сильно вниз
    'pout': ((0.0, 2.0), lambda s, t: (s * 10.5 * t, 7.0 * t + 6.0 * t * t)),
    # «Сонливость 1–2»: спокойный домик, чуть шире и положе
    'sleepy': ((0.0, 0.5), lambda s, t: (s * 15.0 * t, 7.0 * t + 1.5 * t * t)),
}
# ротик-линия прежних клипов → поза шва
SEAM_KINDS = {'content': 'smile', 'sad': 'sad', 'pout': 'pout', 'sleepy': 'sleepy'}
SEAM_BONES = ['seam_c'] + [f'seam_{side}{i}' for side in 'lr' for i in range(1, len(LEG_T) + 1)]


def _bone_world(name):
    if name == 'seam_c':
        return JUNCTION
    s = -1 if name[5] == 'l' else 1
    dx, dy = _rest_leg(s, LEG_T[int(name[6:]) - 1])
    return JUNCTION[0] + dx, JUNCTION[1] + dy


# кости шва — дети лица (мех у рта держится за лицо), в конце списка: id
# прежних костей не меняются
for _n in SEAM_BONES:
    _x, _y = _bone_world(_n)
    rr.CHAIN.append((_n, 'face', (round(_x, 3), round(_y, 3)), (round(_x, 3), round(_y, 3) - 10)))


def pose_offsets(pose, k=1.0):
    """{кость: (dx, dy) мира} — сдвиг костей шва от покоя к позе, доля k."""
    (jx, jy), leg = POSES[pose]
    out = {'seam_c': (jx * k, jy * k)}
    for side, s in (('l', -1), ('r', 1)):
        for i, t in enumerate(LEG_T, 1):
            px, py = leg(s, t)
            rx, ry = _rest_leg(s, t)
            out[f'seam_{side}{i}'] = ((jx + px - rx) * k, (jy + py - ry) * k)
    return out


def _to_local(dx, dy):
    """Сдвиг мира → ключи x/y кости эмоции под лицом (лицо смотрит вверх:
    локальный x — вверх, y — вправо)."""
    return -dy, dx


def _leg_weights(side, t):
    knots = [0.0] + list(LEG_T)
    names = ['seam_c'] + [f'seam_{side}{i}' for i in range(1, len(LEG_T) + 1)]
    for (t0, a), (t1, b) in zip(zip(knots, names), zip(knots[1:], names[1:])):
        if t <= t1 + 1e-9:
            u = (t - t0) / (t1 - t0)
            return {n: v for n, v in ((a, 1 - u), (b, u)) if v > 1e-4}
    return {names[-1]: 1.0}


def seam(ctx):
    """Шов вместо картинки ротика покоя: та же роль в клипах и приложении
    (ключи прозрачности `mouth_rest_img`, клип `mop_rest`); картинки
    ртов-линий убраны, их прозрачность — прозрачность шва."""
    ab, B = ctx['ab'], ctx['B']
    rest = ctx['byname'].get('face_mouth_rest_img') or next(
        e for e in ab.iter('Image') if e.get('name') == 'face_mouth_rest_img')
    holder = next(p for p in ab.iter() if rest in list(p))
    hw = ctx['W'][holder]
    common = dict(bones=B, pack=rr.pack, next_id=ctx['next_id'], holder_world=hw, stroke=(SEAM_W, SEAM_RGB))

    # стежок от носа: верх — за мехом носа, низ — за развилкой
    nose_pts = [(NOSE_TIP[0], NOSE_TIP[1] + (JUNCTION[1] - NOSE_TIP[1]) * i / 6) for i in range(7)]

    def nose_w(x, y):
        u = (y - NOSE_TIP[1]) / (JUNCTION[1] - NOSE_TIP[1])
        fur = rr.weights_for('face_seam', x, y, B)
        w = {b: v * (1 - u) for b, v in fur.items()}
        w['seam_c'] = w.get('seam_c', 0) + u
        return {b: v for b, v in w.items() if v > 1e-4}
    nose = vec.shape('face_seam_nose', nose_pts, weights=nose_w, **common)

    leg_pts, leg_ws = [], []
    for side, s in (('l', -1), ('r', 1)):
        part = []
        for i in range(LEG_STEPS + 1):
            t = i / LEG_STEPS
            dx, dy = _rest_leg(s, t)
            part.append(((JUNCTION[0] + dx, JUNCTION[1] + dy), _leg_weights(side, t)))
        if side == 'l':
            part = part[::-1]
        else:
            part = part[1:]
        for p, w in part:
            leg_pts.append(p)
            leg_ws.append(w)
    lookup = dict(zip(leg_pts, leg_ws))
    legs = vec.shape('face_seam_legs', leg_pts, weights=lambda x, y: lookup[(x, y)], **common)

    at = list(holder).index(rest)
    holder.insert(at, legs)
    holder.insert(at, nose)
    holder.remove(rest)
    rr.E_IDS['mouth_rest_img'] = legs.get('id')
    for kind in SEAM_KINDS:                    # картинки ртов-линий не нужны
        img = next(e for e in ab.iter('Image') if e.get('id') == rr.E_IDS[f'mouth_{kind}_img'])
        next(p for p in ab.iter() if img in list(p)).remove(img)
        rr.E_IDS[f'mouth_{kind}_img'] = legs.get('id')


rr.HOOKS.append(seam)


# --- Клипы: рты-линии → позы шва ---------------------------------------------
_mouth_open = rr.Emo.mouth_open
_build = rr.Emo.build


def mouth_open(self, pts, kind='open'):
    """Рты-линии прежних клипов — поза шва; доля позы — «высота» рта.
    Полости (смех, зевок, жевание) — как раньше."""
    if kind not in SEAM_KINDS:
        return _mouth_open(self, pts, kind)
    ez = (lambda p: p[3] if len(p) > 3 else rr.EI)
    self.track(f'mh_{kind}', self.Y, [(p[0], p[2], ez(p)) for p in pts])
    self.__dict__.setdefault('_seam', []).append(
        (SEAM_KINDS[kind], [(p[0], min(1.0, max(0.0, p[2])), ez(p)) for p in pts]))
    return self


def build(self):
    """Позы шва клипа — в ключи костей шва; несколько поз складываются.
    Рот-линия считается ртом клипа: ротик покоя (шов) не гаснет — это он и
    есть, а рты петли клип закрывает, как раньше (`Emo._rest_mouth`)."""
    seams = self.__dict__.pop('_seam', [])
    for pose, _ in seams:
        kind = next(k for k, p in SEAM_KINDS.items() if p == pose)
        self.mouth_h.setdefault(kind, [(0, 0.0)])
    if len(seams) == 1:
        pose, amt = seams[0]
        for bone, (dx, dy) in pose_offsets(pose).items():
            lx, ly = _to_local(dx, dy)
            self.track(bone, self.X, [(f, lx * a, e) for f, a, e in amt])
            self.track(bone, self.Y, [(f, ly * a, e) for f, a, e in amt])
    elif seams:
        end = self.dur - 2
        frames = list(range(0, end + 1, 2))
        tracks = {}
        for pose, amt in seams:
            curve = [(0, 0.0, rr.EI)] + amt + [(end, 0.0, None)]
            for fr in frames:
                a = rr.track_at(curve, fr)
                for bone, (dx, dy) in pose_offsets(pose, a).items():
                    acc = tracks.setdefault(bone, {}).setdefault(fr, [0.0, 0.0])
                    acc[0] += dx
                    acc[1] += dy
        for bone, by_fr in tracks.items():
            xs = [(fr, _to_local(*by_fr[fr])[0], rr.LIN) for fr in frames[1:-1]]
            ys = [(fr, _to_local(*by_fr[fr])[1], rr.LIN) for fr in frames[1:-1]]
            self.track(bone, self.X, xs)
            self.track(bone, self.Y, ys)
    return _build(self)


rr.Emo.mouth_open = mouth_open
rr.Emo.build = build

_mood_mouth = rr._mood_mouth


def mood_mouth(spec, kind, w, h):
    """Рот петли настроения: рты-линии — поза шва (доля — высота рта)."""
    if kind not in SEAM_KINDS:
        return _mood_mouth(spec, kind, w, h)
    spec[(f'mh_{kind}', rr.Emo.Y)] = h
    for bone, (dx, dy) in pose_offsets(SEAM_KINDS[kind]).items():
        lx, ly = _to_local(dx, dy)
        prev_x = spec.get((bone, rr.Emo.X))
        prev_y = spec.get((bone, rr.Emo.Y))
        spec[(bone, rr.Emo.X)] = (lambda lx, prev: lambda t: lx * min(1.0, max(0.0, h(t)))
                                  + (prev(t) if prev else 0.0))(lx, prev_x)
        spec[(bone, rr.Emo.Y)] = (lambda ly, prev: lambda t: ly * min(1.0, max(0.0, h(t)))
                                  + (prev(t) if prev else 0.0))(ly, prev_y)


rr._mood_mouth = mood_mouth


def main():
    build_bear.main(out=OUT)


if __name__ == '__main__':
    main()
