import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { loadRig, validateRig, isSnakeCase, artistLayers, repoRoot } from '../lib/rig.mjs';
import { checkLayers } from '../lib/check_layers.mjs';
import { generateDartContract, generateLabSpec, dartIdentifier } from '../lib/gen_dart.mjs';

const rig = loadRig();

test('спека рига проходит собственную валидацию', () => {
  assert.deepEqual(validateRig(rig), []);
});

test('валидатор ловит неизвестного родителя', () => {
  const broken = { ...rig, nodes: [...rig.nodes, { name: 'orphan_node', kind: 'art', parent: 'no_such_bone' }] };
  assert.ok(validateRig(broken).some((p) => p.includes('unknown parent')));
});

test('валидатор ловит цикл в дереве', () => {
  const nodes = rig.nodes.map((n) => (n.name === 'root_body' ? { ...n, parent: 'head' } : n));
  assert.ok(validateRig({ ...rig, nodes }).some((p) => p.includes('cycle')));
});

test('валидатор ловит дубликат имени', () => {
  const broken = { ...rig, nodes: [...rig.nodes, rig.nodes[3]] };
  assert.ok(validateRig(broken).some((p) => p.includes('duplicate node name')));
});

test('валидатор ловит blend state с несуществующим весом', () => {
  const broken = {
    ...rig,
    stateMachine: { ...rig.stateMachine, blendStates: [{ name: 'x', weightProperty: 'nope' }] },
  };
  assert.ok(validateRig(broken).some((p) => p.includes('unknown property')));
});

test('snake_case распознаётся корректно', () => {
  for (const good of ['root', 'ear_in_left', 'finger_1_nail_right']) {
    assert.ok(isSnakeCase(good), good);
  }
  for (const bad of ['EarLeft', 'ear-left', '_ear', 'ear__left', '1ear', 'ear_']) {
    assert.ok(!isSnakeCase(bad), bad);
  }
});

test('точное совпадение слоёв проходит проверку', () => {
  const delivered = artistLayers(rig).map((l) => l.name);
  const result = checkLayers(rig, delivered);
  assert.equal(result.ok, true);
  assert.equal(result.missing.length, 0);
  assert.equal(result.extra.length, 0);
});

test('опечатка попадает в переименования, а не в пропуски', () => {
  const delivered = artistLayers(rig).map((l) => (l.name === 'ear_in_left' ? 'ear_in_lft' : l.name));
  const result = checkLayers(rig, delivered);
  assert.ok(result.renames.some((r) => r.expected === 'ear_in_left' && r.delivered === 'ear_in_lft'));
  assert.equal(result.ok, false);
});

test('пропущенный обязательный слой валит проверку, опциональный - нет', () => {
  const layers = artistLayers(rig).map((l) => l.name);

  const withoutRequired = layers.filter((n) => n !== 'nose');
  assert.equal(checkLayers(rig, withoutRequired).ok, false);

  const withoutOptional = layers.filter((n) => !n.startsWith('scarf_'));
  const result = checkLayers(rig, withoutOptional);
  assert.equal(result.ok, true, 'шарф опционален на MVP');
  assert.equal(result.missing.filter((m) => !m.optional).length, 0);
});

test('не-snake_case имя валит проверку', () => {
  const delivered = [...artistLayers(rig).map((l) => l.name), 'ExtraLayer'];
  assert.equal(checkLayers(rig, delivered).ok, false);
});

test('dartIdentifier переводит snake_case в camelCase', () => {
  assert.equal(dartIdentifier('sleep_action'), 'sleepAction');
  assert.equal(dartIdentifier('care_index'), 'careIndex');
  assert.equal(dartIdentifier('food'), 'food');
  assert.equal(dartIdentifier('first_steps'), 'firstSteps');
});

test('сгенерированный Dart совпадает с тем, что лежит в репозитории', () => {
  const onDisk = readFileSync(resolve(repoRoot, 'app/lib/src/bear_rig_contract.dart'), 'utf8');
  assert.equal(generateDartContract(rig, { rigFile: 'bear_rig.json' }), onDisk, 'запустите: npm run gen:dart');
});

test('сгенерированная спека лаборатории совпадает с репозиторием', () => {
  const onDisk = readFileSync(resolve(repoRoot, 'lab/rig_spec.generated.js'), 'utf8');
  assert.equal(generateLabSpec(rig), onDisk, 'запустите: npm run gen:dart');
});

test('каталог клипов ссылается только на известные стадии и характеры', () => {
  const catalog = JSON.parse(readFileSync(resolve(repoRoot, 'rig/animation_catalog.json'), 'utf8'));
  const stages = new Set(rig.enums.stage.values);
  const traits = new Set(rig.enums.trait.values);
  const moods = new Set(rig.enums.mood.values);

  for (const group of Object.values(catalog.groups)) {
    for (const clip of group.clips) {
      if (clip.stage) assert.ok(stages.has(clip.stage), `стадия ${clip.stage}`);
      if (clip.trait) assert.ok(traits.has(clip.trait), `характер ${clip.trait}`);
      if (clip.mood) assert.ok(moods.has(clip.mood), `настроение ${clip.mood}`);
      if (clip.from) assert.ok(stages.has(clip.from) && stages.has(clip.to), clip.name);
    }
  }
});

test('имена клипов уникальны', () => {
  const catalog = JSON.parse(readFileSync(resolve(repoRoot, 'rig/animation_catalog.json'), 'utf8'));
  const names = Object.values(catalog.groups).flatMap((g) => g.clips.map((c) => c.name));
  assert.equal(new Set(names).size, names.length);
});

test('каждый триггер прибавки ссылается на существующее свойство', () => {
  const props = new Set(rig.viewModel.properties.map((p) => p.name));
  for (const [trigger, boosts] of Object.entries(rig.simulation.actionBoost)) {
    assert.ok(props.has(trigger), `триггер ${trigger}`);
    for (const target of Object.keys(boosts)) assert.ok(props.has(target), `показатель ${target}`);
  }
});

test('безопасный предел лежит внутри диапазона', () => {
  for (const prop of rig.viewModel.properties.filter((p) => p.type === 'number' && p.safeFloor !== undefined)) {
    assert.ok(prop.safeFloor >= prop.min && prop.safeFloor <= prop.max, prop.name);
  }
});
