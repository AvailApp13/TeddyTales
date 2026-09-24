#!/usr/bin/env node
/**
 * Демо-сценарий движений мишки для просмотра в Rive (не клип из каталога КП).
 * Пишет ключи в таймлайн «demo_moves» открытого файла через MCP; если в файле
 * есть нетронутый «Timeline 1», он переименовывается — тогда State Machine 1
 * сразу играет сценарий при нажатии Play.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/demo_moves.mjs
 *
 * 10 с, 60 fps, по кругу:
 *   0–2 с   качает головой (наклоны влево-вправо)
 *   2–5 с   поднимает левую лапу и машет, потом правую
 *   5–8 с   шагает на месте: ножки по очереди, тело подпрыгивает, лапки качаются
 *   8–10 с  «ура»: обе лапы вверх, подпрыгивает, крутит головой, возвращается в покой
 * Углы — поворот костей относительно позы покоя, в градусах; + по часовой.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const NAME = 'demo_moves', FPS = 60, END = 600;
const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => {
  for (let i = 0; i < 6; i++) {
    try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 400)}`); return r; }
    catch (e) { if (!/ENOTFOUND|DNS|пустой ответ/.test(e.message)) throw e; await new Promise((r) => setTimeout(r, 8000)); }
  }
  throw new Error(`${t}: нет связи`);
};
const info = await call('session_info', {});
const file = state[String(info.activeFileId)];
const B = file.bones;

// ---- дельты (кадр: градусы) ----
const head = { 0: 0, 20: 8, 45: -8, 70: 8, 95: -8, 120: 0, 170: -4, 230: 4, 300: 0,
  330: 3, 360: -3, 390: 3, 420: -3, 450: 3, 480: 0, 505: 12, 525: 12, 550: -12, 570: -12, 590: 0, 600: 0 };
const march = (a, b) => { const k = {}; for (let f = 320, i = 0; f <= 460; f += 20, i++) k[f] = i % 2 ? b : a; return k; };
const armL = { 0: 0, 120: 0, 155: 35, 175: 22, 195: 40, 215: 22, 235: 35, 265: 0, 300: 0, ...march(12, -12), 480: 0, 510: 50, 560: 50, 595: 0, 600: 0 };
const armR = { 0: 0, 150: 0, 185: -35, 205: -22, 225: -40, 245: -22, 265: -35, 295: 0, 300: 0, ...march(12, -12), 480: 0, 510: -50, 560: -50, 595: 0, 600: 0 };
const legL = { 0: 0, 300: 0, ...march(10, -3), 480: 0, 600: 0 };
const legR = { 0: 0, 300: 0, ...march(3, -10), 480: 0, 600: 0 };
const bounce = { 0: 0, 300: 0 };                         // смещение root вверх, px
for (let f = 310; f < 480; f += 20) { bounce[f] = -7; bounce[f + 10] = 0; }
Object.assign(bounce, { 480: 0, 505: -14, 525: 0, 540: -8, 555: 0, 600: 0 });

// ---- база: поза покоя ----
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [91], [B.root_body]: [15], [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15] } })).values;
const tracks = [
  [B.root_body, 15, head], [B.root_arm_left, 15, armL], [B.root_arm_right, 15, armR],
  [B.root_leg_left, 15, legL], [B.root_leg_right, 15, legR], [B.root, 91, bounce],
];

// ---- таймлайн ----
const list = (await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? [];
let anim = list.find((a) => a.name === NAME);
if (!anim) {
  const pristine = list.find((a) => /^Timeline( 1)?$/.test(a.name));
  if (pristine) { await call('animation_editor', { command: 'renameAnimations', data: { renameAnimations: { animations: [{ animationId: pristine.id, name: NAME }] } } }); anim = { ...pristine, name: NAME }; }
  else { await call('animation_editor', { command: 'createLinearAnimations', data: { createLinearAnimations: { linearAnimations: [{ name: NAME, duration: END }] } } });
    anim = ((await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? []).find((a) => a.name === NAME); }
}
await call('set_property_values', { propertyValues: { [anim.id]: { 56: FPS, 57: END, 59: 1 } } });   // fps, длительность, loop

// старые ключи этого таймлайна — удалить (скрипт можно запускать повторно)
const old = await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationId: anim.id } } }).catch(() => null);
const oldIds = JSON.stringify(old ?? {}).match(/"(?:keyframeId|id)":"(\d+-\d+)"/g)?.map((s) => s.split('"')[3]).filter((id) => id !== anim.id) ?? [];
if (oldIds.length) await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, delete: oldIds } } }).catch((e) => console.log('удаление ключей:', e.message));

const ease = { x1: 0.42, y1: 0, x2: 0.58, y2: 1 };
const add = [];
for (const [id, key, frames] of tracks) {
  const b = base[id][String(key)];
  for (const [f, d] of Object.entries(frames).sort((x, y) => +x[0] - +y[0]))
    add.push({ objectId: id, propertyKey: key, frame: +f, value: b + d, interpolationType: 'cubic', cubicParams: ease });
}
for (let i = 0; i < add.length; i += 60)
  await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, add: add.slice(i, i + 60) } } });
console.log(`таймлайн ${NAME} (${anim.id}): ${END / FPS} с, ${add.length} ключей на ${tracks.length} дорожках, по кругу`);

// State Machine: Entry -> demo_moves (у дефолтной машины состояние уже указывает на этот таймлайн)
const sm = await call('animation_editor', { command: 'queryStateMachine', data: {} });
const states = JSON.stringify(sm).match(/"animationName":"[^"]*"/g) ?? [];
console.log('состояния машины:', [...new Set(states)].join(', ') || JSON.stringify(sm).slice(0, 300));
file.demoMoves = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: add.length };
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
