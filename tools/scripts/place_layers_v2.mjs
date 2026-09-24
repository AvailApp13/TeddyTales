#!/usr/bin/env node
/**
 * Ставит 9 слоёв мишки v2 (handoff/layers_v2) в открытый файл Rive через MCP.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/place_layers_v2.mjs
 *
 * 1. Позиции групп рига приводятся к новой сетке (reconcileTree).
 * 2. Прежние картинки мишки в этом файле удаляются (state.parts, state.layersV2).
 * 3. Каждый слой — полный кадр 1333×2000 — грузится и ставится в свою группу
 *    одним общим мировым трансформом: рост без капюшона = AB.figureHeight,
 *    земля = AB.groundY, ось между глазами = центр артборда.
 * 4. Порядок отрисовки: торс, ноги, шорты, руки, толстовка, голова;
 *    в голове: уши, лицо, капюшон, контролы лица.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot, loadRig } from '../lib/rig.mjs';
import { AB, loadCatalog, worldLayout } from '../lib/gen_rml.mjs';
import { reconcileTree } from '../lib/mcp_build.mjs';

const L = resolve(repoRoot, 'handoff', 'layers_v2');
const meta = JSON.parse(readFileSync(resolve(L, 'layers.json'), 'utf8'));
const photo = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'bear_proportions.json'), 'utf8')).photo;
const S = AB.figureHeight / photo.bodyHeightPx;
const [W, H] = meta.size;
const WORLD = { x: AB.w / 2 + (W / 2 - photo.axisX) * S, y: AB.groundY - (photo.groundY - H / 2) * S };
const GROUP = { ears: 'head', face: 'head', hood: 'outfit_head', shirt: 'outfit_body', shorts: 'outfit_feet',
  paw_left: 'hand_left', paw_right: 'hand_right', foot_left: 'foot_left', foot_right: 'foot_right' };

const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => {
  for (let i = 0; i < 6; i++) {
    try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 300)}`); return r; }
    catch (e) { if (!/ENOTFOUND|DNS|пустой ответ/.test(e.message)) throw e; await new Promise((r) => setTimeout(r, 8000)); }
  }
  throw new Error(`${t}: нет связи`);
};
const info = await call('session_info', {});
const file = state[String(info.activeFileId)];
if (!file?.artboards?.Bear_Boy) throw new Error(`в состоянии нет файла ${info.activeFileId}: сначала teddy mcp:build`);
const board = { id: file.artboards.Bear_Boy.id, name: 'Bear_Boy' };
console.log(`файл ${info.activeFileId}, артборд ${board.id}; трансформ ${WORLD.x.toFixed(1)},${WORLD.y.toFixed(1)} × ${(S * 100).toFixed(2)}%`);

// 1. группы — по новой сетке
await reconcileTree({ call, log: console.log, rig: loadRig(), catalog: loadCatalog(), board, layout: worldLayout() });

// 2. старые картинки — удалить
const old = [...Object.values(file.parts ?? {}), ...Object.values(file.layersV2 ?? {})].flatMap((p) => [p.instance, p.asset]).filter(Boolean);
if (old.length) { await call('delete_objects', { objectIds: old }).catch((e) => console.log('удаление:', e.message)); console.log('удалено старых объектов:', old.length); }
if (file.parts) { file.partsRemoved = file.parts; delete file.parts; }
file.layersV2 = {};

// 3. слои
const hier = await call('get_artboard_hierarchy', { artboardId: board.id, depth: 12 });
const byName = new Map(); const parentOf = new Map();
for (const o of hier.objects ?? []) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const ids = new Set(); for (const o of hier.objects ?? []) { let cur = o.id; while (cur && cur !== board.id) { ids.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of ids) keys[id] = [13, 14];
const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const worldOf = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== board.id) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };
for (const name of meta.order_back_to_front) {
  const g = byName.get(GROUP[name]); if (!g) throw new Error(`нет группы ${GROUP[name]}`);
  const b64 = readFileSync(resolve(L, `${name}.png`)).toString('base64');
  const asset = (await call('upload_asset', { file: `data:image/png;name=bear_${name}.png;base64,${b64}`, name: `bear_${name}` })).asset;
  const pw = worldOf(g.id);
  const inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: asset.id, parentId: g.id, name: `${name}_img`, x: WORLD.x - pw.x, y: WORLD.y - pw.y } } });
  await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: WORLD.x - pw.x, 14: WORLD.y - pw.y, 16: S * 100, 17: S * 100, 18: 100 } } });
  file.layersV2[name] = { asset: asset.id, instance: inst.imageId, group: GROUP[name], groupId: g.id };
  console.log(`${name.padEnd(11)} -> ${GROUP[name]} (${inst.imageId})`);
}

// 4. порядок отрисовки
const front = async (list) => { for (const id of list.filter(Boolean)) await call('reorder_objects', { operations: [{ objectId: id, order: 'sendToFront' }] }); };
const gid = (n) => byName.get(n)?.id;
await front(['body', 'body_base', 'leg_right', 'leg_left', 'outfit_feet', 'forearm_right', 'forearm_left', 'outfit_body', 'head'].map(gid));
const LV = file.layersV2;
await front([gid('ear_left'), gid('ear_right'), LV.ears.instance, LV.face.instance, gid('outfit_head'), gid('ctrl_face')]);
file.layersV2Transform = { world: WORLD, scalePercent: +(S * 100).toFixed(3), source: 'handoff/layers_v2' };
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');

const r = await c.callTool('capture_artboard', { artboardId: board.id, longEdge: 1024 });
const img = (r.content ?? []).find((p) => p.type === 'image');
if (img) { const out = resolve(repoRoot, 'handoff', 'reference', 'editor_bear_v2.png'); writeFileSync(out, Buffer.from(img.data, 'base64')); console.log('снимок:', out); }
console.log('готово');
