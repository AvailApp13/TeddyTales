#!/usr/bin/env node
import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadRig, renderTree, artistLayers, repoRoot, rigPath } from '../lib/rig.mjs';
import { extractLayerNames, checkLayers, formatReport } from '../lib/check_layers.mjs';
import { generateDartContract, generateLabSpec } from '../lib/gen_dart.mjs';
import { generateRiveProject, loadCatalog } from '../lib/gen_rml.mjs';
import { mkdirSync, copyFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { serveLab } from '../lib/serve.mjs';

const DART_OUT = resolve(repoRoot, 'app', 'lib', 'src', 'bear_rig_contract.dart');
const LAB_SPEC_OUT = resolve(repoRoot, 'lab', 'rig_spec.generated.js');
const RIVE_PROJECT_DIR = resolve(repoRoot, 'rive', 'bear');

const USAGE = `teddy - TeddyTales bear rig workbench

  teddy tree                     print the rig hierarchy
  teddy layers                   list the layers the artist must deliver
  teddy clips                    animation clip catalogue vs the counts promised in the proposal
  teddy check <file>             check delivered layer names against the rig spec
                                 (.svg | .json | .txt - one name per line)
  teddy gen:dart                 regenerate the Dart contract + lab spec from rig/bear_rig.json
  teddy gen:rml                  regenerate the Rive CLI project (rive/bear) from the spec + clip catalogue
  teddy build:riv                gen:rml -> rive --verify -> rive inspect -> rive --once -> app/assets/rive/bear.riv
  teddy doctor                   validate the spec and report what is still blocked
  teddy lab [--port 4321]        serve the local Rive lab
`;

const args = process.argv.slice(2);
const command = args[0];
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

function main() {
  switch (command) {
    case 'tree':
      return cmdTree();
    case 'layers':
      return cmdLayers();
    case 'clips':
      return cmdClips();
    case 'check':
      return cmdCheck();
    case 'gen:dart':
      return cmdGenDart();
    case 'gen:rml':
      return cmdGenRml();
    case 'build:riv':
      return cmdBuildRiv();
    case 'doctor':
      return cmdDoctor();
    case 'lab':
      return cmdLab();
    case undefined:
    case '-h':
    case '--help':
      process.stdout.write(USAGE);
      return 0;
    default:
      process.stderr.write(`Unknown command "${command}"\n\n${USAGE}`);
      return 1;
  }
}

function cmdTree() {
  const rig = loadRig();
  process.stdout.write(renderTree(rig, { color: process.stdout.isTTY }) + '\n');
  return 0;
}

function cmdLayers() {
  const rig = loadRig();
  const layers = artistLayers(rig);
  for (const layer of layers) {
    process.stdout.write(`${layer.name}${layer.optional ? '  # optional' : ''}\n`);
  }
  process.stderr.write(`\n${layers.length} layers (${layers.filter((l) => l.optional).length} optional)\n`);
  return 0;
}

function cmdClips() {
  const catalog = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'animation_catalog.json'), 'utf8'));
  const inScope = Object.entries(catalog.surfaces).filter(([, s]) => s.inScope).map(([key]) => key);

  const lines = [];
  let planned = 0;
  let declared = 0;
  let mismatched = 0;

  for (const [key, group] of Object.entries(catalog.groups)) {
    if (!inScope.includes(group.surface)) continue;
    const count = group.clips.length;
    planned += count;
    declared += group.declaredInProposal;
    const ok = count === group.declaredInProposal;
    if (!ok) mismatched += 1;
    lines.push(
      `  ${ok ? ' ' : '!'} ${group.section.padEnd(5)} ${key.padEnd(10)} ${String(count).padStart(3)} / ${group.declaredInProposal}`,
    );
    if (!ok && group.note) lines.push(`      ${group.note.replace(/\s+/g, ' ')}`);
  }

  for (const surface of inScope) {
    process.stdout.write(`${catalog.surfaces[surface].label}\n`);
  }
  process.stdout.write(lines.join('\n') + '\n');
  process.stdout.write(`\n  ИТОГО        ${planned} расписано / ${declared} обещано в КП\n`);

  if (mismatched) {
    process.stdout.write(
      `\n  ${mismatched} группы не сходятся с цифрой КП. Это вопрос к Заказчику, а не ошибка счёта -\n` +
        '  см. примечание у каждой группы выше и docs/open-questions.md, Q1.\n',
    );
  }

  // Что размечено, но в этой ветке не делается.
  const outOfScope = Object.values(catalog.surfaces).filter((s) => !s.inScope);
  if (outOfScope.length) {
    process.stdout.write('\nВне границ этой ветки\n');
    for (const [key, surface] of Object.entries(catalog.surfaces)) {
      if (surface.inScope) continue;
      const groups = Object.values(catalog.groups).filter((g) => g.surface === key);
      const extra = catalog.birthScene.surface === key ? catalog.birthScene.clips.length : 0;
      const count = groups.reduce((n, g) => n + g.clips.length, 0) + extra;
      process.stdout.write(`  - ${surface.label}: ${count} клипов (КП ${surface.kpSections.join(', ')})\n`);
    }
  }

  process.stdout.write(`\nСлоты одежды: ${catalog.outfitSlots.slots.length} (КП ${catalog.outfitSlots.section}) - привязаны к костям, работают во всех клипах комнаты.\n`);
  return 0;
}

function cmdCheck() {
  const target = args[1];
  if (!target) {
    process.stderr.write('teddy check needs a file: teddy check handoff/bear_layers.svg\n');
    return 1;
  }
  if (!existsSync(target)) {
    process.stderr.write(`No such file: ${target}\n`);
    return 1;
  }
  const rig = loadRig();
  const delivered = extractLayerNames(target);
  process.stderr.write(`Read ${delivered.length} layer names from ${target}\n\n`);
  const result = checkLayers(rig, delivered);
  process.stdout.write(formatReport(result, { color: process.stdout.isTTY }) + '\n');
  return result.ok ? 0 : 1;
}

function cmdGenDart() {
  const rig = loadRig();
  writeFileSync(DART_OUT, generateDartContract(rig, { rigFile: rigPath }));
  writeFileSync(LAB_SPEC_OUT, generateLabSpec(rig));
  process.stdout.write(`Wrote ${DART_OUT.replace(repoRoot + '/', '')}\n`);
  process.stdout.write(`Wrote ${LAB_SPEC_OUT.replace(repoRoot + '/', '')}\n`);
  return 0;
}

function cmdGenRml() {
  const rig = loadRig();
  const catalog = loadCatalog();
  const { rml, yaml } = generateRiveProject(rig, catalog);
  mkdirSync(RIVE_PROJECT_DIR, { recursive: true });
  writeFileSync(resolve(RIVE_PROJECT_DIR, 'scene.rml'), rml);
  writeFileSync(resolve(RIVE_PROJECT_DIR, 'rive.yaml'), yaml);
  process.stdout.write(`Wrote rive/bear/scene.rml (${rml.split('\n').length} lines)\nWrote rive/bear/rive.yaml\n`);
  process.stdout.write('Next: rive rive/bear --verify && rive inspect rive/bear --summary\n');
  return 0;
}

/**
 * Полный цикл спека -> .riv. Каждый шаг останавливает цикл при ошибке, чтобы в
 * app/assets никогда не попал файл, который не прошёл inspect.
 */
function cmdBuildRiv() {
  const rig = loadRig();
  if (cmdGenRml() !== 0) return 1;

  const run = (label, args) => {
    process.stdout.write(`\n> rive ${args.join(' ')}\n`);
    const result = spawnSync('rive', args, { cwd: repoRoot, encoding: 'utf8' });
    if (result.error) {
      process.stderr.write(`rive CLI not found (${result.error.message}). Install: docs/rive-cli-workflow.md\n`);
      return null;
    }
    process.stdout.write((result.stdout ?? '') + (result.stderr ?? ''));
    if (result.status !== 0) {
      process.stderr.write(`${label} failed (exit ${result.status})\n`);
      return null;
    }
    return result.stdout ?? '';
  };

  if (run('verify', ['rive/bear', '--verify']) === null) return 1;

  const inspect = run('inspect', ['inspect', 'rive/bear', '--summary']);
  if (inspect === null) return 1;
  let problems = [];
  try {
    problems = JSON.parse(inspect).problems ?? [];
  } catch {
    process.stderr.write('could not parse `rive inspect` output\n');
    return 1;
  }
  const errors = problems.filter((p) => p.severity === 'error');
  if (errors.length) {
    process.stderr.write(`inspect reported ${errors.length} error(s); not writing the .riv\n`);
    return 1;
  }

  if (run('build', ['rive/bear', '--once']) === null) return 1;

  const built = resolve(RIVE_PROJECT_DIR, 'build', 'bear.riv');
  const target = resolve(repoRoot, rig.runtime.riveAssetPath);
  mkdirSync(resolve(target, '..'), { recursive: true });
  copyFileSync(built, target);
  process.stdout.write(`\nCopied -> ${rig.runtime.riveAssetPath}\n`);
  process.stdout.write(`${problems.length} inspect warning(s). Next: npm run lab -> "Load from repo"\n`);
  return 0;
}

function cmdDoctor() {
  const rig = loadRig();
  const lines = [];
  lines.push('Rig spec');
  lines.push(`  spec version      ${rig.specVersion}`);
  lines.push(`  nodes             ${rig.nodes.length} (${rig.nodes.filter((n) => n.kind === 'bone').length} bone, ${rig.nodes.filter((n) => n.kind === 'control').length} control, ${rig.nodes.filter((n) => n.kind === 'art').length} art)`);
  lines.push(`  artist layers     ${artistLayers(rig).length}`);
  lines.push(`  vm properties     ${rig.viewModel.properties.length}`);
  lines.push(`  states            ${rig.stateMachine.states.length}`);

  const derived = rig.nodes.filter((n) => n.status === 'derived');
  const draftProps = rig.viewModel.properties.filter((p) => p.status !== 'spec');
  lines.push('\nNot yet confirmed by Ruslan');
  lines.push(`  derived nodes     ${derived.length}${derived.length ? ' (' + derived.map((n) => n.name).slice(0, 4).join(', ') + (derived.length > 4 ? ', ...' : '') + ')' : ''}`);
  lines.push(`  draft vm props    ${draftProps.length}${draftProps.length ? ' (' + draftProps.map((p) => p.name).join(', ') + ')' : ''}`);
  lines.push(`  view model        ${rig.viewModel.status}`);
  lines.push(`  simulation        ${rig.simulation.status} - decay rates are placeholders`);

  const riv = resolve(repoRoot, rig.runtime.riveAssetPath);
  lines.push('\nArtifacts');
  lines.push(`  ${rig.runtime.riveAssetPath}   ${existsSync(riv) ? 'present' : 'MISSING - export it from the Rive Editor'}`);
  lines.push(`  app/lib/src/bear_rig_contract.dart   ${existsSync(DART_OUT) ? 'generated' : 'MISSING - run teddy gen:dart'}`);
  lines.push(`  lab/rig_spec.generated.js            ${existsSync(LAB_SPEC_OUT) ? 'generated' : 'MISSING - run teddy gen:dart'}`);
  const catalog = JSON.parse(readFileSync(resolve(repoRoot, 'rig', 'animation_catalog.json'), 'utf8'));
  const planned = Object.values(catalog.groups).reduce((n, g) => n + g.clips.length, 0);
  const roomPlanned = Object.values(catalog.groups)
    .filter((g) => catalog.surfaces[g.surface]?.inScope)
    .reduce((n, g) => n + g.clips.length, 0);
  const roomDeclared = Object.values(catalog.groups)
    .filter((g) => catalog.surfaces[g.surface]?.inScope)
    .reduce((n, g) => n + g.declaredInProposal, 0);
  lines.push(`\nRoom "Игра" clips   ${roomPlanned} planned / ${roomDeclared} promised (teddy clips)`);
  lines.push('\nOpen questions are tracked in docs/open-questions.md');

  process.stdout.write(lines.join('\n') + '\n');
  return 0;
}

async function cmdLab() {
  const port = Number(flag('port', 4321));
  const { url, runtimeAvailable } = await serveLab({ port });
  if (!runtimeAvailable) {
    process.stderr.write('Rive web runtime not found in tools/node_modules.\nRun `npm install` inside tools/ first.\n');
  }
  process.stdout.write(`Rive lab: ${url}\nCtrl-C to stop.\n`);
}

const exitCode = await main();
if (typeof exitCode === 'number' && exitCode !== 0) process.exit(exitCode);
