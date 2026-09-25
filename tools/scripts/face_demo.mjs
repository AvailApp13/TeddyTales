#!/usr/bin/env node
/**
 * Показ мимики: таймлайн face_demo — покой с морганием и взглядом, затем по очереди
 * все выражения (плавное появление 0.2 с, 1.5 с удержание), и каждое — со своим
 * движением тела: смех подпрыгивает и качает головой, при зевке тянет лапы,
 * при грусти голова опускается набок и т. д. Дыхание — животом (D21). Уши отвечают настроению (D24):
 * при грусти, обиде, зевке и сне повисают, при улыбке, смехе, любви и удивлении — «внимание».
 * State Machine 1 переключается на этот таймлайн (demo_moves остаётся в файле).
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/face_demo.mjs [--no-play]
 *   (--no-play — только перезаписать ключи, машина состояний играет прежний таймлайн)
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { Tracks, writeTimeline, playInStateMachine, blinkBead, addBlinkLids, keyBeads, keyEar, earRigs } from '../lib/timeline.mjs';

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
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * t * (t * (6 * t - 15) + 10); };   // smootherstep: без толчков
const env = (u) => sm(0, FADE, u) * (1 - sm(SEG - 4, SEG + FADE - 4, u));   // вход и выход выражения
const S = Math.sin, PI2 = Math.PI * 2;
// движения тела по выражению: u — кадр от начала выражения; head — наклон головы на глаз
// ear — положение ушей (D24): cup — «внимание», droop — «повисли»; доля = огибающая выражения
const MOVE = {
  smile: (u, e) => ({ head: 4 * e, ear: 'cup' }),
  laugh: (u, e) => ({ head: 5 * S(PI2 * u / 22) * e, y: -6 * Math.abs(S(Math.PI * u / 12)) * e, arm: (20 + 5 * S(PI2 * u / 12)) * e, ear: 'cup' }),
  love: (u, e) => ({ head: 8 * e, arm: 6 * e, ear: 'cup' }),
  surprised: (u, e) => ({ head: -2 * e, y: -7 * sm(0, 8, u) * e, arm: 16 * sm(0, 8, u) * e, ear: 'cup' }),
  sad: (u, e) => ({ head: -6 * e, y: 3 * e, ear: 'droop' }),
  upset: (u, e) => ({ head: (-5 + 1.5 * S(PI2 * u / 10)) * e, y: 2.5 * e, ear: 'droop' }),
  chew: (u, e) => ({ head: 2 * S(PI2 * u / 30) * e, y: 2 * S(PI2 * u / 14) * e }),
  lick: (u, e) => ({ head: 5 * e }),
  yawn: (u, e) => ({ head: -3 * e, y: -4 * e, arm: 36 * e, ear: 'droop' }),
  eyes_closed: (u, e) => ({ head: 8 * e, y: 2 * e, ear: 'droop' }),
  squint: (u, e) => ({ head: 3 * S(PI2 * u / 16) * e }),
};
function pose(f) {
  let head = 0, y = 0, arm = 0; const ear = { cup: 0, droop: 0 };
  const inhale = (1 - Math.cos(PI2 * f * 9 / END)) / 2;            // дыхание животом (D21): 9 вдохов, 0 в покое и в конце петли
  for (const n of ORDER) { const u = f - start[n]; if (u < 0 || u > SEG + FADE) continue;
    const m = MOVE[n](u, env(u)); head += m.head ?? 0; y += m.y ?? 0; arm += m.arm ?? 0; if (m.ear) ear[m.ear] = Math.max(ear[m.ear], env(u)); }
  return { head, y, arm, ear, inhale };
}
// взгляд не двигается: смещение бусин читалось неестественно (обратная связь)
// моргания: кадры начала (только когда глаза — бусины основы)
const BLINKS = [20, 70, start.smile + 55, start.chew + 75, END - 70];

// ---- дорожки
const LEAN = 0.4, HEADK = 0.65, LAG = 5;
const tracks = new Tracks(); const key = tracks.key.bind(tracks);
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [15, 91], [B.root_body]: [15], [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15],
  ...Object.fromEntries(Object.keys(B).filter((k) => k.startsWith('root_ear_')).map((k) => [B[k], [15]])), ...(B.root_belly ? { [B.root_belly]: [16, 17] } : {}),
  } })).values;
const b = (id, k) => base[id][String(k)];
// плавные дорожки: ключи каждые 4 кадра, линейно (кубическая кривая на каждом отрезке давала подёргивание)
const lin = (id, k, f, v) => key(id, k, f, v, 'linear');
for (let f = 0; f <= END; f += 4) {
  const p = pose(f), pl = pose(Math.max(0, f - LAG));
  const lean = LEAN * pl.head;
  lin(B.root, 15, f, b(B.root, 15) + lean);
  lin(B.root, 91, f, b(B.root, 91) + p.y);
  lin(B.root_body, 15, f, b(B.root_body, 15) + HEADK * p.head);
  lin(B.root_leg_left, 15, f, b(B.root_leg_left, 15) - lean);
  lin(B.root_leg_right, 15, f, b(B.root_leg_right, 15) - lean);
  lin(B.root_arm_right, 15, f, b(B.root_arm_right, 15) - p.arm + 3 * p.inhale);
  lin(B.root_arm_left, 15, f, b(B.root_arm_left, 15) + p.arm - 3 * p.inhale);
  if (B.root_belly) { lin(B.root_belly, 16, f, b(B.root_belly, 16) * (1 + 0.10 * p.inhale)); lin(B.root_belly, 17, f, b(B.root_belly, 17) * (1 + 0.06 * p.inhale)); }
}
// уши (D24): положения по выражениям + лёгкое покачивание на вдохе
const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const rigs = earRigs(file, meta);
const restRot = Object.fromEntries(Object.keys(B).filter((k) => k.startsWith('root_ear_')).map((k) => [B[k], b(B[k], 15)]));
for (const side of ['left', 'right'])
  keyEar(tracks, rigs[side], restRot, END, (f) => {
    const p = pose(f), { cup, droop } = p.ear;
    // смена «внимание» <-> «повисли» идёт через покой: иначе в середине видны три уха
    // нарисованные положения отключены: ухо наклоняется целиком (вверх 10°, вниз-наружу 16°)
    const sign = side === 'left' ? 1 : -1;
    return { cup: 0, droop: 0, wig: sign * (10 * Math.max(0, cup - droop) - 16 * Math.max(0, droop - cup)) - sign * 3 * p.inhale };
  });
// прозрачность выражений
const op = (name, f, v, interp = 'linear') => key(G[`fx_${name}`], 18, f, v, interp);
for (const n of Object.keys(G).filter((g) => g.startsWith('fx_')).map((g) => g.slice(3))) { op(n, 0, 0); op(n, END, 0); }
for (const n of ORDER) { const s = start[n]; op(n, s, 0); op(n, s + FADE, 100); op(n, s + SEG - 4, 100); op(n, s + SEG + FADE - 4, 0); }
// масштаб бусины в покое — из данных постановки (общий масштаб слоёв × масштаб накладки), а
// не из редактора: если там стоит кадр моргания, прочиталось бы сплющенное значение
const FP = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'face_v2', 'face_parts.json'), 'utf8'));
const beads = ['l', 'r'].map((k) => ({ id: IM[`gaze_bead_${k}`].instance, sy: file.layersV2Transform.scalePercent * FP.gaze[`bead_${k}`].px_scale }));
// бусины: моргание и выражения со своими глазами (накладка закрывает бусины) — одна функция
// по времени, чтобы ключи соседних выражений не перекрывались; бусины сплющиваются до того,
// как накладка станет заметной, и раскрываются, когда она почти ушла (D23)
const OWN_EYES = ORDER.filter((n) => !['chew', 'lick', 'smile'].includes(n));
const shut = (f) => Math.max(0, ...OWN_EYES.map((n) => { const s0 = start[n]; return sm(s0 - 4, s0 + 3, f) * (1 - sm(s0 + SEG + FADE - 9, s0 + SEG + FADE, f)); }));
keyBeads(tracks, beads, END, (f) => Math.min(blinkBead(f, BLINKS), 1 - 0.97 * shut(f)));
for (const f0 of BLINKS) addBlinkLids(tracks, f0, G.fx_eyes_closed);   // D23

// ---- таймлайн
const anim = await writeTimeline(call, { name: NAME, fps: FPS, frames: END, tracks });
console.log(`таймлайн ${NAME} (${anim.id}): ${(END / FPS).toFixed(1)} с, ${anim.keys} ключей на ${tracks.size} дорожках`);
const PLAY = !process.argv.includes('--no-play');
if (PLAY) await playInStateMachine(call, anim.id);   // State Machine 1 -> face_demo
file.faceDemo = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: anim.keys, order: ORDER, start };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
if (PLAY) console.log('машина состояний играет', NAME);
