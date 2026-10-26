"""Мимика v2 девочки — лицо как в видео Ирины.

    PYTHONHASHSEED=0 python3 tool/rive/face_v2_girl.py   # → assets/rive/bear_girl_v2.riv

Риг и слои девочки — `build_girl.py` (её кости, зоны, бант, юбка, свои
движения `girl_emotions.py`); поверх — то же лицо v2, что у мальчика
(`face_v2.py`: шов, бусины, дужки, бровки, румянец, слёзы, сердце, рты),
и те же эмоции (`clips_v2.py`) на её телах. Своё у девочки (задание по
кадрам с ней — «Нежность 1–3», «Улыбка 5», «Испуг 1–4»):
- нос — тёмный шоколад (70, 38, 26) «яйцом» 44 × 37,5, верх 436, кончик 473,5
  (был светлый фетровый овал 48 × 34);
- шов — тёмно-коричневая нитка (была серая), стежок 20 px, развилка 493,5,
  «домик» меньше и круче мальчикова: ножка 12 px под 38°;
- бровки — серо-коричневые, тоньше и короче, ниже (y 384);
- закрытые глаза — черта сна без ресничек (в кадрах их не видно);
- дужки — уже (ширина 30), румянец — ниже, у уголков рта, сильнее;
- широкая улыбка — уголки выше.
Бусины, блик, позы шва, свои рты, слёзы, сердце — как у мальчика.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_girl as bg  # noqa: E402  (её риг — правки модулей мальчика при импорте)
import build_bear  # noqa: E402
import clips_v2  # noqa: E402
import face_v2 as fv  # noqa: E402

GIRL = dict(
    fv.BOY,
    out=os.path.join(fv.ROOT, 'assets/rive/bear_girl_v2.riv'),
    nose_bone=((516, 454.8), (516, 444.8)), nose_zone=(516, 454.8, 24, 19.5),
    nose_tip=(516.0, 471.5), junction=(516.0, 493.5),
    leg=12.0, leg_angle=38,
    seam_rgb='#3e2016', brow_rgb='#5c4842',
    brow_y=384.0, brow_half=11.0, brow_w=2.6, brow_arch=3.5,
    arc_half=15.0, arc_t=3.0,
    blush={'l': (454.0, 497.0), 'r': (578.0, 497.0)}, blush_r=(18.0, 14.0), blush_rgb=(240, 135, 140),
    red_peak=0.30,
    wide_y=(0.0, 2.7, 4.8, 6.2, 6.5, 6.0, 4.5, 2.0, -1.5, -8.0, -12.0),
    # закрытые глаза — толстая ровная черта, ресничек в кадрах не видно
    lashes=(),
    bounce=(516.0, 548.0),
    # на белом меху: белок и тяжёлое веко — мех, тень складки бровей светлее,
    # краска лица мягче (на белом иначе слишком красно)
    white_rgb='#f3eceb', lidcap_rgb='#f6f1ef', lidcap_edge='#b9a898', bshade_rgb='#cbbab0',
    flush_rgb=(240, 120, 125), flush_peak=0.55,
    # сердце — по центру груди между пуговицами планки, пуговицы поверх
    heart=(511.0, 636.0), heart_w=120.0, heart_hole=((511.0, 578.0, 16.0), (511.0, 694.0, 16.0)),
)
NOSE_BOX = (648.0, 929.0, 718.0, 989.0)      # верх 436, кончик 473,5, x 494–538 (мир)
NOSE_ROI = (625, 935, 735, 1020)
NOSE_RGB = (70.0, 38.0, 26.0)
NOSE_EGG = (0.35, 0.6)                       # шире всего на 35 % высоты, низ — 0,6 ширины
GIRL['nose_box'] = NOSE_BOX

# Её выражения поверх общих (кадры с ней): нежность — дужки ниже и уже,
# широкая улыбка с уголками выше, румянец сильнее.
GIRL_EXPR = {
    'tender': {'arc': 1.0, 'arch': 5.0, 'p_smile_wide': 1.0, 'corner': 3.0, 'blush': 0.9,
               'cheek': 5.0, 'cheek_sy': 0.05},
}


def prepare(project):
    """Её слои (`build_girl.prepare`), затем лицо v2: нос, бусины, закрытые
    глаза. Глазницы у неё уже мех (`girl_rig.eye_pieces`)."""
    bg.prepare(project)
    fv.nose_edit(os.path.join(project, 'bear_face.png'), NOSE_ROI, NOSE_BOX, NOSE_RGB, egg=NOSE_EGG)
    for side in 'lr':
        fv.bead(os.path.join(project, f'face_gaze_bead_{side}.png'))
        fv.closed_eye(os.path.join(project, f'face_eyes_closed_eye_{side}.png'))


def main():
    fv.install(GIRL)
    clips_v2.register(extra=GIRL_EXPR, girl=True)
    try:
        build_bear.main(out=GIRL['out'], prepare=prepare)
    finally:
        shutil.rmtree(bg.TILES, ignore_errors=True)


if __name__ == '__main__':
    main()
