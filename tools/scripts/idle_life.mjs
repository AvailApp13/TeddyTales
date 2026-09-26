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
 *   уши (D24)    — нарисованные положения: правое, затем левое повисают и
 *                  поднимаются, левое на миг «внимание», «прислушивание» — оба уха
 *                  «внимание», голова набок; на вдохе уши чуть покачиваются.
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
import { restPose } from '../lib/rest_pose.mjs';
import { Tracks, writeTimeline, playInStateMachine, blinkBead, addBlinkLids, keyBeads, keyEar, earRigs } from '../lib/timeline.mjs';

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
// уши (D24): нарисованные положения, [ухо, положение, от, до]; переход — EAR_T кадров
const EAR_MOVES = [['right', 'droop', 150, 280], ['left', 'droop', 330, 460], ['left', 'cup', 790, 858]];
const EAR_T = 30;
const EAR_UP = 12, EAR_DOWN = 24;                                        // поворот уха вокруг оси в голове, ° (D26, D27): основание тянется, капюшон стоит
const EAR_WIG = 3, EAR_WIG_LAG = 14;                                  // на вдохе уши чуть покачиваются, °
const BELLY = 10, ARMS = 3;                                             // вдох: живот +10 %, лапы 3°
// прислушивание: уши «внимание», голова набок. Наклон набирается и уходит за t кадров так,
// что голова не движется быстрее собственного дрейфа (замер по кадрам рантайма: при 4° за
// 40 кадров макушка уходила на 40 px за полсекунды — «рывок вправо, рывок влево»)
const LISTEN = { from: 480, to: 840, head: 3, t: 160 };

// голова: медленный дрейф (периоды делят петлю) + прислушивание
const listen = (f) => sm(LISTEN.from, LISTEN.from + LISTEN.t, f) * (1 - sm(LISTEN.to - LISTEN.t, LISTEN.to, f));
const drift = (f) => 2.2 * S(PI2 * f / 432) + 1.0 * S(PI2 * f / 288 + 1.3);   // до ±3°
const headAt = (f) => drift(f) - drift(0) + LISTEN.head * listen(f);        // кадр 0 — покой
const inhale = (f) => (1 - Math.cos(PI2 * f / BREATH)) / 2;                 // 0 в покое, 1 на вдохе

// ---- дорожки
const tracks = new Tracks(); const key = tracks.key.bind(tracks);
// покой — из привязки сеток, не из текущего кадра редактора (lib/rest_pose.mjs)
const base = await restPose(call, file);
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
// уши (D24): доли положений по времени + лёгкое покачивание на вдохе
const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const rigs = earRigs(file, meta);
const restRot = Object.fromEntries(Object.keys(B).filter((k) => k.startsWith('root_ear_')).map((k) => [B[k], b(B[k], 15)]));
const pulse = (f0, f1, f) => sm(f0, f0 + EAR_T, f) * (1 - sm(f1 - EAR_T, f1, f));
for (const side of ['left', 'right']) {
  const lag = side === 'right' ? 4 : 0, sign = side === 'left' ? 1 : -1;   // + у левого по часовой = наружу
  const wig = (x) => EAR_WIG * inhale(x - EAR_WIG_LAG - lag);
  keyEar(tracks, rigs[side], restRot, END, (f) => {
    // нарисованные положения (D24) отключены по обратной связи (заломы, «кролик»): ухо
    // утверждённого кадра наклоняется целиком вокруг основания — «внимание» вверх,
    // «повисли» вниз-наружу; картинки положений прозрачны (доля 0)
    let up = 0, down = 0;
    for (const [sd, st, f0, f1] of EAR_MOVES) if (sd === side) (st === 'cup' ? (up = Math.max(up, pulse(f0, f1, f))) : (down = Math.max(down, pulse(f0, f1, f))));
    up = Math.max(up, pulse(LISTEN.from + lag, LISTEN.to, f));
    return { cup: 0, droop: 0, wig: sign * (EAR_UP * up - EAR_DOWN * down) - sign * (wig(f) - wig(0)) };
  }, STEP);
}
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
file.idleLife = { animationId: anim.id, name: NAME, fps: FPS, frames: END, keys: anim.keys, blinks: BLINKS, earMoves: EAR_MOVES, earWig: EAR_WIG, belly: BELLY, arms: ARMS, listen: LISTEN };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
