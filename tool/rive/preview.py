"""Кадр мишки в нужный момент клипа — для проверки рига без приложения.

    python3 tool/rive/preview.py <проект> <клип> <кадр>[,<кадр>…] <папка> [--alone]
    python3 tool/rive/preview.py <проект> bind 0 <папка>   # поза привязки

<проект> — RML-проект, который собирает `build_bear.py` (временная папка
`/tmp/rive_bear_*/bear`, путь печатает сборка). Скрипт делает рядом копию
сцены, в которой машина состояний играет покой `idle_life` и поверх него
<клип> — как приложение: покой двигает кости, клип — кости эмоций, и одно
складывается с другим. `--alone` — клип без покоя. Клип `bind` — пустой:
мишка в позе привязки, ни одна анимация его не трогает (так проверяется,
что правка рига не сдвинула покой ни на пиксель).

Каждый кадр — отдельный запуск `rive --screenshot` (сборка ~25 с), снимок
<папка>/<клип>_<кадр>.png, 1024×1024. Кадры — при 60 к/с, как ключи клипов.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def stage(project, clip, alone):
    """Копия проекта с машиной состояний «покой + клип» по умолчанию."""
    work = tempfile.mkdtemp(prefix='rive_preview_')
    copy = os.path.join(work, 'bear')
    os.mkdir(copy)
    for name in os.listdir(project):
        if name in ('build', 'scene.rml'):
            continue
        os.symlink(os.path.join(project, name), os.path.join(copy, name))
    tree = ET.parse(os.path.join(project, 'scene.rml'))
    ab = tree.getroot().find('Artboard')
    anims = {a.get('name'): a for a in ab.iter('LinearAnimation')}
    if clip == 'bind':
        empty = ET.Element('LinearAnimation', {'duration': '60', 'loopValue': '0', 'name': 'bind'})
        ab.append(empty)
        anims['bind'] = empty
        alone = True
    if clip not in anims:
        raise SystemExit(f'нет клипа {clip}')
    for n, an in (('idle_life', anims['idle_life']), (clip, anims[clip])):
        an.set('id', an.get('id') or f'9:99{len(n):02d}{abs(hash(n)) % 10000:04d}')
    sm = ET.Element('StateMachine', {'name': 'preview', 'id': '9:990000'})
    layers = [] if alone else [('idle', anims['idle_life'])]
    layers.append(('clip', anims[clip]))
    for i, (lname, an) in enumerate(layers):
        layer = ET.SubElement(sm, 'StateMachineLayer', {'name': lname, 'id': f'9:99010{i}'})
        ET.SubElement(layer, 'AnyState', {'x': '200', 'y': '-120'})
        ET.SubElement(layer, 'ExitState', {'x': '400', 'y': '-120'})
        entry = ET.SubElement(layer, 'EntryState', {'x': '0', 'y': '0'})
        ET.SubElement(entry, 'StateTransition', {'stateToId': f'9:99020{i}'})
        ET.SubElement(layer, 'AnimationState', {'x': '200', 'y': '0', 'animationId': an.get('id'),
                                                'id': f'9:99020{i}'})
    ab.insert(0, sm)
    ab.set('defaultStateMachineId', '9:990000')
    tree.write(os.path.join(copy, 'scene.rml'), encoding='unicode')
    return work, copy


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    alone = '--alone' in sys.argv
    project, clip, frames, out = args
    os.makedirs(out, exist_ok=True)
    work, copy = stage(project, clip, alone)
    try:
        for fr in frames.split(','):
            png = os.path.abspath(os.path.join(out, f'{clip}_{fr}.png'))
            subprocess.run(['rive', copy, f'--screenshot={png}', f'--advance={int(fr) + 1}'],
                           check=True, env=dict(os.environ, RIVE_NO_TUI='1'),
                           stdout=subprocess.DEVNULL)
            print(png)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
