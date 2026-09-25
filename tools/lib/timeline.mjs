/**
 * Запись таймлайнов мишки в открытый файл Rive (через MCP): дорожки ключей
 * собираются в памяти, таймлайн создаётся или очищается и заполняется целиком.
 * Используют scripts/face_demo.mjs и scripts/idle_life.mjs.
 */

/** Дорожки ключей: `${objectId}:${propertyKey}` -> Map(кадр -> { v, interp }). */
export class Tracks {
  constructor() { this.map = new Map(); }
  key(id, k, f, v, interp = 'cubic') {
    const t = `${id}:${k}`;
    if (!this.map.has(t)) this.map.set(t, new Map());
    this.map.get(t).set(Math.round(f), { v, interp });
  }
  get size() { return this.map.size; }
  /** Ключи в формате animation_editor.modifyKeyFrames.add. */
  toKeyframes(ease = { x1: 0.42, y1: 0, x2: 0.58, y2: 1 }) {
    const add = [];
    for (const [t, frames] of this.map) {
      const [id, k] = t.split(':');
      for (const [f, { v, interp }] of [...frames].sort((x, y) => x[0] - y[0]))
        add.push({ objectId: id, propertyKey: +k, frame: f, value: v, interpolationType: interp, ...(interp === 'cubic' ? { cubicParams: ease } : {}) });
    }
    return add;
  }
}

/** Создаёт (или очищает) таймлайн `name` и пишет в него дорожки. Возвращает { id, keys }. */
export async function writeTimeline(call, { name, fps, frames, tracks, loop = true }) {
  const list = async () => (await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? [];
  let anim = (await list()).find((a) => a.name === name);
  if (!anim) {
    await call('animation_editor', { command: 'createLinearAnimations', data: { createLinearAnimations: { linearAnimations: [{ name, duration: frames / fps }] } } });
    anim = (await list()).find((a) => a.name === name);
    if (!anim) throw new Error(`таймлайн ${name} не создался`);
  }
  await call('set_property_values', { propertyValues: { [anim.id]: { 56: fps, 57: frames, 59: loop ? 1 : 0 } } });
  const old = await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: [anim.id] } } }).catch(() => null);
  const oldIds = (old?.keyframes?.[anim.id] ?? []).map((k) => k.keyframeId);
  for (let i = 0; i < oldIds.length; i += 200)
    await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, delete: oldIds.slice(i, i + 200) } } });
  const add = tracks.toKeyframes();
  for (let i = 0; i < add.length; i += 80)
    await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: anim.id, add: add.slice(i, i + 80) } } });
  return { id: anim.id, keys: add.length };
}

/** State Machine 1, слой 0: состояние-анимация играет таймлайн animId. */
export async function playInStateMachine(call, animId) {
  const q = await call('animation_editor', { command: 'queryStateMachine', data: {} });
  const st = q.layers[0].states.find((s) => s.type === 'animation');
  await call('animation_editor', { command: 'updateStates', data: { updateStates: { states: [{ id: st.id, animationId: animId }] } } });
}

/**
 * Моргание (D23): бусина глаза сплющивается по вертикали, как будто смыкаются веки (под
 * ней — глазница с мехом закрытого глаза), и когда от неё остаётся тонкая линия, она
 * гаснет и проявляются закрытые глаза с ресницами (fx_eyes_closed). Перетекание картинок
 * полупрозрачной бусины и века давало «силуэт» бусины — здесь просвечивать нечему.
 * ~0.37 с: смыкание 6 кадров, закрыто 8, открытие 8.
 */
const BLINK_BEAD = [[0, 1], [6, 0.03], [14, 0.03], [22, 1]];   // [кадр от начала, масштаб бусины по Y]
const smoothstep = (t) => t * t * (3 - 2 * t);
const piecewise = (pts, x) => {
  if (x <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) if (x <= pts[i][0]) {
    const [x0, y0] = pts[i - 1], [x1, y1] = pts[i]; return y0 + (y1 - y0) * smoothstep((x - x0) / (x1 - x0));
  }
  return pts.at(-1)[1];
};
/** Масштаб бусины (1 — открыта) от морганий: blinks — кадры начала. */
export const blinkBead = (f, blinks) => Math.min(1, ...blinks.map((f0) => piecewise(BLINK_BEAD, f - f0)));
/** Ресницы (fx_eyes_closed) на моргание, начинающееся в кадре f0. */
export function addBlinkLids(tracks, f0, closedId) {
  for (const [df, v] of [[4, 0], [7, 100], [12, 100], [15, 0]]) tracks.key(closedId, 18, f0 + df, v, 'cubic');
}
/**
 * Дорожки бусин по функции k(f) (1 — открыта, ~0 — сплющена): масштаб по Y = sy × k, каждые
 * 2 кадра; почти сплющенная бусина гаснет, иначе её линия видна сквозь ресницы.
 * beads: [{ id, sy }] — картинки бусин и их масштаб по Y в покое.
 */
export function keyBeads(tracks, beads, end, k) {
  for (const { id, sy } of beads)
    for (let f = 0; f <= end; f += 2) {
      const v = k(f); tracks.key(id, 17, f, sy * v, 'linear'); tracks.key(id, 18, f, v < 0.06 ? 0 : 100, 'linear');
    }
}

/**
 * Уши (D24): нарисованные положения (ear_*_cup — «внимание», ear_*_droop — «повисли»)
 * вместо деформации. Переход — навстречу: кость уха рига поворачивается и масштабируется к
 * позе нарисованного уха, кость нарисованного уха — из позы уха рига к своей; картинки
 * меняются в середине, когда обе в одной позе (~0.3 перехода) — «призраков» нет.
 *   rig: { base: { bone, image }, states: { cup: { bone, image, angle, scale }, ... } } на ухо
 *   rest: значения поворота костей в покое (id -> градусы)
 *   at(f) -> { cup: 0..1, droop: 0..1, wig: градусы } — доля каждого положения и покачивание
 */
const smoother = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * t * (t * (6 * t - 15) + 10); };
export function keyEar(tracks, { base, states }, rest, end, at, step = 4) {
  const lin = (id, k, f, v) => tracks.key(id, k, f, v, 'linear');
  for (let f = 0; f <= end; f += step) {
    const w = at(f); let rot = w.wig ?? 0, sc = 1, tmax = 0;
    for (const [n, S] of Object.entries(states)) { const t = w[n] ?? 0; rot += S.angle * t; sc *= S.scale ** t; tmax = Math.max(tmax, t); }
    lin(base.bone, 15, f, rest[base.bone] + rot); lin(base.bone, 16, f, 100 * sc); lin(base.bone, 17, f, 100 * sc);
    lin(base.image, 18, f, 100 * (1 - smoother(0.42, 0.72, tmax)));
    for (const [n, S] of Object.entries(states)) {
      lin(S.bone, 15, f, rest[S.bone] + rot - S.angle); lin(S.bone, 16, f, 100 * sc / S.scale); lin(S.bone, 17, f, 100 * sc / S.scale);
      lin(S.image, 18, f, 100 * smoother(0.28, 0.58, w[n] ?? 0));
    }
  }
}
/** Описание ушей для keyEar из editor_state (file) и layers.json (meta). */
export function earRigs(file, meta) {
  const B = file.bones, LV = file.layersV2;
  return Object.fromEntries(['left', 'right'].map((sd) => [sd, {
    base: { bone: B[`root_ear_${sd}`], image: LV[`ear_${sd}`].instance },
    states: Object.fromEntries(Object.entries(meta.ear_states ?? {}).map(([st, E]) => [st, {
      bone: B[`root_ear_${sd}_${st}`], image: LV[`ear_${sd}_${st}`].instance, angle: E[sd].angle, scale: E[sd].scale }])),
  }]));
}
