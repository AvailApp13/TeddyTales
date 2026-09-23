import { readFileSync, writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S; const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = Object.values(state)[0];
const parts = file.parts; const boardId = file.artboards.Bear_Boy.id;
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const byName = new Map(); const parentOf = new Map();
for (const o of hier.objects ?? []) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const gid = (n) => byName.get(n).id;
// 1. капюшон: по высоте от острия (y=6) до низа обода (0.617U)
const U = 760, GY = 985; const hood = parts.outfit_head; const BB = JSON.parse(readFileSync(`${S}/solo_bbox.json`, 'utf8')).outfit_head;
{ // bbox измерен при 15%; пересчёт от текущего состояния: центр картинки hood.world, масштаб hood.scalePercent
  const k15 = hood.scalePercent / 15; const b = BB.map((v, i) => i % 2 === 0 ? hood.world.x + (v - (BB[0] + BB[2]) / 2) * k15 + ((BB[0] + BB[2]) / 2 - hood.world.x) * k15 : v);
  // проще: пересчитываем заново от 15%-снимка
  const cur = { h: BB[3] - BB[1], cx: (BB[0] + BB[2]) / 2, cy: (BB[1] + BB[3]) / 2 };
  const tgt = { y0: 6, y1: GY - 0.617 * U, cx: 512 + 0.0061 * U }; tgt.h = tgt.y1 - tgt.y0; tgt.cy = (tgt.y0 + tgt.y1) / 2;
  const k = tgt.h / cur.h; const C15 = { x: 513.9, y: 388.7 }; // центр картинки при снимке 15%
  const Cn = { x: tgt.cx - (cur.cx - C15.x) * k, y: tgt.cy - (cur.cy - C15.y) * k }; const s = 15 * k;
  const vals = (await call('query_property_values', { propertyKeys: { [parentOf.get(hood.instance)]: [13, 14], [gid('head')]: [13, 14], [gid('rig')]: [13, 14] } })).values;
  const pw = { x: 0, y: 0 }; let cur2 = parentOf.get(hood.instance); while (cur2 && cur2 !== boardId) { pw.x += vals[cur2]?.['13'] ?? 0; pw.y += vals[cur2]?.['14'] ?? 0; cur2 = parentOf.get(cur2); }
  await call('set_property_values', { propertyValues: { [hood.instance]: { 13: Cn.x - pw.x, 14: Cn.y - pw.y, 16: s, 17: s } } });
  Object.assign(hood, { scalePercent: +s.toFixed(2), world: { x: +Cn.x.toFixed(1), y: +Cn.y.toFixed(1) } });
  console.log(`капюшон: ${s.toFixed(1)}% центр ${Cn.x.toFixed(0)},${Cn.y.toFixed(0)}`);
}
// 2. порядок отрисовки: sendToFront от заднего к переднему
const front = async (ids) => { for (const id of ids) await call('reorder_objects', { operations: [{ objectId: id, order: 'sendToFront' }] }); };
await front([gid('body'), gid('leg_right'), gid('leg_left'), gid('outfit_feet'), gid('forearm_right'), gid('forearm_left'), gid('outfit_body'), gid('head')]);
await front([parts.ears.instance, gid('outfit_head'), parts.head.instance, gid('ctrl_face')]);
console.log('порядок задан');
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: boardId, longEdge: 1024 });
const img = (r.content ?? []).find(x => x.type === 'image'); if (img) writeFileSync(`${S}/editor_order.png`, Buffer.from(img.data, 'base64'));
console.log('готово');
