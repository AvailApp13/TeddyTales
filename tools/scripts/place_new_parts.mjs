import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S; const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = state['2604781']; const boardId = file.artboards.Bear_Boy.id;
const K = 2336 / 1333; // старые трансформы считались для 2336×3504, файлы из чата 1333×2000
const T = { // scale% (x,y) и мировой центр — из подгонки в старом файле
  arm_left: { sx: 9.3, sy: 9.3, x: 296, y: 633, parent: 'forearm_left' }, arm_right: { sx: 8.2, sy: 8.2, x: 734, y: 634, parent: 'forearm_right' },
  body: { sx: 18.22, sy: 18.22, x: 517.6, y: 644.8, parent: 'body' }, ears: { sx: 27.43, sy: 22.35, x: 514.3, y: 357.9, parent: 'head' },
  face_features: { sx: 21.52, sy: 21.52, x: 509.5, y: 435.6, parent: 'ctrl_face' }, head: { sx: 23.03, sy: 23.03, x: 510.8, y: 371.3, parent: 'head' },
  leg_left: { sx: 14.77, sy: 14.77, x: 371.1, y: 785.7, parent: 'leg_left' }, leg_right: { sx: 12.61, sy: 12.61, x: 657.3, y: 812.1, parent: 'leg_right' },
  outfit_head: { sx: 24.61, sy: 23.4, x: 507.6, y: 300.9, parent: 'outfit_head' }, outfit_body: { sx: 28.08, sy: 20.55, x: 514.3, y: 593, parent: 'outfit_body' },
  outfit_feet: { sx: 25.3, sy: 14.33, x: 526.4, y: 740.2, parent: 'outfit_feet' } };
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const byName = new Map(); const parentOf = new Map();
for (const o of hier.objects ?? []) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const ids = new Set(); for (const o of hier.objects ?? []) { let cur = o.id; while (cur && cur !== boardId) { ids.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of ids) keys[id] = [13, 14]; const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const worldOf = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== boardId) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };
file.parts ??= {};
for (const [name, t] of Object.entries(T)) {
  const f = `${S}/new_parts/${name}.png`; if (!existsSync(f) || file.parts[name]) continue;
  const asset = (await call('upload_asset', { file: `data:image/png;name=${name}.png;base64,${readFileSync(f).toString('base64')}`, name })).asset;
  const parent = byName.get(t.parent); const pw = worldOf(parent.id);
  const inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: asset.id, parentId: parent.id, name: `${name}_img`, x: t.x - pw.x, y: t.y - pw.y } } });
  await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: t.x - pw.x, 14: t.y - pw.y, 16: t.sx * K, 17: t.sy * K, 18: 0 } } });
  await call('reorder_objects', { operations: [{ objectId: inst.imageId, order: 'sendToBack' }] });
  file.parts[name] = { asset: asset.id, instance: inst.imageId, parent: parent.id, sizePx: [asset.width, asset.height], scalePercent: +(t.sx * K).toFixed(2), scaleY: +(t.sy * K).toFixed(2), world: { x: t.x, y: t.y }, hidden: true, role: 'запас под скрытые зоны' };
  console.log(name, '->', asset.id, inst.imageId, `${asset.width}x${asset.height}`);
}
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n'); console.log('готово');
