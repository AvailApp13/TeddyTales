#!/usr/bin/env node
/**
 * Ставит слои мишки (PNG из Higgsfield, все в одном кадре) в открытый файл
 * Rive через MCP. Файлы берутся с диска мака по абсолютному пути — редактор
 * читает их сам, через контейнер байты не идут.
 *
 *   RIVE_MCP_URL=https://<tunnel>/mcp node scripts/place_parts.mjs /Users/a123/bear_parts [--replace]
 *
 * Имена файлов = ключи handoff/reference/higgsfield_jobs.json (head.png, ears.png,
 * outfit_head.png, outfit_body.png, body.png, arm_left.png, arm_right.png,
 * leg_left.png, leg_right.png, outfit_feet.png, face_features.png).
 * --replace: удалить старую цельную картинку (rive/editor_state.json → referenceImage).
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { AB } from '../lib/gen_rml.mjs';

// Кадр съёмки: фото 1334×2000; ось симметрии x=665, земля y=1640, рост без капюшона 815 px.
const PHOTO = { w: 1334, axisX: 665, groundY: 1640, figureHeight: 815 };
// Куда кладём слой в риге (группа из спеки).
const PARENT = {
  head: 'head', ears: 'head', face_features: 'ctrl_face',
  outfit_head: 'outfit_head', outfit_body: 'outfit_body', outfit_feet: 'outfit_feet',
  body: 'body', arm_left: 'forearm_left', arm_right: 'forearm_right',
  leg_left: 'leg_left', leg_right: 'leg_right',
  full_no_tag: 'rig', cutout_ai: 'rig',
};

const [folder, ...flags] = process.argv.slice(2);
if (!folder) { console.error('нужен путь к папке с PNG'); process.exit(1); }
const replace = flags.includes('--replace');
const statePath = resolve(repoRoot, 'rive', 'editor_state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const file = Object.values(state)[0];
const boardId = file.artboards.Bear_Boy.id;

const c = new RiveMcpClient({ timeoutMs: 180000 });
await c.initialize();
const call = async (tool, args) => {
  const t = toolText(await c.callTool(tool, args));
  let r; try { r = JSON.parse(t); } catch { throw new Error(`${tool}: ${t.slice(0, 300)}`); }
  if (r.success === false) throw new Error(`${tool}: ${JSON.stringify(r).slice(0, 300)}`);
  return r;
};

// Мировые координаты групп: сумма локальных x/y по цепочке родителей.
const hier = await call('get_artboard_hierarchy', { artboardId: boardId, depth: 12 });
const objects = hier.objects ?? [];
const byName = new Map(); const parentOf = new Map();
for (const o of objects) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const need = new Set(Object.values(PARENT).map((n) => byName.get(n)?.id).filter(Boolean));
const chain = new Set();
for (const id of need) { let cur = id; while (cur && cur !== boardId) { chain.add(cur); cur = parentOf.get(cur); } }
const keys = {}; for (const id of chain) keys[id] = [13, 14];
const vals = (await call('query_property_values', { propertyKeys: keys })).values ?? {};
const world = (id) => { let x = 0, y = 0, cur = id; while (cur && cur !== boardId) { x += vals[cur]?.['13'] ?? 0; y += vals[cur]?.['14'] ?? 0; cur = parentOf.get(cur); } return { x, y }; };

const files = readdirSync(folder).filter((f) => /\.png$/i.test(f)).sort();
file.parts ??= {};
for (const f of files) {
  const name = basename(f, '.png');
  const parentName = PARENT[name];
  if (!parentName) { console.log(`пропуск ${f}: нет места в риге`); continue; }
  const parent = byName.get(parentName);
  if (!parent) { console.log(`пропуск ${f}: группа ${parentName} не найдена`); continue; }
  const up = await call('upload_asset', { file: resolve(folder, f), name });
  const a = up.asset;
  const k = a.width / PHOTO.w;                       // фото -> картинка
  const S = AB.figureHeight / (PHOTO.figureHeight * k); // картинка -> артборд
  const cx = AB.w / 2 - (PHOTO.axisX * k - a.width / 2) * S;
  const cy = AB.groundY - (PHOTO.groundY * k - a.height / 2) * S;
  const pw = world(parent.id);
  const inst = await call('assets_tool', { command: 'addImageInstance', data: { addImageInstance: { assetId: a.id, parentId: parent.id, name: `${name}_img`, x: cx - pw.x, y: cy - pw.y } } });
  await call('set_property_values', { propertyValues: { [inst.imageId]: { 13: cx - pw.x, 14: cy - pw.y, 16: S * 100, 17: S * 100 } } });
  await call('reorder_objects', { operations: [{ objectId: inst.imageId, order: 'sendToBack' }] });
  file.parts[name] = { asset: a.id, instance: inst.imageId, parent: parent.id, sizePx: [a.width, a.height], scalePercent: +(S * 100).toFixed(2), world: { x: +cx.toFixed(1), y: +cy.toFixed(1) } };
  console.log(`${name.padEnd(14)} ${a.width}x${a.height} -> ${parentName} масштаб ${(S * 100).toFixed(1)}%`);
}
if (replace && file.referenceImage) {
  const { instance, asset } = file.referenceImage;
  await call('delete_objects', { objectIds: [instance, asset] });
  console.log(`удалена старая картинка ${instance} и ассет ${asset}`);
  file.referenceImageRemoved = file.referenceImage; delete file.referenceImage;
}
writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
console.log('готово');
