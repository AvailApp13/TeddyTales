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

# Дыхание. Сдача рига качала корпус на 1.5% — на экране это пара пикселей,
# зрителю кажется, что мишка застыл. Размах считаем от экрана, а не от
# артборда: артборд 1080 в ширину показывается примерно в 330 точках, то есть
# один пиксель на экране — это три с лишним в файле.
BREATH_CYCLE = 180          # один вдох-выдох, три секунды
BREATH_SWELL = 1.04         # насколько раздувается кофта на вдохе
BREATH_LIFT = 18.0          # на сколько поднимается голова, пикселей артборда
TORSO_RISE = 6.0            # грудь приподнимается, а не только пухнет
MUZZLE_EXTRA = 3.0          # нос и рот тянутся чуть дальше головы — «принюх»
EAR_SWING = 0.0654          # качание ушей, радианы (около 3.7°)
PAW_SWING = 0.09            # мах лапами от плеча, радианы (около 5°)
PAW_DRIFT = 6.0             # лапы расходятся в стороны вместе с кофтой
PAW_LIFT = 4.0              # и приподнимаются вместе с грудью

# Вершина вдоха у каждой части своя. Во-первых, вдох короче выдоха — живое
# дыхание несимметрично. Во-вторых, части трогаются не разом: сначала грудь,
# следом голова, лапы и уши догоняют. Синхронное движение читается как
# механика, запаздывание — как живое.
PEAK = {'torso': 70, 'head': 82, 'muzzle': 86, 'paw': 88, 'ear': 95}

# Полный idle — два вдоха подряд, и они нарочно разные: второй мельче и с
# поздней вершиной. Подсмотрено у демо-дракона: там циклы разной длины
# наложены друг на друга, и повторяемость не читается. Одинаковые вдохи по
# метроному глаз ловит за пару циклов.
BREATH_CYCLES = ((0, 1.0, 0), (BREATH_CYCLE, 0.85, 6))
IDLE_DURATION = 2 * BREATH_CYCLE

# Моргание — тоже узор, а не метроном: одиночное, пауза, двойное. У дракона
# blink живёт в цикле на 600 кадров с неровными интервалами — потому и не
# выглядит заведённым. Смыкание почти мгновенное (2 кадра): кросс-фейд с
# полупрозрачным веком читался как призрак, настоящее веко так не умеет.
BLINK_DURATION = 240        # четыре секунды на узор
BLINK_PATTERN = [(0, 0.0), (2, 1.0), (10, 1.0), (16, 0.0),
                 (150, 0.0), (152, 1.0), (157, 1.0), (161, 0.0),
                 (165, 0.0), (167, 1.0), (173, 1.0), (180, 0.0)]

# Голова и всё, что на ней нарисовано, поднимается одним куском. Части лица
# лежат в артборде рядом с головой, а не внутри неё, поэтому двигать их надо
# синхронно — иначе на вдохе глаза и нос съедут с морды.
HEAD_GROUP = [
    'head', 'ear_left', 'ear_right', 'eye_left', 'eye_right', 'nose',
    'mouth_stitch', 'mouth_open_v2', 'eyelid_left_v2', 'eyelid_right_v2',
]

X, Y, SCALE_X, SCALE_Y, ROTATION, OPACITY = 13, 14, 16, 17, 15, 18

# Качество перепаковки деталей. Редактор кладёт их в WEBP примерно на этом же
# уровне: выше — файл пухнет вдвое, ниже — на мехе проступает муар.
WEBP_QUALITY = 90


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


def cmd_clean(rig: Rig, scene: Scene, path: Path) -> int:
    """Срезает тёмную кайму по краю деталей — след края с фотографии.

    Игрушку снимали на светлом фоне, и по контуру осталась узкая тень. При
    вырезке она попала внутрь силуэта, а в приложении читается серой обводкой
    вокруг капюшона. Меряем яркость колец вглубь от края: тень занимает ровно
    два пикселя, дальше начинается мех. Подрезаем альфу на эти два пикселя и
    смягчаем срез — деталь становится меньше на два пикселя с каждой стороны,
    а её центр не двигается, поэтому посадка в артборде не меняется.
    """
    import cv2  # noqa: PLC0415 — нужен только этой команде
    import numpy as np  # noqa: PLC0415

    DEPTH, FEATHER, DARKER = 2, 0.8, 12

    name = None
    cleaned = 0
    for type_key, props in rig.objects:
        kind = rig.types.get(type_key)
        if kind == 'ImageAsset':
            name = get(props, Scene.ASSET_NAME).decode()
            continue
        if kind != 'FileAssetContents' or name is None:
            continue

        raw = np.frombuffer(get(props, 212), np.uint8)
        image = cv2.imdecode(raw, cv2.IMREAD_UNCHANGED)
        if image is None or image.shape[2] < 4:
            name = None
            continue

        alpha = image[:, :, 3]
        value = cv2.cvtColor(image[:, :, :3], cv2.COLOR_BGR2HSV)[:, :, 2]
        solid = (alpha > 200).astype(np.uint8)
        rim = (solid > 0) & (cv2.erode(solid, np.ones((3, 3), np.uint8)) == 0)
        deep = cv2.erode(solid, np.ones((15, 15), np.uint8)) > 0
        if not rim.any() or not deep.any():
            name = None
            continue
        drop = float(np.median(value[deep])) - float(np.median(value[rim]))
        if drop < DARKER:
            print(f'  {name:18s} каймы нет ({drop:+.0f})')
            name = None
            continue

        size = 2 * DEPTH + 1
        tight = cv2.erode(alpha, np.ones((size, size), np.uint8))
        image[:, :, 3] = cv2.GaussianBlur(tight, (0, 0), FEATHER)
        # Редактор кладёт детали в WEBP; в PNG тот же кадр весит в четырнадцать
        # раз больше, и риг из 148 КБ распухает до полутора мегабайт.
        put(props, 212, cv2.imencode(
            '.webp', image, [cv2.IMWRITE_WEBP_QUALITY, WEBP_QUALITY],
        )[1].tobytes())
        print(f'  {name:18s} кайма темнее меха на {drop:.0f} — срезано {DEPTH} px')
        cleaned += 1
        name = None

    path.write_bytes(rig.dumps())
    print(f'Почищено деталей: {cleaned}')
    return 0


def cmd_eyes(rig: Rig, scene: Scene, path: Path) -> int:
    """Сажает веки точно на глаза — по центру самого века, а не картинки.

    Кусок века вырезан с запасом меха вокруг, и закрытый глаз в нём лежит не
    посередине: у левого он смещён влево, у правого вправо. Пока веко ставили
    по центру картинки, закрытый глаз уезжал относительно открытого. Центр
    века находим по тени вокруг него — это единственное тёмное пятно на куске.
    """
    import cv2  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415

    blobs: dict[str, tuple[float, float]] = {}
    name = None
    for type_key, props in rig.objects:
        kind = rig.types.get(type_key)
        if kind == 'ImageAsset':
            name = get(props, Scene.ASSET_NAME).decode()
        elif kind == 'FileAssetContents' and name in (
            'eyelid_left_v2', 'eyelid_right_v2'
        ):
            image = cv2.imdecode(np.frombuffer(get(props, 212), np.uint8),
                                 cv2.IMREAD_UNCHANGED)
            alpha = image[:, :, 3]
            grey = cv2.cvtColor(image[:, :, :3], cv2.COLOR_BGR2GRAY)
            level = float(np.median(grey[alpha > 128]))
            dark = ((grey < level - 28) & (alpha > 128)).astype(np.uint8)
            count, _, stats, centres = cv2.connectedComponentsWithStats(dark, 8)
            biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
            centre = centres[biggest]
            blobs[name] = (centre[0] - image.shape[1] / 2,
                           centre[1] - image.shape[0] / 2)
            name = None
        else:
            name = None

    by_name = {scene.image_name(i): i for i in scene.images}
    for lid, eye in (('eyelid_left_v2', 'eye_left'),
                     ('eyelid_right_v2', 'eye_right')):
        shift_x, shift_y = blobs[lid]
        lid_props = rig.objects[by_name[lid]][1]
        eye_props = rig.objects[by_name[eye]][1]
        scale = get(lid_props, SCALE_X)
        was = (get(lid_props, X), get(lid_props, Y))
        put(lid_props, X, get(eye_props, X) - shift_x * scale)
        put(lid_props, Y, get(eye_props, Y) - shift_y * scale)
        print(f'  {lid}: веко в куске смещено на '
              f'({shift_x:+.0f},{shift_y:+.0f}) px, '
              f'посадка {was[0]:.1f},{was[1]:.1f} -> '
              f'{get(lid_props, X):.1f},{get(lid_props, Y):.1f}')

    path.write_bytes(rig.dumps())
    return 0


def image_size(rig: Rig, wanted: str) -> tuple[int, int]:
    """Ширина и высота картинки детали в пикселях."""
    import cv2  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415

    name = None
    for type_key, props in rig.objects:
        kind = rig.types.get(type_key)
        if kind == 'ImageAsset':
            name = get(props, Scene.ASSET_NAME).decode()
        elif kind == 'FileAssetContents' and name == wanted:
            image = cv2.imdecode(np.frombuffer(get(props, 212), np.uint8),
                                 cv2.IMREAD_UNCHANGED)
            return image.shape[1], image.shape[0]
        else:
            name = None
    raise SystemExit(f'Нет картинки {wanted}')


def cmd_breathe(rig: Rig, scene: Scene, path: Path) -> int:
    """Переписывает дорожки анимации idle с заметным на глаз размахом."""
    import numpy as np  # noqa: PLC0415 — нужен только этой команде

    reverse = {name: key for key, name in rig.types.items()}
    keyed_object = reverse['KeyedObject']
    keyed_property = reverse['KeyedProperty']
    keyframe = reverse['KeyFrameDouble']

    interpolator = next(
        scene.local_id(i) for i, (type_key, _) in enumerate(rig.objects)
        if rig.types.get(type_key) == 'CubicEaseInterpolator'
    )
    by_name = {scene.image_name(i): i for i in scene.images}
    full = BREATH_CYCLE

    def track(local: int, tracks: dict[int, list[tuple[int, float]]]) -> list:
        """Одна дорожка: объект, его свойства и ключи по кадрам."""
        out = [(keyed_object, [(Scene.OBJECT_ID, 'Uint', local)])]
        for property_key, frames in tracks.items():
            out.append((keyed_property, [(53, 'Uint', property_key)]))
            for frame, value in frames:
                props = []
                if frame:
                    props.append((67, 'Uint', frame))
                props += [(68, 'Uint', 2),
                          (Scene.INTERPOLATOR_ID, 'Uint', interpolator),
                          (70, 'Double', value)]
                out.append((keyframe, props))
        return out

    def waves(peak: int, value_at) -> list[tuple[int, float]]:
        """Ключи двух вдохов: покой, вершина первого, покой, вершина второго."""
        keys = [(0, float(value_at(0.0)))]
        for start, amp, shift in BREATH_CYCLES:
            keys.append((start + peak + shift, float(value_at(amp))))
            keys.append((start + BREATH_CYCLE, float(value_at(0.0))))
        return keys

    block: list = []

    # Кофта дышит и приподнимается: только раздувание читалось как «двигается
    # одежда», подъём груди тянет весь силуэт.
    torso = rig.objects[by_name['torso']][1]
    scale_x, scale_y, torso_y = (get(torso, SCALE_X), get(torso, SCALE_Y),
                                 get(torso, Y))
    block += track(scene.local_id(by_name['torso']), {
        SCALE_X: waves(PEAK['torso'],
                       lambda k: scale_x * (1 + (BREATH_SWELL - 1) * k)),
        SCALE_Y: waves(PEAK['torso'],
                       lambda k: scale_y * (1 + (BREATH_SWELL - 1) * k)),
        Y: waves(PEAK['torso'], lambda k: torso_y - TORSO_RISE * k),
    })

    # Голова с лицом поднимается на вдохе — одним куском, синхронно. Нос и
    # рот тянутся на пару пикселей дальше и чуть позже — мордочка «принюхивается».
    muzzle = {'nose', 'mouth_stitch', 'mouth_open_v2'}
    for name in HEAD_GROUP:
        base = get(rig.objects[by_name[name]][1], Y)
        lift = BREATH_LIFT + (MUZZLE_EXTRA if name in muzzle else 0.0)
        peak = PEAK['muzzle'] if name in muzzle else PEAK['head']
        block += track(scene.local_id(by_name[name]), {
            Y: waves(peak, lambda k, b=base, l=lift: b - l * k),
        })

    # Лапы качаются от плеча. Костей нет, поэтому поворот вокруг чужой точки
    # собираем руками: центр картинки едет по дуге вокруг плеча, а сама она
    # доворачивается на тот же угол. Плечо — середина верхнего края лапы.
    # Вдобавок лапы расходятся вслед за кофтой и приподнимаются с грудью.
    for name, sign in (('paw_left', -1), ('paw_right', 1)):
        props = rig.objects[by_name[name]][1]
        centre = np.array([get(props, X), get(props, Y)])
        half_height = image_size(rig, name)[1] * get(props, SCALE_Y) / 2
        shoulder = np.array([centre[0], centre[1] - half_height])

        def pose(k, sign=sign, centre=centre, shoulder=shoulder):
            # Знак поворота противоположен сдвигу: ось y смотрит вниз, и
            # положительный угол в Rive крутит по часовой. С одинаковыми
            # знаками дуга от поворота и разъезд лап гасят друг друга —
            # лапа стоит на месте, что и было видно на экране.
            angle = -sign * PAW_SWING * k
            turn = np.array([[np.cos(angle), -np.sin(angle)],
                             [np.sin(angle), np.cos(angle)]])
            x, y = shoulder + turn @ (centre - shoulder)
            return angle, x + sign * PAW_DRIFT * k, y - PAW_LIFT * k

        block += track(scene.local_id(by_name[name]), {
            ROTATION: waves(PEAK['paw'], lambda k: pose(k)[0]),
            X: waves(PEAK['paw'], lambda k: pose(k)[1]),
            Y: waves(PEAK['paw'], lambda k: pose(k)[2]),
        })

    # Уши качаются в противофазе — от этого движение читается как живое.
    for name, sign in (('ear_left', 1), ('ear_right', -1)):
        block += track(scene.local_id(by_name[name]), {
            ROTATION: waves(PEAK['ear'], lambda k, s=sign: s * EAR_SWING * k),
        })

    start = next(i for i, (type_key, props) in enumerate(rig.objects)
                 if rig.types.get(type_key) == 'LinearAnimation'
                 and get(props, 55) == b'idle')
    put(rig.objects[start][1], 57, IDLE_DURATION)
    end = next(i for i in range(start + 1, len(rig.objects))
               if rig.types.get(rig.objects[i][0])
               in ('LinearAnimation', 'StateMachine'))
    rig.objects = rig.objects[:start + 1] + block + rig.objects[end:]

    path.write_bytes(rig.dumps())
    tracks = sum(1 for type_key, _ in block if type_key == keyed_object)
    print(f'Дыхание переписано: кофта +{(BREATH_SWELL - 1) * 100:.0f}%, '
          f'голова на {BREATH_LIFT:.0f} px, лапы от плеча, '
          f'вершины вдоха {sorted(set(PEAK.values()))} из {full}, '
          f'дорожек {tracks}')
    return 0


def cmd_blink(rig: Rig, scene: Scene, path: Path) -> int:
    """Переписывает моргание: мгновенное смыкание и неровный узор.

    Старый blink растворял веко прозрачностью пять кадров — пока оно
    полупрозрачное, под ним просвечивает глаз, и кадр читается как призрак.
    Настоящее веко смыкается почти мгновенно: два кадра вниз, подержать,
    отпустить. И моргаем не по метроному: одиночное, пауза, двойное —
    у демо-дракона моргание живёт в длинном цикле с неровными интервалами,
    поэтому не выглядит заведённым.
    """
    reverse = {name: key for key, name in rig.types.items()}
    keyed_object = reverse['KeyedObject']
    keyed_property = reverse['KeyedProperty']
    keyframe = reverse['KeyFrameDouble']
    interpolator = next(
        scene.local_id(i) for i, (type_key, _) in enumerate(rig.objects)
        if rig.types.get(type_key) == 'CubicEaseInterpolator'
    )
    by_name = {scene.image_name(i): i for i in scene.images}

    block: list = []
    for lid in ('eyelid_left_v2', 'eyelid_right_v2'):
        block.append((keyed_object,
                      [(Scene.OBJECT_ID, 'Uint',
                        scene.local_id(by_name[lid]))]))
        block.append((keyed_property, [(53, 'Uint', OPACITY)]))
        for frame, value in BLINK_PATTERN:
            props = []
            if frame:
                props.append((67, 'Uint', frame))
            props += [(68, 'Uint', 2),
                      (Scene.INTERPOLATOR_ID, 'Uint', interpolator),
                      (70, 'Double', value)]
            block.append((keyframe, props))

    start = next(i for i, (type_key, props) in enumerate(rig.objects)
                 if rig.types.get(type_key) == 'LinearAnimation'
                 and get(props, 55) == b'blink')
    put(rig.objects[start][1], 57, BLINK_DURATION)
    end = next(i for i in range(start + 1, len(rig.objects))
               if rig.types.get(rig.objects[i][0])
               in ('LinearAnimation', 'StateMachine'))
    rig.objects = rig.objects[:start + 1] + block + rig.objects[end:]

    # Выход из состояния blink в стейт-машине — по концу нового узора.
    # Время выхода в миллисекундах: старые 18 кадров при 60 fps дали 300.
    exit_ms = BLINK_DURATION * 1000 // 60
    for type_key, props in rig.objects:
        if (rig.types.get(type_key) == 'StateTransition'
                and get(props, 160) == 300):
            put(props, 160, exit_ms)
            print(f'  выход из blink: 300 мс -> {exit_ms} мс')

    path.write_bytes(rig.dumps())
    print(f'Моргание: узор {len(BLINK_PATTERN)} ключей на веко, '
          f'{BLINK_DURATION} кадров, смыкание за 2 кадра')
    return 0


def main() -> int:
    commands = ('inspect', 'fix', 'clean', 'eyes', 'breathe', 'blink')
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        raise SystemExit(__doc__)
    command, path = sys.argv[1], Path(sys.argv[2])
    fields, types = load_registry(find_runtime(None))
    data = path.read_bytes()

    rig = Rig(data, fields)
    rig.types = types
    if rig.dumps() != data:
        raise SystemExit('Round-trip не сошёлся: не рискую писать файл')
    scene = Scene(rig, types)

    runner = {'inspect': cmd_inspect, 'clean': cmd_clean, 'eyes': cmd_eyes,
              'breathe': cmd_breathe, 'blink': cmd_blink,
              'fix': cmd_fix}[command]
    if command == 'inspect':
        return runner(rig, scene)
    return runner(rig, scene, path)


if __name__ == '__main__':
    sys.exit(main())
