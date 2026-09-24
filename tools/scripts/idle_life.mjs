#!/usr/bin/env node
/**
 * «Живой покой» (ТЗ, мимика комнаты «Игра», пункт 1): таймлайн idle_life — фон,
 * который играет всегда; выражения (fx_<имя>) включаются поверх него.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/idle_life.mjs [--no-play]
 *
 * Петля 14.4 с (6 вдохов по 2.4 с), без видимого повтора:
 *   дыхание      — корпус поднимается на 2 px, лапы расходятся на 1.3° на вдохе;
 *   голова       — медленный дрейф ±1.5° (две синусоиды), корпус берёт 40 %, ноги
 *                  разворачиваются обратно (D18);
 *   моргание     — 5 раз за петлю с неравными паузами, одно двойное;
 *   взгляд       — бусины смещаются влево, вправо, вверх и возвращаются;
 *   уши (D20)    — без резких рывков: чуть приподнимаются на каждом вдохе, одно
 *                  плавное движение правым ухом и «прислушивание» — оба уха
 *                  вверх, голова набок, взгляд в сторону.
 * Все дорожки на последнем кадре равны первому — шов петли не виден.
 * Случайность интервалов — на стороне приложения: машина состояний может
 * запускать петлю с разной скорости/смещения; внутри петли паузы уже неравные.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { Tracks, writeTimeline, playInStateMachine } from '../lib/timeline.mjs';

const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const B = file.bones; const G = file.faceParts.groups; const IM = file.faceParts.images;
if (!B.root_ear_left || !B.root_ear_right) throw new Error('нет костей ушей — сначала scripts/ear_bones.mjs');

const NAME = 'idle_life', FPS = 60, BREATH = 144, END = 6 * BREATH;   // 864 кадра
const S = Math.sin, PI2 = Math.PI * 2;
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// ---- сценарий (кадры). Уши — до 14° (проверено в симуляторе вместе с наклоном головы и руками)
const BLINKS = [70, 262, 282, 540, 780];                               // 262/282 — двойное
const LOOKS = [[130, 210, -2.6, 0], [400, 470, 2.4, 0.3], [790, 832, 0.8, -1.4]];   // [от, до, dx, dy] px артборда
// плавные движения ушей: [ухо, от, до, угол°] — подъём/возврат по 0.5 с; − вниз, + вверх
const EAR_MOVES = [['right', 420, 500, 7]];
const EAR_BREATH = 2.5, EAR_BREATH_LAG = 10;                         // уши на вдохе, с запаздыванием
const LISTEN = { from: 600, to: 760, ear: 11.5, head: 2.5 };              // прислушивание: уши вверх, голова набок

// голова: медленный дрейф (периоды делят петлю) + прислушивание
const listen = (f) => sm(LISTEN.from, LISTEN.from + 24, f) * (1 - sm(LISTEN.to - 30, LISTEN.to, f));
const headAt = (f) => 1.1 * S(PI2 * f / 432) + 0.5 * S(PI2 * f / 288 + 1.3) + LISTEN.head * listen(f);

// ---- дорожки
const tracks = new Tracks(); const key = tracks.key.bind(tracks);
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [15, 91], [B.root_body]: [15], [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15],
  [B.root_ear_left]: [15], [B.root_ear_right]: [15],
  [IM.gaze_bead_l.instance]: [13, 14], [IM.gaze_bead_r.instance]: [13, 14] } })).values;
const b = (id, k) => base[id][String(k)];
const LEAN = 0.4, HEADK = 0.65, LAG = 5;
for (let f = 0; f <= END; f += 6) {
  const breath = S(PI2 * f / BREATH), h = headAt(f), lean = LEAN * headAt((f - LAG + END) % END);
  key(B.root, 91, f, b(B.root, 91) - 2 * breath);                       // вдох — корпус вверх
  key(B.root, 15, f, b(B.root, 15) + lean);
  key(B.root_body, 15, f, b(B.root_body, 15) + HEADK * h);
  key(B.root_leg_left, 15, f, b(B.root_leg_left, 15) - lean);
  key(B.root_leg_right, 15, f, b(B.root_leg_right, 15) - lean);
  key(B.root_arm_left, 15, f, b(B.root_arm_left, 15) - 1.3 * breath);   // лапы расходятся на вдохе
  key(B.root_arm_right, 15, f, b(B.root_arm_right, 15) + 1.3 * breath);
}
// уши: знак для левого + (по часовой) = вверх, для правого — наоборот.
// Всё плавное (ключи каждые 6 кадров): дыхание + движения + прислушивание.
const earKey = (side, f, deg) => { const id = B[`root_ear_${side}`]; key(id, 15, f, b(id, 15) + (side === 'left' ? deg : -deg)); };
const earAt = (side, f) => {
  const lag = side === 'right' ? 4 : 0;                                  // уши двигаются не синхронно
  let a = EAR_BREATH * S(PI2 * (f - EAR_BREATH_LAG - lag) / BREATH);
  for (const [s_, f0, f1, deg] of EAR_MOVES) if (s_ === side) a += deg * sm(f0, f0 + 30, f) * (1 - sm(f1 - 30, f1, f));
  const up = sm(LISTEN.from + lag, LISTEN.from + 20 + lag, f) * (1 - sm(LISTEN.to - 30, LISTEN.to, f));
  return a + LISTEN.ear * up;
};
for (let f = 0; f <= END; f += 6) for (const side of ['left', 'right']) earKey(side, f, earAt(side, f));
// взгляд
const gaze = new Map([[0, [0, 0]], [END, [0, 0]]]);
for (const [a, z, dx, dy] of LOOKS) { gaze.set(a, [0, 0]); gaze.set(a + 8, [dx, dy]); gaze.set(z, [dx, dy]); gaze.set(z + 8, [0, 0]); }
gaze.set(LISTEN.from + 20, [-1.8, -0.4]); gaze.set(LISTEN.to - 30, [-1.8, -0.4]);   // прислушивание — взгляд в сторону
gaze.set(LISTEN.from + 6, [0, 0]); gaze.set(LISTEN.to - 20, [0, 0]);
for (const s of ['l', 'r']) {
  const id = IM[`gaze_bead_${s}`].instance;
  for (const [f, [dx, dy]] of gaze) { key(id, 13, f, b(id, 13) + dx); key(id, 14, f, b(id, 14) + dy); }
}
// моргание и выражения (все выражения в покое скрыты)
const op = (name, f, v) => key(G[`fx_${name}`], 18, f, v, 'linear');
for (const n of Object.keys(G).filter((g) => g.startsWith('fx_')).map((g) => g.slice(3))) { op(n, 0, 0); op(n, END, 0); }
for (const f0 of BLINKS) {
  op('blink_half', f0, 0); op('blink_half', f0 + 2, 100); op('blink_half', f0 + 5, 100); op('blink_half', f0 + 8, 0);
  op('eyes_closed', f0 + 1, 0); op('eyes_closed', f0 + 3, 100); op('eyes_closed', f0 + 4, 100); op('eyes_closed', f0 + 6, 0);
}

const anim = await writeTimeline(call, { name: NAME, fps: FPS, frames: END, tracks });
console.log(`таймлайн ${NAME} (${anim.id}): ${(END / FPS).toFixed(1)} с, ${anim.keys} ключей на ${tracks.size} дорожках`);
const PLAY = !process.argv.includes('--no-play');
if (PLAY) { await playInStateMachine(call, anim.id); console.log('машина состояний играет', NAME); }
file.idleLife = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: anim.keys, blinks: BLINKS, earMoves: EAR_MOVES, earBreath: EAR_BREATH, listen: LISTEN };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
