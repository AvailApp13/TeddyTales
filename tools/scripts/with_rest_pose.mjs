#!/usr/bin/env node
/**
 * Выполняет команду, пока анимация мишки заморожена в позе покоя.
 * Нужно для привязки сеток и перестановки слоёв: если в редакторе идёт
 * проигрывание, кости стоят в случайном кадре и привязка портится.
 *
 *   RIVE_MCP_URL=... node scripts/with_rest_pose.mjs -- node scripts/place_layers_v3.mjs
 *
 * 1. Сохраняет значения всех ключей всех таймлайнов (rive/_keys_backup.json).
 * 2. Ставит каждому ключу значение кадра 0 своей дорожки, скорость таймлайнов 0.
 * 3. Запускает команду. 4. Всегда возвращает ключи и скорость, сверяет.
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { RiveMcpClient, toolText } from '../lib/rive_mcp.mjs';
import { repoRoot } from '../lib/rig.mjs';

const cmd = process.argv.slice(process.argv.indexOf('--') + 1);
const c = new RiveMcpClient({ timeoutMs: 240000 }); await c.initialize();
const call = async (t, a) => {
  for (let i = 0; i < 6; i++) {
    try { const r = JSON.parse(toolText(await c.callTool(t, a))); if (r.success === false) throw new Error(`${t}: ${JSON.stringify(r).slice(0, 300)}`); return r; }
    catch (e) { if (!/ENOTFOUND|DNS|пустой ответ/.test(e.message)) throw e; await new Promise((r) => setTimeout(r, 8000)); }
  }
  throw new Error(`${t}: нет связи`);
};
const anims = (await call('animation_editor', { command: 'listLinearAnimations', data: {} })).linearAnimations ?? [];
const ids = anims.map((a) => a.id);
const kf = (await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: ids } } })).keyframes ?? {};
const speeds = (await call('query_property_values', { propertyKeys: Object.fromEntries(ids.map((id) => [id, [58]])) })).values;
const backup = { speeds, keys: kf };
writeFileSync(resolve(repoRoot, 'rive', '_keys_backup.json'), JSON.stringify(backup));
const change = async (animId, list) => { for (let i = 0; i < list.length; i += 80) await call('animation_editor', { command: 'modifyKeyFrames', data: { modifyKeyFrames: { animationId: animId, change: list.slice(i, i + 80) } } }); };
let status = 1;
try {
  for (const [animId, keys] of Object.entries(kf)) {
    const rest = {}; for (const k of keys) { const t = `${k.objectId}:${k.propertyKey}`; if (!(t in rest) || k.frame < rest[t].frame) rest[t] = k; }
    await change(animId, keys.filter((k) => typeof k.value === 'number').map((k) => ({ keyframeId: k.keyframeId, value: rest[`${k.objectId}:${k.propertyKey}`].value })));
  }
  await call('set_property_values', { propertyValues: Object.fromEntries(ids.map((id) => [id, { 58: 0 }])) });
  await new Promise((r) => setTimeout(r, 1500));
  console.log(`анимация заморожена в покое (${Object.values(kf).flat().length} ключей)`);
  status = spawnSync(cmd[0], cmd.slice(1), { stdio: 'inherit', env: process.env }).status ?? 1;
} finally {
  for (const [animId, keys] of Object.entries(kf)) await change(animId, keys.filter((k) => typeof k.value === 'number').map((k) => ({ keyframeId: k.keyframeId, value: k.value })));
  await call('set_property_values', { propertyValues: Object.fromEntries(Object.entries(speeds).map(([id, v]) => [id, { 58: v['58'] }])) });
  const now = (await call('animation_editor', { command: 'queryKeyFrames', data: { queryKeyFrames: { animationIds: ids } } })).keyframes ?? {};
  const byId = new Map(Object.values(now).flat().map((k) => [k.keyframeId, k.value]));
  const bad = Object.values(kf).flat().filter((k) => typeof k.value === 'number' && Math.abs((byId.get(k.keyframeId) ?? NaN) - k.value) > 1e-6);
  console.log(bad.length ? `ВНИМАНИЕ: не восстановлено ключей: ${bad.length}` : 'ключи и скорость анимации восстановлены');
}
process.exit(status);
