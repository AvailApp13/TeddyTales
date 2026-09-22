import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

import { loadRig, repoRoot } from '../lib/rig.mjs';
import { generateRiveProject, loadCatalog } from '../lib/gen_rml.mjs';

const rig = loadRig();
const catalog = loadCatalog();
const { rml, yaml } = generateRiveProject(rig, catalog);

const count = (re) => (rml.match(re) ?? []).length;

test('генерация детерминирована и совпадает с rive/bear в репозитории', () => {
  const onDisk = readFileSync(resolve(repoRoot, 'rive/bear/scene.rml'), 'utf8');
  assert.equal(rml, onDisk, 'запустите: npm run gen:rml');
  assert.equal(yaml, readFileSync(resolve(repoRoot, 'rive/bear/rive.yaml'), 'utf8'));
});

test('оба артборда героев присутствуют с именами из спеки', () => {
  for (const name of Object.values(rig.artboard.names)) {
    assert.ok(rml.includes(`name="${name}"`), name);
  }
  assert.equal(count(/<Artboard /g), 2);
});

test('каждый узел спеки есть в каждом артборде под своим именем', () => {
  for (const node of rig.nodes) {
    assert.equal(count(new RegExp(`name="${node.name}"`, 'g')), 2, node.name);
  }
});

test('кости спеки стали костями RML, control-узлы — Node', () => {
  const bones = rig.nodes.filter((n) => n.kind === 'bone').length;
  assert.equal(count(/<(RootBone|Bone) /g), bones * 2);
  for (const ctrl of rig.nodes.filter((n) => n.kind === 'control')) {
    assert.ok(new RegExp(`<Node [^>]*name="${ctrl.name}"`).test(rml), ctrl.name);
  }
});

test('каждое свойство View Model объявлено и имеет значение в инстансе', () => {
  for (const prop of rig.viewModel.properties) {
    const decl = new RegExp(`<ViewModelProperty\\w+ [^>]*name="${prop.name}" id="(0:\\d+)"`).exec(rml);
    assert.ok(decl, `нет объявления ${prop.name}`);
    assert.ok(rml.includes(`viewModelPropertyId="${decl[1]}"`), `нет значения для ${prop.name}`);
  }
  assert.ok(rml.includes('exports="true"'), 'инстанс должен быть экспортирован, иначе рантайм его не видит');
});

test('все клипы каталога стали таймлайнами в каждом артборде', () => {
  for (const group of Object.values(catalog.groups)) {
    for (const clip of group.clips) {
      assert.equal(count(new RegExp(`<LinearAnimation [^>]*name="${clip.name}"`, 'g')), 2, clip.name);
    }
  }
});

test('состояния не носят имён, а каждый слой имеет три обязательных узла', () => {
  assert.equal(count(/<AnimationState [^>]*name=/g), 0);
  const layers = count(/<StateMachineLayer /g);
  assert.equal(count(/<AnyState/g), layers);
  assert.equal(count(/<ExitState/g), layers);
  assert.equal(count(/<EntryState/g), layers);
});

test('слои покоя не используют AnyState-переходы', () => {
  // AnyState -> текущее состояние перезапускал бы клип каждый кадр.
  const idleLayers = rml.split('<StateMachineLayer ').filter((chunk) => chunk.startsWith('name="idle_'));
  assert.equal(idleLayers.length, rig.enums.stage.values.length * 2);
  for (const chunk of idleLayers) {
    assert.ok(/<AnyState [^>]*\/>/.test(chunk), 'AnyState в слое покоя должен быть пустым');
  }
});

test('каждый триггер ухода ведёт в клип своей стадии', () => {
  for (const clip of catalog.groups.care.clips) {
    assert.ok(rml.includes(`name="${clip.name}"`), clip.name);
  }
  // 6 действий x 5 стадий переходов из AnyState на артборд
  assert.ok(count(/<TransitionValueTriggerComparator/g) >= catalog.groups.care.clips.length * 2);
});

test('идентификаторы уникальны в пределах документа', () => {
  const ids = rml.match(/ id="(\d+:\d+)"/g).map((m) => m.slice(5, -1));
  assert.equal(new Set(ids).size, ids.length);
});

test('собранный .riv лежит в ассетах приложения', () => {
  assert.ok(existsSync(resolve(repoRoot, rig.runtime.riveAssetPath)), 'запустите: npm run build:riv');
});
