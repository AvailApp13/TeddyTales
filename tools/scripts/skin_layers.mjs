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
 * Веса — tools/lib/bear_weights.mjs (рукава, капюшон, шорты; лапы и лицо — целиком
 * на своей кости). Проверить позу до записи: scripts/simulate_pose.py.
 *
 * Координаты вершин меша — локальные в кадре слоя (1333×2000, центр 0,0).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { loadWeights } from '../lib/bear_weights.mjs';

const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const [W, H] = meta.size;
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

// веса по форме части — общий модуль (его же читает офлайн-симулятор поз)
const { PLAN } = loadWeights();
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
