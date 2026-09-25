#!/usr/bin/env node
/**
 * Заменяет картинки слоёв мишки v2 в открытом файле свежими PNG из
 * handoff/layers_v2 (после перенарезки). Запускать в позе покоя:
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/replace_layers.mjs hood_lining [...]
 *
 * В Rive картинка на сцене держится за ассет: удаление ассета удаляет и её,
 * а подменить ассет свойством нельзя. Поэтому: старые картинка и ассет
 * удаляются, новый ассет -> картинка в rig с общим трансформом -> своя группа.
 * Сетки (skin) удаляются вместе с картинкой: для слоёв из skin_layers.mjs
 * после замены запустить его снова.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { AB } from '../lib/gen_rml.mjs';

const names = process.argv.slice(2);
const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const photo = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'bear_proportions.json'), 'utf8')).photo;
const S = AB.figureHeight / photo.bodyHeightPx; const [W, H] = meta.size;
const WORLD = { x: AB.w / 2 + (W / 2 - photo.axisX) * S, y: AB.groundY - (photo.groundY - H / 2) * S };
const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });   // повторы при кратких сбоях редактора
const file = state[String((await call('session_info', {})).activeFileId)];
const hier = await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id, depth: 14 });
const byName = new Map(); for (const o of hier.objects ?? []) if (!byName.has(o.name)) byName.set(o.name, o);
const rigId = byName.get('rig').id;
// удаление старой картинки и ассета — по одному: если ассета уже нет (устаревший id в
// состоянии), общий вызов отклоняется целиком и старая картинка оставалась дублем
async function removeImage(instance, assetId) {
  for (const id of [instance, assetId].filter(Boolean)) await call('delete_objects', { objectIds: [id] }).catch(() => {});
  const left = ((await call('query_objects', { objectIds: [instance] }).catch(() => ({ objects: [] }))).objects ?? []).some((o) => o.id === instance);
  if (left) throw new Error(`картинка ${instance} не удаляется`);
}
for (const name of names) {
  const L = file.layersV2[name]; const g = byName.get(L.group);
  let asset;
  const assets = (await call('assets_tool', { command: 'listAssets' })).assets ?? [];
  const before = new Set(assets.map((a) => a.id));
  if (!L.instance && assets.some((a) => a.id === L.asset && a.type === 'image')) {
    asset = { id: L.asset };                                   // картинки нет, ассет уже загружен — берём его
  } else {
    if (L.instance) await removeImage(L.instance, L.asset);
    const b64 = readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', `${name}.png`)).toString('base64');
    for (let t = 0; ; t++) {
      asset = (await call('upload_asset', { file: `data:image/png;name=bear_${name}.png;base64,${b64}`, name: `bear_${name}` })).asset;
      // редактор иногда отвечает временным id 0-0, пока ассет не создан, — ждём настоящий по имени
      for (let w = 0; asset?.id === '0-0' && w < 10; w++) {
        await new Promise((r) => setTimeout(r, 1500));
        const now = (await call('assets_tool', { command: 'listAssets' })).assets ?? [];
        const fresh = now.find((a) => a.name === `bear_${name}` && a.type === 'image' && a.id !== '0-0' && !before.has(a.id));
        if (fresh) asset = { id: fresh.id };
      }
      if (asset?.id && asset.id !== '0-0') break;
      if (t >= 2) throw new Error(`${name}: ассет не создаётся (id 0-0)`);
    }
  }
  // картинка иногда не создаётся, хотя id вернулся — проверяем и повторяем
  let inst;
  for (let t = 0; ; t++) {
    // ассет после загрузки иногда ещё не готов («not an ImageAsset») — ждём и повторяем
    try {
      inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: asset.id, parentId: rigId, name: `${name}_img`, x: WORLD.x, y: WORLD.y } } });
    } catch (e) {
      if (!/not an ImageAsset/.test(e.message) || t >= 12) throw e;
      // ждём именно этот ассет: искать «похожий» по имени нельзя — подхватится
      // старый ассет от прошлой неудачной загрузки со старой картинкой.
      // Если за ~10 с он так и не появился в списке — загрузка не состоялась, грузим заново.
      console.log(`  ${name}: ассет ${asset.id} ещё не готов, жду`);
      await new Promise((r) => setTimeout(r, 2500));
      if (t % 4 === 3) {
        const now = (await call('assets_tool', { command: 'listAssets' })).assets ?? [];
        if (!now.some((a) => a.id === asset.id)) {
          console.log(`  ${name}: ассета ${asset.id} нет — загружаю заново`);
          asset = (await call('upload_asset', { file: `data:image/png;name=bear_${name}.png;base64,${readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', `${name}.png`)).toString('base64')}`, name: `bear_${name}` })).asset;
        }
      }
      continue;
    }
    const q = await call('query_objects', { objectIds: [inst.imageId] }).catch(() => ({ objects: [] }));
    if ((q.objects ?? []).some((o) => o.id === inst.imageId && o.types[0] === 'Image')) break;
    if (t >= 3) throw new Error(`${name}: картинка не создаётся`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  await call('reparent_objects', { operations: [{ objectId: inst.imageId, newParentId: rigId, position: 'end' }] });
  // запись трансформа редактор иногда молча теряет (картинка остаётся 100 %) — проверяем
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: WORLD.x, 14: WORLD.y, 15: 0, 16: S * 100, 17: S * 100, 18: 100 } } });
    const v = (await call('query_property_values', { propertyKeys: { [inst.imageId]: [13, 14, 16, 17] } })).values?.[inst.imageId] ?? {};
    if (Math.abs(v['16'] - S * 100) < 1e-3 && Math.abs(v['17'] - S * 100) < 1e-3 && Math.abs(v['13'] - WORLD.x) < 1e-2 && Math.abs(v['14'] - WORLD.y) < 1e-2) break;
    if (t >= 5) throw new Error(`${name}: трансформ не записывается`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  for (let t = 0; ; t++) {
    const rr = await call('reparent_objects', { operations: [{ objectId: inst.imageId, newParentId: g.id, position: 'end' }] });
    // перенос сохраняет мировой трансформ; мировой масштаб в группе должен остаться S
    if ((rr.reparented ?? []).some((x) => x.id === inst.imageId)) break;
    if (t >= 8) throw new Error(`${name}: не переносится в ${L.group}`);
    await new Promise((r) => setTimeout(r, 1500 * (1 + (t >> 1))));   // редактор иногда отвечает отказом несколько секунд подряд
  }
  if (name.endsWith('_shade')) {
    // тень сгиба уха (D22): над своим ухом, в покое прозрачная — проявляется ключами
    await call('reorder_objects', { operations: [{ objectId: inst.imageId, order: 'sendToFront' }] });
    await call('set_property_values', { propertyValues: { [inst.imageId]: { 18: 0 } } });
  }
  Object.assign(L, { asset: asset.id, instance: inst.imageId });
  if (file.skins?.[name]) delete file.skins[name];
  writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');     // после каждого слоя — не терять при сбое
  console.log(`${name}: ${inst.imageId} (ассет ${asset.id}) -> ${L.group}`);
}
