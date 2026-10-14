"""Эмоции девочки — свои, женственные и ярче мальчиковых (заказчик 14.10).

«Для девочки давай добавим эмоции намного поярче… Девочка должна быть
женственной, головой так не трясти… мимически по-другому… рот
открывается вообще не так — когда зевает, когда жует, когда смеется…
нужно сделать красиво».

Приёмы — из обаятельной анимации персонажей (принципы «appeal», маскоты
Rive и Live2D):
- голова не трясётся: наклоняется набок (кокетливый наклон) и плавно
  покачивается по дуге; корпус отвечает S-линией — грудь навстречу;
  бант и ушки догоняют пружинами приложения;
- радость — плечики вверх (ключицы), «хи-хи» — грудью и плечиками, а не
  головой;
- глазки закрываются дужками (^ ^) — с её плитки смеха Higgsfield:
  бусины сначала сплющиваются в черту, как в моргании, и в этот миг
  встают дужки — подмены не видно; моргание покоя не вклинивается;
- ротик меньше и мягче: открытая улыбка-полумесяц с её плитки смеха,
  зевок — аккуратное «о», жевание — маленькое «ам» и «ням» с надутыми
  щёчками;
- румянец нарастает и гаснет плавно — в радости, нежности, ласке
  (⚠ показать заказчику: мальчику 27.09 румянец не делали).

Нижнее веко бусину вверх не поднимает (заказчик 10.10), два рта сразу не
видны — сборка проверяет (`check_eyes`, `check_mouths`).
"""
import math

import mouth
import rebuild_rig as rr
from rebuild_rig import BACK, EI, EO, LIN, Emo

# Её верхняя губа (мир): сюда встаёт верх полостей с челюстью. Ротик покоя
# у девочки — y 495 (у мальчика 507,5, губа 500).
LIP_Y = 489.0
# Полное раскрытие её челюсти — доля полости: зевок — аккуратное «о» (у
# мальчика 0,8 — широкий зевок), жевание — небольшое «ам».
JAW_K = {'yawn': 0.42, 'chew': 0.5}


# --- Помощники ----------------------------------------------------------------

def blush(e, pts):
    """Румянец: pts [(кадр, сила 0..1[, кривая])]; с покоя и в покой."""
    frames = [(0, 0.0, EI)] + [(p[0], p[1], p[2] if len(p) > 2 else EI) for p in pts]
    frames.append((e.dur - 2, 0.0, None))
    e.ch[(rr.E_IDS['face_blush'], Emo.OP)] = frames
    return e


def happy(e, spans, n=5, squint=()):
    """Глазки-дужки (^ ^): spans [(с кадра, по кадр)]. Бусины за n кадров
    сплющиваются в черту — встают дужки — и обратно. squint — прищур
    улыбки вне дужек [(кадр, доля)]."""
    pts = list(squint)
    for on, off in spans:
        pts += [(on - n, 0.0 if not squint else 0.2), (on, 0.95, EO), (off, 0.95), (off + n, 0.0, EO)]
    pts.sort(key=lambda p: p[0])
    e.eyes(pts, lid='both')
    e.face('happy', spans)
    e.face('blink', [])
    return e


def shoulders(e, pts):
    """Плечики вверх: pts [(кадр, подъём, рад)] — обе ключицы."""
    e.pair('clav', Emo.R, pts, mirror=True)
    return e


def tilt(e, pts, chest=0.3, turn=40.0):
    """Наклон головы набок (рад) с S-линией: грудь чуть навстречу (с
    запаздыванием 4 кадра; chest=0 — грудь не трогать), лицо слегка
    поворачивается за наклоном."""
    e.track('head', Emo.R, pts)
    if chest:
        cp, last = [], 0
        for p in pts:
            fr = min(p[0] + 4, e.dur - 4)
            if fr > last:
                cp.append((fr, -chest * p[1], *p[2:]))
                last = fr
        e.track('chest', Emo.R, cp)
    e.track('face', Emo.Y, [(p[0], turn * p[1], *p[2:]) for p in pts])
    return e


def jaw_mouth(e, pts, kind):
    """Рот с нижней челюстью (зевок, жевание): pts [(кадр, ширина, высота
    [, кривая])] как у Emo.mouth_open; верхняя губа стоит на её LIP_Y,
    нижняя челюсть опускается на JAW_K высоты полости."""
    _, top, bot = mouth.rows(kind)
    H = JAW_K[kind] * (bot - top)
    e.mouth_open(pts, kind=kind)
    e.track(f'mouth_{kind}', Emo.X, [(2, top - LIP_Y), (e.dur - 6, top - LIP_Y)])
    e.track(f'jaw_{kind}', Emo.Y, [(p[0], H * p[2], p[3] if len(p) > 3 else EI) for p in pts])
    return H


def beats(times, fade, peak, low, lag=0, up=9, down=13):
    """Толчки «хи»: в кадрах times пик через up кадров, спад через down."""
    pts = []
    for a, k in zip(times, fade):
        pts += [(a + lag + up, low + (peak - low) * k), (a + lag + up + down, low)]
    return pts


# --- Эмоции -------------------------------------------------------------------

def emo_smile():
    """Улыбка, 2,5 с: маленькая открытая улыбка-полумесяц, уголки высоко,
    щёчки вверх; голова кокетливо склоняется набок по дуге, плечико к
    щеке; лёгкий румянец."""
    e = Emo(150)
    e.mouth_open([(6, 0.05, 0.0), (32, 0.55, 0.3, EO), (112, 0.52, 0.28), (136, 0.15, 0.0)])
    e.pair('mouth', Emo.X, [(10, 0), (32, 8, EO), (112, 7.5), (136, 0.5)])
    e.pair('mouth', Emo.Y, [(32, -1.5), (112, -1.3), (136, 0)], mirror=True)
    e.track('chin', Emo.X, [(32, -0.8), (112, -0.6), (136, 0)])
    e.eyes([(8, 0.0), (32, 0.2, EO), (112, 0.18), (140, 0.0)])
    e.pair('lid', Emo.X, [(32, 6, EO), (112, 5.5), (140, 0)])
    e.pair('cheek', Emo.X, [(10, 0), (34, 5, EO), (112, 4.6), (140, 0)])
    e.pair('cheek', Emo.SY, [(34, 0.07), (112, 0.065), (140, 0)])
    e.pair('brow', Emo.X, [(34, 2.5, EO), (112, 2.2), (140, 0)])
    tilt(e, [(8, -0.01), (42, 0.09, EO), (80, 0.075), (112, 0.085), (142, 0.0)])
    e.track('face', Emo.X, [(42, 2.0), (112, 1.6), (142, 0)])
    shoulders(e, [(14, 0.0), (42, 0.05, EO), (108, 0.04), (138, 0.0)])
    e.track('breath', Emo.SY, [(10, 0.02), (40, 0.035), (110, 0.03), (142, 0)])
    e.track('hips', Emo.Y, [(10, 1.5, EO), (36, -3), (110, -2.5), (142, 0)])
    rr._ears(e, [(18, -0.06, EO), (46, 0.02), (76, -0.02), (120, 0.0)])
    blush(e, [(18, 0.0), (52, 0.5, EO), (112, 0.45), (142, 0.0)])
    return e.build()


def emo_laugh():
    """Смех, 4 с — девичье хихиканье: вдох, плечики вверх, глазки
    закрываются дужками, ротик — открытая улыбка средней величины; пять
    мягких «хи» — грудью и плечиками, рот чуть шире на каждом; голова
    склонена набок и почти не качается; румянец. В конце глазки
    открываются, улыбка гаснет."""
    e = Emo(240)
    g = [54, 76, 98, 120, 142]
    fade = [1 - 0.1 * i for i in range(len(g))]
    mo = [(8, 0.05, 0.0), (30, 0.5, 0.28), (50, 0.72, 0.52, EO)]
    for a, k in zip(g, fade):
        mo += [(a + 9, 0.76, 0.52 + 0.12 * k), (a + 22, 0.72, 0.52)]
    mo += [(176, 0.68, 0.42), (196, 0.5, 0.18), (212, 0.3, 0.03), (224, 0.1, 0.0)]
    e.mouth_open(mo)
    e.pair('mouth', Emo.X, [(28, 8, EO), (176, 8), (220, 1)])
    e.pair('mouth', Emo.Y, [(28, -1.5), (176, -1.5), (220, 0)], mirror=True)
    e.track('chin', Emo.X, [(50, -1.5)] + beats(g, fade, -2.2, -1.5) + [(176, -1.4), (220, 0)])
    happy(e, [(36, 186)])
    e.pair('cheek', Emo.X, [(36, 6, EO)] + beats(g, fade, 7.5, 6) + [(186, 6), (214, 0)])
    e.pair('cheek', Emo.SY, [(36, 0.08), (186, 0.08), (214, 0)])
    e.pair('brow', Emo.X, [(36, 2.0), (186, 2.0), (214, 0)])
    e.track('breath', Emo.SY, [(6, -0.01), (30, 0.04, EO)] + beats(g, fade, 0.06, 0.03, -2) + [(186, 0.025), (226, 0)])
    shoulders(e, [(10, 0.0), (36, 0.07, EO)] + beats(g, fade, 0.095, 0.07, -1) + [(186, 0.06), (222, 0.0)])
    tilt(e, [(10, -0.01), (46, 0.11, EO)] + beats(g, fade, 0.12, 0.105, 2) + [(186, 0.1), (228, 0.0)])
    e.track('face', Emo.X, [(46, 1.5)] + beats(g, fade, 2.2, 1.5, 1) + [(186, 1.4), (228, 0)])
    e.track('hips', Emo.Y, [(12, 1.0), (40, -2.0, EO)] + beats(g, fade, -2.8, -2.0, -1) + [(186, -1.5), (228, 0)])
    rr._ears(e, [(40, -0.05)] + beats(g, fade, -0.07, -0.04, 3) + [(200, -0.02)])
    blush(e, [(24, 0.0), (60, 0.85, EO), (186, 0.8), (226, 0.0)])
    return e.build()


def emo_surprised():
    """Удивление, 2,2 с — «ах!»: глазки круглые, бровки вверх, плечики
    вверх, ротик — маленькое «о»; чуть отклонилась назад, голова набок.
    Без прыжка."""
    e = Emo(132)
    e.eyes([(4, 0.0), (12, 0.14, BACK), (96, 0.11), (122, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(12, 4.0, BACK), (96, 3.4), (122, 0)])
    jaw_mouth(e, [(4, -0.1, 0.0), (12, -0.25, 0.42, EO), (96, -0.28, 0.36), (118, -0.1, 0.0)], 'yawn')
    shoulders(e, [(4, 0.0), (12, 0.08, BACK), (90, 0.05), (122, 0.0)])
    e.track('face', Emo.X, [(12, 3.5, BACK), (96, 2.5)])
    tilt(e, [(4, 0.0), (14, -0.03, BACK), (60, -0.055), (96, -0.05), (124, 0.0)])
    e.track('breath', Emo.SY, [(12, 0.05, BACK), (96, 0.035)])
    e.track('hips', Emo.Y, [(4, 1.5), (12, -3.0, BACK), (40, -2.0), (96, -1.5)])
    rr._ears(e, [(10, -0.1, BACK), (96, -0.07), (124, 0.0)])
    e.face('blink', [])
    return e.build()


def emo_yawn():
    """Зевок, 3,6 с — аккуратный: вдох, плечики вверх, голова чуть назад и
    набок, глазки зажмурены, ротик — небольшое «о» (нижняя челюсть, без
    широкого рта мальчика); выдох — мягко осела, довольное «м-м» сомкнутой
    улыбкой. Головой после зевка не трясёт."""
    e = Emo(216)
    H = jaw_mouth(e, [(10, 0.0, 0.0), (40, 0.05, 0.3), (74, 0.15, 1.0, EO), (104, 0.12, 0.94),
                      (120, 0.15, 1.0), (148, 0.05, 0.3), (164, 0.0, 0.0)], 'yawn')
    e.track('jaw_yawn', Emo.X, [(80, 0), (88, 0.4), (96, -0.3), (104, 0.2), (112, 0)])
    e.mouth_open([(168, 0.05, 0.0), (184, 0.6, 0.5, EO), (198, 0.55, 0.45), (210, 0.1, 0.0)], kind='content')
    e.eyes([(6, 0.0), (44, 0.82, EO), (150, 0.8), (186, 0.0)], lid='both')
    e.face('blink', [])
    e.pair('lid', Emo.X, [(44, 7, EO), (150, 6.5), (186, 0)])
    e.pair('ulid', Emo.X, [(44, -4, EO), (150, -3.5), (186, 0)])
    e.pair('brow', Emo.X, [(50, 2.5, EO), (140, 2.2), (176, 0)])
    e.track('chin', Emo.X, [(10, 0), (74, -0.25 * H, EO), (120, -0.25 * H), (164, 0)])
    e.track('muzzle', Emo.SX, [(74, 0.05, EO), (120, 0.045), (160, 0)])
    e.pair('cheek', Emo.SY, [(74, -0.03), (120, -0.025), (160, 0)])
    e.track('breath', Emo.SY, [(20, 0.03), (74, 0.08, EO), (120, 0.07), (166, -0.015), (196, 0)])
    shoulders(e, [(16, 0.0), (74, 0.08, EO), (120, 0.07), (166, 0.0)])
    e.track('hips', Emo.Y, [(74, -4, EO), (120, -3.2), (166, 1.5), (196, 0)])
    e.track('face', Emo.X, [(74, 4, EO), (125, 3.5), (166, 0)])
    tilt(e, [(30, 0.0), (80, 0.07, EO), (125, 0.065), (180, 0.03), (206, 0.0)])
    rr._ears(e, [(74, 0.06), (125, 0.05), (176, 0.0)])
    return e.build()


def emo_chew():
    """Жуёт, 4,1 с — по-девичьи, «ням-ням»: откусила — маленькое «ам»;
    пять жевков — ротик едва приоткрывается, нижняя челюсть ходит по
    кругу, щёчки надуваются там, где еда, и еда перекатывается; довольный
    прищур, голова мягко покачивается (без кивков); проглотила — сомкнутая
    довольная улыбка и румянец. Тайминг — как у мальчика (кухня ждёт
    4,1 с)."""
    DUR = 248
    e = Emo(DUR)
    T, C0, N = 36, 30, 5
    C1 = C0 + T * N
    side = [1, -1, 1, -1, 1]
    food = [1, 1, -1, -1, 1]
    ss = rr.smooth

    def bump(t, a, b):
        return math.sin(math.pi * (t - a) / (b - a)) ** 2 if a <= t <= b else 0.0

    def M(t):
        return ss(4, 14, t) * (1 - ss(204, 220, t))

    def Env(t):
        return ss(26, 40, t) * (1 - ss(C1 - 12, C1 + 4, t))

    def v(t):
        return (1 - math.cos(2 * math.pi * (t - C0) / T)) / 2 if C0 <= t <= C1 else 0.0

    def lat(t):
        if not C0 <= t <= C1:
            return 0.0
        k = min(N - 1, int((t - C0) // T))
        return side[k] * math.sin(2 * math.pi * (t - C0) / T)

    def fd(t):
        k = (t - C0) / T - 0.5
        i = max(0, min(N - 1, math.floor(k)))
        j = max(0, min(N - 1, i + 1))
        u = ss(0.0, 1.0, k - math.floor(k)) if k >= 0 else 0.0
        return food[i] * (1 - u) + food[j] * u

    def bite(t):
        return bump(t, 2, 26)

    def swallow(t):
        return bump(t, 200, 226)

    def content(t):
        return ss(214, 226, t) * (1 - ss(232, 244, t))

    def samp(fn, lag=0):
        return [(f, fn(f - lag), LIN) for f in range(3, DUR - 3, 3)]

    def opn(t):                                 # раскрыт: 1 — вся полость
        return 0.08 * M(t) + 0.7 * bite(t) + 0.45 * Env(t) * v(t)

    def wid(t):
        return -0.25 * M(t) + 0.15 * bite(t)
    _, top, bot = mouth.rows('chew')
    H = JAW_K['chew'] * (bot - top)
    e.mouth_open([(f, wid(f), opn(f), LIN) for f in range(3, DUR - 3, 3)], kind='chew')
    e.track('mouth_chew', Emo.X, [(2, top - LIP_Y, LIN), (DUR - 6, top - LIP_Y, LIN)])
    e.track('jaw_chew', Emo.Y, samp(lambda t: H * opn(t)))
    e.track('jaw_chew', Emo.X, samp(lambda t: 1.8 * Env(t) * lat(t)))
    e.track('jaw_chew', Emo.R, samp(lambda t: 0.05 * Env(t) * lat(t)))
    e.mouth_open([(222, 0.05, 0.0), (232, 0.7, 0.6, EO), (240, 0.6, 0.5), (244, 0.1, 0.0)], kind='content')
    e.track('chin', Emo.X, samp(lambda t: -0.3 * H * opn(t) + 0.6 * Env(t) * (1 - v(t)) - 1.5 * swallow(t)))
    e.track('chin', Emo.Y, samp(lambda t: 1.8 * Env(t) * lat(t)))
    e.track('muzzle', Emo.X, samp(lambda t: 0.4 * M(t) + 0.7 * Env(t) * (1 - v(t))))
    e.track('cheek_l', Emo.SY, samp(lambda t: M(t) * (0.1 + 0.11 * max(0.0, fd(t))) + 0.06 * Env(t) * (1 - v(t))))
    e.track('cheek_r', Emo.SY, samp(lambda t: M(t) * (0.1 + 0.11 * max(0.0, -fd(t))) + 0.06 * Env(t) * (1 - v(t))))
    e.pair('cheek', Emo.X, samp(lambda t: 2.0 * M(t) + 1.0 * Env(t) * (1 - v(t)) + 3 * content(t)))
    e.pair('mouth', Emo.X, samp(lambda t: 1.5 * M(t) + 1.5 * Env(t) * (1 - v(t)) + 4 * content(t)))
    e.eyes(samp(lambda t: 0.25 * M(t) + 0.06 * Env(t) * (1 - v(t)) + 0.15 * content(t)))
    e.pair('lid', Emo.X, samp(lambda t: 5 * M(t) + 2 * Env(t) * (1 - v(t)) + 2 * content(t)))
    # голова мягко покачивается, без кивков; плечики радуются
    sway = lambda t: Env(t) * math.sin(2 * math.pi * (t - C0) / (2 * T))
    e.track('head', Emo.R, samp(lambda t: 0.03 * M(t) + 0.022 * sway(t) + 0.04 * content(t)))
    e.track('face', Emo.Y, samp(lambda t: 1.6 * sway(t) + 1.5 * content(t), 3))
    e.track('face', Emo.X, samp(lambda t: 0.3 * Env(t) * v(t) - 1.0 * bite(t) - 1.5 * swallow(t)))
    e.pair('clav', Emo.R, samp(lambda t: 0.02 * M(t) + 0.03 * content(t)), mirror=True)
    e.track('breath', Emo.SY, samp(lambda t: 0.015 * M(t) + 0.006 * Env(t) * v(t) + 0.02 * swallow(t)))
    e.track('ear_l1', Emo.R, samp(lambda t: -0.02 * sway(t), 5))
    e.track('ear_r1', Emo.R, samp(lambda t: -0.02 * sway(t), 5))
    blush(e, [(196, 0.0), (228, 0.5, EO), (238, 0.45)])
    return e.build()


def emo_lick():
    """Смакует, 2,8 с: глазки-дужки от удовольствия, широкая сомкнутая
    улыбка, три «ням» — губки поджимаются; голова блаженно покачивается
    набок по дуге, плечики вверх; румянец."""
    e = Emo(170)
    s_ = [28, 60, 92]

    def nyam(base, peak, up=10, down=26):
        pts = []
        for a in s_:
            pts += [(a + up, peak), (a + down, base)]
        return pts
    mo = [(8, 0.1, 0.0), (26, 1.2, 1.3, EO)]
    for a in s_:
        mo += [(a + 10, 1.36, 0.85), (a + 26, 1.2, 1.3)]
    mo += [(136, 1.2, 1.3), (160, 0.1, 0.0)]
    e.mouth_open(mo, kind='content')
    e.pair('mouth', Emo.X, [(14, 4, EO), (26, 7)] + nyam(7, 8.5) + [(136, 7), (160, 0)])
    e.track('chin', Emo.X, [(12, 0)] + nyam(0.3, 1.6) + [(136, 0.3), (160, 0)])
    e.track('muzzle', Emo.X, [(12, 0)] + nyam(0.4, 1.2) + [(136, 0.4), (160, 0)])
    happy(e, [(22, 140)])
    e.pair('cheek', Emo.X, [(26, 8, EO)] + nyam(8, 9.5) + [(136, 8), (162, 0)])
    e.pair('cheek', Emo.SY, [(26, 0.09, EO), (136, 0.085), (162, 0)])
    e.pair('brow', Emo.X, [(30, 2.5, EO), (136, 2.2), (162, 0)])
    tilt(e, [(8, 0.0), (30, 0.08, EO), (62, 0.04), (94, 0.085), (126, 0.05), (160, 0.0)])
    e.track('face', Emo.X, [(26, 1.5), (150, 1.2), (164, 0)])
    shoulders(e, [(10, 0.0), (28, 0.05, EO)] + nyam(0.05, 0.065, 8, 24) + [(136, 0.05), (162, 0.0)])
    e.track('breath', Emo.SY, [(20, 0.025)] + nyam(0.02, 0.035, 8, 24) + [(150, 0.015)])
    rr._ears(e, [(26, -0.04), (58, 0.02), (90, -0.03), (122, 0.01), (150, 0.0)])
    blush(e, [(16, 0.0), (44, 0.65, EO), (136, 0.6), (164, 0.0)])
    return e.build()


def emo_love():
    """Любовь, 3,6 с: нежность — глазки мечтательно закрыты дужками, тихая
    сомкнутая улыбка, голова медленно и глубоко склоняется набок и
    покачивается, плечики приподняты, будто обнимает себя; счастливый
    вздох; румянец сильнее всего."""
    e = Emo(216)
    e.mouth_open([(10, 0.1, 0.0), (44, 1.15, 1.2, EO), (176, 1.15, 1.2), (204, 0.1, 0.0)], kind='content')
    e.pair('mouth', Emo.X, [(14, 0), (44, 6, EO), (176, 6), (204, 0)])
    happy(e, [(40, 186)], n=8)
    e.pair('cheek', Emo.X, [(50, 7, EO), (176, 7), (206, 0)])
    e.pair('cheek', Emo.SY, [(50, 0.07, EO), (176, 0.065), (206, 0)])
    e.pair('brow', Emo.X, [(50, 2.2, EO), (176, 2.0), (206, 0)])
    tilt(e, [(10, 0.0), (58, 0.14, EO), (98, 0.11), (138, 0.145), (178, 0.115), (210, 0.0)])
    e.track('face', Emo.X, [(56, 1.2), (176, 1.0), (208, 0)])
    shoulders(e, [(20, 0.0), (64, 0.07, EO), (176, 0.06), (210, 0.0)])
    e.track('breath', Emo.SY, [(20, 0.01), (64, 0.07, EO), (120, 0.02), (176, 0.03), (208, 0)])
    e.track('hips', Emo.Y, [(64, -2.5, EO), (120, -1), (176, -1.5), (208, 0)])
    e.track('hips', Emo.X, [(56, 1.5), (96, 0.5), (136, 1.8), (176, 0.8), (208, 0)])
    rr._ears(e, [(60, 0.08), (136, 0.1), (176, 0.08), (208, 0.0)])
    blush(e, [(20, 0.0), (64, 0.95, EO), (176, 0.9), (210, 0.0)])
    return e.build()


def emo_upset():
    """Обиделась, 3 с — «надулась», не злая: щёчки круглые, губки
    надуты вбок, веки тяжёлые, носик кверху, плечики вверх; «хмф!» —
    отвернулась, глазки закрыла, плечики ещё выше. Без притопов."""
    e = Emo(180)
    e.mouth_open([(8, 0.1, 0.0), (24, 0.62, 0.55, EO), (124, 0.62, 0.55), (140, 0.5, 0.7, EO),
                  (160, 0.5, 0.7), (174, 0.1, 0.0)], kind='pout')
    e.track('mouth_pout', Emo.Y, [(8, 0), (24, 5, EO), (124, 5), (140, 7, EO), (160, 7), (174, 0)])
    e.track('mouth_pout', Emo.R, [(8, 0), (24, 0.12, EO), (124, 0.12), (140, 0.18, EO), (160, 0.18), (174, 0)])
    e.eyes([(6, 0.0), (22, 0.3, EO), (124, 0.28), (140, 0.9, EO), (152, 0.9), (170, 0.0)], lid='top')
    e.pair('ulid', Emo.X, [(22, -3, EO), (124, -3), (140, -8, EO), (152, -8), (170, 0)])
    e.pair('cheek', Emo.SY, [(18, 0.14, EO), (160, 0.12), (174, 0)])
    e.pair('cheek', Emo.X, [(20, 1, EO), (160, 0.8), (174, 0)])
    e.pair('mouth', Emo.X, [(20, -2.5, EO), (160, -2.2), (172, 0)])
    e.track('chin', Emo.X, [(20, 2.5, EO), (160, 2.2), (172, 0)])
    e.track('muzzle', Emo.SX, [(20, 0.04, EO), (160, 0.035), (172, 0)])
    shoulders(e, [(10, 0.0), (24, 0.06, EO), (60, 0.045), (124, 0.045), (138, 0.085, EO), (158, 0.07),
                  (176, 0.0)])
    e.track('head', Emo.R, [(20, -0.02), (124, -0.02), (140, -0.07, EO), (160, -0.065), (176, 0.0)])
    e.track('face', Emo.Y, [(124, 0), (140, -6, EO), (160, -5.5), (176, 0)])
    e.track('face', Emo.X, [(24, 1.5, EO), (124, 1.5), (140, 3.0, EO), (160, 2.8), (176, 0)])
    e.track('chest', Emo.R, [(140, 0.015), (160, 0.012), (176, 0)])
    e.track('breath', Emo.SY, [(8, 0.03), (22, -0.02), (118, -0.02), (130, 0.04), (140, -0.02), (160, -0.015)])
    rr._ears(e, [(16, 0.1), (160, 0.08), (176, 0.0)])
    return e.build()


# --- Ласка, щекотка, «ой» -------------------------------------------------------

def _pet_face_emo(e, at=None):
    """Лицо «гладят»: глазки-дужки, тихая улыбка, щёчки вверх, румянец.
    at — выход (держит до at[0], к at[1] — покой); иначе нарастает к
    PET_HOLD и держится."""
    f = rr.PET_HOLD
    hold = at is None

    def k(v):
        return [(f, v, EO)] if hold else rr.at_pts(at, v)
    e.pair('cheek', Emo.X, k(7))
    e.pair('cheek', Emo.SY, k(0.07))
    e.pair('brow', Emo.X, k(2))
    e.pair('mouth', Emo.X, k(6))
    if hold:
        e.eyes([(f - 6, 0.0), (f - 2, 0.95, EO)], lid='both')
        e.ch[(rr.E_IDS['face_happy'], Emo.OP)] = [(0, 0.0, None), (f - 2, 1.0, None)]
        e.ch[(rr.E_IDS['face_blush'], Emo.OP)] = [(0, 0.0, EI), (f + 6, 0.7, EO)]
    else:
        e.eyes([(at[0], 0.95), (at[0] + 5, 0.0, EO)], lid='both')
        e.ch[(rr.E_IDS['face_happy'], Emo.OP)] = [(0, 1.0, None), (at[0], 0.0, None)]
        e.ch[(rr.E_IDS['face_blush'], Emo.OP)] = [(0, 0.7, EI), (at[1], 0.0, None)]
    e.face('blink', [])


def pet_face():
    e = Emo(40)
    _pet_face_emo(e)
    e.mouth_open([(4, 0.1, 0.0), (rr.PET_HOLD, 1.15, 1.2, EO)], kind='content')
    return rr._drop_end(*e.build())


def pet_out():
    """Отпустили: ещё миг блаженствует, открывает глазки, мягко смотрит
    вверх с улыбкой, ушко дёрнулось. Без подскока."""
    e = Emo(60)
    _pet_face_emo(e, at=(12, 34))
    e.mouth_open([(12, 1.15, 1.2), (40, 0.1, 0.0)], kind='content')
    e.track('face', Emo.X, [(12, 0.0), (30, 2.5, EO), (52, 0.0)])
    e.track('ear_r1', Emo.R, [(30, 0.0), (34, -0.08), (40, 0.03), (46, 0.0)])
    shoulders(e, [(12, 0.0), (26, 0.04, EO), (50, 0.0)])
    dur, ch = e.build()
    _, held = pet_face()
    missing = set(held) - set(ch)
    assert not missing, missing
    for key, frames in ch.items():
        if key in held:
            frames[0] = (0, held[key][-1][1], frames[0][2])
    return dur, ch


def act_pet_b():
    """Щекотно, 2,5 с: глазки-дужки, хихикает — ротик-полумесяц толчками,
    плечики поджаты к ушкам; ёжится — корпус мягко изгибается, голова
    склонена набок и не мотается; румянец."""
    e = Emo(150)
    g = [20, 44, 68, 92]
    fade = [1.0] * len(g)
    mo = [(4, 0.05, 0.0), (16, 0.7, 0.5, EO)]
    for a in g:
        mo += [(a + 8, 0.75, 0.64), (a + 20, 0.7, 0.5)]
    mo += [(118, 0.66, 0.38), (132, 0.35, 0.03), (146, 0.1, 0.0)]
    e.mouth_open(mo)
    happy(e, [(12, 130)], n=4)
    e.pair('cheek', Emo.X, [(14, 6, EO)] + [p for a in g for p in ((a + 8, 7.5), (a + 20, 6))] + [(128, 6), (146, 0)])
    e.pair('cheek', Emo.SY, [(14, 0.08), (128, 0.08), (146, 0)])
    e.pair('mouth', Emo.X, [(14, 7, EO), (128, 7), (146, 0)])
    e.pair('brow', Emo.X, [(14, 1.5), (128, 1.5), (146, 0)])
    shoulders(e, [(4, 0.0), (14, 0.09, EO)] + beats(g, fade, 0.11, 0.09, -1, 8, 12) + [(128, 0.08), (146, 0.0)])
    side = []
    for i, a in enumerate(g):
        s = 1 if i % 2 == 0 else -1
        side += [(a + 8, s), (a + 20, 0.3 * s)]
    e.track('chest', Emo.R, [(f, 0.015 * s) for f, s in side] + [(140, 0)])
    e.track('hips', Emo.X, [(f, 1.5 * s) for f, s in side] + [(140, 0)])
    e.track('hips', Emo.Y, [(12, 1.5, EO), (128, 1.5), (146, 0)])
    e.track('breath', Emo.SY, [(12, -0.025, EO)] + [(a + 8, -0.035) for a in g] + [(128, -0.025), (146, 0)])
    tilt(e, [(4, 0.0), (18, 0.1, EO)] + beats(g, fade, 0.11, 0.095, 2, 8, 12) + [(128, 0.09), (146, 0.0)],
         chest=0)
    e.track('face', Emo.X, [(12, -1.5, EO), (128, -1.2), (146, 0)])
    rr._ears(e, [(14, -0.04)] + beats(g, fade, -0.06, -0.03, 3, 8, 12) + [(140, 0.0)])
    blush(e, [(8, 0.0), (30, 0.8, EO), (128, 0.75), (148, 0.0)])
    return e.build()


def pet_startle():
    """Вздрогнула, 0,7 с — «ой!»: глазки шире, бровки и плечики вверх,
    ротик — маленькое «о»; быстро (0,08 с), потом мягко в покой."""
    e = Emo(42)
    e.eyes([(5, 0.12, EO), (16, 0.07), (36, 0.0)], lid='wide')
    e.pair('brow', Emo.X, [(5, 3.0, EO), (16, 2.0), (36, 0)])
    shoulders(e, [(5, 0.07, EO), (18, 0.04), (36, 0.0)])
    rr._ears(e, [(5, -0.08, EO), (16, -0.05), (36, 0.0)])
    e.track('face', Emo.X, [(5, 2.5, EO), (16, 1.6), (36, 0)])
    e.track('hips', Emo.Y, [(5, -2.0, EO), (14, 0.5), (26, 0)])
    e.track('breath', Emo.SY, [(5, 0.04, EO), (20, 0.01), (36, 0)])
    jaw_mouth(e, [(3, -0.1, 0.0), (7, -0.25, 0.4, EO), (18, -0.25, 0.32), (34, -0.1, 0.0)], 'yawn')
    return e.build()


def idle_bonus_5():
    """Встряхнулась, 2 с — по-девичьи, без тряски: зажмурилась, плечики
    вверх-вниз, голова мягко набок — в другую сторону — ровно (по 0,4 с),
    ушки и бант догоняют; открыла глазки. На кухне это «не то положили» —
    мягкое «не хочу»."""
    e = Emo(120)
    e.eyes([(4, 0.0), (14, 0.85, EO), (88, 0.85), (102, 0.0)], lid='both')
    e.face('blink', [])
    e.track('muzzle', Emo.X, [(10, 1.2), (88, 1.2), (100, 0.0)])
    tilt(e, [(10, 0.0), (32, 0.07, EO), (58, -0.06, EI), (84, 0.02, EO), (106, 0.0)])
    shoulders(e, [(8, 0.0), (22, 0.06, EO), (38, 0.02), (54, 0.06), (72, 0.02), (96, 0.0)])
    e.track('hips', Emo.X, [(34, 1.2), (60, -1.0), (86, 0.3), (106, 0.0)])
    e.track('breath', Emo.SY, [(14, 0.02), (40, -0.01), (60, 0.015), (90, 0.0)])
    rr._ears(e, [(30, -0.04), (56, 0.04), (80, -0.02), (100, 0.0)])
    return e.build()


def mood_dirty():
    """Грязнуля: морщит носик, глазки прищурены, губки поджаты; раз за
    петлю «отряхивается» — плечики вверх-вниз и мягкий наклон головы туда
    и обратно (без дрожи), ушки догоняют."""
    sp = {}
    fluff = lambda t: rr.mbump(t, 390, 60) * math.sin(2 * math.pi * (t - 330) / 40)
    sp[('hips', Emo.X)] = lambda t: 1.2 * fluff(t)
    sp[('head', Emo.R)] = lambda t: 0.05 * fluff(t - 4)
    sp[('clav_l', Emo.R)] = lambda t: 0.05 * abs(fluff(t))
    sp[('clav_r', Emo.R)] = lambda t: -0.05 * abs(fluff(t))
    sp[('ear_l1', Emo.R)] = lambda t: 0.06 * fluff(t - 6) + 0.1 * rr.mbump(t, 150, 8)
    sp[('ear_r1', Emo.R)] = lambda t: -0.06 * fluff(t - 6)
    sp[('muzzle', Emo.X)] = lambda t: 1.0
    rr._mood_eyes(sp, lambda t: 0.15, lambda t: 0.15 + 0.2 * rr.mbump(t, 390, 40))
    rr._pair(sp, 'brow', Emo.X, lambda t: -1.0)
    rr._mood_mouth(sp, 'pout', lambda t: 0.6, lambda t: 0.5)
    return sp


CLIPS = {
    'emo_smile': emo_smile, 'emo_laugh': emo_laugh, 'emo_surprised': emo_surprised,
    'emo_yawn': emo_yawn, 'emo_chew': emo_chew, 'emo_lick': emo_lick,
    'emo_love': emo_love, 'emo_upset': emo_upset,
    'pet_face': pet_face, 'pet_out': pet_out, 'act_pet_b': act_pet_b, 'pet_startle': pet_startle,
    'idle_bonus_5': idle_bonus_5,
}
MOODS = {'mood_dirty': mood_dirty}
