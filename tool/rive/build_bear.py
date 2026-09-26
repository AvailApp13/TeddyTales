"""Сборка мишки для приложения из исходника редактора Rive.

    python3 tool/rive/build_bear.py

1. `rive create` раскладывает `assets_src/rive/bear_boy_v2.rev` (исходник
   заказчика, 26.09) в RML-проект во временной папке.
2. Скрипт правит RML: фон артборда прозрачный, добавляет эмоции
   (`EMOTIONS` ниже — сейчас `emo_smile`).
3. `rive <dir> --once` собирает `.riv` → `assets/rive/bear_boy_v2.riv`.

Нужен Rive CLI 1.1.1 (`docs/rive-bear.md`). Вход в аккаунт Rive для этого
не нужен.
"""

import os
import shutil
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'assets_src/rive/bear_boy_v2.rev')
OUT = os.path.join(ROOT, 'assets/rive/bear_boy_v2.riv')

# Кривые: CSS cubic-bezier.
EI = '0.42 0 0.58 1'   # ease-in-out
EO = '0 0 0.58 1'      # ease-out
EIN = '0.42 0 1 1'     # ease-in
BACK = '0.34 1.56 0.64 1'  # ease-out-back, перелёт

# Объекты рига (id из исходника) и их поза покоя (idle_life, кадр 0).
BEAD_L, BEAD_R = '0:112404', '0:277344'   # бусины глаз
FX_LOVE = '0:107294'                      # глаза-дуги + румянец
ROOT, BODY = '0:390', '0:391'             # таз (y), корпус (поворот)
ARM_L, ARM_R = '0:393', '0:392'
EAR_L, EAR_R = '0:117528', '0:117532'
BELLY = '0:155371'
REST = dict(body=-0.099, arm_l=-2.375, arm_r=2.317, ear_l=-2.617,
            ear_r=-0.557, root_y=811.872, bead_l=0.63, bead_r=0.634)

ROTATION, Y, SCALE_X, SCALE_Y, OPACITY = 15, 91, 16, 17, 18


def kf(frame, value, ease=EI):
    if ease is None:
        return f'<KeyFrameDouble value="{value}" frame="{frame}" interpolationType="hold"/>'
    x1, y1, x2, y2 = ease.split()
    return (f'<KeyFrameDouble value="{value}" frame="{frame}" interpolationType="cubic">'
            f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></KeyFrameDouble>')


def prop(key, frames):
    return f'<KeyedProperty propertyKey="{key}">' + ''.join(kf(*f) for f in frames) + '</KeyedProperty>'


def obj(oid, *props):
    return f'<KeyedObject objectId="{oid}">' + ''.join(props) + '</KeyedObject>'


def emo_smile():
    """Улыбка всем телом, 1,8 с при 60 к/с (заказчик 26.09 — проба)."""
    r = REST
    return 108, [
        # моргнул — улыбка с румянцем — открыл глаза
        obj(BEAD_L, prop(SCALE_Y, [(0, r['bead_l'], EIN), (6, 0.019, None), (90, 0.019, EO), (100, r['bead_l'])]),
            prop(OPACITY, [(0, 1, None), (6, 0, None), (90, 1, None)])),
        obj(BEAD_R, prop(SCALE_Y, [(0, r['bead_r'], EIN), (6, 0.019, None), (90, 0.019, EO), (100, r['bead_r'])]),
            prop(OPACITY, [(0, 1, None), (6, 0, None), (90, 1, None)])),
        obj(FX_LOVE, prop(OPACITY, [(0, 0, None), (4, 0, EO), (14, 1, None), (84, 1, EIN), (94, 0, None)])),
        # корпус: замах, наклон с перелётом, покачивание, возврат
        obj(BODY, prop(ROTATION, [(0, r['body']), (8, r['body'] + 0.02, BACK), (30, r['body'] - 0.075),
                                  (55, r['body'] - 0.06), (80, r['body'] - 0.072), (106, r['body'])])),
        # подскок: присел, вверх, приземлился
        obj(ROOT, prop(Y, [(0, r['root_y']), (8, r['root_y'] + 3, EO), (20, r['root_y'] - 9, EIN),
                           (32, r['root_y'], EO), (38, r['root_y'] - 1.5), (46, r['root_y'], None)])),
        # лапки чуть вверх
        obj(ARM_L, prop(ROTATION, [(0, r['arm_l']), (10, r['arm_l'] - 0.03, BACK), (30, r['arm_l'] + 0.2),
                                   (80, r['arm_l'] + 0.16), (106, r['arm_l'])])),
        obj(ARM_R, prop(ROTATION, [(0, r['arm_r']), (10, r['arm_r'] + 0.03, BACK), (30, r['arm_r'] - 0.2),
                                   (80, r['arm_r'] - 0.16), (106, r['arm_r'])])),
        # уши вздрогнули
        obj(EAR_L, prop(ROTATION, [(0, r['ear_l']), (14, r['ear_l'] - 0.16, EO), (26, r['ear_l'] + 0.05),
                                   (38, r['ear_l'] - 0.06), (96, r['ear_l'] - 0.03), (106, r['ear_l'])])),
        obj(EAR_R, prop(ROTATION, [(0, r['ear_r']), (16, r['ear_r'] + 0.16, EO), (28, r['ear_r'] - 0.05),
                                   (40, r['ear_r'] + 0.06), (96, r['ear_r'] + 0.03), (106, r['ear_r'])])),
        # вдох животом
        obj(BELLY, prop(SCALE_X, [(0, 1.0), (30, 1.06), (106, 1.0)]), prop(SCALE_Y, [(0, 1.0), (30, 1.04), (106, 1.0)])),
    ]


EMOTIONS = {'emo_smile': emo_smile}


def main():
    work = tempfile.mkdtemp(prefix='rive_bear_')
    shutil.copy(SRC, os.path.join(work, 'bear.rev'))
    env = dict(os.environ, RIVE_NO_TUI='1')
    subprocess.run(['rive', 'create', 'bear', '--from-rev=bear.rev'], cwd=work, env=env, check=True)
    project = os.path.join(work, 'bear')
    scene = os.path.join(project, 'scene.rml')
    s = open(scene, encoding='utf-8').read()
    bg = '<SolidColor colorValue="FF282828" name="Component" id="0:4"/>'
    assert s.count(bg) == 1, 'фон артборда не найден'
    s = s.replace(bg, bg.replace('FF282828', '00282828'))
    anchor = s.find('<LinearAnimation duration="864"')
    assert anchor > 0, 'idle_life не найден'
    extra = ''
    for name, build in EMOTIONS.items():
        duration, body = build()
        extra += (f'<LinearAnimation duration="{duration}" loopValue="0" name="{name}">'
                  + ''.join(body) + '</LinearAnimation>\n        ')
    s = s[:anchor] + extra + s[anchor:]
    open(scene, 'w', encoding='utf-8').write(s)
    subprocess.run(['rive', project, '--once'], env=env, check=True)
    shutil.copy(os.path.join(project, 'build', 'bear.riv'), OUT)
    print('готово:', OUT)


if __name__ == '__main__':
    main()
