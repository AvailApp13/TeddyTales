import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { repoRoot, childrenOf } from './rig.mjs';

/**
 * Собирает проект Rive CLI (rive.yaml + scene.rml) из rig/bear_rig.json и
 * rig/animation_catalog.json.
 *
 * Что здесь генерируется и что остаётся руками — в docs/rive-cli-workflow.md.
 * Коротко: скелет, control-узлы, View Model, перечисления, каркас State
 * Machine со всеми переходами по данным, заготовки всех 112 клипов и
 * плейсхолдер-манекен. Веса скиннинга и настоящий арт — в редакторе.
 *
 * Идентификаторы: `0:N` — общие корневые элементы, `1:N` — артборд мальчика,
 * `2:N` — девочки. Так два артборда никогда не пересекутся по id.
 */

// ------------------------------------------------------------ раскладка манекена
//
// Мировые координаты (артборд 1024x1024) считаются из rig/bear_proportions.json —
// размерной сетки, снятой с фото мишки. Локальные координаты для RML выводятся
// из мировых с учётом поворота родительской кости, поэтому здесь нет ни одного
// «подобранного» числа.



const PROPORTIONS = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'bear_proportions.json'), 'utf8'));

// figureHeight: рост без капюшона (макушка под капюшоном -> земля). Остриё
// капюшона на 28,8% выше макушки (HD-кадр: 420/326 старых px), и вся фигура
// должна влезать в 1024: 760 px роста -> остриё на y=6. Раньше стояло 800 по
// вырезу с обрезанным остриём — макушка капюшона вылезала за артборд.
export const AB = { w: 1024, h: 1024, figureHeight: 760, groundY: 985 };
const SCALE = AB.figureHeight; // 1.0 роста без капюшона = 800 px артборда

/** Часть сетки -> мировые координаты артборда. */
function gridWorld(name) {
  const part = PROPORTIONS.parts[name];
  if (!part) return null;
  return {
    x: AB.w / 2 + part.x * SCALE,
    y: AB.groundY - part.y * SCALE,
    w: part.w * SCALE,
    h: part.h * SCALE,
  };
}

const G = new Proxy({}, { get: (_, name) => gridWorld(name) });
const off = (base, dx, dy, w, h) => base && { x: base.x + dx, y: base.y + dy, w, h };

/**
 * Мировая раскладка каждого узла спеки: центр и размер плейсхолдера.
 * Узлы, которых нет на фото напрямую (ctrl_*, зрачки, веки, блики),
 * выводятся из соседей по простым правилам, записанным тут же.
 */
export function worldLayout() {
  const eyeR = G.eye_left.w / 2;
  const L = {
    body: G.body, body_base: G.body_base, head: G.head,
    head_shadow: off(G.head, 0, G.head.h * 0.42, G.head.w * 0.8, G.head.h * 0.18),

    ear_left: G.ear_left, ear_right: G.ear_right,
    ear_in_left: off(G.ear_left, 0, 2, G.ear_left.w * 0.55, G.ear_left.h * 0.55),
    ear_in_right: off(G.ear_right, 0, 2, G.ear_right.w * 0.55, G.ear_right.h * 0.55),
    ear_light_left: off(G.ear_left, -6, -8, 12, 8),
    ear_light_right: off(G.ear_right, 6, -8, 12, 8),

    ctrl_face: off(G.head, 0, G.head.h * 0.08, 0, 0),
    ctrl_eyes: { x: (G.eye_left.x + G.eye_right.x) / 2, y: G.eye_left.y, w: 0, h: 0 },
    ctrl_pupils: { x: (G.eye_left.x + G.eye_right.x) / 2, y: G.eye_left.y, w: 0, h: 0 },
    ctrl_mouth: off(G.mouth, 0, 0, 0, 0),
    ctrl_nose: off(G.nose, 0, 0, 0, 0),
    ctrl_eyebrow_left: off(G.eyebrow_left, 0, 0, 0, 0),
    ctrl_eyebrow_right: off(G.eyebrow_right, 0, 0, 0, 0),

    // Глаза плюшевого мишки — бусины: eye — место под белок (у плюша его нет),
    // pupil — сама бусина, pupil_light — блик.
    eye_left: off(G.eye_left, 0, 0, eyeR * 2.6, eyeR * 2.6),
    eye_right: off(G.eye_right, 0, 0, eyeR * 2.6, eyeR * 2.6),
    pupil_left: G.eye_left, pupil_right: G.eye_right,
    pupil_light_left: off(G.eye_left, -eyeR * 0.35, -eyeR * 0.35, eyeR * 0.7, eyeR * 0.7),
    pupil_light_right: off(G.eye_right, -eyeR * 0.35, -eyeR * 0.35, eyeR * 0.7, eyeR * 0.7),
    eyelid_top_left: off(G.eye_left, 0, -eyeR * 1.1, eyeR * 2.8, eyeR * 0.9),
    eyelid_top_right: off(G.eye_right, 0, -eyeR * 1.1, eyeR * 2.8, eyeR * 0.9),
    eyelid_bottom_left: off(G.eye_left, 0, eyeR * 1.1, eyeR * 2.8, eyeR * 0.7),
    eyelid_bottom_right: off(G.eye_right, 0, eyeR * 1.1, eyeR * 2.8, eyeR * 0.7),
    eyebrow_left: G.eyebrow_left, eyebrow_right: G.eyebrow_right,

    nose: G.nose, mouth: G.mouth,
    teeth: off(G.mouth, 0, -G.mouth.h * 0.2, G.mouth.w * 0.7, G.mouth.h * 0.3),
    tongue: off(G.mouth, 0, G.mouth.h * 0.2, G.mouth.w * 0.5, G.mouth.h * 0.4),
    lips: off(G.mouth, 0, 0, G.mouth.w, G.mouth.h * 0.25),

    scarf_1: off(G.body, 0, -G.body.h * 0.42, G.body.w * 0.75, 34),
    scarf_2: off(G.body, 0, -G.body.h * 0.42 + 16, G.body.w * 0.68, 30),
    scarf_3: off(G.body, 0, -G.body.h * 0.42 + 30, G.body.w * 0.6, 26),

    forearm_left: mid(G.shoulder_left, G.hand_left, 60, 100),
    forearm_light_left: mid(G.shoulder_left, G.hand_left, 24, 50),
    hand_left: G.hand_left, hand_light_left: off(G.hand_left, -6, -6, G.hand_left.w * 0.4, G.hand_left.h * 0.4),
    finger_1_nail_left: off(G.hand_left, -G.hand_left.w * 0.3, -G.hand_left.h * 0.35, 12, 12),
    finger_2_nail_left: off(G.hand_left, -G.hand_left.w * 0.42, 0, 12, 12),
    finger_3_nail_left: off(G.hand_left, -G.hand_left.w * 0.3, G.hand_left.h * 0.35, 12, 12),
    forearm_right: mid(G.shoulder_right, G.hand_right, 60, 100),
    forearm_light_right: mid(G.shoulder_right, G.hand_right, 24, 50),
    hand_right: G.hand_right, hand_light_right: off(G.hand_right, 6, -6, G.hand_right.w * 0.4, G.hand_right.h * 0.4),
    finger_1_nail_right: off(G.hand_right, G.hand_right.w * 0.3, -G.hand_right.h * 0.35, 12, 12),
    finger_2_nail_right: off(G.hand_right, G.hand_right.w * 0.42, 0, 12, 12),
    finger_3_nail_right: off(G.hand_right, G.hand_right.w * 0.3, G.hand_right.h * 0.35, 12, 12),

    leg_left: G.leg_left, leg_right: G.leg_right, foot_left: G.foot_left, foot_right: G.foot_right,
  };
  return L;
}

function mid(a, b, w, h) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, w, h };
}

/**
 * Кости: точка начала, направление и длина — из суставов сетки.
 * Угол — мировой (радианы, от оси +x экрана, по часовой), как рисует Rive.
 */
export function boneLayout() {
  const hips = { x: (G.hip_left.x + G.hip_right.x) / 2, y: (G.hip_left.y + G.hip_right.y) / 2 };
  const chest = { x: G.body.x, y: G.body.y - G.body.h * 0.2 };
  const headC = { x: G.head.x, y: G.head.y };
  const seg = (from, to) => ({ x: from.x, y: from.y, length: Math.hypot(to.x - from.x, to.y - from.y), angle: Math.atan2(to.y - from.y, to.x - from.x) });
  return {
    root: seg(hips, chest),                         // таз -> грудь, вверх
    root_body: seg(chest, headC),                   // грудь -> центр головы
    root_arm_left: seg(G.shoulder_left, G.hand_left),
    root_arm_right: seg(G.shoulder_right, G.hand_right),
    root_leg_left: seg(G.hip_left, G.foot_left),
    root_leg_right: seg(G.hip_right, G.foot_right),
  };
}

export const PLACEHOLDER_COLOR = {
  body: 'FFC9A57C', body_base: 'FFB8946C', head: 'FFC9A57C', head_shadow: 'FF000000',
  ear: 'FFC9A57C', ear_in: 'FFE8B7A3', ear_light: 'FFFFFFFF',
  eye: 'FFEDE3D3', pupil: 'FF1A1411', pupil_light: 'FFFFFFFF', eyelid_top: 'FFC9A57C', eyelid_bottom: 'FFC9A57C', eyebrow: 'FF8A6A48',
  nose: 'FF3B2A22', mouth: 'FF5A2E2E', teeth: 'FFFFFFFF', tongue: 'FFE07A8A', lips: 'FF3B2A22',
  scarf_1: 'FFD9534F', scarf_2: 'FFC9443F', scarf_3: 'FFB9342F',
  forearm: 'FFC9A57C', forearm_light: 'FFFFFFFF', hand: 'FFB8946C', hand_light: 'FFFFFFFF', finger_nail: 'FF8A6A48',
  leg: 'FFC9A57C', foot: 'FFB8946C',
};
export const PLACEHOLDER_OPACITY = { head_shadow: 0.15, ear_light: 0.5, forearm_light: 0.35, hand_light: 0.35 };

/** Отличия героев. Пока только цвет акцентов, чтобы артборды было видно порознь. */
const HERO_TINT = {
  boy:  { scarf: 'FFD9534F', ear_in: 'FFE8B7A3' },
  girl: { scarf: 'FFF48FB1', ear_in: 'FFF2C4D0' },
};

// ------------------------------------------------------------------- ключи свойств
const KEY = { x: 13, y: 14, rotation: 15, scaleX: 16, scaleY: 17, opacity: 18, rootX: 90, rootY: 91 };
const BIND = { number: 636, enum: 637, trigger: 686 };

// -------------------------------------------------------------------- генератор

class Ids {
  constructor(client) {
    this.client = client;
    this.next = 10;
  }
  take() {
    return `${this.client}:${this.next++}`;
  }
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const num = (v) => (Number.isInteger(v) ? String(v) : Number(v).toFixed(4).replace(/0+$/, '').replace(/\.$/, ''));

export function generateRiveProject(rig, catalog) {
  const shared = new Ids(0);
  const lines = [];
  const emit = (depth, text) => lines.push('  '.repeat(depth) + text);

  // ---- перечисления и View Model (общие для обоих героев) -----------------
  const enums = {};
  for (const [name, def] of Object.entries(rig.enums)) {
    enums[name] = { id: shared.take(), values: {} };
    for (const value of def.values) enums[name].values[value] = shared.take();
  }
  const vm = { id: shared.take(), instanceId: shared.take(), props: {} };
  for (const prop of rig.viewModel.properties) vm.props[prop.name] = shared.take();

  const path = (propName) => `${vm.id}-${vm.props[propName]}`;

  // ---- артборды -------------------------------------------------------------
  const artboards = [];
  Object.entries(rig.artboard.names).forEach(([hero, name], index) => {
    const ids = new Ids(index + 1);
    artboards.push(buildArtboard({ rig, catalog, hero, name, ids, enums, vm, path, index }));
  });

  // ---- документ -------------------------------------------------------------
  emit(0, '<?xml version="1.0" encoding="UTF-8"?>');
  emit(0, '<!--');
  emit(0, '  СГЕНЕРИРОВАНО из rig/bear_rig.json и rig/animation_catalog.json.');
  emit(0, '  Не редактировать руками: cd tools && npm run gen:rml');
  emit(0, '');
  emit(0, '  Что здесь есть: скелет, control-узлы, View Model, перечисления,');
  emit(0, '  каркас State Machine с переходами по данным, заготовки всех клипов,');
  emit(0, '  плейсхолдер-манекен. Что делается в редакторе: арт, скиннинг, тайминг.');
  emit(0, '  См. docs/rive-cli-workflow.md');
  emit(0, '-->');
  emit(0, '<Rive version="1" kind="fragment">');
  for (const ab of artboards) for (const l of ab) emit(0, l);
  emit(0, '');

  for (const [name, def] of Object.entries(rig.enums)) {
    emit(1, `<DataEnumCustom name="${name}" id="${enums[name].id}">`);
    for (const value of def.values) {
      emit(2, `<DataEnumValue key="${value}" value="${esc(def.labels?.[value] ?? value)}" id="${enums[name].values[value]}"/>`);
    }
    emit(1, '</DataEnumCustom>');
  }
  emit(0, '');

  emit(1, `<ViewModel defaultInstanceId="${vm.instanceId}" name="${rig.viewModel.name}" id="${vm.id}">`);
  for (const prop of rig.viewModel.properties) {
    const id = vm.props[prop.name];
    if (prop.type === 'number') emit(2, `<ViewModelPropertyNumber name="${prop.name}" id="${id}"/>`);
    else if (prop.type === 'trigger') emit(2, `<ViewModelPropertyTrigger name="${prop.name}" id="${id}"/>`);
    else if (prop.type === 'enum') emit(2, `<ViewModelPropertyEnumCustom enumId="${enums[prop.enumName].id}" name="${prop.name}" id="${id}"/>`);
    else throw new Error(`gen:rml: тип свойства ${prop.type} (${prop.name}) не поддержан`);
  }
  emit(2, `<ViewModelInstance exports="true" name="Default" id="${vm.instanceId}">`);
  for (const prop of rig.viewModel.properties) {
    const id = vm.props[prop.name];
    if (prop.type === 'number') emit(3, `<ViewModelInstanceNumber propertyValue="${num(prop.default)}" viewModelPropertyId="${id}"/>`);
    else if (prop.type === 'trigger') emit(3, `<ViewModelInstanceTrigger viewModelPropertyId="${id}"/>`);
    else if (prop.type === 'enum') emit(3, `<ViewModelInstanceEnum propertyValue="${enums[prop.enumName].values[prop.default]}" viewModelPropertyId="${id}"/>`);
  }
  emit(2, '</ViewModelInstance>');
  emit(1, '</ViewModel>');
  emit(0, '</Rive>');

  const yaml = [
    `name: bear`,
    `main: ${rig.artboard.primary}`,
    `output:`,
    `  dir: build`,
    `logs:`,
    `  file: build/rive.log`,
    `  problems: build/problems.log`,
    ``,
  ].join('\n');

  return { rml: lines.join('\n') + '\n', yaml };
}

// ------------------------------------------------------------------ артборд

function buildArtboard({ rig, catalog, hero, name, ids, enums, vm, path, index }) {
  const out = [];
  const emit = (depth, text) => out.push('  '.repeat(depth) + text);
  const tint = HERO_TINT[hero] ?? HERO_TINT.boy;

  const artboardId = ids.take();
  const styleId = ids.take();
  const smId = ids.take();
  const hitId = ids.take();

  // Имя узла спеки -> id RML-элемента, который получает ключи анимации.
  const nodeIds = {};
  const animIds = {}; // clip name -> LinearAnimation id
  const nameOf = (n) => n;

  const W = AB.w;
  const H = AB.h;
  const stageX = index * (W + 200);

  emit(1, `<!-- ============ ${name} (${hero}) ============ -->`);
  emit(1, `<Artboard defaultStateMachineId="${smId}" viewModelId="${vm.id}" viewModelInstanceId="${vm.instanceId}" styleId="${styleId}" x="${stageX}" y="0" width="${W}" height="${H}" name="${name}" id="${artboardId}">`);
  emit(2, `<LayoutComponentStyle name="Artboard Style" id="${styleId}"/>`);

  // Прозрачная зона касания поверх всего мишки (КП 3.1). Отдельный шейп,
  // чтобы листенер не зависел от того, каким артом заменят плейсхолдер.
  emit(2, `<Shape x="${W / 2}" y="${H * 0.55}" name="hit_area" id="${hitId}">`);
  emit(3, `<Rectangle width="${W * 0.5}" height="${H * 0.75}" name="P"/>`);
  emit(3, `<Fill name="F"><SolidColor colorValue="00000000" name="C"/></Fill>`);
  emit(2, `</Shape>`);

  // ---- скелет --------------------------------------------------------------
  //
  // Каждый узел знает свою мировую позицию и мировой угол. Кость наследует
  // угол от геометрии (плечо -> лапа), Node — от родителя. Локальные x/y для
  // RML — это мировое смещение, повёрнутое на минус угол родителя. Art- и
  // control-узлы получают rotation = -угол родителя, так что внутри них всё
  // остаётся в экранной ориентации, а анимации крутят их относительно этой
  // базы (см. baseRotation).
  const layout = worldLayout();
  const bones = boneLayout();
  const baseRotation = {};
  const rot = (p, a) => ({ x: p.x * Math.cos(a) - p.y * Math.sin(a), y: p.x * Math.sin(a) + p.y * Math.cos(a) });
  const toLocal = (world, origin, originAngle) => rot({ x: world.x - origin.x, y: world.y - origin.y }, -originAngle);

  const root = rig.nodes.find((n) => n.parent === null);
  // frame: { origin, angle } — система координат, в которой живут дети узла
  // Первый брат рисуется сверху. Руки — поверх торса, торс — поверх ног:
  // так у плюшевого мишки и выглядит, а спека порядок не задаёт.
  const DRAW_PRIORITY = { root_arm_left: 0, root_arm_right: 0, root_body: 1, root_leg_left: 2, root_leg_right: 2 };
  const ordered = (list) => [...list].sort((a, b) => (DRAW_PRIORITY[a.name] ?? 1) - (DRAW_PRIORITY[b.name] ?? 1));

  const walk = (node, depth, frame) => {
    const id = ids.take();
    nodeIds[node.name] = id;
    const kids = ordered(childrenOf(rig, node.name));
    const slots = catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name);

    if (node.kind === 'bone') {
      const b = bones[node.name];
      if (!b) throw new Error(`gen:rml: нет геометрии кости ${node.name} в boneLayout()`);
      const tip = { x: b.x + Math.cos(b.angle) * b.length, y: b.y + Math.sin(b.angle) * b.length };
      // Проверено экспериментом (docs/rive-cli-workflow.md, «Система координат
      // кости»): Node внутри кости считается от её НАЧАЛА, дочерняя Bone
      // стартует в КОНЧИКЕ родителя.
      const nodeFrame = { origin: { x: b.x, y: b.y }, angle: b.angle };
      const boneFrame = { origin: tip, angle: b.angle };
      let rotation;
      if (node.parent === null) {
        rotation = b.angle;
        emit(depth, `<RootBone x="${num(b.x)}" y="${num(b.y)}" length="${num(b.length)}" rotation="${num(b.angle)}" name="${node.name}" id="${id}">`);
      } else {
        const local = toLocal({ x: b.x, y: b.y }, frame.boneOrigin, frame.angle);
        const startsAtParentTip = Math.hypot(local.x, local.y) < 1;
        rotation = b.angle - frame.angle;
        if (startsAtParentTip) {
          emit(depth, `<Bone length="${num(b.length)}" rotation="${num(rotation)}" name="${node.name}" id="${id}">`);
        } else {
          // Сустав не в кончике родителя (плечо, бедро): RootBone внутри Bone.
          // Его x/y считаются от НАЧАЛА родительской кости — как у Node, а не
          // как у дочерней Bone. Проверено измерением: при отсчёте от кончика
          // руки и ноги уходили вниз ровно на длину root.
          const fromBase = toLocal({ x: b.x, y: b.y }, frame.baseOrigin, frame.angle);
          emit(depth, `<RootBone x="${num(fromBase.x)}" y="${num(fromBase.y)}" length="${num(b.length)}" rotation="${num(rotation)}" name="${node.name}" id="${id}">`);
          node.__rootBone = true;
        }
      }
      baseRotation[node.name] = rotation;
      const base = { x: b.x, y: b.y };
      for (const kid of kids) walk(kid, depth + 1, kid.kind === 'bone' ? { ...boneFrame, boneOrigin: tip, baseOrigin: base } : { ...nodeFrame, boneOrigin: tip, baseOrigin: base });
      for (const slot of slots) {
        const sid = ids.take();
        nodeIds[slot.name] = sid;
        emit(depth + 1, `<Node rotation="${num(-b.angle)}" name="${slot.name}" id="${sid}"/>`);
      }
      emit(depth, node.parent === null || node.__rootBone ? '</RootBone>' : '</Bone>');
      delete node.__rootBone;
      return;
    }

    const world = layout[node.name] ?? { x: frame.origin.x, y: frame.origin.y, w: 0, h: 0 };
    const local = toLocal(world, frame.origin, frame.angle);
    const rotation = -frame.angle; // выравниваем в экран
    baseRotation[node.name] = rotation;
    const rotAttr = Math.abs(rotation) > 1e-6 ? ` rotation="${num(rotation)}"` : '';
    emit(depth, `<Node x="${num(local.x)}" y="${num(local.y)}"${rotAttr} name="${node.name}" id="${id}">`);
    const childFrame = { origin: world, boneOrigin: world, baseOrigin: world, angle: 0 };
    for (const kid of kids) walk(kid, depth + 1, childFrame);
    for (const slot of slots) {
      const sid = ids.take();
      nodeIds[slot.name] = sid;
      emit(depth + 1, `<Node name="${slot.name}" id="${sid}"/>`);
    }
    if (node.kind === 'art' && world.w > 0) {
      let color = PLACEHOLDER_COLOR[node.name.replace(/_(left|right)$/, '').replace(/^finger_\d_/, 'finger_')] ?? 'FFC9A57C';
      if (node.name.startsWith('scarf')) color = tint.scarf;
      if (node.name.startsWith('ear_in')) color = tint.ear_in;
      const opacity = PLACEHOLDER_OPACITY[node.name.replace(/_(left|right)$/, '')];
      const opAttr = opacity !== undefined ? ` opacity="${num(opacity)}"` : '';
      emit(depth + 1, `<Shape${opAttr} name="${node.name}__placeholder">`);
      emit(depth + 2, `<Ellipse width="${num(world.w)}" height="${num(world.h)}" name="P"/>`);
      emit(depth + 2, `<Fill name="F"><SolidColor colorValue="${color}" name="C"/></Fill>`);
      emit(depth + 1, `</Shape>`);
    }
    emit(depth, '</Node>');
  };
  walk(root, 2, { origin: { x: 0, y: 0 }, boneOrigin: { x: 0, y: 0 }, baseOrigin: { x: 0, y: 0 }, angle: 0 });

  // ---- анимации ------------------------------------------------------------
  const animations = buildAnimations({ catalog, rig, nodeIds, ids, animIds, baseRotation });
  const noneId = ids.take();
  animIds.__none = noneId;

  // ---- state machine -------------------------------------------------------
  emit(2, `<StateMachine name="${rig.stateMachine.name}" id="${smId}">`);

  // Касание питомца -> триггер tap (КП 3.1).
  emit(3, `<StateMachineListenerSingle targetId="${hitId}" listenerTypeValue="click" name="tap_listener">`);
  emit(4, `<ListenerViewModelChange>`);
  emit(5, `<BindablePropertyTrigger propertyValue="1">`);
  emit(6, `<DataBindContext sourcePathIds="${path('tap')}" propertyKey="${BIND.trigger}" direction="true"/>`);
  emit(5, `</BindablePropertyTrigger>`);
  emit(4, `</ListenerViewModelChange>`);
  emit(3, `</StateMachineListenerSingle>`);

  const condEnum = (prop, value, depth) => {
    const enumName = rig.viewModel.properties.find((p) => p.name === prop).enumName;
    emit(depth, `<TransitionViewModelCondition opValue="equal">`);
    emit(depth + 1, `<TransitionPropertyViewModelComparator><BindablePropertyEnum><DataBindContext sourcePathIds="${path(prop)}" propertyKey="${BIND.enum}"/></BindablePropertyEnum></TransitionPropertyViewModelComparator>`);
    emit(depth + 1, `<TransitionValueEnumComparator value="${enums[enumName].values[value]}"/>`);
    emit(depth, `</TransitionViewModelCondition>`);
  };
  const condNotEnum = (prop, value, depth) => {
    const enumName = rig.viewModel.properties.find((p) => p.name === prop).enumName;
    emit(depth, `<TransitionViewModelCondition opValue="notEqual">`);
    emit(depth + 1, `<TransitionPropertyViewModelComparator><BindablePropertyEnum><DataBindContext sourcePathIds="${path(prop)}" propertyKey="${BIND.enum}"/></BindablePropertyEnum></TransitionPropertyViewModelComparator>`);
    emit(depth + 1, `<TransitionValueEnumComparator value="${enums[enumName].values[value]}"/>`);
    emit(depth, `</TransitionViewModelCondition>`);
  };
  const condTrigger = (prop, depth) => {
    emit(depth, `<TransitionViewModelCondition opValue="equal">`);
    emit(depth + 1, `<TransitionPropertyViewModelComparator><BindablePropertyTrigger><DataBindContext sourcePathIds="${path(prop)}" propertyKey="${BIND.trigger}"/></BindablePropertyTrigger></TransitionPropertyViewModelComparator>`);
    emit(depth + 1, `<TransitionValueTriggerComparator value="1"/>`);
    emit(depth, `</TransitionViewModelCondition>`);
  };

  const layerHeader = (layerName, entryTo, depth) => {
    emit(depth, `<StateMachineLayer name="${layerName}" id="${ids.take()}">`);
    emit(depth + 1, `<AnyState x="60" y="-160"/>`);
    emit(depth + 1, `<ExitState x="60" y="-100"/>`);
    emit(depth + 1, `<EntryState x="60" y="-40"><StateTransition stateToId="${entryTo}"/></EntryState>`);
  };
  const gridPos = (i, cols = 6) => ({ x: 200 + (i % cols) * 240, y: 40 + Math.floor(i / cols) * 140 });

  const stages = rig.enums.stage.values;
  const moods = rig.enums.mood.values;
  const traits = rig.enums.trait.values;

  // -- слои покоя: один на стадию, активен только пока stage == своя --------
  // Из AnyState переходить нельзя: AnyState -> текущее состояние перезапускало
  // бы клип каждый кадр. Поэтому переходы явные, состояние -> состояние.
  for (const stage of stages) {
    const offId = ids.take();
    const stateIds = Object.fromEntries(moods.map((m) => [m, ids.take()]));
    layerHeader(`idle_${stage}`, offId, 3);
    emit(4, `<AnimationState x="60" y="40" animationId="${noneId}" id="${offId}">`);
    moods.forEach((mood) => {
      emit(5, `<StateTransition stateToId="${stateIds[mood]}" duration="250">`);
      condEnum('stage', stage, 6);
      condEnum('mood', mood, 6);
      emit(5, `</StateTransition>`);
    });
    emit(4, `</AnimationState>`);
    moods.forEach((mood, i) => {
      const { x, y } = gridPos(i + 1);
      emit(4, `<AnimationState x="${x}" y="${y}" animationId="${animIds[`idle_${mood}_${stage}`]}" id="${stateIds[mood]}">`);
      emit(5, `<StateTransition stateToId="${offId}" duration="250">`);
      condNotEnum('stage', stage, 6);
      emit(5, `</StateTransition>`);
      for (const other of moods) {
        if (other === mood) continue;
        emit(5, `<StateTransition stateToId="${stateIds[other]}" duration="400">`);
        condEnum('mood', other, 6);
        emit(5, `</StateTransition>`);
      }
      emit(4, `</AnimationState>`);
    });
    emit(3, `</StateMachineLayer>`);
  }

  // Слои, стартующие из AnyState по триггеру, и таймлайны.
  return finalizeArtboard({ out, emit, ids, catalog, path, animIds, noneId, animations, traits, condEnum, condTrigger, gridPos });
}

/**
 * Слои, которые стартуют из AnyState по триггеру: действия ухода, эмоции,
 * взросление, характер. Триггер расходуется в кадре срабатывания, поэтому
 * AnyState здесь безопасен — в отличие от слоёв покоя.
 */
function finalizeArtboard(ctx) {
  const { out, emit, ids, catalog, animIds, noneId, animations, traits, condEnum, condTrigger, gridPos } = ctx;

  const anyLayer = (layerName, entries, exitDuration = 120) => {
    // entries: [{ clip, conditions: [(depth)=>void], reset }]
    const offId = ids.take();
    emit(3, `<StateMachineLayer name="${layerName}" id="${ids.take()}">`);
    emit(4, `<AnyState x="60" y="-160">`);
    const stateIds = entries.map(() => ids.take());
    entries.forEach((entry, i) => {
      emit(5, `<StateTransition stateToId="${stateIds[i]}" duration="80">`);
      for (const c of entry.conditions) c(6);
      emit(5, `</StateTransition>`);
    });
    emit(4, `</AnyState>`);
    emit(4, `<ExitState x="60" y="-100"/>`);
    emit(4, `<EntryState x="60" y="-40"><StateTransition stateToId="${offId}"/></EntryState>`);
    emit(4, `<AnimationState x="60" y="40" animationId="${noneId}" id="${offId}"/>`);
    entries.forEach((entry, i) => {
      const { x, y } = gridPos(i + 1);
      emit(4, `<AnimationState x="${x}" y="${y}" reset="true" animationId="${animIds[entry.clip]}" id="${stateIds[i]}">`);
      emit(5, `<StateTransition stateToId="${offId}" duration="${exitDuration}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>`);
      emit(4, `</AnimationState>`);
    });
    emit(3, `</StateMachineLayer>`);
  };

  // действия ухода
  const triggerFor = { feed: 'feed', wash: 'wash', sleep: 'sleep_action', wake: 'wake', play: 'play_action', pet: 'pet' };
  anyLayer(
    'action',
    catalog.groups.care.clips.map((c) => ({
      clip: c.name,
      conditions: [(d) => condTrigger(triggerFor[c.action], d), (d) => condEnum('stage', c.stage, d)],
    })),
  );

  // эмоции: первый вариант подключён, второй (_b) — руками через random
  anyLayer(
    'emotion',
    catalog.groups.emotions.clips
      .filter((c) => c.name.endsWith('_a'))
      .map((c) => ({ clip: c.name, conditions: [(d) => condTrigger(`emote_${c.emotion}`, d)] })),
  );

  // взросление: триггер grow + стадия, в которую пришли
  anyLayer(
    'growth',
    catalog.groups.growth.clips.map((c) => ({
      clip: c.name,
      conditions: [(d) => condTrigger('grow', d), (d) => condEnum('stage', c.to, d)],
    })),
    300,
  );

  // характер: инициатива и реакция на касание
  anyLayer('trait', [
    ...traits.map((t) => ({ clip: `trait_${t}_initiative`, conditions: [(d) => condTrigger('initiative', d), (d) => condEnum('trait', t, d)] })),
    ...traits.map((t) => ({ clip: `trait_${t}_reaction`, conditions: [(d) => condTrigger('tap', d), (d) => condEnum('trait', t, d)] })),
  ]);

  // осанка от общего ухода: blend между заброшенной и ухоженной позой (КП 5.7, 6.2)
  {
    const layerId = ids.take();
    const blendId = ids.take();
    emit(3, `<StateMachineLayer name="posture" id="${layerId}">`);
    emit(4, `<AnyState x="60" y="-160"/>`);
    emit(4, `<ExitState x="60" y="-100"/>`);
    emit(4, `<EntryState x="60" y="-40"><StateTransition stateToId="${blendId}"/></EntryState>`);
    emit(4, `<BlendState1DViewModel x="200" y="40" id="${blendId}">`);
    emit(5, `<BindablePropertyNumber><DataBindContext sourcePathIds="${ctx.path('care_index')}" propertyKey="${BIND.number}"/></BindablePropertyNumber>`);
    emit(5, `<BlendAnimation1D animationId="${animIds.pose_neglected}" value="0"/>`);
    emit(5, `<BlendAnimation1D animationId="${animIds.pose_cared}" value="100"/>`);
    emit(4, `</BlendState1DViewModel>`);
    emit(3, `</StateMachineLayer>`);
  }

  emit(2, `</StateMachine>`);

  // ---- таймлайны --------------------------------------------------------------
  emit(2, `<LinearAnimation duration="1" name="none" id="${noneId}"/>`);
  for (const a of animations) {
    const loop = a.loop ? ` loopValue="${a.loop}"` : '';
    emit(2, `<LinearAnimation${loop} duration="${a.duration}" name="${a.name}" id="${a.id}">`);
    for (const track of a.tracks) {
      emit(3, `<KeyedObject objectId="${track.objectId}">`);
      emit(4, `<KeyedProperty propertyKey="${track.key}">`);
      for (const [frame, value, interp] of track.keys) {
        emit(5, `<KeyFrameDouble value="${num(value)}" frame="${frame}" interpolationType="${interp ?? 'cubic'}"/>`);
      }
      emit(4, `</KeyedProperty>`);
      emit(3, `</KeyedObject>`);
    }
    emit(2, `</LinearAnimation>`);
  }

  emit(1, `</Artboard>`);
  return out;
}

// ------------------------------------------------------------------ анимации
//
// Заготовки: у каждого клипа есть имя из каталога, длительность и 1-3 дорожки,
// чтобы в лаборатории было видно, какое состояние сейчас играет. Тайминг и
// характер движения — работа аниматора в редакторе; здесь только каркас.

function buildAnimations({ catalog, rig, nodeIds, ids, animIds, baseRotation }) {
  const list = [];
  const add = (name, { duration, loop, tracks }) => {
    const id = ids.take();
    animIds[name] = id;
    list.push({ id, name, duration, loop, tracks: tracks.filter((t) => t.objectId) });
  };
  // Поворот в дорожках задаётся ДЕЛЬТОЙ к базовому повороту узла: узлы под
  // наклонными костями выровнены в экран через rotation, и абсолютный ключ
  // сломал бы эту базу.
  const T = (node, key, keys) => ({
    objectId: nodeIds[node],
    key,
    keys: key === KEY.rotation ? keys.map(([f, v, i]) => [f, (baseRotation[node] ?? 0) + v, i]) : keys,
  });

  const breath = (amp = 0.03, len = 120) => [
    T('body', KEY.scaleX, [[0, 1], [len / 2, 1 + amp], [len, 1]]),
    T('body', KEY.scaleY, [[0, 1], [len / 2, 1 + amp * 1.5], [len, 1]]),
  ];
  const blink = (at = 100) => [
    T('eyelid_top_left', KEY.scaleY, [[0, 1, 'hold'], [at, 1, 'linear'], [at + 4, 3.4, 'linear'], [at + 9, 1, 'hold']]),
    T('eyelid_top_right', KEY.scaleY, [[0, 1, 'hold'], [at, 1, 'linear'], [at + 4, 3.4, 'linear'], [at + 9, 1, 'hold']]),
  ];
  const headTilt = (rad, len = 120) => [T('head', KEY.rotation, [[0, rad, 'hold'], [len, rad, 'hold']])];
  const bob = (node, amp, len) => [T(node, KEY.y, [[0, 0], [len / 2, -amp], [len, 0]])];

  // -- покой: 6 настроений x 5 стадий -----------------------------------------
  const idleTracks = {
    calm:   () => [...breath(0.03), ...blink(100)],
    happy:  () => [...breath(0.04, 90), ...blink(70), ...bob('head', 12, 90)],
    sad:    () => [...breath(0.02, 150), ...headTilt(-0.18, 150), ...bob('ctrl_eyebrow_left', -6, 150)],
    hungry: () => [...breath(0.02, 140), ...blink(60), T('ctrl_mouth', KEY.scaleY, [[0, 1], [70, 1.3], [140, 1]])],
    sleepy: () => [...breath(0.025, 160), T('eyelid_top_left', KEY.scaleY, [[0, 2.2, 'hold'], [160, 2.2, 'hold']]), T('eyelid_top_right', KEY.scaleY, [[0, 2.2, 'hold'], [160, 2.2, 'hold']]), ...headTilt(0.08, 160)],
    messy:  () => [...breath(0.03), ...blink(110), ...headTilt(0.12, 120), T('ear_left', KEY.rotation, [[0, 0], [60, -0.25], [120, 0]])],
  };
  for (const clip of catalog.groups.idle.clips) {
    const len = { calm: 120, happy: 90, sad: 150, hungry: 140, sleepy: 160, messy: 120 }[clip.mood];
    add(clip.name, { duration: len, loop: 'loop', tracks: idleTracks[clip.mood]() });
  }

  // -- действия ухода --------------------------------------------------------
  const careTracks = {
    feed:  () => [T('ctrl_mouth', KEY.scaleY, [[0, 1], [12, 1.7], [24, 1], [36, 1.7], [48, 1]]), ...bob('head', 8, 48)],
    wash:  () => [T('head', KEY.rotation, [[0, 0], [15, -0.2], [30, 0.2], [45, -0.2], [60, 0]]), T('hand_left', KEY.y, [[0, 0], [30, -40], [60, 0]])],
    sleep: () => [T('eyelid_top_left', KEY.scaleY, [[0, 1], [40, 3.4]]), T('eyelid_top_right', KEY.scaleY, [[0, 1], [40, 3.4]]), ...headTilt(0.25, 60)],
    wake:  () => [T('eyelid_top_left', KEY.scaleY, [[0, 3.4], [30, 1]]), T('eyelid_top_right', KEY.scaleY, [[0, 3.4], [30, 1]]), ...bob('body', 10, 40)],
    play:  () => [...bob('body', 30, 40), T('root_arm_left', KEY.rotation, [[0, 0], [20, -0.6], [40, 0]]), T('root_arm_right', KEY.rotation, [[0, 0], [20, 0.6], [40, 0]])],
    pet:   () => [T('head', KEY.rotation, [[0, 0], [25, 0.15], [50, 0]]), T('ear_left', KEY.rotation, [[0, 0], [12, -0.3], [24, 0], [36, -0.3], [50, 0]]), T('ear_right', KEY.rotation, [[0, 0], [12, 0.3], [24, 0], [36, 0.3], [50, 0]])],
  };
  const careLen = { feed: 48, wash: 60, sleep: 60, wake: 40, play: 40, pet: 50 };
  for (const clip of catalog.groups.care.clips) {
    add(clip.name, { duration: careLen[clip.action], tracks: careTracks[clip.action]() });
  }

  // -- перемещение (не подключено к state machine — нет триггера в VM) ----
  const rootX = AB.w / 2 + ((PROPORTIONS.parts.hip_left.x + PROPORTIONS.parts.hip_right.x) / 2) * SCALE;
  for (const clip of catalog.groups.move.clips) {
    const dir = clip.name.includes('left') ? -1 : 1;
    add(clip.name, { duration: 60, loop: 'loop', tracks: [T('root', KEY.rootX, [[0, rootX], [60, rootX + 40 * dir]]), ...bob('body', 6, 30)] });
  }

  // -- взросление ------------------------------------------------------------
  for (const clip of catalog.groups.growth.clips) {
    add(clip.name, {
      duration: 150,
      tracks: [
        T('root', KEY.scaleX, [[0, 1], [75, 1.18], [150, 1]]),
        T('root', KEY.scaleY, [[0, 1], [75, 1.18], [150, 1]]),
        T('root', KEY.opacity, [[0, 1], [40, 0.35], [80, 1, 'linear'], [150, 1, 'hold']]),
      ],
    });
  }

  // -- характеры -------------------------------------------------------------
  const traitTilt = { active: 0.2, curious: -0.2, affectionate: 0.12, calm: 0.03, independent: -0.1, reserved: 0.05 };
  for (const clip of catalog.groups.trait.clips) {
    const tilt = traitTilt[clip.trait];
    if (clip.name.endsWith('_idle')) add(clip.name, { duration: 120, loop: 'loop', tracks: [...headTilt(tilt), ...breath(0.03)] });
    else if (clip.name.endsWith('_reaction')) add(clip.name, { duration: 45, tracks: [T('head', KEY.rotation, [[0, 0], [20, tilt * 2], [45, 0]]), ...bob('body', 14, 45)] });
    else add(clip.name, { duration: 60, tracks: [...bob('head', 18, 60), T('ctrl_eyes', KEY.x, [[0, 0], [30, 10], [60, 0]])] });
  }

  // -- вариативность: заготовки с тем же движением, чуть другим таймингом ----
  for (const clip of catalog.groups.variants.clips) {
    if (clip.name.startsWith('var_idle_')) {
      const mood = clip.name.replace('var_idle_', '').replace('_alt', '');
      add(clip.name, { duration: 130, loop: 'loop', tracks: idleTracks[mood]() });
    } else if (clip.name.startsWith('var_')) {
      const action = clip.name.replace('var_', '').replace('_alt', '');
      add(clip.name, { duration: careLen[action] + 10, tracks: careTracks[action]() });
    } else {
      add(clip.name, { duration: 90, tracks: [T('head', KEY.rotation, [[0, 0], [45, 0.5], [90, 0]])] });
    }
  }

  // -- эмоции ----------------------------------------------------------------
  const emoteTracks = {
    joy:      () => [...bob('body', 40, 40), T('ear_left', KEY.rotation, [[0, 0], [20, -0.4], [40, 0]]), T('ear_right', KEY.rotation, [[0, 0], [20, 0.4], [40, 0]])],
    upset:    () => [...headTilt(-0.3, 60), T('ctrl_eyebrow_left', KEY.y, [[0, 0], [30, 6], [60, 0]])],
    surprise: () => [T('ctrl_eyes', KEY.scaleX, [[0, 1], [10, 1.4], [40, 1]]), T('ctrl_eyes', KEY.scaleY, [[0, 1], [10, 1.4], [40, 1]]), ...bob('head', -10, 40)],
    love:     () => [T('head', KEY.rotation, [[0, 0], [30, 0.2], [60, 0]]), T('ctrl_eyes', KEY.scaleY, [[0, 1], [30, 0.6], [60, 1]])],
  };
  for (const clip of catalog.groups.emotions.clips) {
    add(clip.name, { duration: clip.name.endsWith('_b') ? 70 : 60, tracks: emoteTracks[clip.emotion]() });
  }

  // -- осанка для blend по общему уходу --------------------------------------
  add('pose_neglected', { duration: 1, tracks: [T('head', KEY.rotation, [[0, -0.22, 'hold']]), T('body', KEY.scaleY, [[0, 0.95, 'hold']])] });
  add('pose_cared', { duration: 1, tracks: [T('head', KEY.rotation, [[0, 0, 'hold']]), T('body', KEY.scaleY, [[0, 1, 'hold']])] });

  return list;
}

export function loadCatalog() {
  return JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'animation_catalog.json'), 'utf8'));
}
