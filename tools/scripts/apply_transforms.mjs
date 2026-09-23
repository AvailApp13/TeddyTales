import { readFileSync, writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S; const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = Object.values(state)[0]; const parts = file.parts; const boardId = file.artboards.Bear_Boy.id;
const NEW = JSON.parse(readFileSync(`${S}/${process.argv[2] ?? 'new_transforms.json'}`, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const parentOf = new Map(); for (const o of hier.objects ?? []) for (const ch of o.children ?? []) parentOf.set(ch, o.id);
const chain = new Set(); for (const p of Object.values(parts)) { let cur = parentOf.get(p.instance); while (cur && cur !== boardId) { chain.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of chain) keys[id] = [13, 14]; const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const worldOf = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== boardId) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };
const pv = {};
for (const [name, t] of Object.entries(NEW)) { const p = parts[name]; if (!p) continue; const pw = worldOf(parentOf.get(p.instance));
  pv[p.instance] = { 13: t.cx - pw.x, 14: t.cy - pw.y, 16: t.sx, 17: t.sy };
  Object.assign(p, { scalePercent: +t.sx.toFixed(2), scaleY: +t.sy.toFixed(2), world: { x: +t.cx.toFixed(1), y: +t.cy.toFixed(1) } }); }
await call('set_property_values', { propertyValues: pv });
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: boardId, longEdge: 1024 });
const img = (r.content ?? []).find(x => x.type === 'image'); if (img) writeFileSync(`${S}/${process.argv[3] ?? 'editor_v2.png'}`, Buffer.from(img.data, 'base64'));
console.log('применено', Object.keys(pv).length);
