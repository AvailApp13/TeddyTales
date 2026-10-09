"""Вещи игровой в 3D: каждая вещь на своём месте, светом комнаты, с тенью.

Заказчик 09.10 (docs/room-furniture-plan.md): картинки вещей, наклеенные на
3D-комнату, не встают — у каждой свой ракурс и свой свет, теней нет. Здесь
вещь ставится в ту же сцену, что и комната (tool/nursery3d/scene.py), и
считается той же камерой и тем же светом. Стены, пол, отделка и тюль —
«ловцы теней»: на картинке их нет, есть только тень вещи на них. Слой вещи
вместе с тенью кладётся в приложении поверх комнаты — на любые стены и пол.

Как сделаны вещи:
  картины, полки — нынешняя картинка магазина на тонкой основе у стены:
                   заднюю стену камера видит прямо, без искажений;
  ковры          — картинка, «развёрнутая» в вид сверху, на мягкой основе;
  кресло         — модель по фото: объёмы слиты в одну пухлую форму, ткань
                   букле.

Запуск (Blender как модуль Python, см. scene.py):

    python tool/nursery3d/items.py --out <папка> --room <рендер комнаты>
        [--samples 256] [--only место/вещь,...] [--scale 1.0] [--assets]

--room — папка рендера комнаты (light.exr, маски): по ней баланс белого и
экспозиция, как у слоёв стен и пола. --assets — сложить слои в
assets/rooms/nursery/items и обновить lib/game/room_renders.dart.
"""

import argparse
import json
import math
import pathlib
import sys

import bpy
import bmesh
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).parent))
sys.path.insert(0, str(pathlib.Path(__file__).parents[1]))
import scene as room  # noqa: E402
from hit_grid import grid as hit_grid, to_hex  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHOP = ROOT / 'assets/shop'

# Мишка в 3D-мерках — 0,97 м; размеры вещей утверждались при мишке 1,15 м.
# Чтобы вещи остались той же величины рядом с мишкой — множитель.
SCALE = 0.973 / 1.15

# Места игровой (docs/room-furniture-plan.md). x — вправо от оси камеры,
# y — вглубь, z — вверх, метры. face — куда смотрит перед вещи, градусы от
# оси x против часовой (−90 — прямо на камеру).
SPOTS = {
    # Кресло у окна (заказчик 09.10): спинкой к стене у окна и развёрнуто к
    # комнате на 40° — из камеры виден тот же ракурс, что на фото магазина:
    # перед и правый подлокотник спереди слева. Против середины окна его
    # закрывал мишка — заказчик обвёл место левее мишки, перед окном, ближе
    # к нам: 3,3 м вглубь, задний угол — у стены.
    'nursery.floor_left': dict(kind='left', y=3.30, face=-40),
    # Справа (проверка интерьера 09.10: вещи срезались краем экрана и
    # наезжали друг на друга). Правее мишки до края экрана — 20 см пола у
    # ног и 80 см задней стены, поэтому три места разведены по глубине:
    # комод у задней стены — правым краем у края экрана Android; в углу
    # рядом с ним — растение или корзина; игрушка — впереди, у ног мишки.
    'nursery.floor_right': dict(kind='back', x=-0.33, face=-90),
    'nursery.corner_right': dict(kind='floor', x=0.05, y=4.10, face=-100),
    'nursery.rug': dict(kind='rug', x=-0.33, y=1.62),
    # Игрушки — по бокам от мишки, на ковре, на той же глубине, что и он:
    # слева игрушка больше не заслоняет низ кресла (проверка 09.10).
    'nursery.toy_left': dict(kind='floor', x=-0.67, y=1.62, face=-70),
    'nursery.toy_right': dict(kind='floor', x=-0.03, y=1.62, face=-110),
    # Полка выше на 15 см — комод до неё не достаёт; левее на 9 см — не
    # срезается краем экрана. Картины сдвинуты влево за ней — над мишкой.
    'nursery.wall_shelf': dict(kind='wall', x=-0.09, z=1.77),
    'nursery.wall_pic_left': dict(kind='wall', x=-1.50, z=1.95),
    'nursery.wall_pic_right': dict(kind='wall', x=-0.82, z=1.95),
}

# Что считается в 3D: ковры, картины, полка, кресло (заказчик 09.10).
JOBS = [
    ('nursery.rug', 'rug'),
    ('nursery.rug', 'rug_cloud'),
    ('nursery.rug', 'rug_heart'),
    ('nursery.wall_pic_left', 'pic_bear'),
    ('nursery.wall_pic_right', 'pic_bear'),
    ('nursery.wall_shelf', 'pic_bear'),
    ('nursery.wall_pic_left', 'pic_heart'),
    ('nursery.wall_pic_right', 'pic_heart'),
    ('nursery.wall_shelf', 'pic_heart'),
    ('nursery.wall_shelf', 'shelf'),
    ('nursery.floor_left', 'armchair'),
]

# Ширина вещей — из lib/game/item_groups.dart (с исключениями item_metrics).
WIDTH = {
    'rug': 0.945, 'rug_cloud': 0.945, 'rug_heart': 0.945,
    'pic_bear': 0.55, 'pic_heart': 0.55,
    'shelf': 0.85, 'shelf_moon': 0.85, 'shelf_house': 0.72,
    'armchair': 0.88,
}

# Вещи в настоящий размер комнаты, без поправки на мишку. Заказчик 09.10:
# кресло «не может быть ниже подоконника» — на обставленной детской от 20.09
# оно около 0,82 × 0,76 м, спинка выше подоконника.
REAL_SIZE = {'armchair'}


def item_scale(item_id):
    return 1.0 if item_id in REAL_SIZE else SCALE


# Ковёр на картинке магазина снят сверху под углом: круглые глаза мишки
# сплющены до 0,82 — во столько и сжата глубина. Разворачиваем обратно.
# «Облако» снято так же: пятиконечные звёзды на нём сплющены в среднем до
# 0,78 при 0,95 у ровной звезды — те же 0,82. Ковёр с сердцем круглый:
# кольца на нём сжаты до 0,63–0,66, контур с помпонами — до 0,635.
RUG_FORESHORTEN = {'rug': 0.82, 'rug_cloud': 0.82, 'rug_heart': 0.635}


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


# --- текстуры из картинок магазина --------------------------------------------

def shop_source(item_id):
    mapping = json.loads((SHOP / 'mapping.json').read_text())
    return SHOP / mapping[item_id]


def prepare_texture(item_id, tex_dir, unsquash=1.0, single=False):
    """Картинка вещи без пустых полей; для ковра — ещё и в виде сверху.

    single — оставить один самый крупный кусок: ковёр цельный, а в вырезку
    с листа магазина попадают чужие клочки (у «облака» — лист растения).

    Возвращает путь к PNG, пропорцию (высота / ширина) и контур вещи в долях
    картинки (для ковра — форма основы)."""
    import cv2
    im = Image.open(shop_source(item_id)).convert('RGBA')
    a = np.asarray(im)[..., 3]
    if single:
        n, lab, st, _ = cv2.connectedComponentsWithStats((a > 200).astype(np.uint8))
        big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        px = np.asarray(im).copy()
        px[..., 3][lab != big] = 0
        im = Image.fromarray(px, 'RGBA')
        a = px[..., 3]
    ys, xs = np.nonzero(a > 200)
    im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    if unsquash != 1.0:
        im = im.resize((im.width, round(im.height / unsquash)), Image.LANCZOS)
    tex_dir.mkdir(parents=True, exist_ok=True)
    path = tex_dir / f'{item_id}.png'
    im.save(path)
    mask = (np.asarray(im)[..., 3] > 200).astype(np.uint8)
    mask = cv2.erode(mask, np.ones((3, 3), np.uint8))
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 1.5, True)[:, 0, :].astype(float)
    contour = [(x / im.width, y / im.height) for x, y in c]
    return path, im.height / im.width, contour


def image_material(name, path, rough=0.7, bump=0.0, bump_scale=600.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(path))
    tex.interpolation = 'Cubic'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Specular IOR Level'].default_value = 0.25
    if bump > 0:
        coord = nt.nodes.new('ShaderNodeTexCoord')
        noise = nt.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = bump_scale
        noise.inputs['Detail'].default_value = 4
        nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
        b = nt.nodes.new('ShaderNodeBump')
        b.inputs['Strength'].default_value = bump
        b.inputs['Distance'].default_value = 0.002
        nt.links.new(noise.outputs['Fac'], b.inputs['Height'])
        nt.links.new(b.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def link(ob):
    coll = bpy.data.collections.get('items')
    if coll is None:
        coll = bpy.data.collections.new('items')
        bpy.context.scene.collection.children.link(coll)
    coll.objects.link(ob)
    return ob


# --- вещи ---------------------------------------------------------------------
# Каждая вещь строится в своих осях: пол — z = 0, перед смотрит в −y,
# центр — в начале координат. Настенные — в плоскости XZ, лицом в −y.

def build_card(item_id, tex_dir, depth):
    """Картина или полка: картинка магазина на тонкой основе у стены."""
    path, aspect, _ = prepare_texture(item_id, tex_dir)
    w = WIDTH[item_id] * SCALE
    h = w * aspect
    me = bpy.data.meshes.new(item_id)
    me.from_pydata([(-w / 2, 0, -h / 2), (w / 2, 0, -h / 2), (w / 2, 0, h / 2),
                    (-w / 2, 0, h / 2)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for loop, co in zip(uv.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop.uv = co
    ob = link(bpy.data.objects.new(item_id, me))
    ob.data.materials.append(image_material(item_id, path, rough=0.65))
    ob['wall_depth'] = depth
    return [ob]


def build_rug(item_id, tex_dir):
    """Ковёр: основа в форме ковра толщиной 12 мм, сверху — картинка."""
    path, aspect, contour = prepare_texture(item_id, tex_dir, RUG_FORESHORTEN.get(item_id, 1.0),
                                            single=True)
    w = WIDTH[item_id] * SCALE
    d = w * aspect
    t = 0.012
    bm = bmesh.new()
    verts = [bm.verts.new(((u - 0.5) * w, (0.5 - v) * d, 0.0)) for u, v in contour]
    face = bm.faces.new(verts)
    if face.normal.z < 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [e for e in ext['geom'] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, t))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    uv = bm.loops.layers.uv.new()
    for f in bm.faces:
        for lp in f.loops:
            x, y = lp.vert.co.x, lp.vert.co.y
            lp[uv].uv = (x / w + 0.5, y / d + 0.5)
    me = bpy.data.meshes.new(item_id)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(item_id, me))
    # Ворс — мелкая неровность поверх картинки.
    ob.data.materials.append(image_material(item_id, path, rough=0.95, bump=0.25, bump_scale=900))
    return [ob]


def boucle(name, color_srgb, bump=0.35):
    """Ткань букле: матовая, с мягким блеском ворса и мелкими петлями."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*srgb_to_linear(color_srgb), 1)
    bsdf.inputs['Roughness'].default_value = 1.0
    bsdf.inputs['Specular IOR Level'].default_value = 0.15
    bsdf.inputs['Sheen Weight'].default_value = 0.6
    bsdf.inputs['Sheen Roughness'].default_value = 0.4
    coord = nt.nodes.new('ShaderNodeTexCoord')
    vor = nt.nodes.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = 260.0
    vor.feature = 'F1'
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 45.0
    noise.inputs['Detail'].default_value = 8
    nt.links.new(coord.outputs['Object'], vor.inputs['Vector'])
    nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMath')
    mix.operation = 'ADD'
    nt.links.new(vor.outputs['Distance'], mix.inputs[0])
    nt.links.new(noise.outputs['Fac'], mix.inputs[1])
    b = nt.nodes.new('ShaderNodeBump')
    b.inputs['Strength'].default_value = bump
    b.inputs['Distance'].default_value = 0.005
    nt.links.new(mix.outputs[0], b.inputs['Height'])
    nt.links.new(b.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def quilted(name, color_srgb):
    """Стёганая подушка: ромбы прострочки по ткани."""
    m = boucle(name, color_srgb, bump=0.15)
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    coord = nt.nodes['Texture Coordinate']
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(coord.outputs['Object'], sep.inputs[0])
    lines = []
    for sgn in (1, -1):
        add = nt.nodes.new('ShaderNodeMath')
        add.operation = 'ADD'
        mul = nt.nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = sgn
        nt.links.new(sep.outputs['Z'], mul.inputs[0])
        nt.links.new(sep.outputs['X'], add.inputs[0])
        nt.links.new(mul.outputs[0], add.inputs[1])
        wave = nt.nodes.new('ShaderNodeMath')
        wave.operation = 'PINGPONG'
        wave.inputs[1].default_value = 0.022
        nt.links.new(add.outputs[0], wave.inputs[0])
        lines.append(wave)
    mn = nt.nodes.new('ShaderNodeMath')
    mn.operation = 'MINIMUM'
    nt.links.new(lines[0].outputs[0], mn.inputs[0])
    nt.links.new(lines[1].outputs[0], mn.inputs[1])
    b2 = nt.nodes.new('ShaderNodeBump')
    b2.inputs['Strength'].default_value = 1.0
    b2.inputs['Distance'].default_value = 0.008
    nt.links.new(mn.outputs[0], b2.inputs['Height'])
    old = nt.nodes['Bump']
    nt.links.new(old.outputs['Normal'], b2.inputs['Normal'])
    nt.links.new(b2.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def ellipsoid(bm, center, radii, segs=40, rings=24):
    mat = Matrix.Translation(center) @ Matrix.Diagonal((*radii, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=mat)


def rounded_box(name, size, center, bevel, mat, levels=2):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0)))
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    bv = ob.modifiers.new('bevel', 'BEVEL')
    bv.width = bevel
    bv.segments = 6
    bv.profile = 0.7
    sub = ob.modifiers.new('sub', 'SUBSURF')
    sub.levels = sub.render_levels = levels
    for p in me.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    return ob


def superellipse(n, power):
    """Точки сечения «округлый прямоугольник»: power 2 — эллипс, больше — квадратнее."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s_ = math.cos(a), math.sin(a)
        pts.append((math.copysign(abs(c) ** (2 / power), c),
                    math.copysign(abs(s_) ** (2 / power), s_)))
    return pts


def tub(name, xa, y_front, y_back0, yb, thick, z_bot, z_arm, z_back, dome, mat,
        n_sec=40, power=2.6, flare=0.0, droop=0.0):
    """Спинка и подлокотники — один толстый валик подковой.

    Путь сверху: левый подлокотник спереди назад, дуга спинки, правый
    подлокотник назад-вперёд. Сечение — округлый прямоугольник толщиной
    thick; верх валика — z_arm у подлокотников и z_back у спинки. Передки
    подлокотников закруглены куполом радиуса dome."""
    path = []          # (x, y, tx, ty, z_top, scale, front)
    n_arm, n_arc, n_dome = 26, 64, 10
    # купол левого подлокотника: от кончика назад
    for i in range(n_dome, 0, -1):
        th = (math.pi / 2) * i / n_dome
        path.append((-xa, y_front - dome * math.sin(th), 0, 1, z_arm, math.cos(th), 1.0))
    for i in range(n_arm):
        f = 1 - i / n_arm
        y = y_front + (y_back0 - y_front) * i / n_arm
        path.append((-xa, y, 0, 1, z_arm, 1.0, f))
    for i in range(n_arc + 1):
        a = math.pi - math.pi * i / n_arc
        x, y = xa * math.cos(a), y_back0 + yb * math.sin(a)
        tx, ty = -xa * math.sin(a), yb * math.cos(a)
        ln = math.hypot(tx, ty)
        lift = math.sin(a) ** 1.5
        path.append((x, y, -tx / ln, -ty / ln, z_arm + (z_back - z_arm) * lift, 1.0, 0.0))
    for i in range(1, n_arm + 1):
        f = i / n_arm
        y = y_back0 + (y_front - y_back0) * i / n_arm
        path.append((xa, y, 0, -1, z_arm, 1.0, f))
    for i in range(1, n_dome + 1):
        th = (math.pi / 2) * i / n_dome
        path.append((xa, y_front - dome * math.sin(th), 0, -1, z_arm, math.cos(th), 1.0))
    sec = superellipse(n_sec, power)
    verts, faces = [], []
    for (x, y, tx, ty, z_top, sc, front) in path:
        nx, ny = ty, -tx              # горизонтальная нормаль к пути
        z_top = z_top - droop * front
        t = thick * (1 + flare * front)
        zc, hh = (z_bot + z_top) / 2, (z_top - z_bot) / 2
        sc = max(sc, 0.02)
        for (cu, cz) in sec:
            verts.append((x + nx * cu * t / 2 * sc, y + ny * cu * t / 2 * sc,
                          zc + cz * hh * (0.35 + 0.65 * sc)))
    rows = len(path)
    for r in range(rows - 1):
        for i in range(n_sec):
            a = r * n_sec + i
            b = r * n_sec + (i + 1) % n_sec
            faces.append((a, b, b + n_sec, a + n_sec))
    # концы — веером в точку
    for end, flip in ((0, False), (rows - 1, True)):
        c = len(verts)
        ring = [end * n_sec + i for i in range(n_sec)]
        cx = sum(verts[i][0] for i in ring) / n_sec
        cy = sum(verts[i][1] for i in ring) / n_sec
        cz = sum(verts[i][2] for i in ring) / n_sec
        verts.append((cx, cy, cz))
        for i in range(n_sec):
            f = (ring[i], ring[(i + 1) % n_sec], c)
            faces.append(f[::-1] if flip else f)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    ob = link(bpy.data.objects.new(name, me))
    sub = ob.modifiers.new('sub', 'SUBSURF')
    sub.levels = sub.render_levels = 1
    ob.data.materials.append(mat)
    return ob


def build_armchair(item_id='armchair'):
    """Розовое кресло-«облако» по фото магазина (assets/shop/incoming/armchair_pink.png).

    Спинка и подлокотники — один толстый валик подковой: спинка выше,
    подлокотники ниже, передки круглые. Под ним — плоское основание на полу,
    в середине — толстая подушка сиденья, в спинку уложена кремовая стёганая
    подушка. Ткань — букле. Ширина — как у рода «Кресла» (0,88 м при мишке
    1,15 м); модель задана при ширине 0,76 и масштабируется."""
    k = WIDTH[item_id] * item_scale(item_id) / 0.88
    pink = boucle('boucle_pink', (232, 146, 136))
    cream = quilted('pillow_cream', (243, 232, 214))
    parts = []
    # Подлокотники и спинка доходят до пола; спереди подлокотники толще и
    # чуть ниже, передки круглые.
    body = tub('armchair_tub', xa=0.305 * k, y_front=-0.21 * k, y_back0=0.05 * k,
               yb=0.20 * k, thick=0.25 * k, z_bot=0.0, z_arm=0.53 * k,
               z_back=0.72 * k, dome=0.11 * k, mat=pink, power=2.5,
               flare=0.12, droop=0.03 * k)
    parts.append(body)
    # Сиденье — толстая подушка вровень с подлокотниками, до самого пола.
    seat = rounded_box('armchair_seat', Vector((0.38, 0.47, 0.38)) * k,
                       Vector((0.0, -0.075, 0.195)) * k, 0.10 * k, pink)
    soft = seat.modifiers.new('soft', 'CAST')
    soft.factor = 0.12
    parts.append(seat)
    pillow = rounded_box('armchair_pillow', Vector((0.33, 0.11, 0.23)) * k,
                         Vector((0.0, 0.0, 0.0)), 0.05 * k, cream, levels=3)
    cast = pillow.modifiers.new('puff', 'CAST')
    cast.factor = 0.2
    pillow.rotation_euler = (math.radians(-16), 0, 0)
    pillow.location = Vector((0.0, 0.10, 0.55)) * k
    parts.append(pillow)
    return parts


def build_item(item_id, tex_dir):
    if item_id.startswith('rug'):
        return build_rug(item_id, tex_dir)
    if item_id.startswith('pic_'):
        return build_card(item_id, tex_dir, 0.025)
    if item_id.startswith('shelf'):
        return build_card(item_id, tex_dir, 0.05)
    if item_id == 'armchair':
        return build_armchair(item_id)
    raise SystemExit(f'нет модели для {item_id}')


def footprint_depth(objs):
    """Глубина вещи по y (для мест у стены): по габаритам после модификаторов."""
    dg = bpy.context.evaluated_depsgraph_get()
    ys = []
    for ob in objs:
        ev = ob.evaluated_get(dg)
        for corner in ev.bound_box:
            ys.append((ob.matrix_world @ Vector(corner)).y)
    return min(ys), max(ys)


def footprint_x(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    xs = []
    for ob in objs:
        ev = ob.evaluated_get(dg)
        for corner in ev.bound_box:
            xs.append((ob.matrix_world @ Vector(corner)).x)
    return min(xs), max(xs)


def place(objs, slot_id):
    """Ставит вещь на место: поворот, положение."""
    s = SPOTS[slot_id]
    root = bpy.data.objects.new('item_root', None)
    link(root)
    for ob in objs:
        if ob.parent is None:
            ob.parent = root
    if s['kind'] == 'wall':
        depth = objs[0].get('wall_depth', 0.03)
        root.location = (s['x'], room.D - depth, s['z'])
    elif s['kind'] == 'left':
        root.rotation_euler = (0, 0, math.radians(s['face'] + 90))
        bpy.context.view_layer.update()
        x0, _ = footprint_x(objs)
        # Спинкой к левой стене: ближняя к стене точка — у плинтуса.
        root.location = (-room.WL + 0.035 - x0, s['y'], 0.0)
    elif s['kind'] == 'rug':
        root.location = (s['x'], s['y'], 0.0)
    else:
        root.rotation_euler = (0, 0, math.radians(s['face'] + 90))
        if s['kind'] == 'back':
            bpy.context.view_layer.update()
            y0, y1 = footprint_depth(objs)
            # Вплотную к стене, с зазором под плинтус.
            root.location = (s['x'], room.D - 0.035 - y1, 0.0)
        else:
            root.location = (s['x'], s['y'], 0.0)
    bpy.context.view_layer.update()
    return root


# --- рендер -------------------------------------------------------------------

def screen_bbox(cam, objs, margin=0.35, pad=40, sun_shadow=True):
    """Где вещь в кадре — с запасом на тень (солнце и мягкий свет)."""
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    sun = Vector((1.1, -1.9, -1.6)).normalized()
    us, vs = [], []
    for ob in objs:
        if ob.type != 'MESH':
            continue
        ev = ob.evaluated_get(dg)
        mw = ob.matrix_world
        for corner in ev.bound_box:
            p = mw @ Vector(corner)
            pts = [p]
            if sun_shadow and p.z > 0.01 and sun.z < 0:
                pts.append(p + sun * (p.z / -sun.z))     # тень солнца на полу
            for q in pts:
                c = world_to_camera_view(sc, cam, q)
                us.append(c.x * room.W_PX)
                vs.append((1 - c.y) * room.H_PX)
    u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
    mu, mv = (u1 - u0) * margin + pad, (v1 - v0) * margin + pad
    return (max(0, u0 - mu), min(room.W_PX, u1 + mu),
            max(0, v0 - mv), min(room.H_PX, v1 + mv))


def setup_job(samples, scale):
    sc = bpy.context.scene
    room.setup_render(scale, samples)
    sc.render.film_transparent = True
    # Комната — «ловец теней»: её самой на картинке нет, есть тень вещи на
    # ней. Улица за окном камере не видна.
    for coll in bpy.data.collections:
        for ob in coll.objects:
            if coll.name == 'view':
                ob.visible_camera = False
            elif coll.name != 'items':
                ob.is_shadow_catcher = True
    vl = sc.view_layers[0]
    vl.cycles.use_pass_shadow_catcher = True
    sc.render.use_compositing = True
    sc.use_nodes = True
    tree = sc.node_tree
    tree.nodes.clear()
    rl = tree.nodes.new('CompositorNodeRLayers')
    fo = tree.nodes.new('CompositorNodeOutputFile')
    fo.format.file_format = 'OPEN_EXR'
    fo.format.color_depth = '32'
    fo.format.exr_codec = 'ZIP'
    fo.file_slots.clear()
    fo.file_slots.new('item')
    fo.file_slots.new('shadow')
    tree.links.new(rl.outputs['Image'], fo.inputs['item'])
    tree.links.new(rl.outputs['Shadow Catcher'], fo.inputs['shadow'])
    return fo


def render_job(slot_id, item_id, out, samples, scale):
    room.build()
    room.lights()
    cam = room.camera()
    tex_dir = out / 'tex'
    objs = build_item(item_id, tex_dir)
    place(objs, slot_id)
    fo = setup_job(samples, scale)
    wall = SPOTS[slot_id]['kind'] == 'wall'
    u0, u1, v0, v1 = (screen_bbox(cam, objs, margin=0.25, pad=36, sun_shadow=False)
                      if wall else screen_bbox(cam, objs))
    sc = bpy.context.scene
    sc.render.use_border = True
    sc.render.use_crop_to_border = False
    sc.render.border_min_x = u0 / room.W_PX
    sc.render.border_max_x = u1 / room.W_PX
    sc.render.border_min_y = 1 - v1 / room.H_PX
    sc.render.border_max_y = 1 - v0 / room.H_PX
    name = f'{slot_id.split(".")[1]}__{item_id}'
    job_dir = out / name
    job_dir.mkdir(parents=True, exist_ok=True)
    fo.base_path = str(job_dir)
    sc.frame_set(1)
    bpy.ops.render.render(write_still=False)
    (job_dir / 'border.json').write_text(json.dumps([u0, u1, v0, v1]))
    print(f'{name}: кадр u {u0:.0f}–{u1:.0f}, v {v0:.0f}–{v1:.0f}')
    return job_dir


# --- слои для приложения -------------------------------------------------------

def load_exr(path):
    import exr
    return exr.load(path)


def compose_job(job_dir, r, floor_like):
    """Слой вещи с тенью: RGBA, обрезан по содержимому. Цвет — как у слоёв
    комнаты: тот же баланс белого и экспозиция (compose.Room)."""
    import compose
    item = load_exr(next(job_dir.glob('item*.exr')))
    shadow = load_exr(next(job_dir.glob('shadow*.exr')))
    h, w = item.shape[:2]
    a = np.clip(item[..., 3], 0, 1)
    rgb = item[..., :3] / np.maximum(a, 1e-4)[..., None]
    lin = rgb * r.wb * r.exposure
    if floor_like:
        knee, top = 0.68, 0.30
        over = lin > knee
        lin[over] = knee + top * np.tanh((lin[over] - knee) / top)
    col = compose.lin_to_srgb8(lin).astype(np.float64)
    # Тень: доля света, которую вещь отняла у стены и пола.
    import cv2
    s = np.clip(shadow[..., :3].mean(axis=2), 0, 1)
    sa = np.clip(1 - s, 0, 1).astype(np.float32)
    # Вне рамки рендера пусто: там и тени нет.
    u0, u1, v0, v1 = json.loads((job_dir / 'border.json').read_text())
    k = w / room.W_PX
    inside = np.zeros_like(sa)
    inside[int(v0 * k) + 2:int(v1 * k) - 2, int(u0 * k) + 2:int(u1 * k) - 2] = 1
    sa *= inside
    # Шум ловца теней — мягко размыть; едва заметное потемнение (вещь чуть
    # заслонила свет на всю стену) — убрать, иначе по краю рамки ступенька.
    sa = cv2.GaussianBlur(sa, (0, 0), 1.2 * k)
    floor = 0.035
    sa = np.clip((sa - floor) / (1 - floor), 0, 1)
    # И к краю рамки тень сходит на нет.
    edge = cv2.GaussianBlur(inside.astype(np.float32), (0, 0), 10 * k)
    sa *= np.clip((edge - 0.5) * 2, 0, 1)
    out_a = a + sa * (1 - a)
    out_rgb = col * (a / np.maximum(out_a, 1e-4))[..., None]
    rgba = np.dstack([np.clip(out_rgb, 0, 255), out_a * 255]).astype(np.uint8)
    ys, xs = np.nonzero(rgba[..., 3] > 1)
    x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, w)
    y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, h)
    img = Image.fromarray(rgba[y0:y1, x0:x1], 'RGBA')
    k = room.W_PX / w
    rect = (x0 * k / room.W_PX, y0 * k / room.H_PX, (x1 - x0) * k / room.W_PX,
            (y1 - y0) * k / room.H_PX)
    # Сетка нажатия — по самой вещи, без тени (заказчик 09.10: нажатие по
    # комоду и ковру открывало кресло — его слой с тенью накрывал полкомнаты).
    hit = to_hex(hit_grid(a[y0:y1, x0:x1]))
    return img, rect, hit


def write_dart(entries, path):
    """entries: «место/вещь» → {'rect': [l, t, w, h], 'hit': сетка}. Пишется
    сразу так, как его оставил бы `dart format`."""
    lines = [
        '// Сгенерировано tool/nursery3d/items.py — не править руками.',
        '//',
        '// Вещи игровой, посчитанные в 3D на своих местах: слой вещи вместе с',
        '// тенью, где он лежит в кадре комнаты (доли ширины и высоты кадра) и',
        '// где в нём сама вещь — сетка нажатия (lib/game/hit_mask.dart).',
        '// Пара «место/вещь», которой здесь нет, рисуется картинкой магазина.',
        '',
        "import 'hit_mask.dart';",
        "import 'room_render.dart';",
        '',
        'const Map<String, RoomRender> roomRenders = {',
    ]
    for key in sorted(entries):
        l, t, w, h = entries[key]['rect']
        lines.append(f"  '{key}': RoomRender(")
        lines += [f'    {v:.5f},' for v in (l, t, w, h)]
        lines.append(f"    HitMask('{entries[key]['hit']}'),")
        lines.append('  ),')
    lines.append('};')
    path.write_text('\n'.join(lines) + '\n')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--room', required=True, help='папка рендера комнаты (scene.py)')
    ap.add_argument('--samples', type=int, default=256)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--only', default='')
    ap.add_argument('--skip-render', action='store_true')
    ap.add_argument('--assets', action='store_true')
    args = ap.parse_args(argv)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    jobs = JOBS
    if args.only:
        want = set(args.only.split(','))
        jobs = [j for j in JOBS if f'{j[0].split(".")[1]}/{j[1]}' in want]
    if not args.skip_render:
        for slot_id, item_id in jobs:
            render_job(slot_id, item_id, out, args.samples, args.scale)

    import compose
    r = compose.Room(args.room)
    entries = {}
    layer_dir = ROOT / 'assets/rooms/nursery/items' if args.assets else out / 'layers'
    layer_dir.mkdir(parents=True, exist_ok=True)
    for slot_id, item_id in jobs:
        name = f'{slot_id.split(".")[1]}__{item_id}'
        img, rect, hit = compose_job(out / name, r, floor_like=item_id.startswith('rug'))
        img.save(layer_dir / f'{name}.webp', quality=90, alpha_quality=100, method=6)
        entries[f'{slot_id}/{item_id}'] = {'rect': [round(v, 5) for v in rect], 'hit': hit}
        print(f'{name}: {img.width}×{img.height}, '
              f'{(layer_dir / (name + ".webp")).stat().st_size // 1024} КБ')
    if args.assets:
        # Пересчитанные пары дописываются к уже готовым; пары, которых больше
        # нет в JOBS (место переехало), выбрасываются вместе со слоем.
        book = pathlib.Path(__file__).parent / 'renders.json'
        allr = json.loads(book.read_text()) if book.exists() else {}
        allr.update(entries)
        known = {f'{s}/{i}' for s, i in JOBS}
        for key in [k for k in allr if k not in known]:
            del allr[key]
            s, i = key.split('/')
            (layer_dir / f'{s.split(".")[1]}__{i}.webp').unlink(missing_ok=True)
        book.write_text(json.dumps(allr, indent=1, sort_keys=True, ensure_ascii=False) + '\n')
        write_dart(allr, ROOT / 'lib/game/room_renders.dart')
    (out / 'rects.json').write_text(json.dumps(entries, indent=1))


if __name__ == '__main__':
    main()
