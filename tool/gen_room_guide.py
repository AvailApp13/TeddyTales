"""Собирает `docs/room-furnishing.md` — решение по каждой вещи комнаты.

Читает `lib/game/item_metrics.dart` и `lib/game/room_slots.dart` и считает по
камере комнаты то же, что считает приложение: какой ширины вещь в метрах,
какой она станет на экране в каждом месте и куда вообще встанет.

Документ не пишется руками именно поэтому: разойдись он с кодом — и разговор
о размерах пойдёт по бумажке, которая врёт.

    python3 tool/gen_room_guide.py
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Камера детской — из lib/game/room_camera.dart.
EYE = 0.38
FLOOR_LINE = 0.525
WALL_TOP = 0.15
CEILING_M = 2.5
ART_W, ART_H = 941, 1672
CAMERA_M = (FLOOR_LINE - EYE) / (FLOOR_LINE - WALL_TOP) * CEILING_M

TITLES = {}


def width_per_metre(y: float) -> float:
    return (y - EYE) / CAMERA_M * ART_H / ART_W


def metrics() -> dict[str, tuple[float, float, str]]:
    text = (ROOT / 'lib/game/item_metrics.dart').read_text()
    found = re.findall(
        r"'([a-z_]+)': ItemMetrics\(([0-9.]+), ([0-9.]+), ItemFit\.([a-z]+)\)",
        text,
    )
    return {i: (float(w), float(a), fit) for i, w, a, fit in found}


def slots() -> list[dict]:
    text = (ROOT / 'lib/game/room_slots.dart').read_text()
    out = []
    for block in re.findall(r'RoomSlot\((.*?)\n  \)', text, re.S):
        field = dict(re.findall(r"(\w+): ([^,\n]+),", block))
        if 'nursery' not in field.get('id', ''):
            continue
        out.append({
            'id': field['id'].strip("'"),
            'x': float(field['x']),
            'y': float(field['y']),
            'fit': field['fit'].split('.')[1],
            'metres': float(field['metres']),
            'max': float(field['maxMetres']),
        })
    return out


def titles() -> dict[str, str]:
    text = (ROOT / 'lib/game/shop_items.dart').read_text()
    pairs = re.findall(r"id: '([a-z_]+)',\s*\n\s*title: '([^']+)'", text)
    return dict(pairs)


SLOT_NAMES = {
    'nursery.floor_left': 'у окна',
    'nursery.floor_right': 'у задней стены',
    'nursery.corner_right': 'правый угол',
    'nursery.rug': 'под ногами',
    'nursery.toy_left': 'слева от мишки',
    'nursery.toy_right': 'справа от мишки',
    'nursery.wall_shelf': 'стена, над комодом',
    'nursery.wall_pic_left': 'стена, слева',
    'nursery.wall_pic_right': 'стена, справа',
}


def main() -> int:
    items, names, places = metrics(), titles(), slots()

    lines = [
        '# Комната: решение по каждой вещи',
        '',
        '> Файл собирается скриптом `tool/gen_room_guide.py` из',
        '> `lib/game/item_metrics.dart` и `lib/game/room_slots.dart`.',
        '> Не править руками: меняются размеры — правится код, документ',
        '> пересобирается.',
        '',
        '## Как считается размер',
        '',
        'У каждой вещи есть настоящая ширина в метрах. Высоту даёт сама',
        'картинка: она обрезана впритык к вещи, поэтому её пропорция — это',
        'пропорция вещи.',
        '',
        'Место в комнате не задаёт размер. Оно говорит только, **где** вещь',
        'стоит, а размер считает перспектива:',
        '',
        '```',
        'доля ширины кадра = ширина в метрах × (y − точка схода) / высота камеры',
        '```',
        '',
        f'Детская снята с высоты {CAMERA_M:.2f} м (точка схода {EYE}, стык стены',
        f'с полом {FLOOR_LINE}, потолок {CEILING_M} м). Проверка формулы — сама',
        'комната: стена в 2.5 м встаёт ровно от пола до карниза. Вторая',
        'проверка — обставленный фон, который прислал заказчик: кресло на нём',
        'выходит 0.85 × 0.64 м, ковёр — метр в поперечнике.',
        '',
        'Мишка ростом 1.15 м стоит на линии 0.80 — он и есть мерка, с которой',
        'сверяется всё остальное.',
        '',
        '## Места детской',
        '',
        '| Место | Где | Линия пола | Принимает до | Что здесь стоит |',
        '|---|---|---|---|---|',
    ]

    for slot in places:
        fits = [
            names.get(i, i)
            for i, (w, _, fit) in sorted(items.items())
            if fit == slot['fit'] and w <= slot['max'] + 1e-9
        ]
        lines.append(
            f"| `{slot['id'].split('.')[1]}` | {SLOT_NAMES.get(slot['id'], '')} "
            f"| {slot['y']:.3f} | {slot['max']:.2f} м | {len(fits)} вещей |"
        )

    lines += [
        '',
        '## Вещи',
        '',
        'Ширина и высота — настоящие, в метрах. «На экране» — какую долю',
        'ширины кадра вещь займёт в своём месте (для стен — на стене).',
        '',
        '| Вещь | id | Ш × В, м | Держится | Места | На экране |',
        '|---|---|---|---|---|---|',
    ]

    order = sorted(items.items(), key=lambda kv: (kv[1][2], -kv[1][0]))
    for item_id, (w, aspect, fit) in order:
        homes = [s for s in places if s['fit'] == fit and w <= s['max'] + 1e-9]
        if not homes:
            share = '—'
            where = '—'
        else:
            y = FLOOR_LINE if fit == 'wall' else homes[0]['y']
            share = f'{w * width_per_metre(y) * 100:.0f}%'
            where = ', '.join(
                SLOT_NAMES.get(s['id'], s['id']) for s in homes
            )
        lines.append(
            f"| {names.get(item_id, item_id)} | `{item_id}` "
            f"| {w:.2f} × {w * aspect:.2f} | {fit} | {where} | {share} |"
        )

    lines.append('')
    (ROOT / 'docs/room-furnishing.md').write_text('\n'.join(lines))
    print(f'вещей {len(items)}, мест в детской {len(places)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
