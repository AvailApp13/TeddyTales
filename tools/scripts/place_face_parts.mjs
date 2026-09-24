#!/usr/bin/env node
/**
 * Мимика мишки v2 в открытом файле Rive: накладки из handoff/face_v2 (face_parts.py).
 * Запускать в позе покоя:
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/place_face_parts.mjs [--replace]
 *   (после --replace перезапустить scripts/face_demo.mjs: ключи взгляда ссылаются на бусины)
 *
 * Структура (всё внутри группы head на кости root_body, поверх face_img):
 *   face_fx
 *     gaze_l, gaze_r      — глазница без бусины + бусина (взгляд: двигается бусина)
 *     fx_<выражение>      — накладки глаз/рта/румянца, прозрачность группы 0
 * В покое накладок не видно, лицо = утверждённая картинка. Выражение включается
 * прозрачностью группы fx_<имя> (плавный переход — ключами opacity).
 * Состояние (id групп и картинок) — rive/editor_state.json → faceParts.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const D = resolve(repoRoot, 'handoff', 'face_v2');
const REPLACE = process.argv.includes('--replace');   // заменить уже поставленные накладки (после перенарезки)
const P = JSON.parse(readFileSync(resolve(D, 'face_parts.json'), 'utf8'));
const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const T = file.layersV2Transform; const S = T.scalePercent / 100; const WORLD = T.world;
const [FW, FH] = P.frame;
const fp = (file.faceParts ??= { groups: {}, images: {} });
const save = () => writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');

const hierarchy = async () => {
  const h = await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id, depth: 16 });
  const all = new Map(), parentOf = new Map();
  const walk = (o, p) => { all.set(o.id, o); if (p) parentOf.set(o.id, p); for (const ch of o.children ?? []) if (typeof ch === 'object') walk(ch, o.id); };
  for (const o of h.objects ?? []) walk(o, null);
  return { all, parentOf, byName: (n) => [...all.values()].find((o) => o.name === n && (o.types ?? [])[0] === 'Node') };
};
let H = await hierarchy();
const rigId = [...H.all.values()].find((o) => o.name === 'rig').id;
const headId = file.layersV2.face.groupId;

// ---- группы
async function group(name, parentId, opacity = 100) {
  let g = fp.groups[name] && H.all.has(fp.groups[name]) ? fp.groups[name] : H.byName(name)?.id;
  if (!g) {
    await call('group_editor', { name, parentId: rigId, x: 0, y: 0 }); H = await hierarchy(); g = H.byName(name)?.id;
    if (!g) throw new Error(`группа ${name} не создалась`);
  }
  if (H.parentOf.get(g) !== parentId) {
    await call('reparent_objects', { operations: [{ objectId: g, newParentId: parentId, position: 'end' }] }); H = await hierarchy();
  }
  await call('set_property_values', { propertyValues: { [g]: { 18: opacity } } });
  fp.groups[name] = g; save(); return g;
}

// ---- картинка накладки: ассет -> картинка в rig с мировым положением -> в группу
async function place(part, groupId) {
  const key = part.file.replace(/\.png$/, '');
  const old = fp.images[key];
  if (old && H.all.has(old.instance)) {
    if (!REPLACE) return old.instance;
    await call('delete_objects', { objectIds: [old.instance, old.asset] }).catch(() => {});   // --replace: новая картинка
  }
  const b64 = readFileSync(resolve(D, part.file)).toString('base64');
  let asset;
  for (let t = 0; ; t++) {
    const before = new Set(((await call('assets_tool', { command: 'listAssets' })).assets ?? []).map((a) => a.id));
    asset = (await call('upload_asset', { file: `data:image/png;name=face_${key}.png;base64,${b64}`, name: `face_${key}` })).asset;
    // редактор иногда отвечает временным id 0-0 — ждём настоящий ассет с этим именем
    for (let w = 0; asset?.id === '0-0' && w < 8; w++) {
      await new Promise((r) => setTimeout(r, 1500));
      const fresh = ((await call('assets_tool', { command: 'listAssets' })).assets ?? []).find((a) => a.name === `face_${key}` && a.id !== '0-0' && !before.has(a.id));
      if (fresh) asset = { id: fresh.id };
    }
    if (asset?.id !== '0-0') break;
    if (t >= 3) throw new Error(`${key}: ассет не создаётся (0-0)`);
    console.log(`  ${key}: загрузка не состоялась, повтор`);
  }
  let inst;
  for (let t = 0; ; t++) {
    try { inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: asset.id, parentId: rigId, name: `${key}_img`, x: 0, y: 0 } } }); }
    catch (e) { if (!/not an ImageAsset/.test(e.message) || t >= 12) throw e; await new Promise((r) => setTimeout(r, 2500)); continue; }
    const q = await call('query_objects', { objectIds: [inst.imageId] }).catch(() => ({ objects: [] }));
    if ((q.objects ?? []).some((o) => o.id === inst.imageId && o.types[0] === 'Image')) break;
    if (t >= 3) throw new Error(`${key}: картинка не создаётся`);
  }
  const [cx, cy] = part.center_frame; const sc = S * part.px_scale * 100;
  const x = WORLD.x + (cx - FW / 2) * S, y = WORLD.y + (cy - FH / 2) * S;
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: x, 14: y, 15: 0, 16: sc, 17: sc, 18: 100 } } });
    const v = (await call('query_property_values', { propertyKeys: { [inst.imageId]: [13, 14, 16] } })).values?.[inst.imageId] ?? {};
    if (Math.abs(v['16'] - sc) < 1e-3 && Math.abs(v['13'] - x) < 1e-2 && Math.abs(v['14'] - y) < 1e-2) break;
    if (t >= 5) throw new Error(`${key}: трансформ не записывается`);
  }
  for (let t = 0; ; t++) {
    const rr = await call('reparent_objects', { operations: [{ objectId: inst.imageId, newParentId: groupId, position: 'end' }] });
    if ((rr.reparented ?? []).some((o) => o.id === inst.imageId)) break;
    if (t >= 8) throw new Error(`${key}: не переносится в группу`);
    await new Promise((r) => setTimeout(r, 1500 * (1 + (t >> 1))));
  }
  fp.images[key] = { asset: asset.id, instance: inst.imageId, group: groupId }; save();
  console.log(`  ${key} -> ${inst.imageId}`);
  return inst.imageId;
}

const fx = await group('face_fx', headId);
for (const k of ['l', 'r']) {
  const g = await group(`gaze_${k}`, fx);
  await place(P.gaze[`socket_${k}`], g);
  const bead = await place(P.gaze[`bead_${k}`], g);
  await call('reorder_objects', { operations: [{ objectId: bead, order: 'sendToFront' }] });   // бусина над глазницей
}
for (const [name, e] of Object.entries(P.expressions)) {
  const g = await group(`fx_${name}`, fx, 0);
  for (const k of ['mouth', 'eye_l', 'eye_r', 'blush']) if (e[k]) await place(e[k], g);
  console.log(`fx_${name} готово`);
}
// порядок внутри face_fx: взгляд снизу, выражения сверху; face_fx — поверх face_img
for (const name of ['gaze_l', 'gaze_r', ...Object.keys(P.expressions).map((n) => `fx_${n}`)])
  await call('reorder_objects', { operations: [{ objectId: fp.groups[name], order: 'sendToFront' }] });
await call('reorder_objects', { operations: [{ objectId: fx, order: 'sendToFront' }] });
save();
console.log('мимика на месте:', Object.keys(fp.images).length, 'картинок');
