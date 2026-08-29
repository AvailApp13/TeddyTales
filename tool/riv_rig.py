#!/usr/bin/env python3
"""Правит структуру рига внутри `.riv`: порядок отрисовки и лишние слои.

Зачем. Редактор Rive пишет слои артборда в файл в том же порядке, в каком они
стоят в панели Hierarchy, а рантайм рисует записанного раньше ПОВЕРХ тех, кто
идёт следом (проверено изоляционным тестом на официальном рантайме). В сборке
v3 голова записана раньше глаз, поэтому лицо было закрыто мехом, а «пальчики»
arm_root лежали поверх торса. Поправить это в редакторе сейчас нельзя: MCP из
Rive убран (см. rive.app/docs/editor/mcp/integration), а руками порядок легко
сбить снова. Поэтому порядок задан здесь списком и применяется к файлу.

    python3 tool/riv_rig.py inspect assets/rive/bear_main.riv
    python3 tool/riv_rig.py fix assets/rive/bear_main.riv

Правка не «по месту»: поток объектов разбирается целиком и пересобирается
заново, поэтому пересчитываются все ссылки по индексам — `parentId` компонентов,
`objectId` кейфрейм-дорожек и `assetId` картинок. Безопасность обеспечивает
round-trip: перед любой записью файл пересобирается без изменений и сверяется
байт в байт с оригиналом; не сошлось — выходим, ничего не тронув.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from riv_paint import Reader, find_runtime, load_registry  # noqa: E402

VARUINT_FIELDS = {'Uint', 'Bool'}
BLOB_FIELDS = {'String', 'Bytes'}
TOC_FIELDS = {0: 'Uint', 1: 'String', 2: 'Double', 3: 'Color'}

# Порядок отрисовки сверху вниз: первый в списке рисуется поверх остальных.
# Веки и открытый рот лежат над лицом (их включает анимация), лицо над головой,
# уши за головой, лапы поверх кофты, ноги в самом низу.
DRAW_ORDER = [
    'eyelid_left_v2',
    'eyelid_right_v2',
    'mouth_open_v2',
    'eye_left',
    'eye_right',
    'nose',
    'mouth_stitch',
    'head',
    'ear_left',
    'ear_right',
    'paw_left',
    'paw_right',
    'torso',
    'legs_tummy_v2',
]

# Куски первой волны (нарисованы нейросетью, а не сняты с игрушки). В наборе
# деталей их уже нет — из рига и из файла ассетов они тоже уходят.
DROP = {'arm_root_left', 'arm_root_right'}


class Rig:
    """Разобранный `.riv`: заголовок и поток объектов со значениями свойств."""

    def __init__(self, data: bytes, fields: dict[int, str]) -> None:
        reader = Reader(data)
        if data[:4] != b'RIVE':
            raise SystemExit('Это не .riv')
        reader.at = 4
        for _ in range(3):  # major, minor, file id
            reader.varuint()

        toc_keys: list[int] = []
        while True:
            key = reader.varuint()
            if key == 0:
                break
            toc_keys.append(key)
        toc: dict[int, str] = {}
        word, bit = 0, 0
        for key in toc_keys:
            if bit == 0:
                word = reader.uint32()
            toc[key] = TOC_FIELDS[(word >> bit) & 3]
            bit = (bit + 2) % 8

        self.header = data[:reader.at]
        self.objects: list[tuple[int, list[tuple[int, str, object]]]] = []
        # Поток может обрываться концом файла, а может закрываться нулевым
        # ключом типа. Запоминаем, как было, чтобы вернуть файл байт в байт.
        self.terminated = False
        while reader.at < len(data):
            type_key = reader.varuint()
            if type_key == 0:
                self.terminated = True
                break
            props: list[tuple[int, str, object]] = []
            while True:
                key = reader.varuint()
                if key == 0:
                    break
                field = fields.get(key) or toc.get(key)
                if field is None:
                    raise SystemExit(f'Неизвестный ключ свойства {key}')
                if field in VARUINT_FIELDS:
                    value = reader.varuint()
                elif field in BLOB_FIELDS:
                    length = reader.varuint()
                    value = data[reader.at:reader.at + length]
                    reader.at += length
                elif field == 'Double':
                    value = struct.unpack_from('<f', data, reader.at)[0]
                    reader.at += 4
                else:  # Color
                    value = struct.unpack_from('<I', data, reader.at)[0]
                    reader.at += 4
                props.append((key, field, value))
            self.objects.append((type_key, props))
        self.tail = data[reader.at:]

    def dumps(self) -> bytes:
        out = bytearray(self.header)
        for type_key, props in self.objects:
            out += varuint(type_key)
            for key, field, value in props:
                out += varuint(key)
                if field in VARUINT_FIELDS:
                    out += varuint(value)
                elif field in BLOB_FIELDS:
                    out += varuint(len(value)) + value
                elif field == 'Double':
                    out += struct.pack('<f', value)
                else:
                    out += struct.pack('<I', value)
            out += b'\x00'
        if self.terminated:
            out += b'\x00'
        return bytes(out) + self.tail


def varuint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def get(props: list, key: int):
    for prop_key, _, value in props:
        if prop_key == key:
            return value
    return None


def put(props: list, key: int, value) -> None:
    for index, (prop_key, field, _) in enumerate(props):
        if prop_key == key:
            props[index] = (prop_key, field, value)
            return
    raise SystemExit(f'У объекта нет свойства {key}')


class Scene:
    """Индексы того, что нам интересно: артборд, картинки, ассеты, дорожки."""

    NAME, PARENT = 4, 5
    ASSET_NAME, ASSET_ID, OBJECT_ID = 203, 206, 51
    # Кейфрейм ссылается на кривую разгона тем же номером компонента, что и
    # дорожка — на свой объект. Забыть про неё нельзя: ссылка уезжает, кривая
    # не находится, и анимация тихо перестаёт двигаться, хотя файл открывается
    # и рисуется правильно.
    INTERPOLATOR_ID = 69

    def __init__(self, rig: Rig, types: dict[int, str]) -> None:
        self.rig, self.types = rig, types
        self.assets: list[int] = []       # индексы объектов ImageAsset
        self.images: list[int] = []       # индексы объектов Image
        self.artboard: int | None = None
        for index, (type_key, props) in enumerate(rig.objects):
            name = types.get(type_key)
            if name == 'ImageAsset':
                self.assets.append(index)
            elif name == 'Artboard':
                if self.artboard is not None:
                    raise SystemExit('В файле больше одного артборда')
                self.artboard = index
            elif name == 'Image':
                self.images.append(index)
        if self.artboard is None:
            raise SystemExit('Не нашёл артборд')

    def asset_names(self) -> list[bytes]:
        return [get(self.rig.objects[i][1], self.ASSET_NAME) for i in self.assets]

    def image_name(self, index: int) -> str:
        asset = get(self.rig.objects[index][1], self.ASSET_ID)
        return self.asset_names()[asset].decode()

    def local_id(self, index: int) -> int:
        """Номер компонента внутри артборда: сам артборд — ноль."""
        return index - self.artboard


def cmd_inspect(rig: Rig, scene: Scene) -> int:
    print(f'объектов {len(rig.objects)}, картинок {len(scene.images)}, '
          f'ассетов {len(scene.assets)}')
    print('порядок отрисовки (первый — поверх всех):')
    for index in scene.images:
        print(f'  {scene.local_id(index):3d}  {scene.image_name(index)}')
    return 0


def cmd_fix(rig: Rig, scene: Scene, path: Path) -> int:
    by_name = {scene.image_name(i): i for i in scene.images}
    missing = [n for n in DRAW_ORDER if n not in by_name]
    if missing:
        raise SystemExit(f'В файле нет слоёв: {", ".join(missing)}')
    extra = set(by_name) - set(DRAW_ORDER) - DROP
    if extra:
        raise SystemExit(f'Незнакомые слои: {", ".join(sorted(extra))}')

    # 1. Ассеты: выкидываем ненужные вместе с их содержимым (пара объектов
    #    ImageAsset + FileAssetContents) и строим карту старый номер -> новый.
    names = [name.decode() for name in scene.asset_names()]
    keep = [i for i, name in enumerate(names) if name not in DROP]
    asset_map = {old: new for new, old in enumerate(keep)}
    drop_objects = set()
    for old, name in enumerate(names):
        if name in DROP:
            at = scene.assets[old]
            drop_objects.update({at, at + 1})  # ImageAsset и его содержимое
    for name in DROP:
        if name in by_name:
            drop_objects.add(by_name[name])

    # 2. Новые локальные номера компонентов: порядок картинок задаёт DRAW_ORDER,
    #    всё остальное внутри артборда остаётся на своих местах.
    ordered = [by_name[name] for name in DRAW_ORDER]
    head = [i for i in range(scene.artboard, min(scene.images))
            if i not in drop_objects]
    tail = [i for i in range(max(scene.images) + 1, len(rig.objects))
            if i not in drop_objects]
    before = [i for i in range(scene.artboard) if i not in drop_objects]
    new_indices = before + head + ordered + tail
    local_map = {scene.local_id(old): position
                 for position, old in enumerate(head + ordered + tail)}

    # 3. Пересобираем поток и правим ссылки по индексам.
    objects = [rig.objects[i] for i in new_indices]
    rig.objects = objects
    for type_key, props in objects:
        name = rig.types.get(type_key)
        if name == 'Image':
            put(props, Scene.ASSET_ID, asset_map[get(props, Scene.ASSET_ID)])
        elif name == 'KeyedObject':
            old = get(props, Scene.OBJECT_ID)
            if old not in local_map:
                raise SystemExit(f'Дорожка ссылается на удалённый объект {old}')
            put(props, Scene.OBJECT_ID, local_map[old])
        elif get(props, Scene.INTERPOLATOR_ID) is not None:
            old = get(props, Scene.INTERPOLATOR_ID)
            if old not in local_map:
                raise SystemExit(f'Кейфрейм ссылается на удалённую кривую {old}')
            put(props, Scene.INTERPOLATOR_ID, local_map[old])

    path.write_bytes(rig.dumps())
    print(f'Записано: {path} ({path.stat().st_size} байт)')
    return 0


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ('inspect', 'fix'):
        raise SystemExit(__doc__)
    command, path = sys.argv[1], Path(sys.argv[2])
    fields, types = load_registry(find_runtime(None))
    data = path.read_bytes()

    rig = Rig(data, fields)
    rig.types = types
    if rig.dumps() != data:
        raise SystemExit('Round-trip не сошёлся: не рискую писать файл')
    scene = Scene(rig, types)

    if command == 'inspect':
        return cmd_inspect(rig, scene)
    return cmd_fix(rig, scene, path)


if __name__ == '__main__':
    sys.exit(main())
