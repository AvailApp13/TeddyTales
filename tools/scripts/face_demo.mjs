#!/usr/bin/env node
/**
 * Показ мимики: таймлайн face_demo — покой с морганием и взглядом, затем по очереди
 * все выражения (плавное появление 0.2 с, 1.5 с удержание), и каждое — со своим
 * движением тела: смех подпрыгивает и качает головой, при зевке тянет лапы,
 * при грусти голова опускается набок и т. д. Дыхание идёт всё время.
 * State Machine 1 переключается на этот таймлайн (demo_moves остаётся в файле).
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/face_demo.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const B = file.bones; const G = file.faceParts.groups; const IM = file.faceParts.images;
const NAME = 'face_demo', FPS = 60, FADE = 12, HOLD = 90, SEG = FADE + HOLD;

// ---- сценарий
const ORDER = ['smile', 'laugh', 'love', 'surprised', 'sad', 'upset', 'chew', 'lick', 'yawn', 'eyes_closed', 'squint'];
const START0 = 90;                                     // покой до первого выражения
const start = Object.fromEntries(ORDER.map((n, i) => [n, START0 + i * SEG]));
const END = START0 + ORDER.length * SEG + FADE + 108;
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const env = (u) => sm(0, FADE, u) * (1 - sm(SEG - 4, SEG + FADE - 4, u));   // вход и выход выражения
const S = Math.sin, PI2 = Math.PI * 2;
// движения тела по выражению: u — кадр от начала выражения; head — наклон головы на глаз
const MOVE = {
  smile: (u, e) => ({ head: 4 * e }),
  laugh: (u, e) => ({ head: 5 * S(PI2 * u / 22) * e, y: -6 * Math.abs(S(Math.PI * u / 12)) * e, arm: (20 + 5 * S(PI2 * u / 12)) * e }),
  love: (u, e) => ({ head: 8 * e, arm: 6 * e }),
  surprised: (u, e) => ({ head: -2 * e, y: -7 * sm(0, 8, u) * e, arm: 16 * sm(0, 8, u) * e }),
  sad: (u, e) => ({ head: -6 * e, y: 3 * e }),
  upset: (u, e) => ({ head: (-5 + 1.5 * S(PI2 * u / 10)) * e, y: 2.5 * e }),
  chew: (u, e) => ({ head: 2 * S(PI2 * u / 30) * e, y: 2 * S(PI2 * u / 14) * e }),
  lick: (u, e) => ({ head: 5 * e }),
  yawn: (u, e) => ({ head: -3 * e, y: -4 * e, arm: 36 * e }),
  eyes_closed: (u, e) => ({ head: 8 * e, y: 2 * e }),
  squint: (u, e) => ({ head: 3 * S(PI2 * u / 16) * e }),
};
function pose(f) {
  let head = 0, y = 1.2 * S(PI2 * f / 150), arm = 0;           // дыхание
  for (const n of ORDER) { const u = f - start[n]; if (u < 0 || u > SEG + FADE) continue;
    const m = MOVE[n](u, env(u)); head += m.head ?? 0; y += m.y ?? 0; arm += m.arm ?? 0; }
  return { head, y, arm };
}
// взгляд (бусины основы; работает, пока на глазах нет накладки выражения): смещение в px артборда
function gaze(f) {
  const look = (a, b, dx, dy) => { const k = sm(a, a + 8, f) * (1 - sm(b, b + 8, f)); return [dx * k, dy * k]; };
  const parts = [look(40, 75, -2.6, 0), look(1240, 1275, 2.6, 0.4),
    look(start.chew + 30, start.chew + 60, 2.2, 0), look(start.lick + 14, start.lick + 90, 0, -1.6)];
  return parts.reduce((s, [a, b]) => [s[0] + a, s[1] + b], [0, 0]);
}
// моргания: кадры начала (только когда глаза — бусины основы)
const BLINKS = [20, 70, start.smile + 55, start.chew + 75, END - 70];

// ---- дорожки
const LEAN = 0.4, HEADK = 0.65, LAG = 5;
const tracks = new Map();   // objectId:key -> Map(frame -> {value, interp})
const key = (id, k, f, v, interp = 'cubic') => { const t = `${id}:${k}`; if (!tracks.has(t)) tracks.set(t, new Map()); tracks.get(t).set(Math.round(f), { v, interp }); };
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [15, 91], [B.root_body]: [15], [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15],
  [IM.gaze_bead_l.instance]: [13, 14], [IM.gaze_bead_r.instance]: [13, 14] } })).values;
const b = (id, k) => base[id][String(k)];
for (let f = 0; f <= END; f += 6) {
  const p = pose(f), pl = pose(Math.max(0, f - LAG));
  const lean = LEAN * pl.head;
  key(B.root, 15, f, b(B.root, 15) + lean);
  key(B.root, 91, f, b(B.root, 91) + p.y);
  key(B.root_body, 15, f, b(B.root_body, 15) + HEADK * p.head);
  key(B.root_leg_left, 15, f, b(B.root_leg_left, 15) - lean);
  key(B.root_leg_right, 15, f, b(B.root_leg_right, 15) - lean);
  key(B.root_arm_left, 15, f, b(B.root_arm_left, 15) + p.arm);
  key(B.root_arm_right, 15, f, b(B.root_arm_right, 15) - p.arm);
  const [gx, gy] = gaze(f);
  for (const s of ['l', 'r']) { const id = IM[`gaze_bead_${s}`].instance; key(id, 13, f, b(id, 13) + gx); key(id, 14, f, b(id, 14) + gy); }
}
// прозрачность выражений
const op = (name, f, v) => key(G[`fx_${name}`], 18, f, v, 'linear');
for (const n of Object.keys(G).filter((g) => g.startsWith('fx_')).map((g) => g.slice(3))) { op(n, 0, 0); op(n, END, 0); }
for (const n of ORDER) { const s = start[n]; op(n, s, 0); op(n, s + FADE, 100); op(n, s + SEG - 4, 100); op(n, s + SEG + FADE - 4, 0); }
for (const f0 of BLINKS) {
  op('blink_half', f0, 0); op('blink_half', f0 + 2, 100); op('blink_half', f0 + 5, 100); op('blink_half', f0 + 8, 0);
  op('eyes_closed', f0 + 1, 0); op('eyes_closed', f0 + 3, 100); op('eyes_closed', f0 + 4, 100); op('eyes_closed', f0 + 6, 0);
}

// ---- таймлайн
const list = (await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? [];
let anim = list.find((a) => a.name === NAME);
if (!anim) {
  await call('animation_editor', { command: 'createLinearAnimations', data: { createLinearAnimations: { linearAnimations: [{ name: NAME, duration: END / FPS }] } } });
  anim = ((await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? []).find((a) => a.name === NAME);
}
await call('set_property_values', { propertyValues: { [anim.id]: { 56: FPS, 57: END, 59: 1 } } });
const old = await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: [anim.id] } } }).catch(() => null);
const oldIds = (old?.keyframes?.[anim.id] ?? []).map((k) => k.keyframeId);
for (let i = 0; i < oldIds.length; i += 200) await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, delete: oldIds.slice(i, i + 200) } } });
const ease = { x1: 0.42, y1: 0, x2: 0.58, y2: 1 };
const add = [];
for (const [t, frames] of tracks) {
  const [id, k] = t.split(':');
  for (const [f, { v, interp }] of [...frames].sort((x, y) => x[0] - y[0]))
    add.push({ objectId: id, propertyKey: +k, frame: f, value: v, interpolationType: interp, ...(interp === 'cubic' ? { cubicParams: ease } : {}) });
}
for (let i = 0; i < add.length; i += 80)
  await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, add: add.slice(i, i + 80) } } });
console.log(`таймлайн ${NAME} (${anim.id}): ${(END / FPS).toFixed(1)} с, ${add.length} ключей на ${tracks.size} дорожках`);

// State Machine 1: состояние Entry -> face_demo
const q = await call('animation_editor', { command: 'queryStateMachine', data: {} });
const st = q.layers[0].states.find((s) => s.type === 'animation');
await call('animation_editor', { command: 'updateStates', data: { updateStates: { states: [{ id: st.id, animationId: anim.id }] } } });
file.faceDemo = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: add.length, order: ORDER, start };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
console.log('машина состояний играет', NAME);
