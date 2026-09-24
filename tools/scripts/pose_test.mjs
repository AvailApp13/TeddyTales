import { writeFileSync } from 'node:fs';
import { RiveMcpClient, toolText } from '/home/user/TeddyTales/tools/lib/rive_mcp.mjs';
const S = process.env.S ?? '.'; // куда класть снимки поз
const B = { root_body: '0-391', root_arm_left: '0-393', root_arm_right: '0-392', root_leg_left: '0-394', root_leg_right: '0-395' };
const POSES = JSON.parse(process.argv[2]); // [{name, delta:{bone:deg}}]
const c = new RiveMcpClient({ timeoutMs: 120000 }); await c.initialize();
const call = async (t, a) => JSON.parse(toolText(await c.callTool(t, a)));
const base = (await call('query_property_values', { propertyKeys: Object.fromEntries(Object.values(B).map((id) => [id, [15]])) })).values;
try {
  for (const pose of POSES) {
    const pv = {}; for (const [b, id] of Object.entries(B)) pv[id] = { 15: base[id]["15"] + (pose.delta[b] ?? 0) };
    await call('set_property_values', { propertyValues: pv });
    const r = await c.callTool('capture_artboard', { artboardId: '0-2', longEdge: 1024 });
    const img = (r.content ?? []).find((p) => p.type === 'image'); writeFileSync(`${S}/pose_${pose.name}.png`, Buffer.from(img.data, 'base64'));
    console.log('поза', pose.name);
  }
} finally {
  await call('set_property_values', { propertyValues: Object.fromEntries(Object.entries(base).map(([id, v]) => [id, { 15: v['15'] }])) });
  console.log('кости возвращены');
}
