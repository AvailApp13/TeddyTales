#!/usr/bin/env node
/**
 * Веса сеток (tools/lib/bear_weights.mjs) на сетке кадра — для офлайн-симулятора
 * поз (simulate_pose.py). Пишет JSON: { step, size, layers: { слой: { кость: [[...]] } } }.
 *
 *   node tools/scripts/dump_weights.mjs <out.json> [step=6]
 */
import { writeFileSync } from 'node:fs';
import { loadWeights } from '../lib/bear_weights.mjs';

const [out, stepArg] = process.argv.slice(2);
const step = Number(stepArg ?? 6);
const { PLAN, meta } = loadWeights();
const [W, H] = meta.size;
const layers = {};
for (const [name, p] of Object.entries(PLAN)) {
  const grids = Object.fromEntries(p.bones.map((b) => [b, []]));
  for (let y = 0; y <= H; y += step) {
    const rows = Object.fromEntries(p.bones.map((b) => [b, []]));
    for (let x = 0; x <= W; x += step) {
      const w = p.w(x, y); const sum = Object.values(w).reduce((s, v) => s + v, 0) || 1;
      for (const b of p.bones) rows[b].push(Math.round(((w[b] ?? 0) / sum) * 1000) / 1000);
    }
    for (const b of p.bones) grids[b].push(rows[b]);
  }
  layers[name] = grids;
}
writeFileSync(out, JSON.stringify({ step, size: [W, H], layers }));
