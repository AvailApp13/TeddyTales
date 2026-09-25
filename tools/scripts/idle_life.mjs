#!/usr/bin/env node
/**
 * «Живой покой» (ТЗ, мимика комнаты «Игра», пункт 1): таймлайн idle_life — фон,
 * который играет всегда; выражения (fx_<имя>) включаются поверх него.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/idle_life.mjs [--no-play]
 *
 * Петля 14.4 с (6 вдохов по 2.4 с), без видимого повтора:
 *   дыхание      — животом (D21): на вдохе живот расширяется на 10 % (кость
 *                  root_belly), лапы расходятся на 3°; корпус и голова на месте;
 *   голова       — медленный дрейф до ±3° (две синусоиды), корпус берёт 40 %, ноги
 *                  разворачиваются обратно (D18);
 *   моргание     — 5 раз за петлю с неравными паузами, одно двойное (D23): бусины
 *                  сплющиваются, как смыкающиеся веки, затем проявляются ресницы;
 *   взгляд       — не двигается (смещение бусин читалось неестественно);
 *   уши (D22)    — поворачиваются к зрителю: часть за линией сгиба сжимается вдоль оси
 *                  и чуть расширяется вдоль линии (ближе к зрителю), на складке блик:
 *                  чуть на каждом вдохе, по очереди на 30 %, правое ещё раз на 22 %, и
 *                  «прислушивание» — оба уха на 24 %, голова набок.
 * Размах рассчитан на маленького мишку в приложении: при мелком масштабе движения
 * в 1–2 px не видны.
 * Плавные дорожки — ключи каждые 4 кадра с линейной интерполяцией: с кривой
 * «разгон-торможение» на каждом отрезке движение замирало 10 раз в секунду
 * и читалось как подёргивание.
 * Кадр 0 — точно поза покоя (with_rest_pose.mjs замораживает анимацию на нём),
 * все дорожки на последнем кадре равны первому — шов петли не виден.
 * Случайность интервалов — на стороне приложения: машина состояний может
 * запускать петлю с разной скорости/смещения; внутри петли паузы уже неравные.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { Tracks, writeTimeline, playInStateMachine, blinkBead, addBlinkLids, keyBeads } from '../lib/timeline.mjs';

const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const B = file.bones; const G = file.faceParts.groups; const IM = file.faceParts.images;
if (!B.root_ear_left || !B.root_ear_right) throw new Error('нет костей ушей — сначала scripts/ear_bones.mjs');

const NAME = 'idle_life', FPS = 60, BREATH = 144, END = 6 * BREATH;   // 864 кадра
const S = Math.sin, PI2 = Math.PI * 2;
// переход 0 -> 1 с нулевыми скоростью и ускорением на концах (smootherstep): старт и
// остановка без толчка — со smoothstep начало «прислушивания» читалось рывком
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * t * (t * (6 * t - 15) + 10); };

// ---- сценарий (кадры). Уши — до 22° (предел, D20). Переходы медленные: замер
// скорости по кадрам рантайма показал толчки там, где движение занимало 0.13–0.4 с
const BLINKS = [70, 262, 300, 540, 700];                               // 262/300 — двойное
// уши загибаются на зрителя (D22): сгиб, % — насколько сложилась внешняя часть уха
// (масштаб кости уха вдоль оси = 100 − сгиб); тень сгиба проявляется вместе с ним
const EAR_MOVES = [['right', 150, 270, 30], ['left', 370, 490, 30], ['right', 770, 862, 22]];   // [ухо, от, до, сгиб %]
const EAR_T = 45;                                                       // загиб и возврат, кадров
const EAR_BREATH = 6, EAR_BREATH_LAG = 14;                             // на каждом вдохе уши чуть загибаются
const SHADE_FULL = 30, SHADE_MAX = 100;                                 // светотень сгиба проявляется полностью при сгибе 30 % (как simulate_pose.py)
const EAR_WIDEN = 0.3;                                                  // загнутая часть шире вдоль линии сгиба на 0.3 × сгиб (край ближе к зрителю)
const BELLY = 10, ARMS = 3;                                             // вдох: живот +10 %, лапы 3°
const LISTEN = { from: 540, to: 760, ear: 24, head: 4, t: 60 };       // прислушивание: уши загибаются вперёд, голова набок; вход и выход по 1 с

// голова: медленный дрейф (периоды делят петлю) + прислушивание
const listen = (f) => sm(LISTEN.from, LISTEN.from + LISTEN.t, f) * (1 - sm(LISTEN.to - LISTEN.t, LISTEN.to, f));
const drift = (f) => 2.2 * S(PI2 * f / 432) + 1.0 * S(PI2 * f / 288 + 1.3);   // до ±3°
const headAt = (f) => drift(f) - drift(0) + LISTEN.head * listen(f);        // кадр 0 — покой
const inhale = (f) => (1 - Math.cos(PI2 * f / BREATH)) / 2;                 // 0 в покое, 1 на вдохе

// ---- дорожки
const tracks = new Tracks(); const key = tracks.key.bind(tracks);
const base = (await call('query_property_values', { propertyKeys: {
  [B.root]: [15, 91], [B.root_body]: [15], ...(B.root_belly ? { [B.root_belly]: [16, 17] } : {}), [B.root_arm_left]: [15], [B.root_arm_right]: [15], [B.root_leg_left]: [15], [B.root_leg_right]: [15],
  [B.root_ear_left]: [16, 17], [B.root_ear_right]: [16, 17],
  } })).values;
const b = (id, k) => base[id][String(k)];
const LEAN = 0.4, HEADK = 0.65, LAG = 5;
const STEP = 4, lin = (id, k, f, v) => key(id, k, f, v, 'linear');
for (let f = 0; f <= END; f += STEP) {
  const inh = inhale(f), h = headAt(f), lean = LEAN * (headAt(f - LAG) - headAt(-LAG));   // корпус с запаздыванием; 0 на кадре 0
  lin(B.root, 91, f, b(B.root, 91));                                     // корпус не поднимается — дышит живот
  lin(B.root, 15, f, b(B.root, 15) + lean);
  lin(B.root_body, 15, f, b(B.root_body, 15) + HEADK * h);
  lin(B.root_leg_left, 15, f, b(B.root_leg_left, 15) - lean);
  lin(B.root_leg_right, 15, f, b(B.root_leg_right, 15) - lean);
  lin(B.root_arm_left, 15, f, b(B.root_arm_left, 15) - ARMS * inh);     // лапы расходятся на вдохе
  lin(B.root_arm_right, 15, f, b(B.root_arm_right, 15) + ARMS * inh);
  if (B.root_belly) {                                                    // живот: только расширение (≥ покоя)
    lin(B.root_belly, 16, f, b(B.root_belly, 16) * (1 + BELLY / 100 * inh));
    lin(B.root_belly, 17, f, b(B.root_belly, 17) * (1 + 0.6 * BELLY / 100 * inh));
  }
}
// уши: знак для левого + (по часовой) = вверх, для правого — наоборот.
// Всё плавное: дыхание + движения + прислушивание.
const shadeId = (side) => file.layersV2[`ear_${side}_shade`]?.instance;
const earKey = (side, f, fold) => {
  const id = B[`root_ear_${side}`]; lin(id, 16, f, b(id, 16) * (1 - fold / 100)); lin(id, 17, f, b(id, 17) * (1 + EAR_WIDEN * fold / 100));
  if (shadeId(side)) lin(shadeId(side), 18, f, SHADE_MAX * Math.min(1, Math.max(0, fold) / SHADE_FULL));
};
const earAt = (side, f) => {
  const lag = side === 'right' ? 4 : 0;                                  // уши двигаются не синхронно
  const eb = (x) => EAR_BREATH * inhale(x - EAR_BREATH_LAG - lag);
  let a = eb(f) - eb(0);                                                 // кадр 0 — покой
  for (const [s_, f0, f1, fold] of EAR_MOVES) if (s_ === side) a += fold * sm(f0, f0 + EAR_T, f) * (1 - sm(f1 - EAR_T, f1, f));
  const up = sm(LISTEN.from + lag, LISTEN.from + LISTEN.t + lag, f) * (1 - sm(LISTEN.to - LISTEN.t, LISTEN.to, f));
  return a + LISTEN.ear * up;
};
for (let f = 0; f <= END; f += STEP) for (const side of ['left', 'right']) earKey(side, f, earAt(side, f));
// взгляд
// взгляд не двигается: смещение бусин читалось неестественно (обратная связь)
// все выражения в покое скрыты (0 на первом и последнем кадре)
for (const g of Object.keys(G).filter((n) => n.startsWith('fx_'))) { key(G[g], 18, 0, 0, 'linear'); key(G[g], 18, END, 0, 'linear'); }
// моргание (D23, lib/timeline.mjs): бусины сплющиваются, затем проявляются ресницы
// масштаб бусины в покое — из данных постановки (общий масштаб слоёв × масштаб накладки), а
// не из редактора: если там стоит кадр моргания, прочиталось бы сплющенное значение
const FP = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'face_v2', 'face_parts.json'), 'utf8'));
const beads = ['l', 'r'].map((k) => ({ id: IM[`gaze_bead_${k}`].instance, sy: file.layersV2Transform.scalePercent * FP.gaze[`bead_${k}`].px_scale }));
keyBeads(tracks, beads, END, (f) => blinkBead(f, BLINKS));
for (const f0 of BLINKS) addBlinkLids(tracks, f0, G.fx_eyes_closed);

const anim = await writeTimeline(call, { name: NAME, fps: FPS, frames: END, tracks });
console.log(`таймлайн ${NAME} (${anim.id}): ${(END / FPS).toFixed(1)} с, ${anim.keys} ключей на ${tracks.size} дорожках`);
const PLAY = !process.argv.includes('--no-play');
if (PLAY) { await playInStateMachine(call, anim.id); console.log('машина состояний играет', NAME); }
file.idleLife = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: anim.keys, blinks: BLINKS, earMoves: EAR_MOVES, earWiden: EAR_WIDEN, earBreath: EAR_BREATH, belly: BELLY, arms: ARMS, listen: LISTEN };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
