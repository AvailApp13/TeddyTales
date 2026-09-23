import { writeFileSync, readFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const state = JSON.parse(readFileSync('/home/user/TeddyTales/rive/editor_state.json', 'utf8'));
const parts = Object.values(state)[0].parts;
const ids = Object.fromEntries(Object.entries(parts).map(([n, p]) => [n, p.instance]));
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => { for (let i = 0; i < 6; i++) { try { return JSON.parse(toolText(await c.callTool(t, a))); } catch (e) { if (!/ENOTFOUND|DNS/.test(e.message)) throw e; await new Promise(r => setTimeout(r, 8000)); } } throw new Error('DNS'); };
const q = await call('query_property_values', { propertyKeys: Object.fromEntries(Object.values(ids).map(id => [id, [13, 14, 16, 17, 18]])) });
for (const [n, id] of Object.entries(ids)) console.log(n.padEnd(14), JSON.stringify(q.values?.[id]));
const setOp = async (vals) => call('set_property_values', { propertyValues: Object.fromEntries(Object.values(ids).map(id => [id, { 18: vals[id] ?? 100 }])) });
const only = process.argv[2] ? process.argv[2].split(',') : Object.keys(ids);
for (const n of only) {
  await setOp(Object.fromEntries(Object.values(ids).map(id => [id, id === ids[n] ? 100 : 0])));
  const r = await c.callTool('capture_artboard', { artboardId: '0-2', longEdge: 512 });
  const img = (r.content ?? []).find(p => p.type === 'image');
  if (img) writeFileSync(`${process.env.OUT ?? '.'}/solo_${n}.png`, Buffer.from(img.data, 'base64'));
  console.log('captured', n);
}
await setOp({});
console.log('opacity restored');
