#!/usr/bin/env python3
"""Автоматическая приёмка рига: проверяет `.riv` по требованиям ТЗ.

Зачем. Риг приезжает от аниматора шестью этапами, и половина требований ТЗ —
числовые: сколько костей, сколько вершин на меш, какая вложенность, сколько
весит файл, все ли входы State Machine на месте. Проверять это глазами в
редакторе долго и ненадёжно, а расхождение вылезает уже в приложении.

    python3 tool/riv_lint.py assets/rive/bear_main.riv

Что важно понимать про границы проверки. Имена компонентов в экспортированный
`.riv` не попадают: редактор их вырезает. В стороннем демо-риге на 3299
объектов сохранилось ровно два имени — самого артборда и события. Поэтому
чеклист именования частей тела (`docs/rig-naming.md`) этим скриптом проверить
нельзя в принципе, он принимается по исходнику `.rev` или по иерархии в
редакторе. Здесь проверяется то, что в файл действительно попадает: имена
артборда, State Machine, входов, анимаций и событий — и вся геометрия.

Ожидаемые имена входов не зашиты в скрипт, а читаются из
`lib/bear/bear_rig_spec.dart` — там единственный источник правды, и если
контракт меняется, линтер меняется вместе с ним сам.
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import riv_paint as riv  # noqa: E402

# Значения по умолчанию — из раздела «Ограничения» docs/rig-naming.md.
MAX_BONES = 60
MAX_VERTICES_PER_MESH = 400
MAX_NESTING = 5
MAX_BYTES = 3 * 1024 * 1024

# Куски WebP и PNG, которые не несут пикселей. Их оставляет Photoshop, и в
# демо-риге они съели 80% веса файла.
WEBP_JUNK = {b'XMP ', b'ICCP', b'EXIF'}
PNG_JUNK = {b'iTXt', b'tEXt', b'zTXt', b'iCCP', b'eXIf'}


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def error(self, text: str) -> None:
        self.errors.append(text)

    def warn(self, text: str) -> None:
        self.warnings.append(text)

    def note(self, text: str) -> None:
        self.notes.append(text)

    def print(self) -> int:
        for text in self.notes:
            print(f'  ·  {text}')
        for text in self.warnings:
            print(f'  ⚠  {text}')
        for text in self.errors:
            print(f'  ✗  {text}')
        print()
        if self.errors:
            print(f'Не принято: нарушений {len(self.errors)}, '
                  f'предупреждений {len(self.warnings)}')
            return 1
        print(f'Принято. Предупреждений: {len(self.warnings)}')
        return 0


def contract_names(repo: Path) -> tuple[str, str, set[str]]:
    """Имена артборда, State Machine и всех входов из спецификации кода."""
    spec = repo / 'lib' / 'bear' / 'bear_rig_spec.dart'
    text = spec.read_text(encoding='utf-8')
    values = dict(re.findall(r"static const String (\w+) = '([^']+)';", text))
    if not values:
        raise SystemExit(f'Не нашёл констант в {spec}')

    artboard = values.get('artboard', 'bear_main')
    machine = values.get('stateMachine', 'bear_main')
    # Пути к файлам и имена объектов входами не являются.
    skip = {'artboard', 'stateMachine'}
    inputs = {
        value
        for name, value in values.items()
        if name not in skip and not value.endswith('.riv')
    }
    return artboard, machine, inputs


def image_junk(blob: bytes) -> tuple[int, list[str]]:
    """Сколько байт в картинке занимают метаданные и какие именно."""
    found: list[str] = []
    total = 0

    if blob[:4] == b'RIFF' and blob[8:12] == b'WEBP':
        at = 12
        while at + 8 <= len(blob):
            tag = blob[at:at + 4]
            size = struct.unpack_from('<I', blob, at + 4)[0]
            if tag in WEBP_JUNK:
                total += size + 8
                found.append(f'{tag.decode("ascii", "replace").strip()} {size}Б')
            at += 8 + size + (size & 1)
    elif blob[:8] == b'\x89PNG\r\n\x1a\n':
        at = 8
        while at + 8 <= len(blob):
            size = struct.unpack_from('>I', blob, at)[0]
            tag = blob[at + 4:at + 8]
            if tag in PNG_JUNK:
                total += size + 12
                found.append(f'{tag.decode("ascii", "replace")} {size}Б')
            at += 12 + size

    return total, found


def lint(path: Path, repo: Path, report: Report) -> None:
    data = path.read_bytes()
    generated = riv.find_runtime(None)
    fields, types = riv.load_registry(generated)
    objects = riv.parse(data, fields)

    def key(name: str) -> int:
        return riv.type_key(types, name)

    def pk(name: str) -> int:
        return riv.property_key(name)

    def value(props, name: str):
        return riv.prop(data, props, pk(name))

    def name_of(props):
        """Первое строковое свойство объекта — это его имя."""
        for prop_key, field, at in props:
            if field == 'String':
                return riv.value_at(data, field, at)
        return None

    print(f'{path} — {len(data)} Б, объектов {len(objects)}\n')

    # --- вес ---------------------------------------------------------------
    if len(data) > MAX_BYTES:
        report.error(f'Вес {len(data) / 1024 / 1024:.2f} МБ больше лимита '
                     f'{MAX_BYTES / 1024 / 1024:.0f} МБ')
    else:
        report.note(f'Вес {len(data) / 1024:.0f} КБ из '
                    f'{MAX_BYTES / 1024 / 1024:.0f} МБ')

    by_type: dict[str, list[tuple[int, list]]] = {}
    for index, (type_key_value, props) in enumerate(objects):
        by_type.setdefault(types.get(type_key_value, str(type_key_value)), []).append(
            (index, props)
        )

    # --- артборд и State Machine -------------------------------------------
    want_artboard, want_machine, want_inputs = contract_names(repo)

    artboards = by_type.get('Artboard', [])
    if len(artboards) != 1:
        report.error(f'Артбордов в файле {len(artboards)}, ожидается 1')
    artboard_index, artboard_props = artboards[0] if artboards else (None, [])
    if artboards:
        got = value(artboard_props, 'ComponentBase::namePropertyKey')
        width = value(artboard_props, 'LayoutComponentBase::widthPropertyKey') or 0
        height = value(artboard_props, 'LayoutComponentBase::heightPropertyKey') or 0
        report.note(f'Артборд «{got}», {width:.0f}x{height:.0f}')
        if got != want_artboard:
            report.error(f'Имя артборда «{got}», по контракту «{want_artboard}»')

    machines = by_type.get('StateMachine', [])
    if len(machines) != 1:
        report.error(f'State Machine в файле {len(machines)}, ожидается 1')
    for _, props in machines:
        got = name_of(props)
        if got != want_machine:
            report.error(f'Имя State Machine «{got}», по контракту «{want_machine}»')

    # --- входы --------------------------------------------------------------
    got_inputs: dict[str, str] = {}
    for kind in ('StateMachineNumber', 'StateMachineBool', 'StateMachineTrigger'):
        for _, props in by_type.get(kind, []):
            got_inputs[name_of(props) or '?'] = kind

    missing = sorted(want_inputs - set(got_inputs))
    extra = sorted(set(got_inputs) - want_inputs)
    if missing:
        report.error(f'Нет входов State Machine ({len(missing)}): '
                     + ', '.join(missing))
    if extra:
        report.warn('Входы, которых нет в контракте: ' + ', '.join(extra))
    if not missing:
        report.note(f'Все {len(want_inputs)} входов на месте')

    # --- кости --------------------------------------------------------------
    bones = by_type.get('Bone', []) + by_type.get('RootBone', [])
    if len(bones) > MAX_BONES:
        report.error(f'Костей {len(bones)}, лимит {MAX_BONES}')
    else:
        report.note(f'Костей {len(bones)} из {MAX_BONES}')

    # --- вершины на меш -----------------------------------------------------
    vertex_types = {'MeshVertex', 'ContourMeshVertex', 'StraightVertex',
                    'CubicDetachedVertex', 'CubicMirroredVertex',
                    'CubicAsymmetricVertex'}
    vertex_keys = {key(name) for name in vertex_types if name in types.values()}
    mesh_key = key('Mesh')
    parent_key = pk('ComponentBase::parentIdPropertyKey')

    # parentId — индекс в списке объектов артборда: сам артборд идёт нулевым,
    # дальше по порядку чтения.
    index_of_component: dict[int, int] = {}
    if artboard_index is not None:
        counter = 0
        for index in range(artboard_index, len(objects)):
            index_of_component[counter] = index
            counter += 1

    per_mesh: dict[int, int] = {}
    for index, (type_key_value, props) in enumerate(objects):
        if type_key_value not in vertex_keys:
            continue
        parent = riv.prop(data, props, parent_key)
        if parent is None:
            continue
        owner = index_of_component.get(parent)
        if owner is not None and objects[owner][0] == mesh_key:
            per_mesh[owner] = per_mesh.get(owner, 0) + 1

    if per_mesh:
        worst = max(per_mesh.values())
        if worst > MAX_VERTICES_PER_MESH:
            report.error(f'Самый тяжёлый меш — {worst} вершин, лимит '
                         f'{MAX_VERTICES_PER_MESH}')
        else:
            report.note(f'Мешей {len(per_mesh)}, максимум вершин на меш — '
                        f'{worst} из {MAX_VERTICES_PER_MESH}')

    # --- вложенность --------------------------------------------------------
    def depth_of(component: int, guard: int = 0) -> int:
        if guard > 64:
            return guard
        index = index_of_component.get(component)
        if index is None or index == artboard_index:
            return 0
        parent = riv.prop(data, objects[index][1], parent_key)
        if parent is None:
            return 1
        return 1 + depth_of(parent, guard + 1)

    if index_of_component:
        deepest = max(depth_of(component) for component in index_of_component)
        if deepest > MAX_NESTING:
            report.error(f'Глубина вложенности {deepest}, лимит {MAX_NESTING}')
        else:
            report.note(f'Глубина вложенности {deepest} из {MAX_NESTING}')

    # --- привязка данных ----------------------------------------------------
    instances = by_type.get('ViewModelInstance', [])
    if len(instances) > 1:
        report.error(
            f'Экземпляров вью-модели {len(instances)}. Рантайм берёт '
            'DataBind.auto() → instance(0), при нескольких экземплярах выбор '
            'перестаёт быть предсказуемым'
        )
    elif instances:
        report.note('Экземпляр вью-модели один — DataBind.auto() однозначен')

    # --- фоновая подложка ---------------------------------------------------
    if artboards:
        width = value(artboard_props, 'LayoutComponentBase::widthPropertyKey') or 0
        height = value(artboard_props, 'LayoutComponentBase::heightPropertyKey') or 0
        for index, props in by_type.get('Rectangle', []):
            rect_w = value(props, 'ParametricPathBase::widthPropertyKey') or 0
            rect_h = value(props, 'ParametricPathBase::heightPropertyKey') or 0
            if rect_w >= width * 0.95 and rect_h >= height * 0.95:
                report.error(
                    f'Прямоугольник {rect_w:.0f}x{rect_h:.0f} (объект {index}) '
                    'закрывает весь артборд — фон рисует приложение, подложки '
                    'в риге быть не должно'
                )

    # --- ключи вне рабочей области ------------------------------------------
    animations = by_type.get('LinearAnimation', [])
    report.note(f'Анимаций {len(animations)}: '
                + ', '.join(sorted(filter(None, (name_of(p) for _, p in animations)))))

    # --- растровые ассеты ----------------------------------------------------
    contents = by_type.get('FileAssetContents', [])
    if contents:
        bytes_key = pk('FileAssetContentsBase::bytesPropertyKey')
        total = junk_total = 0
        dirty: list[str] = []
        names = [name_of(p) for _, p in by_type.get('ImageAsset', [])]
        for position, (_, props) in enumerate(contents):
            blob = riv.prop(data, props, bytes_key)
            if not isinstance(blob, (bytes, bytearray)):
                continue
            total += len(blob)
            junk, found = image_junk(bytes(blob))
            junk_total += junk
            if junk:
                label = names[position] if position < len(names) else f'#{position}'
                dirty.append(f'{label} ({", ".join(found)})')

        report.note(f'Растровых ассетов {len(contents)}, всего '
                    f'{total / 1024:.0f} КБ ({total / len(data) * 100:.0f}% файла)')
        if junk_total:
            report.error(
                f'В картинках {junk_total / 1024:.0f} КБ метаданных '
                f'({junk_total / len(data) * 100:.0f}% веса файла) — '
                'XMP, ICC и EXIF надо срезать перед импортом в Rive. '
                'Грязные: ' + '; '.join(dirty[:6])
                + ('…' if len(dirty) > 6 else '')
            )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('file', type=Path)
    ap.add_argument('--repo', type=Path, default=Path(__file__).resolve().parent.parent)
    args = ap.parse_args()

    report = Report()
    lint(args.file, args.repo, report)
    return report.print()


if __name__ == '__main__':
    sys.exit(main())
