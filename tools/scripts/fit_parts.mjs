import { readFileSync, writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S;
const statePath = '/home/user/TeddyTales/rive/editor_state.json';
const state = JSON.parse(readFileSync(statePath, 'utf8')); const file = Object.values(state)[0];
const parts = file.parts; const boardId = file.artboards.Bear_Boy.id;
const P = JSON.parse(readFileSync('/home/user/TeddyTales/rig/bear_proportions.json', 'utf8')).parts;
const U = 760, AX = 512, GY = 985;
const X = (x) => AX + x * U, Y = (y) => GY - y * U;
// целевые рамки [x0,y0,x1,y1] в артборде и по чему подгонять: 'w' | 'h'
const e = (p) => [X(p.x - p.w / 2), Y(p.y + p.h / 2), X(p.x + p.w / 2), Y(p.y - p.h / 2)];
const T = {
  head: [e(P.head), 'w'],
  ears: [[X(P.ear_left.x - P.ear_left.w / 2), Y(P.ear_left.y + P.ear_left.h / 2), X(P.ear_right.x + P.ear_right.w / 2), Y(P.ear_left.y - P.ear_left.h / 2)], 'w'],
  face_features: [[X(P.eye_left.x - P.eye_left.w / 2), Y(P.eye_left.y + P.eye_left.h / 2), X(P.eye_right.x + P.eye_right.w / 2), Y(P.mouth.y - P.mouth.h / 2)], 'w'],
  outfit_head: [e(P['outfit_head (капюшон)']), 'h'],
  outfit_body: [e(P['outfit_body (толстовка)']), 'w'],
  body: [[X(P.body.x - P.body.w / 2), Y(0.615), X(P.body.x + P.body.w / 2), Y(0.11)], 'h'],
  arm_left: [[X(P.hand_left.x - P.hand_left.w / 2), Y(P.shoulder_left.y + 0.07), X(P.shoulder_left.x + 0.06), Y(P.hand_left.y - P.hand_left.h / 2)], 'h'],
  arm_right: [[X(P.shoulder_right.x - 0.06), Y(P.shoulder_right.y + 0.07), X(P.hand_right.x + P.hand_right.w / 2), Y(P.hand_right.y - P.hand_right.h / 2)], 'h'],
  leg_left: [[X(P.foot_left.x - P.foot_left.w / 2), Y(P.hip_left.y + 0.08), X(P.foot_left.x + P.foot_left.w / 2), Y(0)], 'h'],
  leg_right: [[X(P.foot_right.x - P.foot_right.w / 2), Y(P.hip_right.y + 0.08), X(P.foot_right.x + P.foot_right.w / 2), Y(0)], 'h'],
  outfit_feet: [e(P['outfit_feet (шорты)']), 'w'],
};
const BB = JSON.parse(readFileSync(`${S}/solo_bbox.json`, 'utf8'));
const bbox = (name) => BB[name];
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(JSON.stringify(r)); return r; } catch (err) { if (!/ENOTFOUND|DNS/.test(err.message)) throw err; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
// мировые координаты родителей
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const parentOf = new Map(); for (const o of hier.objects ?? []) for (const ch of o.children ?? []) parentOf.set(ch, o.id);
const chain = new Set(); for (const p of Object.values(parts)) { let cur = parentOf.get(p.instance); while (cur && cur !== boardId) { chain.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of chain) keys[id] = [13, 14];
const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const worldOf = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== boardId) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };
const pv = {};
for (const [name, p] of Object.entries(parts)) {
  const [t, by] = T[name]; const b = bbox(name);
  const cur = { w: b[2] - b[0], h: b[3] - b[1], cx: (b[0] + b[2]) / 2, cy: (b[1] + b[3]) / 2 };
  const tgt = { w: t[2] - t[0], h: t[3] - t[1], cx: (t[0] + t[2]) / 2, cy: (t[1] + t[3]) / 2 };
  const k = by === 'w' ? tgt.w / cur.w : tgt.h / cur.h;
  const C = p.world; // текущий мировой центр картинки
  const Cn = { x: tgt.cx - (cur.cx - C.x) * k, y: tgt.cy - (cur.cy - C.y) * k };
  const s = p.scalePercent * k; const pw = worldOf(parentOf.get(p.instance));
  pv[p.instance] = { 13: Cn.x - pw.x, 14: Cn.y - pw.y, 16: s, 17: s };
  Object.assign(p, { scalePercent: +s.toFixed(2), world: { x: +Cn.x.toFixed(1), y: +Cn.y.toFixed(1) }, fitted: true });
  console.log(name.padEnd(14), `было ${cur.w.toFixed(0)}x${cur.h.toFixed(0)} @${cur.cx.toFixed(0)},${cur.cy.toFixed(0)}  цель ${tgt.w.toFixed(0)}x${tgt.h.toFixed(0)} @${tgt.cx.toFixed(0)},${tgt.cy.toFixed(0)}  k=${k.toFixed(2)} -> ${s.toFixed(1)}%`);
}
await call('set_property_values', { propertyValues: pv });
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const r = await c.callTool('capture_artboard', { artboardId: boardId, longEdge: 1024 });
const img = (r.content ?? []).find(x => x.type === 'image'); if (img) writeFileSync(`${S}/editor_fit.png`, Buffer.from(img.data, 'base64'));
console.log('готово');
