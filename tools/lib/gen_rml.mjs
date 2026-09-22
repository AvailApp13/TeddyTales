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
// Экран 1024x1024, мишка анфас, нейтральная поза (как в брифе художнику).
// Для потомков кости координаты ЛОКАЛЬНЫЕ: x — вдоль кости, y — вправо от неё.
// Для root и root_body (направлены вверх) local = (parentTipY - screenY, screenX - parentTipX).

const ART = {
  // name: { local: [x, y], size: [w, h], color, opacity }
  body:        { local: [-280, 0],  size: [300, 340], color: 'FFC9A57C' },
  body_base:   { local: [-420, 0],  size: [260, 120], color: 'FFB8946C' },
  head:        { local: [-20, 0],   size: [280, 260], color: 'FFC9A57C' },
  head_shadow: { local: [-140, 0],  size: [240, 60],  color: 'FF000000', opacity: 0.15 },

  ear_left:        { local: [120, -112], size: [90, 90], color: 'FFC9A57C' },
  ear_right:       { local: [120, 112],  size: [90, 90], color: 'FFC9A57C' },
  ear_in_left:     { local: [0, 0],      size: [50, 50], color: 'FFE8B7A3' },
  ear_in_right:    { local: [0, 0],      size: [50, 50], color: 'FFE8B7A3' },
  ear_light_left:  { local: [12, -10],   size: [20, 14], color: 'FFFFFFFF', opacity: 0.5 },
  ear_light_right: { local: [12, 10],    size: [20, 14], color: 'FFFFFFFF', opacity: 0.5 },

  ctrl_face:          { local: [-20, 0] },
  ctrl_eyes:          { local: [20, 0] },
  ctrl_pupils:        { local: [0, 0] },
  ctrl_mouth:         { local: [-55, 0] },
  ctrl_nose:          { local: [-25, 0] },
  ctrl_eyebrow_left:  { local: [50, -42] },
  ctrl_eyebrow_right: { local: [50, 42] },

  eye_left:            { local: [0, -42],  size: [44, 44], color: 'FFFFFFFF' },
  eye_right:           { local: [0, 42],   size: [44, 44], color: 'FFFFFFFF' },
  pupil_left:          { local: [0, -42],  size: [22, 22], color: 'FF2B1E16' },
  pupil_right:         { local: [0, 42],   size: [22, 22], color: 'FF2B1E16' },
  pupil_light_left:    { local: [4, -4],   size: [8, 8],   color: 'FFFFFFFF' },
  pupil_light_right:   { local: [4, -4],   size: [8, 8],   color: 'FFFFFFFF' },
  eyelid_top_left:     { local: [22, 0],   size: [48, 14], color: 'FFC9A57C' },
  eyelid_top_right:    { local: [22, 0],   size: [48, 14], color: 'FFC9A57C' },
  eyelid_bottom_left:  { local: [-22, 0],  size: [48, 10], color: 'FFC9A57C' },
  eyelid_bottom_right: { local: [-22, 0],  size: [48, 10], color: 'FFC9A57C' },
  eyebrow_left:        { local: [0, 0],    size: [50, 12], color: 'FF8A6A48' },
  eyebrow_right:       { local: [0, 0],    size: [50, 12], color: 'FF8A6A48' },

  nose:   { local: [0, 0],  size: [46, 32], color: 'FF3B2A22' },
  mouth:  { local: [0, 0],  size: [70, 30], color: 'FF5A2E2E' },
  teeth:  { local: [6, 0],  size: [40, 10], color: 'FFFFFFFF' },
  tongue: { local: [-6, 0], size: [30, 14], color: 'FFE07A8A' },
  lips:   { local: [0, 0],  size: [70, 8],  color: 'FF3B2A22' },

  scarf_1: { local: [-150, 0], size: [200, 40], color: 'FFD9534F' },
  scarf_2: { local: [-18, 0],  size: [180, 36], color: 'FFC9443F' },
  scarf_3: { local: [-18, 0],  size: [160, 32], color: 'FFB9342F' },

  forearm_left:        { local: [0, 0],    size: [70, 110], color: 'FFC9A57C' },
  forearm_light_left:  { local: [-10, -12], size: [30, 60], color: 'FFFFFFFF', opacity: 0.35 },
  hand_left:           { local: [80, 0],   size: [70, 70],  color: 'FFB8946C' },
  hand_light_left:     { local: [-8, -8],  size: [30, 30],  color: 'FFFFFFFF', opacity: 0.35 },
  finger_1_nail_left:  { local: [30, -18], size: [14, 14],  color: 'FF8A6A48' },
  finger_2_nail_left:  { local: [34, 0],   size: [14, 14],  color: 'FF8A6A48' },
  finger_3_nail_left:  { local: [30, 18],  size: [14, 14],  color: 'FF8A6A48' },
  forearm_right:       { local: [0, 0],    size: [70, 110], color: 'FFC9A57C' },
  forearm_light_right: { local: [-10, 12], size: [30, 60],  color: 'FFFFFFFF', opacity: 0.35 },
  hand_right:          { local: [80, 0],   size: [70, 70],  color: 'FFB8946C' },
  hand_light_right:    { local: [-8, 8],   size: [30, 30],  color: 'FFFFFFFF', opacity: 0.35 },
  finger_1_nail_right: { local: [30, 18],  size: [14, 14],  color: 'FF8A6A48' },
  finger_2_nail_right: { local: [34, 0],   size: [14, 14],  color: 'FF8A6A48' },
  finger_3_nail_right: { local: [30, -18], size: [14, 14],  color: 'FF8A6A48' },
};

const BONES = {
  // rotation — радианы относительно родительской кости; root — от оси +x экрана.
  root:           { x: 512, y: 780, length: 240, rotation: -Math.PI / 2 },
  root_body:      { length: 260, rotation: 0 },
  root_arm_left:  { length: 130, rotation: -2.3 },
  root_arm_right: { length: 130, rotation: 2.3 },
};

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

  const W = rig.artboard.width;
  const H = rig.artboard.height;
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
  const root = rig.nodes.find((n) => n.parent === null);
  const walk = (node, depth) => {
    const id = ids.take();
    nodeIds[node.name] = id;
    const kids = childrenOf(rig, node.name);
    const art = ART[node.name] ?? { local: [0, 0] };
    const [lx, ly] = art.local;

    if (node.kind === 'bone') {
      const b = BONES[node.name] ?? { length: 40, rotation: 0 };
      if (node.parent === null) {
        emit(depth, `<RootBone x="${b.x}" y="${b.y}" length="${b.length}" rotation="${num(b.rotation)}" name="${nameOf(node.name)}" id="${id}">`);
      } else {
        emit(depth, `<Bone length="${b.length}" rotation="${num(b.rotation)}" name="${nameOf(node.name)}" id="${id}">`);
      }
      for (const kid of kids) walk(kid, depth + 1);
      // Слоты одежды висят на костях, к которым их привязывает каталог (КП 4.9).
      for (const slot of catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name)) {
        const sid = ids.take();
        nodeIds[slot.name] = sid;
        emit(depth + 1, `<Node name="${slot.name}" id="${sid}"/>`);
      }
      emit(depth, node.parent === null ? '</RootBone>' : '</Bone>');
      return;
    }

    if (node.kind === 'control') {
      emit(depth, `<Node x="${num(lx)}" y="${num(ly)}" name="${nameOf(node.name)}" id="${id}">`);
      for (const kid of kids) walk(kid, depth + 1);
      emit(depth, '</Node>');
      return;
    }

    // art: группа с именем спеки; внутри — дети (сверху) и плейсхолдер (снизу).
    // Художник заменяет плейсхолдер своим слоем, имя группы не трогает.
    emit(depth, `<Node x="${num(lx)}" y="${num(ly)}" name="${nameOf(node.name)}" id="${id}">`);
    for (const kid of kids) walk(kid, depth + 1);
    for (const slot of catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name)) {
      const sid = ids.take();
      nodeIds[slot.name] = sid;
      emit(depth + 1, `<Node name="${slot.name}" id="${sid}"/>`);
    }
    if (art.size) {
      // Потомки root/root_body живут в системе кости, повёрнутой на -90°:
      // ширина фигуры уходит по экранной вертикали. Размеры в ART заданы «как
      // на экране», поэтому здесь они меняются местами. Руки повёрнуты иначе
      // и остаются как есть.
      const underArm = /(_left|_right)$/.test(node.name) && /^(forearm|hand|finger)/.test(node.name);
      const [w, h] = underArm ? art.size : [art.size[1], art.size[0]];
      let color = art.color;
      if (node.name.startsWith('scarf')) color = tint.scarf;
      if (node.name.startsWith('ear_in')) color = tint.ear_in;
      const opacity = art.opacity !== undefined ? ` opacity="${num(art.opacity)}"` : '';
      emit(depth + 1, `<Shape${opacity} name="${node.name}__placeholder">`);
      emit(depth + 2, `<Ellipse width="${w}" height="${h}" name="P"/>`);
      emit(depth + 2, `<Fill name="F"><SolidColor colorValue="${color}" name="C"/></Fill>`);
      emit(depth + 1, `</Shape>`);
    }
    emit(depth, '</Node>');
  };
  walk(root, 2);

  // ---- анимации ------------------------------------------------------------
  const animations = buildAnimations({ catalog, rig, nodeIds, ids, animIds });
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

function buildAnimations({ catalog, rig, nodeIds, ids, animIds }) {
  const list = [];
  const add = (name, { duration, loop, tracks }) => {
    const id = ids.take();
    animIds[name] = id;
    list.push({ id, name, duration, loop, tracks: tracks.filter((t) => t.objectId) });
  };
  const T = (node, key, keys) => ({ objectId: nodeIds[node], key, keys });

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
  for (const clip of catalog.groups.move.clips) {
    const dir = clip.name.includes('left') ? -1 : 1;
    add(clip.name, { duration: 60, loop: 'loop', tracks: [T('root', KEY.rootX, [[0, 512], [60, 512 + 40 * dir]]), ...bob('body', 6, 30)] });
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
