#!/usr/bin/env node
/**
 * Возвращает ключи и скорость таймлайнов из rive/_keys_backup.json — копии, которую
 * пишет with_rest_pose.mjs перед заморозкой анимации в покое. Нужен, если связь с
 * редактором оборвалась посреди with_rest_pose (туннель упал) и ключи остались
 * замороженными.
 *
 *   RIVE_MCP_URL=... node scripts/restore_keys.mjs
 *
 * Ключи удалённых с тех пор объектов и таймлайнов пропускаются.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RiveMcpClient, jsonCaller } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const { speeds, keys } = JSON.parse(readFileSync(resolve(repoRoot, 'rive', '_keys_backup.json'), 'utf8'));
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = jsonCaller(c, { log: console.log });
const anims = new Set(((await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? []).map((a) => a.id));
const ids = Object.keys(keys).filter((id) => anims.has(id));
const now = (await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: ids } } })).keyframes ?? {};
let n = 0;
for (const animId of ids) {
  const live = new Set((now[animId] ?? []).map((k) => k.keyframeId));
  const list = keys[animId].filter((k) => typeof k.value === 'number' && live.has(k.keyframeId)).map((k) => ({ keyframeId: k.keyframeId, value: k.value }));
  for (let i = 0; i < list.length; i += 80) await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: animId, change: list.slice(i, i + 80) } } });
  n += list.length;
}
await call('set_property_values', { propertyValues: Object.fromEntries(Object.entries(speeds).filter(([id]) => anims.has(id)).map(([id, v]) => [id, { 58: v['58'] }])) });
console.log(`восстановлено ключей: ${n} в ${ids.length} таймлайнах`);
