import { readFileSync, writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S; const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = Object.values(state)[0];
const parts = file.parts; const boardId = file.artboards.Bear_Boy.id;
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const parentOf = new Map(); for (const o of hier.objects ?? []) for (const ch of o.children ?? []) parentOf.set(ch, o.id);
const worldOf = async (id) => { const chain = []; let cur = id; while (cur && cur !== boardId) { chain.push(cur); cur = parentOf.get(cur); } const keys = {}; for (const c2 of chain) keys[c2] = [13, 14]; const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {}; let x = 0, y = 0; for (const c2 of chain) { x += vals[c2]?.['13'] ?? 0; y += vals[c2]?.['14'] ?? 0; } return { x, y }; };
const BB = JSON.parse(readFileSync(`${S}/solo_bbox.json`, 'utf8')); const C15 = { x: 513.9, y: 388.7 }; const U = 760, GY = 985;
const pv = {};
// лицо: пока прячем — на голове уже есть глаза, вторая пара двоится
pv[parts.face_features.instance] = { 18: 0 }; parts.face_features.hidden = true;
// шорты: ширина 0.454U, низ на 0.078U над землёй (как на фото), верх уходит под толстовку
{ const b = BB.outfit_feet; const k = (0.454 * U) / (b[2] - b[0]); const s = 15 * k;
  const Cn = { x: 512 + 0.0184 * U - ((b[0] + b[2]) / 2 - C15.x) * k, y: (GY - 0.078 * U) - (b[3] - C15.y) * k };
  const pw = await worldOf(parentOf.get(parts.outfit_feet.instance));
  pv[parts.outfit_feet.instance] = { 13: Cn.x - pw.x, 14: Cn.y - pw.y, 16: s, 17: s };
  Object.assign(parts.outfit_feet, { scalePercent: +s.toFixed(2), world: { x: +Cn.x.toFixed(1), y: +Cn.y.toFixed(1) } });
  console.log(`шорты ${s.toFixed(1)}% центр ${Cn.x.toFixed(0)},${Cn.y.toFixed(0)}`); }
await call('set_property_values', { propertyValues: pv });
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: boardId, longEdge: 1024 });
const img = (r.content ?? []).find(x => x.type === 'image'); if (img) writeFileSync(`${S}/editor_tweak.png`, Buffer.from(img.data, 'base64'));
console.log('готово');
