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
# Риг v4: лицо нарисовано прямо на голове (моргание убрано решением
# заказчика, отдельные глаза/веки/рты не нужны — и швов на лице нет).
# Уши за головой, лапы поверх кофты, кофта поверх ног.
DRAW_ORDER = [
    'mouth',
    'head',
    'ear_left',
    'ear_right',
    'paw_left',
    'paw_right',
    'torso',
    'legs',
]

# Что выкидываем из файла вместе с картинками: куски первой волны от
# нейросети и весь набор отдельных черт лица из v3 — в v4 лицо цельное.
DROP = {'arm_root_left', 'arm_root_right',
        'eye_left', 'eye_right', 'eyelid_left_v2', 'eyelid_right_v2',
        'nose', 'mouth_stitch', 'mouth_open_v2'}

# Дыхание. Сдача рига качала корпус на 1.5% — на экране это пара пикселей,
# зрителю кажется, что мишка застыл. Размах считаем от экрана, а не от
# артборда: артборд 1080 в ширину показывается примерно в 330 точках, то есть
# один пиксель на экране — это три с лишним в файле.
BREATH_CYCLE = 180          # один вдох-выдох, три секунды
BREATH_SWELL = 1.04         # насколько раздувается кофта на вдохе
BREATH_LIFT = 18.0          # на сколько поднимается голова, пикселей артборда
TORSO_RISE = 6.0            # грудь приподнимается, а не только пухнет
EAR_SWING = 0.07            # качание ушей, радианы (около 4°)
PAW_SWING = 0.06            # мах лапами от плеча, радианы (около 3.4°)
PAW_DRIFT = 3.0             # лапы расходятся в стороны вместе с кофтой
PAW_LIFT = 4.0              # и приподнимаются вместе с грудью
MOUTH_SWELL = (1.05, 1.11)  # улыбка тянется на вдохе: чуть вширь, больше ввысь

# Анимация смеха по тапу (trg_pet): два подскока всем телом, кофта пружинит,
# лапы взлетают, уши хлопают, улыбка распахивается. Длительность в кадрах.
GIGGLE_DURATION = 78

# Вершина вдоха у каждой части своя. Во-первых, вдох короче выдоха — живое
# дыхание несимметрично. Во-вторых, части трогаются не разом: сначала грудь,
# следом голова, лапы и уши догоняют. Синхронное движение читается как
# механика, запаздывание — как живое.
PEAK = {'torso': 70, 'head': 82, 'mouth': 84, 'paw': 88, 'ear': 95}

# Полный idle — два вдоха подряд, и они нарочно разные: второй мельче и с
# поздней вершиной. Подсмотрено у демо-дракона: там циклы разной длины
# наложены друг на друга, и повторяемость не читается. Одинаковые вдохи по
# метроному глаз ловит за пару циклов.
BREATH_CYCLES = ((0, 1.0, 0), (BREATH_CYCLE, 0.85, 6))
IDLE_DURATION = 2 * BREATH_CYCLE

# Голова с ушами поднимается одним куском; лицо нарисовано на голове и
# едет вместе с ней само.
HEAD_GROUP = ['head', 'ear_left', 'ear_right']

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


# Оригиналы деталей в репозитории: имя в риге -> файл набора parts-v4.
# Чистка всегда стартует с них, а не с картинок из файла — иначе каждая
# правка пережимает WEBP ещё раз и деталь постепенно замыливается.
PART_SOURCES = {
    'mouth': 'mouth',
    'head': 'head', 'ear_left': 'ear_left', 'ear_right': 'ear_right',
    'paw_left': 'paw_left', 'paw_right': 'paw_right',
    'torso': 'torso', 'legs': 'legs',
}
PARTS_DIR = 'docs/reference/parts-v4'


def cmd_clean(rig: Rig, scene: Scene, path: Path) -> int:
    """Убирает след старого края: тёмную кромку и серую юбку растушёвки.

    Игрушку снимали на светлом фоне, и по контуру осталась узкая тень — в
    приложении она читалась серой обводкой вокруг капюшона. Два лечения:

    1. Адаптивная подрезка: срезаем альфу по пикселю, пока кромка темнее
       глубины меха, но не больше четырёх, и растушёвываем срез.
    2. Перекраска юбки: у полупрозрачных пикселей после растушёвки остаётся
       ЦВЕТ старого края, и тонкая серая линия лезет обратно. Каждый
       неплотный пиксель берёт цвет ближайшего плотного — просвечивать
       больше нечему.

    Детали берутся из оригиналов набора parts-v2 (без повторного пережатия)
    и кладутся обратно в WEBP: в PNG риг пухнет со 148 КБ до полутора
    мегабайт.
    """
    import cv2  # noqa: PLC0415 — нужен только этой команде
    import numpy as np  # noqa: PLC0415

    MAX_TRIM, DARKER, FEATHER = 4, 12, 0.8
    root = Path(__file__).resolve().parent.parent / PARTS_DIR

    name = None
    for type_key, props in rig.objects:
        kind = rig.types.get(type_key)
        if kind == 'ImageAsset':
            name = get(props, Scene.ASSET_NAME).decode()
            continue
        if kind != 'FileAssetContents' or name is None:
            continue
        wanted, name = name, None
        source = root / f'{PART_SOURCES[wanted]}.png'
        image = cv2.imread(str(source), cv2.IMREAD_UNCHANGED)
        embedded = cv2.imdecode(np.frombuffer(get(props, 212), np.uint8),
                                cv2.IMREAD_UNCHANGED)
        if image is None or image.shape[:2] != embedded.shape[:2]:
            raise SystemExit(f'{wanted}: оригинал {source.name} не совпал')

        alpha = image[:, :, 3]
        value = cv2.cvtColor(image[:, :, :3],
                             cv2.COLOR_BGR2HSV)[:, :, 2].astype(np.float32)
        solid = (alpha > 200).astype(np.uint8)
        deep_mask = cv2.erode(solid, np.ones((15, 15), np.uint8)) > 0

        trimmed = 0
        if deep_mask.any():
            deep = float(np.median(value[deep_mask]))
            work = alpha.copy()
            for _ in range(MAX_TRIM):
                shell = (work > 200).astype(np.uint8)
                rim = (shell > 0) & (cv2.erode(
                    shell, np.ones((3, 3), np.uint8)) == 0)
                if not rim.any():
                    break
                if deep - float(np.median(value[rim])) < DARKER:
                    break
                work = cv2.erode(work, np.ones((3, 3), np.uint8))
                trimmed += 1
            if trimmed:
                alpha = cv2.GaussianBlur(work, (0, 0), FEATHER)
                image[:, :, 3] = alpha

        # Юбка: каждому неплотному пикселю — цвет ближайшего плотного.
        shell = (alpha > 200).astype(np.uint8)
        if shell.any() and (shell == 0).any():
            _, labels = cv2.distanceTransformWithLabels(
                1 - shell, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
            ys, xs = np.nonzero(shell)
            lut_y = np.zeros(int(labels.max()) + 1, np.int32)
            lut_x = np.zeros_like(lut_y)
            lut_y[labels[ys, xs]] = ys
            lut_x[labels[ys, xs]] = xs
            donor = image[lut_y[labels], lut_x[labels], :3]
            image[:, :, :3] = np.where((shell == 0)[..., None],
                                       donor, image[:, :, :3])

        put(props, 212, cv2.imencode(
            '.webp', image, [cv2.IMWRITE_WEBP_QUALITY, WEBP_QUALITY],
        )[1].tobytes())
        print(f'  {wanted:18s} срез {trimmed} px, юбка перекрашена')

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

    # Голова с ушами поднимается на вдохе — одним куском, синхронно.
    for name in HEAD_GROUP:
        base = get(rig.objects[by_name[name]][1], Y)
        block += track(scene.local_id(by_name[name]), {
            Y: waves(PEAK['head'],
                     lambda k, b=base: b - BREATH_LIFT * k),
        })

    # Улыбка дышит: накладка рта лежит на собственных пикселях головы,
    # поэтому растяжение читается как движение рта, а не как шов. Якорь —
    # верхняя губа: при растяжении центр съезжает вниз на половину прироста,
    # и открывается «челюсть», а не вся улыбка враспор. Y пишем здесь же:
    # это подъём головы плюс ход челюсти, одной дорожкой.
    mouth = rig.objects[by_name['mouth']][1]
    mouth_sx, mouth_sy = get(mouth, SCALE_X), get(mouth, SCALE_Y)
    mouth_y = get(mouth, Y)
    jaw = image_size(rig, 'mouth')[1] * mouth_sy * (MOUTH_SWELL[1] - 1) / 2
    block += track(scene.local_id(by_name['mouth']), {
        SCALE_X: waves(PEAK['mouth'],
                       lambda k: mouth_sx * (1 + (MOUTH_SWELL[0] - 1) * k)),
        SCALE_Y: waves(PEAK['mouth'],
                       lambda k: mouth_sy * (1 + (MOUTH_SWELL[1] - 1) * k)),
        Y: waves(PEAK['mouth'],
                 lambda k: mouth_y - BREATH_LIFT * k + jaw * k),
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
    """Отключает моргание: у анимации blink не остаётся ни одной дорожки.

    Решение заказчика: лицо v4 цельное, век в риге нет, глаза всегда
    открыты. Пустая анимация оставлена на месте, чтобы не трогать стейт-
    машину: состояние blink проигрывает тишину и возвращается в eyes_open.
    """
    start = next(i for i, (type_key, props) in enumerate(rig.objects)
                 if rig.types.get(type_key) == 'LinearAnimation'
                 and get(props, 55) == b'blink')
    end = next(i for i in range(start + 1, len(rig.objects))
               if rig.types.get(rig.objects[i][0])
               in ('LinearAnimation', 'StateMachine'))
    removed = end - start - 1
    rig.objects = rig.objects[:start + 1] + rig.objects[end:]
    path.write_bytes(rig.dumps())
    print(f'Моргание отключено: удалено {removed} объектов дорожек blink')
    return 0


def cmd_place(rig: Rig, scene: Scene, path: Path) -> int:
    """Сажает детали набора parts-v4 в риг: контент, размеры и позиции.

    Замена мишки целиком: картинки берутся из нарезки нового эталонного
    фото, посадка — из placements.json (там координаты артборда, посчитанные
    от габарита прежнего героя: размер на экране не меняется).
    """
    import json  # noqa: PLC0415
    import cv2  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415

    root = Path(__file__).resolve().parent.parent / PARTS_DIR
    placements = json.loads((root / 'placements.json').read_text())
    # Имя ассета в риге -> имя куска v4 (низ в старом риге звался иначе).
    to_v4 = dict(PART_SOURCES)
    to_v4.setdefault('legs_tummy_v2', 'legs')

    name = None
    asset_props = None
    for type_key, props in rig.objects:
        kind = rig.types.get(type_key)
        if kind == 'ImageAsset':
            name = get(props, Scene.ASSET_NAME).decode()
            asset_props = props
            continue
        if kind != 'FileAssetContents' or name not in to_v4:
            name = None
            continue
        v4 = to_v4[name]
        image = cv2.imread(str(root / f'{v4}.png'), cv2.IMREAD_UNCHANGED)
        old = cv2.imdecode(np.frombuffer(get(props, 212), np.uint8),
                           cv2.IMREAD_UNCHANGED)
        # У пары свойств 207/208 порядок «ширина-высота» в файлах гуляет —
        # определяем его по старой картинке этого же ассета.
        oh, ow = old.shape[:2]
        nh, nw = image.shape[:2]
        first, second = get(asset_props, 207), get(asset_props, 208)
        if (first, second) == (ow, oh):
            put(asset_props, 207, float(nw))
            put(asset_props, 208, float(nh))
        elif (first, second) == (oh, ow):
            put(asset_props, 207, float(nh))
            put(asset_props, 208, float(nw))
        else:
            raise SystemExit(f'{name}: не понял порядок размеров '
                             f'{first}x{second} при картинке {ow}x{oh}')
        put(asset_props, Scene.ASSET_NAME, v4.encode())
        put(props, 212, cv2.imencode(
            '.webp', image, [cv2.IMWRITE_WEBP_QUALITY, WEBP_QUALITY],
        )[1].tobytes())
        print(f'  {name} -> {v4}: {nw}x{nh}, {len(get(props, 212))} Б')
        name = None

    # Детали, которых в файле ещё нет (рот появился только в v4), создаются:
    # пара ImageAsset+FileAssetContents в конец списка ассетов и узел Image
    # следом за последним существующим. Ссылки по индексам это сдвигает, но
    # дорожки анимаций всё равно переписываются командами breathe и fix.
    reverse = {name: key for key, name in rig.types.items()}
    present = {get(rig.objects[i][1], Scene.ASSET_NAME).decode()
               for i in scene.assets}
    created = [v4 for v4 in sorted(set(PART_SOURCES) - present)
               if v4 in placements]
    for v4 in created:
        image = cv2.imread(str(root / f'{v4}.png'), cv2.IMREAD_UNCHANGED)
        blob = cv2.imencode('.webp', image,
                            [cv2.IMWRITE_WEBP_QUALITY, WEBP_QUALITY],
                            )[1].tobytes()
        nh, nw = image.shape[:2]
        last_contents = max(i + 1 for i in scene.assets)
        rig.objects[last_contents + 1:last_contents + 1] = [
            (reverse['ImageAsset'],
             [(Scene.ASSET_NAME, 'String', v4.encode()),
              (204, 'Uint', 1), (207, 'Double', float(nw)),
              (208, 'Double', float(nh))]),
            (reverse['FileAssetContents'], [(212, 'Bytes', blob)]),
        ]
        target = placements[v4]
        after_image = max(scene.images) + 2 + 1  # +2 за пару ассета выше
        rig.objects[after_image:after_image] = [
            (reverse['Image'],
             [(5, 'Uint', 0),
              (SCALE_X, 'Double', target['scale']),
              (SCALE_Y, 'Double', target['scale']),
              (X, 'Double', target['x']), (Y, 'Double', target['y']),
              (Scene.ASSET_ID, 'Uint', len(scene.assets))]),
        ]
        print(f'  создана деталь {v4}: {nw}x{nh}, ассет #{len(scene.assets)}')
        scene = Scene(rig, rig.types)

    # Позиции и масштаб узлов Image — по посадочной карте.
    assets = [get(rig.objects[i][1], Scene.ASSET_NAME).decode()
              for i in scene.assets]
    for index in scene.images:
        props = rig.objects[index][1]
        asset_name = assets[get(props, Scene.ASSET_ID)]
        if asset_name not in placements:
            continue
        target = placements[asset_name]
        put(props, X, target['x'])
        put(props, Y, target['y'])
        put(props, SCALE_X, target['scale'])
        put(props, SCALE_Y, target['scale'])

    path.write_bytes(rig.dumps())
    print('Посадка v4 записана')
    return 0


def cmd_giggle(rig: Rig, scene: Scene, path: Path) -> int:
    """Смех по тапу: мишка прыгает как ОДНО упругое тело, а не набор кусков.

    Первая версия двигала части порознь — лапы своей дугой, голова своим
    подскоком — и коллаж разваливался на глазах. Дракон смотрится дорого,
    потому что деформируется целиком: приседание перед прыжком, вытяжение в
    полёте, смятие при приземлении. Здесь это воспроизведено без костей:
    каждый ключ задаёт ОБЩЕЕ преобразование от точки опоры (пол под
    ступнями) — сжатие/вытяжение по вертикали с сохранением объёма, высоту
    прыжка и лёгкий крен. Все восемь кусков получают одну и ту же формулу,
    поэтому границы между ними не расходятся ни на пиксель. Сверху — только
    два невинных акцента: уши отстают на долю такта, улыбка распахивается.
    """
    import numpy as np  # noqa: PLC0415

    reverse = {name: key for key, name in rig.types.items()}
    keyed_object = reverse['KeyedObject']
    keyed_property = reverse['KeyedProperty']
    keyframe = reverse['KeyFrameDouble']
    interpolator = next(
        scene.local_id(i) for i, (type_key, _) in enumerate(rig.objects)
        if rig.types.get(type_key) == 'CubicEaseInterpolator'
    )
    by_name = {scene.image_name(i): i for i in scene.images}

    def track(local, tracks):
        out = [(keyed_object, [(Scene.OBJECT_ID, 'Uint', local)])]
        for property_key, frames in tracks.items():
            out.append((keyed_property, [(53, 'Uint', property_key)]))
            for frame, value in frames:
                props = []
                if frame:
                    props.append((67, 'Uint', int(frame)))
                props += [(68, 'Uint', 2),
                          (Scene.INTERPOLATOR_ID, 'Uint', interpolator),
                          (70, 'Double', float(value))]
                out.append((keyframe, props))
        return out

    # Опора — пол под ступнями, центр по ширине героя.
    GROUND = np.array([540.0, 1350.0])

    # Партитура прыжка: (кадр, сжатие по Y, высота, крен в радианах).
    # Присел -> вытянулся на взлёте -> завис -> смялся на приземлении ->
    # короткий второй подскок -> пружинит и успокаивается.
    SCORE = [
        (0,  1.00,  0.0,  0.000),
        (6,  0.90,  0.0,  0.000),
        (12, 1.07, 30.0,  0.020),
        (18, 1.03, 40.0, -0.018),
        (24, 0.88,  0.0,  0.014),
        (30, 1.05, 12.0, -0.012),
        (36, 1.00, 16.0,  0.008),
        (42, 0.93,  0.0, -0.006),
        (50, 1.02,  0.0,  0.000),
        (60, 1.00,  0.0,  0.000),
        (GIGGLE_DURATION, 1.00, 0.0, 0.000),
    ]

    def posed(base_x, base_y, squash, jump, tilt):
        """Точка после общего преобразования тела."""
        stretch_x = 1 + (1 - squash) * 0.7   # объём сохраняется примерно
        rel = np.array([ (base_x - GROUND[0]) * stretch_x,
                         (base_y - GROUND[1]) * squash ])
        turn = np.array([[np.cos(tilt), -np.sin(tilt)],
                         [np.sin(tilt), np.cos(tilt)]])
        out = GROUND + turn @ rel
        return out[0], out[1] - jump

    block: list = []
    for name, index in by_name.items():
        props = rig.objects[index][1]
        bx, by = get(props, X), get(props, Y)
        bsx, bsy = get(props, SCALE_X), get(props, SCALE_Y)
        xs, ys, sxs, sys_, rots = [], [], [], [], []
        for frame, squash, jump, tilt in SCORE:
            px, py = posed(bx, by, squash, jump, tilt)
            xs.append((frame, px))
            ys.append((frame, py))
            sxs.append((frame, bsx * (1 + (1 - squash) * 0.7)))
            sys_.append((frame, bsy * squash))
            rots.append((frame, tilt))
        tracks = {X: xs, Y: ys, SCALE_X: sxs, SCALE_Y: sys_, ROTATION: rots}

        if name in ('ear_left', 'ear_right'):
            # Уши мягкие — отстают от тела на пару кадров.
            sign = 1 if name == 'ear_left' else -1
            tracks[ROTATION] = [
                (frame, tilt + sign * lag) for (frame, _, _, tilt), lag in
                zip(SCORE, (0, 0.10, -0.12, 0.08, -0.10, 0.07, -0.05,
                            0.04, -0.02, 0.0, 0.0))
            ]
        if name == 'mouth':
            # Улыбка распахивается в такт подскокам, якорь на верхней губе.
            mouth_h = image_size(rig, 'mouth')[1] * bsy
            pulse = dict([(0, 1.0), (6, 1.04), (12, 1.22), (18, 1.18),
                          (24, 1.02), (30, 1.15), (36, 1.1), (42, 1.0),
                          (50, 1.0), (60, 1.0), (GIGGLE_DURATION, 1.0)])
            tracks[SCALE_Y] = [(f, v * pulse[f]) for f, v in sys_]
            tracks[Y] = [(f, v + mouth_h * (pulse[f] - 1) / 2)
                         for f, v in ys]
        block += track(scene.local_id(index), tracks)

    # --- анимация в файл: заменить существующую или вставить перед SM.
    anim_type = reverse['LinearAnimation']
    sm_at = next(i for i, (tk, _) in enumerate(rig.objects)
                 if rig.types.get(tk) == 'StateMachine')
    existing = [i for i, (tk, props) in enumerate(rig.objects)
                if rig.types.get(tk) == 'LinearAnimation'
                and get(props, 55) == b'giggle']
    if existing:
        start = existing[0]
        end = next(i for i in range(start + 1, len(rig.objects))
                   if rig.types.get(rig.objects[i][0])
                   in ('LinearAnimation', 'StateMachine'))
        rig.objects[start:end] = [rig.objects[start]] + block
        put(rig.objects[start][1], 57, GIGGLE_DURATION)
        print('  анимация giggle заменена')
    else:
        head = (anim_type, [(55, 'String', b'giggle'),
                            (57, 'Uint', GIGGLE_DURATION)])
        rig.objects[sm_at:sm_at] = [head] + block
        print('  анимация giggle добавлена (номер 3)')

    # --- стейт-машина: вход и состояние, если их ещё нет.
    if any(rig.types.get(tk) == 'StateMachineTrigger'
           for tk, _ in rig.objects):
        path.write_bytes(rig.dumps())
        print('Вход trg_pet уже есть — стейт-машина не тронута')
        return 0

    sm_at = next(i for i, (tk, _) in enumerate(rig.objects)
                 if rig.types.get(tk) == 'StateMachine')
    rig.objects[sm_at + 1:sm_at + 1] = [
        (reverse['StateMachineTrigger'], [(138, 'String', b'trg_pet')]),
    ]
    idle_state = next(
        i for i in range(sm_at, len(rig.objects))
        if rig.types.get(rig.objects[i][0]) == 'AnimationState'
        and get(rig.objects[i][1], 149) == 2)
    insert = idle_state + 1
    rig.objects[insert:insert] = [
        (reverse['StateTransition'], [(151, 'Uint', 4), (158, 'Uint', 120)]),
        (reverse['TransitionTriggerCondition'], [(155, 'Uint', 0)]),
        (reverse['AnimationState'], [(149, 'Uint', 3)]),
        (reverse['StateTransition'], [(151, 'Uint', 3), (152, 'Uint', 4),
                                      (158, 'Uint', 250),
                                      (160, 'Uint', 1100)]),
    ]
    path.write_bytes(rig.dumps())
    print('Смех подключён: вход trg_pet, состояние giggle, переходы записаны')
    return 0


def main() -> int:
    commands = ('inspect', 'fix', 'clean', 'place', 'breathe', 'blink', 'giggle')
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

    runner = {'inspect': cmd_inspect, 'clean': cmd_clean, 'place': cmd_place, 'breathe': cmd_breathe, 'blink': cmd_blink, 'giggle': cmd_giggle,
              'fix': cmd_fix}[command]
    if command == 'inspect':
        return runner(rig, scene)
    return runner(rig, scene, path)


if __name__ == '__main__':
    sys.exit(main())
