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
