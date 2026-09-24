#!/usr/bin/env node
/**
 * Мишка v2, шаг 2 (D13): рукава на костях рук, ось головы на шее, скрытые
 * продолжения слоёв. Работает с файлом, где уже стоят 6 костей и группы
 * привязаны (teddy mcp:bind).
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/place_layers_v3.mjs
 *
 * 1. Всё, что висит на root / root_body, временно снимается с костей (редактор
 *    сохраняет мировое положение), кости root и root_body выставляются по
 *    bonePlan (таз -> шея -> центр головы), всё возвращается обратно.
 * 2. Создаются группы sleeve_left / sleeve_right.
 * 3. Прежние слои удаляются, 11 новых из handoff/layers_v2 ставятся одним
 *    общим трансформом: сначала в группу rig (без поворота), затем переносятся
 *    в свои группы — мировое положение сохраняется.
 * 4. teddy mcp:bind — группы на кости, порядок отрисовки.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot, loadRig } from '../lib/rig.mjs';
import { AB, loadCatalog } from '../lib/gen_rml.mjs';
import { bindToBones, bonePlan } from '../lib/mcp_build.mjs';
import { boneLayout } from '../lib/gen_rml.mjs';

const L = resolve(repoRoot, 'handoff', 'layers_v2');
const meta = JSON.parse(readFileSync(resolve(L, 'layers.json'), 'utf8'));
const photo = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'bear_proportions.json'), 'utf8')).photo;
const S = AB.figureHeight / photo.bodyHeightPx;
const [W, H] = meta.size;
const WORLD = { x: AB.w / 2 + (W / 2 - photo.axisX) * S, y: AB.groundY - (photo.groundY - H / 2) * S };
const GROUP = { ears: 'head', face: 'head', hood: 'outfit_head', shirt: 'outfit_body', shorts: 'outfit_feet',
  paw_left: 'hand_left', paw_right: 'hand_right', sleeve_left: 'sleeve_left', sleeve_right: 'sleeve_right',
  foot_left: 'foot_left', foot_right: 'foot_right', hood_lining: 'hood_lining' };
const deg = (r) => (r * 180) / Math.PI;

const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => {
  for (let i = 0; i < 6; i++) {
    try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 400)}`); return r; }
    catch (e) { if (!/ENOTFOUND|DNS|пустой ответ/.test(e.message)) throw e; await new Promise((r) => setTimeout(r, 8000)); }
  }
  throw new Error(`${t}: нет связи`);
};
const info = await call('session_info', {});
const file = state[String(info.activeFileId)];
const board = { id: file.artboards.Bear_Boy.id };
const hierarchy = async () => {
  const h = await call('get_artboard_hierarchy', { artboardId: board.id, depth: 14 });
  const byName = new Map(); const parentOf = new Map(); const byId = new Map();
  for (const o of h.objects ?? []) { byId.set(o.id, o); if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
  return { byName, parentOf, byId };
};
let { byName, parentOf, byId } = await hierarchy();
const id = (n) => byName.get(n)?.id;
const rigId = id('rig');
const B = file.bones;

// ---- 1. кости root / root_body по новому плану
const onSpine = [...byId.values()].filter((o) => [B.root, B.root_body].includes(parentOf.get(o.id)) && o.id !== B.root_body);
const parked = onSpine.map((o) => ({ objectId: o.id, newParentId: /Bone$/.test(o.types[0]) ? board.id : rigId, back: parentOf.get(o.id) }));
if (parked.length) await call('reparent_objects', { operations: parked.map(({ objectId, newParentId }) => ({ objectId, newParentId, position: 'end' })) });
console.log('снято с позвоночника:', parked.length);
const plan = boneLayout();
const rootAng = deg(plan.root.angle), bodyAng = deg(plan.root_body.angle);
await call('set_property_values', { propertyValues: {
  [B.root]: { 90: plan.root.x, 91: plan.root.y, 89: plan.root.length, 15: rootAng },
  [B.root_body]: { 89: plan.root_body.length, 15: bodyAng - rootAng },
} });
console.log(`root: (${plan.root.x.toFixed(1)}, ${plan.root.y.toFixed(1)}) длина ${plan.root.length.toFixed(1)} угол ${rootAng.toFixed(2)}°; root_body до центра головы, длина ${plan.root_body.length.toFixed(1)}`);
// кости рук и ног — обратно в root (мировое положение сохраняется)
const boneBack = parked.filter((p) => p.newParentId === board.id);
if (boneBack.length) await call('reparent_objects', { operations: boneBack.map((p) => ({ objectId: p.objectId, newParentId: p.back, position: 'end' })) });

// ---- 2. группы рукавов (id берём из иерархии по имени: ответ group_editor его не отдаёт)
({ byName, parentOf, byId } = await hierarchy());
const NEW_GROUPS = { sleeve_left: plan.root_arm_left, sleeve_right: plan.root_arm_right, hood_lining: { x: plan.root_body.x, y: plan.root_body.y } };
for (const [name, sh] of Object.entries(NEW_GROUPS)) {
  if (!id(name)) { await call('group_editor', { name, parentId: rigId, x: sh.x, y: sh.y }); ({ byName, parentOf, byId } = await hierarchy()); }
  const gid = id(name); if (!gid) throw new Error(`группа ${name} не создалась`);
  if (parentOf.get(gid) === board.id || parentOf.get(gid) === undefined) await call('reparent_objects', { operations: [{ objectId: gid, newParentId: rigId, position: 'end' }] });
  if (parentOf.get(gid) === rigId || parentOf.get(gid) === board.id) await call('set_property_values', { propertyValues: { [gid]: { 13: sh.x, 14: sh.y } } });
  console.log('группа', name, gid);
}
({ byName, parentOf, byId } = await hierarchy());

// ---- 3. слои
const old = Object.values(file.layersV2 ?? {}).flatMap((p) => [p.instance, p.asset]).filter(Boolean);
file.skins = {};   // сетки удаляются вместе с картинками — перепривязать: scripts/skin_layers.mjs
if (old.length) { await call('delete_objects', { objectIds: old }).catch((e) => console.log('удаление:', e.message)); console.log('удалено прежних объектов:', old.length); }
file.layersV2 = {};
for (const name of meta.order_back_to_front) {
  const g = byName.get(GROUP[name]); if (!g) throw new Error(`нет группы ${GROUP[name]}`);
  const b64 = readFileSync(resolve(L, `${name}.png`)).toString('base64');
  const asset = (await call('upload_asset', { file: `data:image/png;name=bear_${name}.png;base64,${b64}`, name: `bear_${name}` })).asset;
  const inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: asset.id, parentId: rigId, name: `${name}_img`, x: WORLD.x, y: WORLD.y } } });
  if (parentOf.get(inst.imageId) !== rigId) await call('reparent_objects', { operations: [{ objectId: inst.imageId, newParentId: rigId, position: 'end' }] });
  await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: WORLD.x, 14: WORLD.y, 16: S * 100, 17: S * 100, 15: 0, 18: 100 } } });
  // редактор иногда молча не переносит только что созданную картинку — повторяем до успеха
  for (let tries = 0; ; tries++) {
    const rr = await call('reparent_objects', { operations: [{ objectId: inst.imageId, newParentId: g.id, position: 'end' }] });
    if ((rr.reparented ?? []).some((x) => x.id === inst.imageId)) break;
    if (tries >= 4) throw new Error(`${name}: не переносится в ${GROUP[name]}: ${JSON.stringify(rr)}`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  file.layersV2[name] = { asset: asset.id, instance: inst.imageId, group: GROUP[name], groupId: g.id };
  console.log(`${name.padEnd(12)} -> ${GROUP[name]} (${inst.imageId})`);
}

// ---- 4. группы на кости, порядок
await bindToBones({ call, log: console.log, rig: loadRig(), catalog: loadCatalog(), board });
({ byName, parentOf, byId } = await hierarchy());
const front = async (list) => { for (const x of list.filter(Boolean)) await call('reorder_objects', { operations: [{ objectId: x, order: 'sendToFront' }] }); };
const LV = file.layersV2;
await front([id('ear_left'), id('ear_right'), LV.ears.instance, LV.face.instance, id('outfit_head'), id('ctrl_face')]);
file.layersV2Transform = { world: WORLD, scalePercent: +(S * 100).toFixed(3), source: 'handoff/layers_v2', step: 'D13' };
file.bonesPlan = bonePlan();
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: board.id, longEdge: 1024 });
const img = (r.content ?? []).find((p) => p.type === 'image');
if (img) { const out = resolve(repoRoot, 'handoff', 'reference', 'editor_bear_v2.png'); writeFileSync(out, Buffer.from(img.data, 'base64')); console.log('снимок:', out); }
console.log('готово');
