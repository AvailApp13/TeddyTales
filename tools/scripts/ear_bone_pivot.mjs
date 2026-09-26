#!/usr/bin/env node
/**
 * Ставит начало костей ушей root_ear_left/right на ось уха: ear_pivots.swing — в голове,
 * от центра круга уха к лицу (D26, ear_swing.py), без неё — ear_pivots.pivot, середина стыка
 * с капюшоном (D20, D25). reparent_objects в
 * редакторе сдвигал кость при переносе в группу уха — начало стояло на 34–37 px наружу, в
 * теле уха: ухо поворачивалось вокруг точки в себе, край у капюшона уходил, полоса у
 * капюшона оставалась — залом («крючок») у нижнего конца стыка.
 *
 * Кость переносится вместе с её привязкой (тенданы сеток: положение при привязке), поэтому в
 * покое ничего не сдвигается; меняется только ось поворота. Ключей положения у костей ушей нет.
 *
 *   RIVE_MCP_URL=... node scripts/ear_bone_pivot.mjs
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { restWorld, toLocal } from '../lib/rest_pose.mjs';

const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const state = JSON.parse(readFileSync(resolve(repoRoot, 'rive', 'editor_state.json'), 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const T = file.layersV2Transform; const S = T.scalePercent / 100; const [W, H] = meta.size;
const art = ([x, y]) => [T.world.x + (x - W / 2) * S, T.world.y + (y - H / 2) * S];
const h = (await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
const parentOf = {}; for (const o of h) for (const ch of o.children ?? []) parentOf[typeof ch === 'string' ? ch : ch.id] = o.id;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

for (const side of ['left', 'right']) {
  const bone = file.bones[`root_ear_${side}`]; const G = await restWorld(call, file, parentOf[bone]);
  const E = meta.ear_pivots[`ear_${side}`]; const P = art(E.swing ?? E.pivot); const [lx, ly] = toLocal(G, P);   // ось D26 (ear_swing.py), иначе D20
  // тенданы этой кости во всех сетках — мировое положение при привязке переезжает на ось
  const tendons = [];
  for (const s of Object.values(file.skins)) {
    const skin = ((await call('query_objects', { objectIds: [s.meshId] })).objects ?? []).find((o) => o.types[0] === 'Skin'); if (!skin) continue;
    const v = (await call('query_property_values', { propertyKeys: Object.fromEntries(skin.children.map((t) => [t, [95, 100, 101]])) })).values;
    for (const [t, x] of Object.entries(v)) if (x['95'] === bone) tendons.push([t, x]);
  }
  const was = (await call('query_property_values', { propertyKeys: { [bone]: [90, 91] } })).values[bone];
  const wx = G[0] * was['90'] + G[2] * was['91'] + G[4], wy = G[1] * was['90'] + G[3] * was['91'] + G[5];
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [bone]: { 90: lx, 91: ly }, ...Object.fromEntries(tendons.map(([id]) => [id, { 100: P[0], 101: P[1] }])) } });
    await sleep(400 * (t + 1));
    const v = (await call('query_property_values', { propertyKeys: { [bone]: [90, 91], ...Object.fromEntries(tendons.map(([id]) => [id, [100, 101]])) } })).values;
    if (Math.abs(v[bone]['90'] - lx) < 1e-3 && Math.abs(v[bone]['91'] - ly) < 1e-3
      && tendons.every(([id]) => Math.abs(v[id]['100'] - P[0]) < 1e-3 && Math.abs(v[id]['101'] - P[1]) < 1e-3)) break;
    if (t >= 5) throw new Error(`root_ear_${side}: запись не держится ${JSON.stringify(v)}`);
  }
  console.log(`root_ear_${side}: начало (${wx.toFixed(2)}, ${wy.toFixed(2)}) -> ось (${P[0].toFixed(2)}, ${P[1].toFixed(2)}), сдвиг ${Math.hypot(P[0] - wx, P[1] - wy).toFixed(1)} px; тенданов ${tendons.length}`);
}
