/**
 * Строит каркас мишки прямо в открытом файле Rive Editor через MCP.
 *
 * Делает всё, что MCP умеет: перечисления, View Model с инстансом, дерево
 * групп по спеке с плейсхолдерами по размерной сетке, зону касания. Кости MCP
 * создавать не умеет (см. mesh_rigging_tool: «Does NOT create bones») — их
 * ставит человек по координатам из `teddy mcp:bones`, после чего группы
 * перепривязываются под кости командой `teddy mcp:reparent`.
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadRig, childrenOf, repoRoot } from './rig.mjs';
import { loadCatalog, worldLayout, boneLayout, PLACEHOLDER_COLOR, PLACEHOLDER_OPACITY, AB } from './gen_rml.mjs';
import { RiveMcpClient, toolText } from './rive_mcp.mjs';

const argb = (hex, opacity = 1) => {
  // hex = 'FFRRGGBB' -> '#aarrggbb' с учётом opacity плейсхолдера
  const a = Math.round(255 * opacity).toString(16).padStart(2, '0');
  return `#${a}${hex.slice(2)}`;
};

const parseJson = (result) => {
  const text = toolText(result);
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
};

const STATE_PATH = resolve(repoRoot, 'rive', 'editor_state.json');
export function loadState() {
  return existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, 'utf8')) : {};
}
export function saveState(state) {
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + '\n');
}

export async function buildInEditor({ log = () => {}, artboardName } = {}) {
  const rig = loadRig();
  const catalog = loadCatalog();
  const client = new RiveMcpClient();
  await client.initialize();
  const call = async (tool, args) => parseJson(await client.callTool(tool, args));

  // ---- артборд --------------------------------------------------------------
  const target = artboardName ?? rig.artboard.primary;
  let boards = (await call('list_artboards', {})).artboards ?? [];
  let board = boards.find((b) => b.name === target);
  if (!board) {
    await call('open_file_editor', { command: 'createArtboard', data: { createArtboard: [{ name: target, width: AB.w, height: AB.h }] } });
    boards = (await call('list_artboards', {})).artboards ?? [];
    board = boards.find((b) => b.name === target);
    log(`артборд ${target} создан`);
  }
  await call('open_file_editor', { command: 'focusArtboard', data: { focusArtboard: { artboardId: board.id } } });
  log(`артборд ${target} (${board.id})`);

  // ---- перечисления ---------------------------------------------------------
  // listDataEnums в MCP 0.6 не показывает пользовательские перечисления,
  // поэтому и их существование, и id значений живут в файле состояния.
  const file = await call('session_info', {});
  const state = loadState();
  const fileKey = String(file.activeFileId);
  state[fileKey] ??= { fileName: file.activeFileName, artboards: {} };
  const st = state[fileKey];
  st.enums ??= {};

  const missingEnums = Object.entries(rig.enums).filter(([name]) => !st.enums[name]);
  if (missingEnums.length) {
    const created = await call('viewmodel_editor', {
      command: 'createDataEnums',
      data: { createDataEnums: { dataEnums: missingEnums.map(([name, def]) => ({ name, values: def.values })) } },
    });
    for (const e of created.dataEnums ?? []) {
      st.enums[e.name] = { id: e.id, values: Object.fromEntries((e.values ?? []).map((v) => [v.key, v.id])) };
    }
    saveState(state);
    log(`перечисления: ${missingEnums.map(([n]) => n).join(', ')}`);
  }

  // ---- view model -----------------------------------------------------------
  // listViewModels в этой сборке редактора (MCP 0.6) возвращает пустой список,
  // поэтому id берутся из ответа createViewModels и запоминаются в файле
  // состояния rive/editor_state.json — сборка идемпотентна по нему.
  if (!st.viewModel) {
    const props = rig.viewModel.properties.map((p) =>
      p.type === 'enum' ? { name: p.name, propertyType: 'enum', enumName: p.enumName } : { name: p.name, propertyType: p.type },
    );
    const created = await call('viewmodel_editor', { command: 'createViewModels', data: { createViewModels: { viewModels: [{ name: rig.viewModel.name, viewModelProperties: props }] } } });
    const vm = created.viewModels?.[0];
    if (!vm?.id) throw new Error(`createViewModels не вернул id: ${JSON.stringify(created).slice(0, 300)}`);
    st.viewModel = { id: vm.id, properties: Object.fromEntries((vm.viewModelProperties ?? []).map((p) => [p.name, p.id])) };
    saveState(state);
    log(`view model ${rig.viewModel.name}: ${props.length} свойств (${vm.id})`);
  }
  const vmId = st.viewModel.id;
  const propIds = st.viewModel.properties;

  // Значения по умолчанию: инстанс создаётся редактором вместе с моделью, его
  // значения идут сразу за свойствами (prop N -> value N+1). Пишем напрямую:
  // число — ключ 575, enum — ключ 560 (id значения перечисления).
  if (!st.defaultsWritten) {
    const next = (id) => id.replace(/-(\d+)$/, (_, n) => `-${Number(n) + 1}`);
    const propertyValues = {};
    for (const p of rig.viewModel.properties) {
      const valueId = next(propIds[p.name]);
      if (p.type === 'number') propertyValues[valueId] = { 575: p.default };
      if (p.type === 'enum') {
        const vid = st.enums[p.enumName]?.values?.[p.default];
        if (vid) propertyValues[valueId] = { 560: vid };
        else log(`  нет id значения ${p.enumName}.${p.default} — пропущено`);
      }
    }
    const r = await call('set_property_values', { propertyValues });
    if (r.errors && Object.keys(r.errors).length) log(`  предупреждение при записи значений: ${JSON.stringify(r.errors).slice(0, 300)}`);
    st.defaultsWritten = true;
    saveState(state);
    log(`значения по умолчанию записаны (${Object.keys(propertyValues).length})`);
  }
  await call('viewmodel_editor', { command: 'bindViewModelToArtboard', data: { bindViewModelToArtboard: { artboardId: board.id, viewModelId: vmId } } });
  log('view model привязана к артборду');

  // ---- дерево групп по спеке ---------------------------------------------------
  // Кости пропускаем (MCP их не создаёт): их дети временно живут под группой
  // `rig`, координаты — мировые. После ручной расстановки костей группы
  // перепривязываются (teddy mcp:reparent).
  const layout = worldLayout();
  const existing = (await call('find_objects', { artboardId: board.id })).objects ?? [];
  const byName = new Map(existing.map((o) => [o.name, o.id]));
  const ids = {};

  const rigGroup = byName.get('rig') ?? (await call('group_editor', { name: 'rig', parentId: board.id, x: 0, y: 0 })).id;
  ids.rig = rigGroup;

  const walk = async (node, parentId, parentWorld) => {
    if (node.kind === 'bone') {
      for (const kid of childrenOf(rig, node.name)) await walk(kid, parentId, parentWorld);
      for (const slot of catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name)) {
        if (!byName.has(slot.name)) {
          const r = await call('group_editor', { name: slot.name, parentId, x: 0, y: 0 });
          ids[slot.name] = r.id;
        }
      }
      return;
    }
    const world = layout[node.name] ?? { x: parentWorld.x, y: parentWorld.y, w: 0, h: 0 };
    let id = byName.get(node.name);
    if (!id) {
      const r = await call('group_editor', { name: node.name, parentId, x: world.x - parentWorld.x, y: world.y - parentWorld.y });
      id = r.id;
      if (node.kind === 'art' && world.w > 0) {
        const key = node.name.replace(/_(left|right)$/, '').replace(/^finger_\d_/, 'finger_');
        const color = PLACEHOLDER_COLOR[key] ?? 'FFC9A57C';
        const opacity = PLACEHOLDER_OPACITY[key] ?? 1;
        await call('path_editor', {
          command: 'createParametricShapes',
          data: { createParametricShapes: { shapes: [{ primitive: 'ellipse', name: `${node.name}__placeholder`, parentId: id, x: 0, y: 0, width: world.w, height: world.h, paints: [{ paintType: 'fill', color: argb(color, opacity) }] }] } },
        });
      }
      log(`  ${node.kind === 'control' ? 'ctrl' : 'art '} ${node.name}`);
    }
    ids[node.name] = id;
    for (const kid of childrenOf(rig, node.name)) await walk(kid, id, world);
    for (const slot of catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name)) {
      if (!byName.has(slot.name)) {
        const r = await call('group_editor', { name: slot.name, parentId: id, x: 0, y: 0 });
        ids[slot.name] = r.id;
      }
    }
  };
  const root = rig.nodes.find((n) => n.parent === null);
  await walk(root, rigGroup, { x: 0, y: 0 });

  // зона касания (КП 3.1) — отдельный прозрачный шейп, чтобы листенер не
  // зависел от арта
  if (!byName.has('hit_area')) {
    await call('path_editor', {
      command: 'createParametricShapes',
      data: { createParametricShapes: { shapes: [{ primitive: 'rectangle', name: 'hit_area', parentId: board.id, x: AB.w / 2, y: AB.h * 0.55, width: AB.w * 0.5, height: AB.h * 0.75, paints: [{ paintType: 'fill', color: '#00000000' }] }] } },
    });
    log('  hit_area');
  }

  st.artboards[board.name] = { id: board.id, ids };
  saveState(state);

  await reconcileTree({ call, log, rig, catalog, board, layout });
  return { board, vmId, ids, bones: boneLayout() };
}

/** Координаты костей для ручной расстановки — в артборде, мировые. */
export function bonePlan() {
  const b = boneLayout();
  const deg = (r) => Math.round((r * 180) / Math.PI);
  return Object.entries(b).map(([name, s]) => ({
    name,
    from: { x: Math.round(s.x), y: Math.round(s.y) },
    to: { x: Math.round(s.x + Math.cos(s.angle) * s.length), y: Math.round(s.y + Math.sin(s.angle) * s.length) },
    length: Math.round(s.length),
    angleDeg: deg(s.angle),
  }));
}


/**
 * Приводит дерево в редакторе к дереву спеки. Нужно потому, что group_editor
 * и path_editor в MCP 0.6 игнорируют parentId и кладут всё плоско на
 * артборд. Идемпотентно: перепривязывает только то, что стоит не там, и
 * всегда переписывает локальные x/y (после reparent редактор их не
 * пересчитывает предсказуемо).
 */
export async function reconcileTree({ call, log, rig, catalog, board, layout }) {
  const hier = await call('get_artboard_hierarchy', { artboardId: board.id, depth: 12 });
  const objects = hier.objects ?? [];
  const byName = new Map();
  for (const o of objects) if (!byName.has(o.name)) byName.set(o.name, o);
  const parentOf = new Map();
  for (const o of objects) for (const c of o.children ?? []) parentOf.set(c, o.id);
  const idOf = (name) => byName.get(name)?.id;

  const rigId = idOf('rig');
  const DRAW_PRIORITY = { root_arm_left: 0, root_arm_right: 0, root_body: 1, root_leg_left: 2, root_leg_right: 2 };
  const ordered = (list) => [...list].sort((a, b) => (DRAW_PRIORITY[a.name] ?? 1) - (DRAW_PRIORITY[b.name] ?? 1));

  const ops = [];
  const positions = {};
  const plan = (childName, parentId, x, y) => {
    const id = idOf(childName);
    if (!id) return;
    if (parentOf.get(id) !== parentId) ops.push({ objectId: id, newParentId: parentId, position: 'end' });
    positions[id] = { 13: x, 14: y };
  };

  // кости пропускаем: их дети временно под rig, мировые координаты
  const walk = (node, parentId, parentWorld) => {
    const kids = ordered(childrenOf(rig, node.name));
    const slots = catalog.outfitSlots.slots.filter((s) => s.boundTo === node.name);
    if (node.kind === 'bone') {
      for (const kid of kids) walk(kid, parentId, parentWorld);
      for (const slot of slots) plan(slot.name, parentId, 0, 0);
      return;
    }
    const world = layout[node.name] ?? { x: parentWorld.x, y: parentWorld.y, w: 0, h: 0 };
    plan(node.name, parentId, world.x - parentWorld.x, world.y - parentWorld.y);
    const id = idOf(node.name);
    for (const kid of kids) walk(kid, id, world);
    for (const slot of slots) plan(slot.name, id, 0, 0);
    // плейсхолдер — последним, чтобы оказаться под детьми
    plan(`${node.name}__placeholder`, id, 0, 0);
  };
  const root = rig.nodes.find((n) => n.parent === null);
  plan('rig', board.id, 0, 0);
  walk(root, rigId, { x: 0, y: 0 });

  if (ops.length) {
    // Порядок важен: сначала родители, потом дети — ops уже в порядке обхода.
    const chunk = 40;
    for (let i = 0; i < ops.length; i += chunk) {
      const r = await call('reparent_objects', { operations: ops.slice(i, i + chunk) });
      if (r.errors?.length) log(`  reparent: ${JSON.stringify(r.errors).slice(0, 300)}`);
    }
    log(`перепривязано объектов: ${ops.length}`);
  }
  const r = await call('set_property_values', { propertyValues: positions });
  if (r.errors && Object.keys(r.errors).length) log(`  позиции: ${JSON.stringify(r.errors).slice(0, 300)}`);
  log(`позиции записаны: ${Object.keys(positions).length}`);
}
