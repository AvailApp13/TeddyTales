#!/usr/bin/env node
/**
 * Проверяет, что каждый слой мишки v2 лежит в своей группе рига, и чинит
 * сбившиеся: слой -> rig, точный общий трансформ (как в place_layers_v3),
 * -> своя группа (редактор сохраняет мировое положение). Запускать только в
 * позе покоя: scripts/with_rest_pose.mjs -- node scripts/fix_layer_parents.mjs
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';
import { AB } from '../lib/gen_rml.mjs';

const meta = JSON.parse(readFileSync(resolve(repoRoot, 'handoff', 'layers_v2', 'layers.json'), 'utf8'));
const photo = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'bear_proportions.json'), 'utf8')).photo;
const S = AB.figureHeight / photo.bodyHeightPx; const [W, H] = meta.size;
const WORLD = { x: AB.w / 2 + (W / 2 - photo.axisX) * S, y: AB.groundY - (photo.groundY - H / 2) * S };
const state = JSON.parse(readFileSync(resolve(repoRoot, 'rive', 'editor_state.json'), 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = async (t, a) => { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 300)}`); return r; };
const info = await call('session_info', {}); const file = state[String(info.activeFileId)];
const board = file.artboards.Bear_Boy.id;
const hier = await call('get_artboard_hierarchy', { artboardId: board, depth: 14 });
const byName = new Map(); const parentOf = new Map();
for (const o of hier.objects ?? []) { if (!byName.has(o.name)) byName.set(o.name, o); for (const ch of o.children ?? []) parentOf.set(ch, o.id); }
const rigId = byName.get('rig').id;
let fixed = 0;
for (const [name, L] of Object.entries(file.layersV2)) {
  const g = byName.get(L.group);
  if (parentOf.get(L.instance) === g.id) continue;
  await call('reparent_objects', { operations: [{ objectId: L.instance, newParentId: rigId, position: 'end' }] });
  await call('set_property_values', { propertyValues: { [L.instance]: { 13: WORLD.x, 14: WORLD.y, 15: 0, 16: S * 100, 17: S * 100 } } });
  const r = await call('reparent_objects', { operations: [{ objectId: L.instance, newParentId: g.id, position: 'end' }] });
  if (!(r.reparented ?? []).length) throw new Error(`${name}: не перенёсся в ${L.group}: ${JSON.stringify(r)}`);
  console.log(`${name}: перенесён в ${L.group}`); fixed++;
}
console.log(fixed ? `исправлено слоёв: ${fixed}` : 'все слои на своих местах');
