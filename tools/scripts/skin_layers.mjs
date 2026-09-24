#!/usr/bin/env node
/**
 * Сетки с весами костей для слоёв мишки v2 — ткань тянется, а не режется.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/skin_layers.mjs [слой ...]
 *
 * Для каждого слоя: generateMesh (по контуру, с подразбиением) -> bindBones ->
 * веса по вершинам вычисляются здесь по форме части и пишутся в Weight
 * (values: 4 байта весов 0..255, indices: 4 байта номеров тенданов, 1 = первая кость).
 *
 *  sleeve_*  : у шва реглана — root (туловище), к манжете — кость руки.
 *              Рукав тянется от плеча, подмышка не открывается.
 *  hood      : обод и воротник — root, остриё и лоб — root_body (голова).
 *              Низ капюшона остаётся на плечах, щели у плеча нет.
 *  shorts    : пояс — root, штанины — кости ног (левая/правая по оси).
 *  paw_*, face: целиком на кости (рука / голова) — без растяжения.
 *  sleeve_*  : край у лапы идёт с лапой; hood: кольцо вокруг лица идёт с головой.
 *
 * Координаты вершин меша — локальные в кадре слоя (1333×2000, центр 0,0).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const [W, H] = meta.size; const AXIS = meta.axisX;
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = async (t, a) => {
  for (let i = 0; i < 6; i++) {
    try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 400)}`); return r; }
    catch (e) { if (!/ENOTFOUND|DNS|пустой ответ/.test(e.message)) throw e; await new Promise((r) => setTimeout(r, 8000)); }
  }
  throw new Error(`${t}: нет связи`);
};
const info = await call('session_info', {});
const file = state[String(info.activeFileId)];
const B = file.bones; const LV = file.layersV2;

const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;
// шов реглана (кадр) — те же точки, что в split_full_bear.py
const SEAM_L = [[472, 1040], [466, 1110], [452, 1180], [440, 1240], [425, 1285], [410, 1318], [404, 1352]];
const SEAM_R = [[893, 1040], [893, 1120], [905, 1190], [918, 1250], [940, 1290], [960, 1320], [966, 1352]];
const seamX = (seam, y) => { if (y <= seam[0][1]) return seam[0][0]; for (let i = 1; i < seam.length; i++) if (y <= seam[i][1]) return lerp(seam[i - 1][0], seam[i][0], (y - seam[i - 1][1]) / (seam[i][1] - seam[i - 1][1])); return seam.at(-1)[0]; };

// карты расстояний до лица и лап (scripts/weight_fields.py), шаг 4 px
const F = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'weight_fields.json'), 'utf8'));
const dist = (name, x, y) => { const r = F[name][Math.min(F[name].length - 1, Math.max(0, Math.round(y / F.step)))]; return r[Math.min(r.length - 1, Math.max(0, Math.round(x / F.step)))]; };
// рукав: у шва реглана — туловище, к манжете — рука; край у лапы идёт с лапой целиком
// (кроме самой линии шва, она всегда держится за туловище)
const sleeveW = (seam, sign, paw, arm) => (x, y) => {
  const d = sign * (seamX(seam, y) - x);
  const a = smooth(10, 150, d);
  const nearPaw = 1 - smooth(6, 55, dist(paw, x, y));
  const w = a + (1 - a) * nearPaw * smooth(0, 22, d);
  return { root: 1 - w, [arm]: w };
};
// капюшон: остриё и кольцо вокруг лица — голова (лицо не выходит за обод),
// низ у плеч и воротник — туловище. Переходы широкие (кольцо 20→150 px от лица,
// по высоте 940→1140): при крутом переходе обод под подбородком при наклоне
// головы тянулся полосами вместе с ворсинками лица с внутренней кромки.
const hoodW = (x, y) => {
  const top = 1 - smooth(940, 1140, y);
  const ring = 1 - smooth(20, 150, dist('face', x, y));
  const h = Math.max(top, ring);
  return { root: 1 - h, root_body: h };
};
// веса: функция (x, y кадра) -> { boneKey: вес }
const PLAN = {
  sleeve_left: { bones: ['root', 'root_arm_left'], w: sleeveW(SEAM_L, 1, 'paw_left', 'root_arm_left') },
  sleeve_right: { bones: ['root', 'root_arm_right'], w: sleeveW(SEAM_R, -1, 'paw_right', 'root_arm_right') },
  // лапы и лицо двигаются целиком — без растяжения (обратная связь: лапы раздувались, морда кривилась)
  paw_left: { bones: ['root', 'root_arm_left'], w: () => ({ root_arm_left: 1 }) },
  paw_right: { bones: ['root', 'root_arm_right'], w: () => ({ root_arm_right: 1 }) },
  face: { bones: ['root', 'root_body'], w: () => ({ root_body: 1 }) },
  hood: { bones: ['root', 'root_body'], w: hoodW },
  shorts: { bones: ['root', 'root_leg_left', 'root_leg_right'], w: (x, y) => {
    const leg = smooth(1520, 1640, y); const side = smooth(AXIS - 40, AXIS + 40, x);
    return { root: 1 - leg, root_leg_left: leg * (1 - side), root_leg_right: leg * side }; } },
};
const only = process.argv.slice(2); const todo = Object.keys(PLAN).filter((n) => !only.length || only.includes(n));
file.skins ??= {};
for (const name of todo) {
  const p = PLAN[name]; const imageId = LV[name].instance;
  // сетка: если уже есть — берём её, иначе генерируем
  let meshId = file.skins[name]?.meshId;
  if (!meshId) {
    const g = await call('mesh_rigging_tool', { command: 'generateMesh', data: { generateMesh: { imageId, trace: true, detail: 1.0, subdivisions: 3 } } });
    meshId = g.meshId; console.log(`${name}: сетка ${meshId}, вершин ${g.vertexCount}`);
  }
  await call('mesh_rigging_tool', { command: 'bindBones', data: { bindBones: { targetId: meshId, boneIds: p.bones.map((b) => B[b]) } } })
    .catch((e) => { if (!/already bound/.test(e.message)) throw e; });
  await call('mesh_rigging_tool', { command: 'querySkin', data: { querySkin: { targetId: meshId, includeVertexWeights: true } } });
  // порядок тенданов -> номер (1..n)
  const objs = (await call('query_objects', { objectIds: [meshId] })).objects;
  const skinObj = objs.find((o) => o.types[0] === 'Skin');
  const tendons = skinObj.children;
  const tv = (await call('query_property_values', { propertyKeys: Object.fromEntries(tendons.map((t) => [t, [95]])) })).values;
  const idxOf = {}; tendons.forEach((t, i) => { const boneId = tv[t]['95']; const key = Object.keys(B).find((k) => B[k] === boneId); idxOf[key] = i + 1; });
  // вершина -> Weight
  const verts = objs.filter((o) => /MeshVertex$/.test(o.types[0]));
  const vpos = (await call('query_property_values', { propertyKeys: Object.fromEntries(verts.map((v) => [v.id, [24, 25]])) })).values;
  const pv = {}; let n = 0;
  for (const v of verts) {
    const wId = v.children?.[0]; if (!wId) continue;
    const x = vpos[v.id]['24'] + W / 2, y = vpos[v.id]['25'] + H / 2;
    const ws = Object.entries(p.w(x, y)).filter(([, w]) => w > 0.004).sort((a, b) => b[1] - a[1]).slice(0, 4);
    const sum = ws.reduce((s, [, w]) => s + w, 0);
    let bytes = ws.map(([, w]) => Math.round((w / sum) * 255));
    bytes[0] += 255 - bytes.reduce((s, b) => s + b, 0);                    // сумма ровно 255
    const values = bytes.reduce((acc, b, i) => acc + b * 2 ** (8 * i), 0);
    const indices = ws.reduce((acc, [k], i) => acc + idxOf[k] * 2 ** (8 * i), 0);
    pv[wId] = { 102: values, 103: indices }; n++;
  }
  const ids = Object.keys(pv);
  for (let i = 0; i < ids.length; i += 150) await call('set_property_values', { propertyValues: Object.fromEntries(ids.slice(i, i + 150).map((k) => [k, pv[k]])) });
  file.skins[name] = { meshId, bones: p.bones, vertices: n };
  console.log(`${name}: вершин ${n}, кости ${p.bones.join(' + ')}`);
}
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
console.log('готово');
