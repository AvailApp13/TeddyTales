import { readFileSync, writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S; const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = Object.values(state)[0]; const parts = file.parts; const boardId = file.artboards.Bear_Boy.id;
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const byName = new Map(); const parentOf = new Map();
for (const o of hier.objects ?? []) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const chainIds = new Set(); for (const o of hier.objects ?? []) { let cur = o.id; while (cur && cur !== boardId) { chainIds.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of chainIds) keys[id] = [13, 14]; const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const worldOf = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== boardId) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };
const PARENT = { p_hood: 'outfit_head', p_face: 'head', p_ears: 'head', p_shirt: 'outfit_body', p_paw_left: 'forearm_left', p_paw_right: 'forearm_right', p_foot_left: 'leg_left', p_foot_right: 'leg_right' };
const WORLD = { x: 518, y: 494 }, SCALE = 93.25;
file.photoLayers ??= {};
for (const [name, parentName] of Object.entries(PARENT)) {
  if (file.photoLayers[name]) { console.log(name, 'уже есть'); continue; }
  const b64 = readFileSync(`${S}/photo_layers/${name}.png`).toString('base64');
  const up = await call('upload_asset', { file: `data:image/png;name=${name}.png;base64,${b64}`, name });
  const parent = byName.get(parentName); const pw = worldOf(parent.id);
  const inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: up.asset.id, parentId: parent.id, name: `${name}_img`, x: WORLD.x - pw.x, y: WORLD.y - pw.y } } });
  await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: WORLD.x - pw.x, 14: WORLD.y - pw.y, 16: SCALE, 17: SCALE } } });
  await call('reorder_objects', { operations: [{ objectId: inst.imageId, order: 'sendToFront' }] });
  file.photoLayers[name] = { asset: up.asset.id, instance: inst.imageId, parent: parent.id, world: WORLD, scalePercent: SCALE };
  console.log(name, '->', up.asset.id, inst.imageId, 'в', parentName);
}
// порядок групп: лицо/уши поверх капюшона? Нет: капюшон (фото) поверх лица, уши под капюшоном
// внутри head: p_ears(низ) < head AI < p_face < outfit_head(группа с p_hood) < ctrl_face
const front = async (ids) => { for (const id of ids) await call('reorder_objects', { operations: [{ objectId: id, order: 'sendToFront' }] }); };
await front([parts.ears.instance, file.photoLayers.p_ears.instance, parts.head.instance, file.photoLayers.p_face.instance, byName.get('outfit_head').id, byName.get('ctrl_face').id]);
// AI-слои, которые перекрываются фото: спрятать
const hide = ['outfit_head', 'ears', 'outfit_body', 'arm_left', 'arm_right', 'leg_left', 'leg_right'];
const pv = {}; for (const n of hide) { pv[parts[n].instance] = { 18: 0 }; parts[n].hidden = true; }
await call('set_property_values', { propertyValues: pv });
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: boardId, longEdge: 1024 });
const img = (r.content ?? []).find(x => x.type === 'image'); if (img) writeFileSync(`${S}/editor_v3.png`, Buffer.from(img.data, 'base64'));
console.log('готово');
