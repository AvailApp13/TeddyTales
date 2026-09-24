#!/usr/bin/env node
/**
 * Кость живота (D21): root_belly — дыхание животом, а не всем телом.
 * Запускать в позе покоя:
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/belly_bone.mjs
 * затем сетка корпуса толстовки: skin_layers.mjs shirt.
 *
 * Начало кости — центр живота (handoff/layers_v2/weight_fields.json → belly, считает
 * weight_fields.py), направление — вправо: масштаб кости по X — ширина живота, по Y —
 * высота. Кость лежит в группе body (на кости root) и идёт с корпусом.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { ensureBone } from '../lib/bones.mjs';

const L = resolve(repoRoot, 'handoff', 'layers_v2');
const meta = JSON.parse(readFileSync(resolve(L, 'layers.json'), 'utf8'));
const F = JSON.parse(readFileSync(resolve(L, 'weight_fields.json'), 'utf8'));
const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const T = file.layersV2Transform; const S = T.scalePercent / 100;
const [W, H] = meta.size;
const art = ([x, y]) => [T.world.x + (x - W / 2) * S, T.world.y + (y - H / 2) * S];   // кадр слоёв -> артборд
const save = () => writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
const objs = (await call('find_objects', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
const groupId = objs.find((o) => o.name === 'body' && o.type === 'Node')?.id;
if (!groupId) throw new Error('нет группы body');
const [bx, by] = F.belly;
await ensureBone(call, file, save, { name: 'root_belly', groupId, from: art([bx, by]), to: art([bx + 150, by]) });
save();
