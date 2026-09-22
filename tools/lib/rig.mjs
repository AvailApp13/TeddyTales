import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const rigPath = resolve(repoRoot, 'rig', 'bear_rig.json');

/** Reads and structurally validates rig/bear_rig.json. Throws on a malformed spec. */
export function loadRig(path = rigPath) {
  const rig = JSON.parse(readFileSync(path, 'utf8'));
  const problems = validateRig(rig);
  if (problems.length) {
    throw new Error(`${path} is not a valid rig spec:\n  - ${problems.join('\n  - ')}`);
  }
  return rig;
}

/**
 * Invariants the rest of the toolchain relies on: unique names, resolvable
 * parents, no cycles, exactly one root, and snake_case throughout the rig.
 */
export function validateRig(rig) {
  const problems = [];
  const nodes = rig.nodes ?? [];
  const byName = new Map();

  for (const node of nodes) {
    if (byName.has(node.name)) problems.push(`duplicate node name "${node.name}"`);
    byName.set(node.name, node);
    if (!isSnakeCase(node.name)) problems.push(`node "${node.name}" is not snake_case`);
  }

  const roots = nodes.filter((n) => n.parent === null);
  if (roots.length !== 1) {
    problems.push(`expected exactly 1 root node, found ${roots.length} (${roots.map((r) => r.name).join(', ')})`);
  }

  for (const node of nodes) {
    if (node.parent !== null && !byName.has(node.parent)) {
      problems.push(`node "${node.name}" has unknown parent "${node.parent}"`);
    }
  }

  // Cycle detection: walk each node to the root with a bounded hop count.
  for (const node of nodes) {
    const seen = new Set([node.name]);
    let cursor = node;
    while (cursor?.parent) {
      if (seen.has(cursor.parent)) {
        problems.push(`cycle in the node tree at "${node.name}"`);
        break;
      }
      seen.add(cursor.parent);
      cursor = byName.get(cursor.parent);
    }
  }

  const vmNames = new Set();
  for (const prop of rig.viewModel?.properties ?? []) {
    if (vmNames.has(prop.name)) problems.push(`duplicate view model property "${prop.name}"`);
    vmNames.add(prop.name);
    if (prop.type === 'number' && !(prop.min < prop.max)) {
      problems.push(`view model property "${prop.name}" needs min < max`);
    }
  }

  const blendWeight = rig.stateMachine?.blendStates ?? [];
  for (const blend of blendWeight) {
    if (blend.weightProperty && !vmNames.has(blend.weightProperty)) {
      problems.push(`blend state "${blend.name}" is weighted by unknown property "${blend.weightProperty}"`);
    }
  }

  for (const key of Object.keys(rig.simulation?.decayPerSecond ?? {})) {
    if (!vmNames.has(key)) problems.push(`simulation decays unknown property "${key}"`);
  }
  for (const [action, boosts] of Object.entries(rig.simulation?.actionBoost ?? {})) {
    if (!vmNames.has(action)) problems.push(`simulation boosts on unknown trigger "${action}"`);
    for (const key of Object.keys(boosts)) {
      if (!vmNames.has(key)) problems.push(`simulation boost "${action}" targets unknown property "${key}"`);
    }
  }

  return problems;
}

export function isSnakeCase(name) {
  return /^[a-z][a-z0-9]*(_[a-z0-9]+)*$/.test(name);
}

/** Node names the artist must deliver as separate layers. */
export function artistLayers(rig) {
  return rig.nodes.filter((n) => n.artistLayer);
}

export function childrenOf(rig, name) {
  return rig.nodes.filter((n) => n.parent === name);
}

/** Renders the node hierarchy as an indented ASCII tree. */
export function renderTree(rig, { color = false } = {}) {
  const paint = (text, code) => (color ? `\u001b[${code}m${text}\u001b[0m` : text);
  const NAME_COLUMN = 40;

  const badge = (node) => {
    const kind = { bone: 'bone', control: 'ctrl', art: 'art' }[node.kind] ?? node.kind;
    const tint = { bone: '36', control: '35', art: '32' }[node.kind] ?? '37';
    const flags = [
      node.status !== 'spec' ? paint(node.status, '33') : null,
      node.optional ? paint('optional', '90') : null,
    ].filter(Boolean);
    return [paint(kind, tint), ...flags].join(' ');
  };

  const lines = [];
  const emit = (indent, node) => {
    const label = indent + node.name;
    const pad = ' '.repeat(Math.max(2, NAME_COLUMN - label.length));
    lines.push(label + pad + badge(node));
  };

  const walk = (node, indent) => {
    const kids = childrenOf(rig, node.name);
    kids.forEach((kid, i) => {
      const last = i === kids.length - 1;
      emit(indent + (last ? '\u2514\u2500\u2500 ' : '\u251c\u2500\u2500 '), kid);
      walk(kid, indent + (last ? '    ' : '\u2502   '));
    });
  };

  const root = rig.nodes.find((n) => n.parent === null);
  emit('', root);
  walk(root, '');
  return lines.join('\n');
}
