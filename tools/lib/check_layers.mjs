import { readFileSync } from 'node:fs';
import { extname } from 'node:path';
import { artistLayers, isSnakeCase } from './rig.mjs';

/**
 * Extracts layer names from what an artist actually hands over.
 *
 * Supported inputs:
 *   .svg        - id / inkscape:label / data-name on any element
 *   .txt / .md  - one layer name per line (export a layer list from the DCC tool)
 *   .json       - either a bare array of names, or { layers: [...] }
 */
export function extractLayerNames(filePath) {
  const raw = readFileSync(filePath, 'utf8');
  const ext = extname(filePath).toLowerCase();

  if (ext === '.json') {
    const parsed = JSON.parse(raw);
    const list = Array.isArray(parsed) ? parsed : parsed.layers;
    if (!Array.isArray(list)) throw new Error(`${filePath}: expected an array or { "layers": [...] }`);
    return dedupe(list.map((entry) => (typeof entry === 'string' ? entry : entry.name)).filter(Boolean));
  }

  if (ext === '.svg') {
    const names = [];
    // Layer identity in exported SVG lands in one of these three attributes
    // depending on the tool (Illustrator, Figma, Inkscape).
    for (const attr of ['inkscape:label', 'data-name', 'id']) {
      const pattern = new RegExp(`${attr.replace(':', '\\\\:')}="([^"]+)"`, 'g');
      for (const match of raw.matchAll(pattern)) names.push(match[1]);
    }
    return dedupe(names);
  }

  return dedupe(
    raw
      .split(/\r?\n/)
      .map((line) => line.replace(/^[\s\-*+>|]+/, '').trim())
      .filter((line) => line && !line.startsWith('#')),
  );
}

function dedupe(list) {
  return [...new Set(list)];
}

/** Longest-common-subsequence-free cheap edit distance, capped for speed. */
function distance(a, b) {
  if (Math.abs(a.length - b.length) > 4) return 99;
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i += 1) {
    let diagonal = prev[0];
    prev[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const next = Math.min(prev[j] + 1, prev[j - 1] + 1, diagonal + (a[i - 1] === b[j - 1] ? 0 : 1));
      diagonal = prev[j];
      prev[j] = next;
    }
  }
  return prev[b.length];
}

/**
 * Compares delivered layer names against the layers the rig spec requires.
 * Near-misses are reported as renames rather than as missing+extra pairs,
 * because a rename is a one-click fix and a genuine omission is not.
 */
export function checkLayers(rig, delivered) {
  const required = artistLayers(rig);
  const deliveredSet = new Set(delivered);
  const claimed = new Set();

  const matched = [];
  const missing = [];
  const renames = [];

  for (const node of required) {
    if (deliveredSet.has(node.name)) {
      matched.push(node.name);
      claimed.add(node.name);
      continue;
    }
    const candidate = delivered
      .filter((name) => !claimed.has(name))
      .map((name) => ({ name, score: distance(node.name, name) }))
      .filter(({ score }) => score <= 3)
      .sort((a, b) => a.score - b.score)[0];

    if (candidate) {
      renames.push({ expected: node.name, delivered: candidate.name, distance: candidate.score, optional: !!node.optional });
      claimed.add(candidate.name);
    } else {
      missing.push({ name: node.name, optional: !!node.optional, status: node.status });
    }
  }

  const knownNames = new Set(rig.nodes.map((n) => n.name));
  const extra = delivered.filter((name) => !claimed.has(name) && !knownNames.has(name));
  const badCase = delivered.filter((name) => !isSnakeCase(name));

  const blocking = missing.filter((m) => !m.optional);
  return {
    matched,
    missing,
    renames,
    extra,
    badCase,
    requiredCount: required.length,
    ok: blocking.length === 0 && renames.filter((r) => !r.optional).length === 0 && badCase.length === 0,
  };
}

export function formatReport(result, { color = true } = {}) {
  const paint = (text, code) => (color ? `\u001b[${code}m${text}\u001b[0m` : text);
  const out = [];
  const covered = result.matched.length;
  out.push(`Layers matched: ${covered}/${result.requiredCount}`);

  if (result.badCase.length) {
    out.push(paint(`\nNot snake_case (${result.badCase.length}) - rename in the source file:`, '31'));
    for (const name of result.badCase) out.push(`  ${name}`);
  }
  if (result.renames.length) {
    out.push(paint(`\nProbable renames (${result.renames.length}):`, '33'));
    for (const r of result.renames) out.push(`  ${r.delivered}  ->  ${r.expected}${r.optional ? ' (optional)' : ''}`);
  }
  const blocking = result.missing.filter((m) => !m.optional);
  if (blocking.length) {
    out.push(paint(`\nMissing required layers (${blocking.length}):`, '31'));
    for (const m of blocking) out.push(`  ${m.name}`);
  }
  const optionalMissing = result.missing.filter((m) => m.optional);
  if (optionalMissing.length) {
    out.push(paint(`\nMissing optional layers (${optionalMissing.length}) - fine for MVP:`, '90'));
    out.push(`  ${optionalMissing.map((m) => m.name).join(', ')}`);
  }
  if (result.extra.length) {
    out.push(paint(`\nUnexpected layers (${result.extra.length}) - not in the rig spec:`, '36'));
    for (const name of result.extra) out.push(`  ${name}`);
  }
  out.push(result.ok ? paint('\nPASS - ready to rig.', '32') : paint('\nFAIL - send the notes above back to the artist.', '31'));
  return out.join('\n');
}
