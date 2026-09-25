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
 * ней — глазница с мехом закрытого глаза), и когда от неё остаётся тонкая линия,
 * проявляются закрытые глаза с ресницами (fx_eyes_closed). Перетекание картинок
 * полупрозрачной бусины и века давало «силуэт» бусины — здесь просвечивать нечему.
 * ~0.37 с: смыкание 6 кадров, закрыто 8, открытие 8.
 *   beads: [{ id, sy }] — картинки бусин и их масштаб по Y в покое; closedId — группа fx_eyes_closed.
 */
export function addBlink(tracks, f0, { beads, closedId }) {
  for (const { id, sy } of beads)
    for (const [df, k] of [[0, 1], [6, 0.1], [14, 0.1], [22, 1]]) tracks.key(id, 17, f0 + df, sy * k, 'cubic');
  for (const [df, v] of [[4, 0], [7, 100], [12, 100], [15, 0]]) tracks.key(closedId, 18, f0 + df, v, 'cubic');
}
