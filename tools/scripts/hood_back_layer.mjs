#!/usr/bin/env node
/**
 * Группа слоя hood_back (D27) в открытом файле: пустая группа под head, позади групп ушей —
 * уши лежат между задней частью капюшона и капюшоном. Регистрирует слой в editor_state
 * (layersV2.hood_back), картинку ставит replace_layers.mjs, сетку — skin_layers.mjs:
 *
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- sh -c "node scripts/hood_back_layer.mjs && \
 *     node scripts/replace_layers.mjs hood_back ear_left ear_right hood && \
 *     node scripts/skin_layers.mjs hood hood_back ear_left ear_right"
 *
 * Повторный запуск группу не дублирует.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const sp = resolve(repoRoot, 'rive', 'editor_state.json'); const state = JSON.parse(readFileSync(sp, 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 180000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const file = state[String((await call('session_info', {})).activeFileId)];
const headId = file.layersV2.face.groupId;
const hier = async () => (await call('get_artboard_hierarchy', { artboardId: file.artboards.Bear_Boy.id, depth: 14 })).objects ?? [];
const kids = (h) => (h.find((o) => o.id === headId)?.children ?? []).map((ch) => (typeof ch === 'string' ? ch : ch.id));
let h = await hier();
let group = h.find((o) => o.name === 'hood_back' && o.types[0] === 'Node' && kids(h).includes(o.id))?.id;
if (!group) {
  const r = await call('group_editor', { name: 'hood_back', parentId: headId, x: 0, y: 0 });
  group = r.groupId ?? r.id ?? r.group?.id;
  h = await hier();
  group ??= h.find((o) => o.name === 'hood_back' && o.types[0] === 'Node' && kids(h).includes(o.id))?.id;
  if (!group) throw new Error('группа hood_back не создалась под head');
  console.log(`hood_back: группа ${group}`);
}
// позади групп ушей: последним ребёнком head (дальше всех от зрителя)
for (let t = 0; kids(h).at(-1) !== group; t++) {
  if (t >= 5) throw new Error(`hood_back: не встаёт позади ушей (${kids(h).join(', ')})`);
  await call('reorder_objects', { operations: [{ objectId: group, order: 'sendToBack' }] });
  h = await hier();
}
const names = Object.fromEntries(h.map((o) => [o.id, o.name]));
console.log('head (спереди -> назад):', kids(h).map((id) => names[id]).join(', '));
file.layersV2.hood_back = { ...(file.layersV2.hood_back ?? {}), group: 'hood_back', groupId: group };
writeFileSync(sp, JSON.stringify(state, null, 2) + '\n');
