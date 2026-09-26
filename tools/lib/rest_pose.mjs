/**
 * Поза покоя костей — из привязки сеток (Skin → Tendon: мировое положение кости в момент
 * привязки), а не из текущих значений в редакторе. Текущие значения — это кадр, на котором
 * стоит проигрывание или открытый таймлайн: таймлайн, записанный от них, начинал с чужой
 * позы (ухо на 37° от покоя — из-под капюшона выглядывал скрытый запас уха).
 *
 * Покой = поза привязки: в ней сетки складываются в кадр слоёв пиксель в пиксель.
 * Локальный поворот кости = мировой при привязке − мировой родительской кости − повороты
 * групп между ними (группы не анимируются). Масштаб — из матрицы привязки, положение —
 * только у кости верхнего уровня (root: её родитель — артборд).
 *
 *   const rest = await restPose(call, file);   // { [boneId]: { 15, 16, 17, 90?, 91? } }
 */
const deg = (r) => r * 180 / Math.PI;

export async function restPose(call, file) {
  const B = file.bones; const nameOf = Object.fromEntries(Object.entries(B).map(([k, v]) => [v, k]));
  // мировые матрицы костей при привязке — из тенданов всех сеток (у одной кости во всех сетках одинаковые)
  const bind = {};
  for (const [layer, s] of Object.entries(file.skins ?? {})) {
    const objs = (await call('query_objects', { objectIds: [s.meshId] })).objects ?? [];
    const skin = objs.find((o) => o.types[0] === 'Skin'); if (!skin) continue;
    const v = (await call('query_property_values', { propertyKeys: Object.fromEntries(skin.children.map((t) => [t, [95, 96, 97, 98, 99, 100, 101]])) })).values;
    for (const x of Object.values(v)) {
      const id = x['95']; if (!nameOf[id]) continue;
      const m = { r: deg(Math.atan2(x['98'], x['96'])), s: Math.hypot(x['96'], x['98']), sy: Math.hypot(x['97'], x['99']), tx: x['100'], ty: x['101'] };
      if (bind[id] && Math.abs(((bind[id].r - m.r + 540) % 360) - 180) > 0.01)
        throw new Error(`кость ${nameOf[id]} привязана в разных позах (${bind[id].layer}: ${bind[id].r.toFixed(3)}°, ${layer}: ${m.r.toFixed(3)}°) — перепривязать skin_layers.mjs в покое`);
      bind[id] ??= { ...m, layer };
    }
  }
  // родители: цепочка до ближайшей кости или артборда
  const h = (await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
  const obj = Object.fromEntries(h.map((o) => [o.id, o])); const parent = {};
  for (const o of h) for (const ch of o.children ?? []) parent[typeof ch === 'string' ? ch : ch.id] = o.id;
  const chain = (id) => { const nodes = []; let p = parent[id];
    while (p && !/Bone$/.test(obj[p].types[0]) && obj[p].types[0] !== 'Artboard') { nodes.push(p); p = parent[p]; }
    return { nodes, bone: p && /Bone$/.test(obj[p].types[0]) ? p : null }; };
  const chains = Object.fromEntries(Object.values(B).map((id) => [id, chain(id)]));
  const nodeIds = [...new Set(Object.values(chains).flatMap((c) => c.nodes))];
  const nodeR = nodeIds.length ? (await call('query_property_values', { propertyKeys: Object.fromEntries(nodeIds.map((n) => [n, [15, 16, 17]])) })).values : {};

  // ветка угла — ближайшая к текущему значению в редакторе (223.9° и −136.1° — один поворот,
  // но между таймлайнами с разными ветками машина состояний крутила бы кость на 360°)
  const live = (await call('query_property_values', { propertyKeys: Object.fromEntries(Object.values(B).map((id) => [id, [15]])) })).values;
  const rest = {};
  for (const [name, id] of Object.entries(B)) {
    const w = bind[id]; if (!w) throw new Error(`кость ${name} не привязана ни к одной сетке — поза покоя неизвестна`);
    const { nodes, bone } = chains[id];
    for (const n of nodes) if (Math.abs(nodeR[n]['16'] - 100) > 1e-3 || Math.abs(nodeR[n]['17'] - 100) > 1e-3)
      throw new Error(`группа ${obj[n].name} над костью ${name} с масштабом — поворот кости по привязке не вычислить`);
    const up = (bone ? bind[bone].r : 0) + nodes.reduce((s, n) => s + nodeR[n]['15'], 0);
    const sc = bone ? bind[bone].s : 1;
    const r = w.r - up, cur = live[id]?.['15'] ?? 0;
    rest[id] = { 15: cur + ((((r - cur) % 360) + 540) % 360) - 180, 16: 100 * w.s / sc, 17: 100 * w.sy / sc };
    if (!bone && !nodes.length) Object.assign(rest[id], { 90: w.tx, 91: w.ty });
  }
  return rest;
}

/**
 * Мировая матрица узла (группы) в покое: [a, b, c, d, tx, ty] (x' = a·x + c·y + tx,
 * y' = b·x + d·y + ty). Цепочка групп вверх до ближайшей кости — её поза покоя из привязки
 * сеток (тенданы), либо до артборда. Нужна, чтобы ставить кость в группу по мировой точке:
 * reparent_objects в редакторе пересчитывает локальное положение неверно (кости ушей стояли
 * на 34–37 px от оси — ухо поворачивалось вокруг точки в своём теле, D25).
 */
export async function restWorld(call, file, nodeId) {
  const h = (await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
  const obj = Object.fromEntries(h.map((o) => [o.id, o])); const parent = {};
  for (const o of h) for (const ch of o.children ?? []) parent[typeof ch === 'string' ? ch : ch.id] = o.id;
  const mul = (A, B) => [A[0] * B[0] + A[2] * B[1], A[1] * B[0] + A[3] * B[1], A[0] * B[2] + A[2] * B[3], A[1] * B[2] + A[3] * B[3],
    A[0] * B[4] + A[2] * B[5] + A[4], A[1] * B[4] + A[3] * B[5] + A[5]];
  const nodes = []; let p = nodeId;
  while (p && !/Bone$/.test(obj[p].types[0]) && obj[p].types[0] !== 'Artboard') { nodes.push(p); p = parent[p]; }
  let M = [1, 0, 0, 1, 0, 0];
  if (p && /Bone$/.test(obj[p].types[0])) {
    const skins = Object.values(file.skins ?? {});
    for (const s of skins) {
      const skin = ((await call('query_objects', { objectIds: [s.meshId] })).objects ?? []).find((o) => o.types[0] === 'Skin'); if (!skin) continue;
      const v = (await call('query_property_values', { propertyKeys: Object.fromEntries(skin.children.map((t) => [t, [95, 96, 97, 98, 99, 100, 101]])) })).values;
      const x = Object.values(v).find((t) => t['95'] === p); if (!x) continue;
      M = [x['96'], x['98'], x['97'], x['99'], x['100'], x['101']]; break;
    }
    if (M[0] === 1 && M[4] === 0) throw new Error(`кость ${obj[p].name} не привязана ни к одной сетке — положение в покое неизвестно`);
  }
  const vals = nodes.length ? (await call('query_property_values', { propertyKeys: Object.fromEntries(nodes.map((n) => [n, [13, 14, 15, 16, 17]])) })).values : {};
  for (const n of nodes.reverse()) {
    const v = vals[n]; const r = v['15'] * Math.PI / 180, sx = v['16'] / 100, sy = v['17'] / 100;
    M = mul(M, [Math.cos(r) * sx, Math.sin(r) * sx, -Math.sin(r) * sy, Math.cos(r) * sy, v['13'], v['14']]);
  }
  return M;
}
/** Точка артборда -> локальные координаты узла с мировой матрицей M. */
export const toLocal = (M, [x, y]) => { const det = M[0] * M[3] - M[1] * M[2]; const dx = x - M[4], dy = y - M[5];
  return [(M[3] * dx - M[2] * dy) / det, (-M[1] * dx + M[0] * dy) / det]; };
