"""Игровая в 3D: комната по меркам assets/rooms/nursery.jpg.

Заказчик 09.10 (docs/room-structure-plan.md): база игровой собирается не
одной картинкой, а слоями — стены, пол, отделка, шторы, вид за окном, — чтобы
стены и пол менялись, а потолок, плинтусы, рама и тюль оставались белыми.

Запуск (Blender как модуль Python, ставится `pip install bpy==4.5.14`):

    python tool/nursery3d/scene.py --out <папка> [--scale 0.5] [--samples 64]
        [--only light,masks,curtains]

Что считается:
  light.exr      — вся комната с белыми стенами и полом (альбедо NEUTRAL):
                   свет стен и пола, отделка, потолок, вид за окном. Тюль
                   невидим для камеры, но тень от него есть.
  mask_<класс>.png — покрытие класса с учётом того, что перед ним
                   (walls, floor, trim, ceiling, view), сглаженные края.
  curtains.png   — один тюль на прозрачном фоне: полупрозрачность настоящая,
                   кладётся поверх любой стены.

Геометрия. Камера смотрит прямо на заднюю стену (её линии горизонтальны), все
линии глубины сходятся в точку (757, 715) кадра 941 × 1672. Из линий картинки:
пол у задней стены y = 892, верх карниза y = 233, угол стен x = 279 → при
высоте потолка 2,7 м глаз на 0,725 м, задняя стена в D = F / 244,07 м,
левая — в 1,958 м левее камеры. Фокус F (px) — свободный, задаёт глубину
комнаты; 1300 px ≈ 65° по вертикали.
"""

import argparse
import math
import pathlib
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

W_PX, H_PX = 941, 1672
VP = (757.0, 715.0)          # точка схода в пикселях кадра
F_PX = 1300.0                 # фокус камеры, px
PX_PER_M = 892.0 - 233.0      # пикселей на 2,7 м задней стены
CEIL = 2.70                   # высота потолка, м
K = PX_PER_M / CEIL           # px на метр у задней стены
EYE = (892.0 - VP[1]) / K     # высота глаза, м
D = F_PX / K                  # расстояние до задней стены, м
WL = (VP[0] - 279.0) / K      # левая стена левее камеры, м
WR = 3.2                      # правая стена — за кадром
FRONT = -1.6                  # стена за камерой — за кадром

BASEBOARD = (892.0 - 861.0) / K        # высота плинтуса, ~0,127 м
CORNICE = CEIL - (EYE + (VP[1] - 250.0) / K)  # высота карниза, ~0,07 м
WALL_T = 0.05                 # глубина откосов: окно видно почти вдоль стены,
                              # толстые откосы закрыли бы стекло

NEUTRAL = 0.75                # альбедо стен и пола при расчёте света


def depth_at_u(u):
    """Глубина точки левой стены, видной в столбце u кадра."""
    return F_PX * WL / (VP[0] - u)


# Окно на левой стене — по картинке: рама от края кадра до u ≈ 95,
# стекло с y ≈ 100 до 770 у u = 50.
WIN_Y0 = depth_at_u(-140)     # ближний край проёма (за кадром слева)
WIN_Y1 = depth_at_u(96)       # дальний край проёма
WIN_Z0 = 0.58                 # низ проёма (подоконник)
WIN_Z1 = 2.42                 # верх проёма

# Тюль: главный — между окном и углом (u 100…215), второй — у ближнего
# края окна (u 0…20, почти весь за кадром).
CURTAIN_MAIN = (depth_at_u(98), depth_at_u(216))
CURTAIN_NEAR = (depth_at_u(-40), depth_at_u(22))
ROD_Z = 2.50


# --- Сцена ------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in ('walls', 'floor', 'trim', 'ceiling', 'view', 'curtains',
                 'shell'):
        c = bpy.data.collections.new(coll)
        bpy.context.scene.collection.children.link(c)


def material(name, color, rough=0.95, spec=0.25):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Specular IOR Level'].default_value = spec
    return m


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64) / 255.0
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


def box(name, coll, lo, hi, mat, bevel=0.0):
    lo, hi = Vector(lo), Vector(hi)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(lo + hi) / 2)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = hi - lo
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    if bevel > 0:
        mod = ob.modifiers.new('bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = 'ANGLE'
    for c in ob.users_collection:
        c.objects.unlink(ob)
    bpy.data.collections[coll].objects.link(ob)
    return ob


def curtain(name, y0, y1, mat, seed):
    """Тюль: полотно со складками, висит в 9 см от левой стены."""
    rng = np.random.default_rng(seed)
    nx, nz = 160, 120
    width = y1 - y0
    verts, faces = [], []
    phases = rng.uniform(0, 2 * math.pi, 3)
    for j in range(nz + 1):
        t = j / nz                       # 0 — низ, 1 — верх
        z = 0.012 + t * (ROD_Z - 0.012)
        amp = 0.018 + 0.030 * (1 - t) ** 1.5   # книзу складки глубже
        for i in range(nx + 1):
            s = i / nx
            y = y0 + s * width
            fold = (math.sin(2 * math.pi * s * width / 0.13 + phases[0])
                    + 0.45 * math.sin(2 * math.pi * s * width / 0.071 + phases[1])
                    + 0.25 * math.sin(2 * math.pi * s * width / 0.29 + phases[2]))
            x = -WL + 0.09 + amp * fold
            verts.append((x, y, z))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.data.collections['curtains'].objects.link(ob)
    return ob


def sheer_material():
    """Белый тюль: часть света проходит насквозь, часть рассеивается."""
    m = bpy.data.materials.new('sheer')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    mix = nt.nodes.new('ShaderNodeMixShader')
    transp = nt.nodes.new('ShaderNodeBsdfTransparent')
    cloth = nt.nodes.new('ShaderNodeMixShader')
    transl = nt.nodes.new('ShaderNodeBsdfTranslucent')
    diff = nt.nodes.new('ShaderNodeBsdfDiffuse')
    white = (0.92, 0.90, 0.86, 1)
    transl.inputs['Color'].default_value = white
    diff.inputs['Color'].default_value = white
    cloth.inputs[0].default_value = 0.45
    nt.links.new(transl.outputs[0], cloth.inputs[1])
    nt.links.new(diff.outputs[0], cloth.inputs[2])
    mix.inputs[0].default_value = 0.62          # доля ткани, остальное — просвет
    nt.links.new(transp.outputs[0], mix.inputs[1])
    nt.links.new(cloth.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    return m


def view_material(path):
    """Вид за окном — светящаяся картинка (небо, облака, листва)."""
    m = bpy.data.materials.new('view')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(path))
    em.inputs['Strength'].default_value = 1.0
    nt.links.new(tex.outputs['Color'], em.inputs['Color'])
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    return m


def make_view_texture(path):
    """Вид за окном: голубое небо с облаком, ниже — кроны деревьев.

    Картинка ровно на ту часть плоскости, что видна сквозь окно (см.
    VIEW_Y, VIEW_Z): небо сверху, зелень в нижних двух пятых.
    """
    from PIL import Image, ImageFilter
    w, h = 512, 1024
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    t = yy[..., None]
    sky = np.array([0.40, 0.66, 0.94]) * (1 - t) + np.array([0.78, 0.89, 0.99]) * t
    img = sky.copy()
    rng = np.random.default_rng(5)
    clouds = np.zeros((h, w))
    for cx, cy, r in ((0.3, 0.16, 0.16), (0.55, 0.13, 0.12), (0.75, 0.2, 0.14),
                      (0.15, 0.34, 0.10), (0.45, 0.36, 0.12), (0.85, 0.40, 0.09)):
        clouds += np.exp(-(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.35)) ** 2) * 2.5)
    c = np.clip(clouds, 0, 1)[..., None] * 0.95
    img = img * (1 - c) + c
    crown = np.zeros((h, w))
    tone = np.zeros((h, w))
    for _ in range(26):
        cx, cy = rng.uniform(-0.1, 1.1), rng.uniform(0.58, 1.02)
        r = rng.uniform(0.10, 0.22)
        d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.55)) ** 2)
        m = np.clip((1.0 - d) * 6, 0, 1)
        lit = np.clip(0.5 + (cx - xx) / r * 0.5 + (cy - yy) / r * 0.6, 0, 1)
        tone = np.where(m > crown, lit, tone)
        crown = np.maximum(crown, m)
    green_dark = np.array([0.42, 0.66, 0.24])
    green_lit = np.array([0.72, 0.86, 0.36])
    green = green_dark * (1 - tone[..., None]) + green_lit * tone[..., None]
    k = crown[..., None]
    img = img * (1 - k) + green * k
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    im.filter(ImageFilter.GaussianBlur(2.5)).save(path)


def build(view_png):
    reset()
    white = material('white', srgb_to_linear((240, 236, 228)), rough=0.6, spec=0.3)
    neutral = material('neutral', (NEUTRAL,) * 3)
    ceiling = material('ceiling', srgb_to_linear((236, 232, 225)))
    shell = material('shell', (0.8, 0.78, 0.75))

    # Стены и пол — белые (альбедо NEUTRAL): их свет потом умножается на
    # выбранный цвет или узор.
    box('wall_back', 'walls', (-WL - WALL_T, D, 0), (WR, D + 0.2, CEIL), neutral)
    # Левая стена — куски вокруг оконного проёма.
    x0, x1 = -WL - WALL_T, -WL
    box('wall_left_front', 'walls', (x0, FRONT, 0), (x1, WIN_Y0, CEIL), neutral)
    box('wall_left_back', 'walls', (x0, WIN_Y1, 0), (x1, D, CEIL), neutral)
    box('wall_left_low', 'walls', (x0, WIN_Y0, 0), (x1, WIN_Y1, WIN_Z0), neutral)
    box('wall_left_high', 'walls', (x0, WIN_Y0, WIN_Z1), (x1, WIN_Y1, CEIL), neutral)
    box('floor', 'floor', (-WL - 0.3, FRONT, -0.1), (WR, D + 0.2, 0), neutral)
    box('ceiling', 'ceiling', (-WL - 0.3, FRONT, CEIL), (WR, D + 0.2, CEIL + 0.1), ceiling)
    box('wall_right', 'shell', (WR, FRONT, 0), (WR + 0.2, D, CEIL), shell)
    box('wall_front', 'shell', (-WL, FRONT - 0.2, 0), (WR, FRONT, CEIL), shell)

    # Отделка — всегда тёплый белый.
    bb_t = 0.018
    box('baseboard_back', 'trim', (-WL, D - bb_t, 0), (WR, D, BASEBOARD), white, 0.006)
    box('baseboard_left', 'trim', (-WL, FRONT, 0), (-WL + bb_t, D, BASEBOARD), white, 0.006)
    cd = 0.055
    box('cornice_back', 'trim', (-WL, D - cd, CEIL - CORNICE), (WR, D, CEIL), white, 0.02)
    box('cornice_left', 'trim', (-WL, FRONT, CEIL - CORNICE), (-WL + cd, D, CEIL), white, 0.02)
    # Откосы, подоконник и рама.
    lt = 0.02
    box('jamb_head', 'trim', (x0, WIN_Y0, WIN_Z1 - lt), (x1, WIN_Y1, WIN_Z1), white)
    box('jamb_near', 'trim', (x0, WIN_Y0, WIN_Z0), (x1, WIN_Y0 + lt, WIN_Z1), white)
    box('jamb_far', 'trim', (x0, WIN_Y1 - lt, WIN_Z0), (x1, WIN_Y1, WIN_Z1), white)
    box('sill', 'trim', (x0, WIN_Y0 - 0.05, WIN_Z0 - 0.04), (x1 + 0.07, WIN_Y1 + 0.05, WIN_Z0), white, 0.008)
    fx0, fx1 = x0 + 0.005, x0 + 0.04      # рама в проёме
    fw = 0.06
    # Рама из брусков встык, без перекрытий: в перекрытиях свет не доходит
    # до граней, и на углах получались чёрные точки. Бруски чуть заходят
    # в откосы, чтобы не было щелей на небо.
    e = 0.004
    zb, zt = WIN_Z0 + fw, WIN_Z1 - fw
    box('frame_bottom', 'trim', (fx0, WIN_Y0 - e, WIN_Z0 - e), (fx1, WIN_Y1 + e, zb), white)
    box('frame_top', 'trim', (fx0, WIN_Y0 - e, zt), (fx1, WIN_Y1 + e, WIN_Z1 + e), white)
    box('frame_near', 'trim', (fx0, WIN_Y0 - e, zb), (fx1, WIN_Y0 + fw, zt), white)
    box('frame_far', 'trim', (fx0, WIN_Y1 - fw, zb), (fx1, WIN_Y1 + e, zt), white)
    mid = (WIN_Y0 + WIN_Y1) / 2
    tz = WIN_Z0 + (WIN_Z1 - WIN_Z0) * 0.68
    i = 0.003                              # переплёт чуть тоньше рамы
    box('transom', 'trim', (fx0 + i, WIN_Y0 + fw, tz - 0.025), (fx1 - i, WIN_Y1 - fw, tz + 0.025), white)
    box('mullion_low', 'trim', (fx0 + i, mid - 0.025, zb), (fx1 - i, mid + 0.025, tz - 0.025), white)
    box('mullion_high', 'trim', (fx0 + i, mid - 0.025, tz + 0.025), (fx1 - i, mid + 0.025, zt), white)
    # Короб карниза для штор над окном.
    box('pelmet', 'trim', (-WL, CURTAIN_NEAR[0] - 0.15, ROD_Z - 0.03),
        (-WL + 0.15, CURTAIN_MAIN[1] + 0.08, CEIL - CORNICE), white, 0.01)

    # Вид за окном.
    view = bpy.data.objects.new('view', bpy.data.meshes.new('view'))
    # Окно видно под острым углом: сквозь него видна полоса плоскости
    # y 4,6…6,2 м, z 0,5…3,5 м (на 1,2 м за стеной). Картинка вида
    # растянута ровно на неё, с запасом.
    vx = -WL - 1.2
    y0, y1, z0, z1 = 4.2, 6.6, 0.0, 4.0
    view.data.from_pydata([(vx, y0, z0), (vx, y1, z0), (vx, y1, z1), (vx, y0, z1)],
                          [], [(0, 1, 2, 3)])
    uv = view.data.uv_layers.new(name='UVMap')
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for loop in view.data.loops:
        uv.data[loop.index].uv = corners[loop.vertex_index]
    view.data.materials.append(view_material(view_png))
    bpy.data.collections['view'].objects.link(view)
    view.visible_shadow = False

    sheer = sheer_material()
    curtain('curtain_main', *CURTAIN_MAIN, sheer, 1)
    curtain('curtain_near', *CURTAIN_NEAR, sheer, 2)


def lights():
    sc = bpy.context.scene
    world = bpy.data.worlds.new('world')
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.85, 0.9, 1.0, 1)
    bg.inputs['Strength'].default_value = 0.0
    sc.world = world

    # Солнце через окно: пятна рам на полу, как на нынешней картинке.
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 4.2
    sun.angle = math.radians(1.0)
    sun.color = (1.0, 0.92, 0.80)
    ob = bpy.data.objects.new('sun', sun)
    # Пятна — как на картинке: от окна к центру пола, ближе к камере.
    direction = Vector((0.75, -0.82, -1.0)).normalized()
    ob.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    sc.collection.objects.link(ob)

    # Небо в проёме окна — мягкий голубоватый свет.
    sky = bpy.data.lights.new('sky', 'AREA')
    sky.shape = 'RECTANGLE'
    sky.size = WIN_Y1 - WIN_Y0
    sky.size_y = WIN_Z1 - WIN_Z0
    sky.energy = 55
    sky.color = (0.96, 0.97, 1.0)
    ob = bpy.data.objects.new('sky', sky)
    ob.location = (-WL - WALL_T - 0.05, (WIN_Y0 + WIN_Y1) / 2, (WIN_Z0 + WIN_Z1) / 2)
    ob.rotation_euler = Vector((1, 0, 0)).to_track_quat('-Z', 'Y').to_euler()
    ob.visible_camera = False      # в окне видно небо, а не лампу
    sc.collection.objects.link(ob)

    # Мягкая подсветка от стены за камерой: комната светлая, тени лёгкие.
    fill = bpy.data.lights.new('fill', 'AREA')
    fill.shape = 'RECTANGLE'
    fill.size = 4.0
    fill.size_y = 2.2
    fill.energy = 38
    fill.color = (1.0, 0.95, 0.89)
    ob = bpy.data.objects.new('fill', fill)
    ob.location = (0.2, FRONT + 0.05, 1.5)
    ob.rotation_euler = Vector((0, 1, 0)).to_track_quat('-Z', 'Y').to_euler()
    sc.collection.objects.link(ob)

    # Отражённый от пола свет снизу: потолок и карниз светлые, как на
    # картинке, а не серые.
    bounce = bpy.data.lights.new('bounce', 'AREA')
    bounce.shape = 'RECTANGLE'
    bounce.size = 3.2
    bounce.size_y = 4.0
    bounce.energy = 70
    bounce.color = (1.0, 0.93, 0.85)
    ob = bpy.data.objects.new('bounce', bounce)
    ob.location = (-0.3, 2.6, 0.02)
    ob.rotation_euler = Vector((0, 0, 1)).to_track_quat('-Z', 'Y').to_euler()
    ob.visible_camera = False
    sc.collection.objects.link(ob)

    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.12
    # В щели рамы камера видит небо, а не темноту: для лучей камеры фон
    # светлый, для освещения комнаты — слабый.
    nt = world.node_tree
    bright = nt.nodes.new('ShaderNodeBackground')
    bright.inputs['Color'].default_value = (0.78, 0.88, 0.98, 1)
    bright.inputs['Strength'].default_value = 1.0
    path = nt.nodes.new('ShaderNodeLightPath')
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(path.outputs['Is Camera Ray'], mix.inputs[0])
    nt.links.new(nt.nodes['Background'].outputs[0], mix.inputs[1])
    nt.links.new(bright.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes['World Output'].inputs['Surface'])


def camera():
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.sensor_fit = 'VERTICAL'
    cam.sensor_height = 36.0
    cam.lens = F_PX * cam.sensor_height / H_PX
    # Сдвиг объектива: точка схода не в центре кадра. Единица сдвига —
    # бо́льшая сторона кадра; знак проверяется проекцией ниже.
    cam.shift_x = -(VP[0] - W_PX / 2) / H_PX
    cam.shift_y = -(H_PX / 2 - VP[1]) / H_PX
    cam.clip_start = 0.05
    cam.clip_end = 50
    ob = bpy.data.objects.new('cam', cam)
    ob.location = (0, 0, EYE)
    ob.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(ob)
    sc.camera = ob
    sc.render.resolution_x = W_PX
    sc.render.resolution_y = H_PX
    return ob


def project(cam, co):
    sc = bpy.context.scene
    p = world_to_camera_view(sc, cam, Vector(co))
    return p.x * W_PX, (1 - p.y) * H_PX


def check_camera(cam):
    """Ключевые точки должны лечь туда же, где они на картинке."""
    bpy.context.view_layer.update()
    pts = {
        'угол стен у пола (279, 892)': (-WL, D, 0),
        'угол стен у карниза (279, 250)': (-WL, D, EYE + (VP[1] - 250) / K),
        'пол у задней стены справа (941, 892)': ((941 - VP[0]) / K, D, 0),
        'точка схода (757, 715)': (0, 1000, EYE),
        'карниз левой стены у края кадра': (-WL, depth_at_u(0), CEIL - CORNICE),
    }
    for name, co in pts.items():
        u, v = project(cam, co)
        print(f'  {name}: {u:7.1f} {v:7.1f}')


def setup_render(scale, samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 8
    sc.cycles.diffuse_bounces = 5
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.sample_clamp_indirect = 8
    sc.render.resolution_percentage = int(scale * 100)
    sc.render.threads_mode = 'AUTO'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0
    sc.render.film_transparent = False


def collections_state(visible_camera=None, holdout=None):
    """Видимость для камеры и «дыры» по классам; свет и тени не трогаем."""
    for coll in bpy.data.collections:
        for ob in coll.objects:
            if visible_camera is not None:
                ob.visible_camera = coll.name in visible_camera
            if holdout is not None:
                ob.is_holdout = coll.name in holdout


def render_exr(path):
    sc = bpy.context.scene
    sc.render.image_settings.file_format = 'OPEN_EXR'
    sc.render.image_settings.color_depth = '32'
    sc.render.image_settings.exr_codec = 'ZIP'
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_png(path):
    sc = bpy.context.scene
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '16'
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def emission_override(on):
    """Для масок: всё светится ровным белым, без света и теней."""
    sc = bpy.context.scene
    if on:
        m = bpy.data.materials.get('mask_white') or bpy.data.materials.new('mask_white')
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Strength'].default_value = 1.0
        nt.links.new(em.outputs[0], out.inputs['Surface'])
        sc.view_layers[0].material_override = m
    else:
        sc.view_layers[0].material_override = None


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--samples', type=int, default=256)
    ap.add_argument('--only', default='light,masks,curtains')
    args = ap.parse_args(argv)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    jobs = set(args.only.split(','))

    view_png = out / 'view_texture.png'
    make_view_texture(view_png)
    build(view_png)
    lights()
    cam = camera()
    print(f'Комната: глаз {EYE:.3f} м, задняя стена {D:.3f} м, левая {WL:.3f} м, '
          f'плинтус {BASEBOARD:.3f} м, карниз {CORNICE:.3f} м')
    check_camera(cam)
    setup_render(args.scale, args.samples)

    if 'light' in jobs:
        # Тюль невидим для камеры, но свет через него проходит и тень есть.
        collections_state(visible_camera={'walls', 'floor', 'trim', 'ceiling',
                                          'view', 'shell'}, holdout=set())
        render_exr(out / 'light.exr')

    if 'masks' in jobs:
        sc = bpy.context.scene
        keep = sc.cycles.samples
        sc.cycles.samples = 32
        sc.cycles.use_denoising = False
        sc.render.film_transparent = True
        emission_override(True)
        classes = ['walls', 'floor', 'trim', 'ceiling', 'view']
        for c in classes:
            collections_state(
                visible_camera={'walls', 'floor', 'trim', 'ceiling', 'view', 'shell'},
                holdout=set(classes) - {c},
            )
            render_png(out / f'mask_{c}.png')
        emission_override(False)
        sc.render.film_transparent = False
        sc.cycles.samples = keep
        sc.cycles.use_denoising = True

    if 'curtains' in jobs:
        sc = bpy.context.scene
        sc.render.film_transparent = True
        collections_state(
            visible_camera={'walls', 'floor', 'trim', 'ceiling', 'view',
                            'shell', 'curtains'},
            holdout={'walls', 'floor', 'trim', 'ceiling', 'view', 'shell'},
        )
        render_exr(out / 'curtains.exr')
        sc.render.film_transparent = False


if __name__ == '__main__':
    main()
