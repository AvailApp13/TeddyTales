#!/usr/bin/env node
/**
 * Кости ушей (D20): root_ear_left / root_ear_right — изгиб уха без жёсткого поворота.
 * Запускать в позе покоя:
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/ear_bones.mjs
 * затем картинки ушей (replace_layers.mjs ear_left ear_right) и сетки (skin_layers.mjs ear_left ear_right).
 *
 * MCP не создаёт кости, поэтому кость получается копией root_leg_left: копия
 * (с копией ноги внутри) -> потомки удаляются -> имя -> группа rig (мировые
 * координаты артборда) -> ось, угол, длина по handoff/layers_v2/layers.json →
 * ear_pivots (ось — середина стыка уха с капюшоном, под капюшоном; кончик — край
 * уха) -> перенос в группу ear_<сторона> под головой (мировое положение
 * сохраняется, кость идёт с головой).
 * Id — rive/editor_state.json → bones.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const T = file.layersV2Transform; const S = T.scalePercent / 100;
const [W, H] = meta.size;
const art = ([x, y]) => [T.world.x + (x - W / 2) * S, T.world.y + (y - H / 2) * S];   // кадр слоёв -> артборд
const save = () => writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');

const find = async () => (await call('find_objects', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
let objs = await find();
const idOf = (name, type) => objs.find((o) => o.name === name && (!type || o.type === type))?.id;
const rigId = idOf('rig', 'Node');

for (const side of ['left', 'right']) {
  const name = `root_ear_${side}`; const group = idOf(`ear_${side}`, 'Node');
  const P = meta.ear_pivots[`ear_${side}`];
  let bone = objs.some((o) => o.id === file.bones[name]) ? file.bones[name] : idOf(name, 'RootBone');
  if (!bone) {
    const before = new Set(objs.filter((o) => o.type === 'RootBone').map((o) => o.id));
    await call('duplicate_objects', { objectIds: [file.bones.root_leg_left] });
    objs = await find();
    bone = objs.find((o) => o.type === 'RootBone' && !before.has(o.id))?.id;
    if (!bone) throw new Error(`${name}: копия кости не появилась`);
    const kids = (await call('query_objects', { objectIds: [bone] })).objects.filter((o) => o.id !== bone).map((o) => o.id);
    if (kids.length) await call('delete_objects', { objectIds: kids });   // копия ноги
    await call('rename_objects', { renames: [{ id: bone, name }] });
    file.bones[name] = bone; save();
    console.log(`${name}: создана ${bone}`);
  }
  // ось и направление — в rig (артборд), затем в группу уха
  await call('reparent_objects', { operations: [{ objectId: bone, newParentId: rigId, position: 'end' }] });
  const [x0, y0] = art(P.pivot), [x1, y1] = art(P.tip);
  const rot = (Math.atan2(y1 - y0, x1 - x0) * 180) / Math.PI, len = Math.hypot(x1 - x0, y1 - y0);
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [bone]: { 90: x0, 91: y0, 15: rot, 89: len, 16: 1, 17: 1 } } });
    const v = (await call('query_property_values', { propertyKeys: { [bone]: [90, 91, 15, 89] } })).values?.[bone] ?? {};
    if (Math.abs(v['90'] - x0) < 1e-2 && Math.abs(v['91'] - y0) < 1e-2 && Math.abs(v['89'] - len) < 1e-2) break;
    if (t >= 5) throw new Error(`${name}: положение не записывается`);
  }
  for (let t = 0; ; t++) {
    const rr = await call('reparent_objects', { operations: [{ objectId: bone, newParentId: group, position: 'end' }] });
    if ((rr.reparented ?? []).some((o) => o.id === bone)) break;
    if (t >= 8) throw new Error(`${name}: не переносится в ear_${side}`);
    await new Promise((r) => setTimeout(r, 1500 * (1 + (t >> 1))));
  }
  console.log(`${name}: ось (${x0.toFixed(1)}, ${y0.toFixed(1)}), ${rot.toFixed(1)}°, длина ${len.toFixed(1)} -> ear_${side}`);
}
save();
