#!/usr/bin/env python3
"""Показывает и правит цвета внутри `.riv`.

Зачем. Пока настоящий риг не собран, на главном экране крутится сторонний
демонстрационный файл. У таких файлов почти всегда есть собственный фон —
прямоугольник во весь артборд с заливкой. В приложении он закрывает нашу
комнату: вместо кремовой карточки виден чужой чёрный (или синий) фон, и
никакими настройками рантайма это не убрать — `RiveWidget` умеет только
вписать артборд в область, а не отключить в нём слой.

Правка делается по месту: цвет в `.riv` лежит как uint32 ARGB, и замена
не меняет ни длину файла, ни индексы объектов. Удалять объекты нельзя —
ссылки на родителей в формате идут по индексам, любое удаление рассыпет граф.

    python3 tool/riv_paint.py list assets/rive/demo_monster.riv
    python3 tool/riv_paint.py set assets/rive/demo_monster.riv 809=00000000

Ключи свойств и имена типов берутся из сгенерированного реестра ядра Rive,
который приезжает исходниками внутри пакета `rive_native` — отдельной копии
таблицы в репозитории не держим, чтобы она не разошлась с версией пакета.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import struct
import sys
from pathlib import Path

# Как кодируются значения свойств. Bool и Uint — varuint, Bytes и String —
# длина плюс данные, Double — float32, Color — uint32 ARGB.
VARUINT_FIELDS = {'Uint', 'Bool'}
BLOB_FIELDS = {'String', 'Bytes'}

# Типы полей из таблицы файла (для ключей, которых нет в реестре ядра).
TOC_FIELDS = {0: 'Uint', 1: 'String', 2: 'Double', 3: 'Color'}


def find_runtime(explicit: str | None) -> Path:
    """Каталог `runtime/include/rive/generated` из пакета rive_native."""
    if explicit:
        return Path(explicit)
    home = os.environ.get('PUB_CACHE') or str(Path.home() / '.pub-cache')
    pattern = f'{home}/hosted/*/rive_native-*/runtime/include/rive/generated'
    found = sorted(glob.glob(pattern))
    if not found:
        raise SystemExit(
            'Не нашёл исходники rive_native. Выполните `flutter pub get` '
            'или укажите путь через --runtime.'
        )
    return Path(found[-1])


def load_registry(generated: Path) -> tuple[dict[int, str], dict[int, str]]:
    """Возвращает (ключ свойства -> тип поля, ключ типа -> имя класса)."""
    keys: dict[str, int] = {}
    types: dict[int, str] = {}

    for header in generated.rglob('*.hpp'):
        text = header.read_text()
        base = re.search(r'class (\w+)Base\s*:', text)
        if not base:
            continue
        for match in re.finditer(
            r'static const uint16_t (\w+PropertyKey)\s*=\s*(\d+);', text
        ):
            keys[f'{base.group(1)}Base::{match.group(1)}'] = int(match.group(2))
        type_key = re.search(r'static const uint16_t typeKey\s*=\s*(\d+);', text)
        if type_key:
            types[int(type_key.group(1))] = base.group(1)

    registry = generated / 'core_registry.hpp'
    text = registry.read_text()
    start = text.index('static int propertyFieldId(int propertyKey)')
    body = text[start:]
    body = body[: body.index('\n    static ', 10)]

    fields: dict[int, str] = {}
    pending: list[str] = []
    for line in body.splitlines():
        line = line.strip()
        case = re.match(r'case (\w+Base::\w+PropertyKey):', line)
        if case:
            pending.append(case.group(1))
            continue
        ret = re.match(r'return Core(\w+)Type::id;', line)
        if ret:
            for name in pending:
                if name in keys:
                    fields[keys[name]] = ret.group(1)
            pending = []

    return fields, types


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.at = 0

    def varuint(self) -> int:
        value, shift = 0, 0
        while True:
            byte = self.data[self.at]
            self.at += 1
            value |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return value
            shift += 7

    def uint32(self) -> int:
        value = struct.unpack_from('<I', self.data, self.at)[0]
        self.at += 4
        return value

    def skip_blob(self) -> None:
        # Длину читаем отдельной строкой: `self.at += self.varuint()` берёт
        # старое значение `at` до вызова и теряет байты длины.
        length = self.varuint()
        self.at += length


def parse(data: bytes, fields: dict[int, str]) -> list[tuple[int, list]]:
    """Разбирает поток объектов. Возвращает [(тип, [(ключ, тип поля, смещение)])]."""
    reader = Reader(data)
    if data[:4] != b'RIVE':
        raise SystemExit('Это не .riv')
    reader.at = 4
    reader.varuint()  # major
    reader.varuint()  # minor
    reader.varuint()  # file id

    toc_keys: list[int] = []
    while True:
        key = reader.varuint()
        if key == 0:
            break
        toc_keys.append(key)

    # Битовая карта типов: два бита на ключ, но новое 32-битное слово читается
    # каждые четыре ключа — задействован только младший байт слова.
    toc: dict[int, str] = {}
    word, bit = 0, 0
    for key in toc_keys:
        if bit == 0:
            word = reader.uint32()
        toc[key] = TOC_FIELDS[(word >> bit) & 3]
        bit = (bit + 2) % 8

    objects: list[tuple[int, list]] = []
    while reader.at < len(data):
        type_key = reader.varuint()
        if type_key == 0:
            break
        props = []
        while True:
            prop = reader.varuint()
            if prop == 0:
                break
            at = reader.at
            field = fields.get(prop) or toc.get(prop)
            if field is None:
                raise SystemExit(f'Неизвестный ключ свойства {prop} на {at}')
            if field in VARUINT_FIELDS:
                reader.varuint()
            elif field in BLOB_FIELDS:
                reader.skip_blob()
            else:  # Double и Color — по четыре байта
                reader.at += 4
            props.append((prop, field, at))
        objects.append((type_key, props))

    return objects


def colors(objects: list[tuple[int, list]], data: bytes):
    for index, (type_key, props) in enumerate(objects):
        for prop, field, at in props:
            if field == 'Color':
                value = struct.unpack_from('<I', data, at)[0]
                yield index, type_key, prop, at, value


def cmd_list(args, fields, types) -> int:
    data = Path(args.file).read_bytes()
    objects = parse(data, fields)
    print(f'{args.file}: объектов {len(objects)}')
    for index, type_key, prop, at, value in colors(objects, data):
        name = types.get(type_key, str(type_key))
        print(f'  {index:5d}  {name:16s} ключ {prop:3d}  #{value:08X}  байт {at}')
    return 0


def cmd_set(args, fields, types) -> int:
    path = Path(args.file)
    data = bytearray(path.read_bytes())
    objects = parse(bytes(data), fields)
    index_to_offsets: dict[int, list[int]] = {}
    for index, _, _, at, _ in colors(objects, bytes(data)):
        index_to_offsets.setdefault(index, []).append(at)

    for assignment in args.assignments:
        raw_index, _, raw_color = assignment.partition('=')
        index = int(raw_index)
        color = int(raw_color, 16)
        offsets = index_to_offsets.get(index)
        if not offsets:
            raise SystemExit(f'У объекта {index} нет цветовых свойств')
        for at in offsets:
            was = struct.unpack_from('<I', data, at)[0]
            struct.pack_into('<I', data, at, color)
            print(f'  {index:5d}  #{was:08X} -> #{color:08X}  байт {at}')

    path.write_bytes(bytes(data))
    print(f'Записано: {path} ({len(data)} байт, размер не изменился)')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--runtime', help='каталог generated из rive_native')
    sub = ap.add_subparsers(dest='command', required=True)

    lister = sub.add_parser('list', help='показать цвета')
    lister.add_argument('file')
    lister.set_defaults(run=cmd_list)

    setter = sub.add_parser('set', help='заменить цвета: <индекс>=AARRGGBB')
    setter.add_argument('file')
    setter.add_argument('assignments', nargs='+')
    setter.set_defaults(run=cmd_set)

    args = ap.parse_args()
    fields, types = load_registry(find_runtime(args.runtime))
    return args.run(args, fields, types)


if __name__ == '__main__':
    sys.exit(main())
