#!/usr/bin/env node
/**
 * Кости ушей (D20, D24): root_ear_left / root_ear_right — ухо рига; и по кости на каждое
 * нарисованное положение уха (root_ear_<сторона>_<состояние>, layers.json → ear_states):
 * переход — поворот и масштаб костей навстречу друг другу со сменой картинок.
 * Запускать в позе покоя:
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/ear_bones.mjs
 * затем картинки ушей (replace_layers.mjs) и сетки (skin_layers.mjs) — для всех слоёв ушей.
 *
 * Кость — lib/bones.mjs (копия root_leg_left: MCP костей не создаёт). Ось и кончик —
 * handoff/layers_v2/layers.json → ear_pivots (ось — середина стыка уха с капюшоном,
 * под капюшоном; кончик — край уха); кость лежит в группе ear_<сторона> под
 * головой и идёт с головой.
 * Повторный запуск переставляет кости; после него — replace_layers.mjs и
 * skin_layers.mjs для ушей (привязка сетки запоминает кость в момент привязки).
 * Id — rive/editor_state.json → bones.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { ensureBone } from '../lib/bones.mjs';

const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const T = file.layersV2Transform; const S = T.scalePercent / 100;
const [W, H] = meta.size;
const art = ([x, y]) => [T.world.x + (x - W / 2) * S, T.world.y + (y - H / 2) * S];   // кадр слоёв -> артборд
const save = () => writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
const objs = (await call('find_objects', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];

for (const side of ['left', 'right']) {
  const P = meta.ear_pivots[`ear_${side}`];
  const groupId = objs.find((o) => o.name === `ear_${side}` && o.type === 'Node')?.id;
  // начало кости — на линии сгиба (D22): масштаб кости вдоль оси загибает ухо на
  // зрителя; направление то же, что от оси к краю уха (D20), — ключи поворота прежние
  for (const st of ['', ...Object.keys(meta.ear_states ?? {})])   // '' — ухо рига
    await ensureBone(call, file, save, { name: `root_ear_${side}${st && '_' + st}`, groupId, from: art(P.pivot), to: art(P.tip) });
}
save();
