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
 * Амплитуды после обратной связи: голова до 8°, лапы до 40°, в шаге лапки только наружу.
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
// наклон головы на глаз (итоговый, до ±6°). Голова не качается одна: корпус от
// таза с задержкой LAG кадров берёт LEAN наклона (толстовка, плечи, руки идут с
// ним), голова относительно тела — остальное. Так голова не выглядит приставленной,
// а капюшон относительно плеч поворачивается меньше — из-под него ничего не лезет.
const headLook = { 0: 0, 20: 6, 45: -6, 70: 6, 95: -6, 120: 0, 170: -4, 230: 4, 300: 0,
  330: 3, 360: -3, 390: 3, 420: -3, 450: 3, 480: 0, 505: 6, 525: 6, 550: -6, 570: -6, 590: 0, 600: 0 };
const LEAN = 0.4, HEAD = 0.65, LAG = 5;
const scale = (k, m, lag = 0) => Object.fromEntries(Object.entries(k).map(([f, d]) => [+f === 0 || +f === END ? +f : Math.min(END, +f + lag), d * m]));
const head = scale(headLook, HEAD);
const lean = scale(headLook, LEAN, LAG);
// значение дорожки в кадре f (линейно между ключами — для сложения дорожек)
const at = (k, f) => { const e = Object.entries(k).map(([a, b]) => [+a, b]).sort((x, y) => x[0] - y[0]);
  for (let i = 1; i < e.length; i++) if (f <= e[i][0]) return e[i - 1][1] + (e[i][1] - e[i - 1][1]) * (f - e[i - 1][0]) / (e[i][0] - e[i - 1][0]); return e.at(-1)[1]; };
// ноги — дети root: поворот корпуса вычитается, чтобы стопы стояли на месте
const minusLean = (leg) => Object.fromEntries([...new Set([...Object.keys(leg), ...Object.keys(lean)].map(Number))].sort((a, b) => a - b).map((f) => [f, at(leg, f) - at(lean, f)]));
const march = (a, b) => { const k = {}; for (let f = 320, i = 0; f <= 460; f += 20, i++) k[f] = i % 2 ? b : a; return k; };
// лапки качаются только наружу (0…12°): внутрь рукав уходил под капюшон с клином
const armL = { 0: 0, 120: 0, 155: 32, 175: 20, 195: 36, 215: 20, 235: 32, 265: 0, 300: 0, ...march(12, 0), 480: 0, 510: 40, 560: 40, 595: 0, 600: 0 };
const armR = { 0: 0, 150: 0, 185: -32, 205: -20, 225: -36, 245: -20, 265: -32, 295: 0, 300: 0, ...march(0, -12), 480: 0, 510: -40, 560: -40, 595: 0, 600: 0 };
const legL = minusLean({ 0: 0, 300: 0, ...march(10, -3), 480: 0, 600: 0 });
const legR = minusLean({ 0: 0, 300: 0, ...march(3, -10), 480: 0, 600: 0 });
const bounce = { 0: 0, 300: 0 };                         // смещение root вверх, px
for (let f = 310; f < 480; f += 20) { bounce[f] = -7; bounce[f + 10] = 0; }
Object.assign(bounce, { 480: 0, 505: -14, 525: 0, 540: -8, 555: 0, 600: 0 });

// ---- база: поза покоя ----
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [15, 91], [B.root_body]: [15], [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15] } })).values;
const tracks = [
  [B.root_body, 15, head], [B.root_arm_left, 15, armL], [B.root_arm_right, 15, armR],
  [B.root_leg_left, 15, legL], [B.root_leg_right, 15, legR], [B.root, 91, bounce], [B.root, 15, lean],
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
const old = await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: [anim.id] } } }).catch(() => null);
const oldIds = (old?.keyframes?.[anim.id] ?? []).map((k) => k.keyframeId);
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
