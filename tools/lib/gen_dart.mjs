import { basename } from 'node:path';

const HEADER = (rigFile) => `// GENERATED FILE - DO NOT EDIT BY HAND.
//
// Source of truth: rig/${rigFile}
// Regenerate:      cd tools && npm run gen:dart
//
// Every name below must exist verbatim in the Rive file. The lab
// (tools/ -> npm run lab) checks a .riv against the same spec, so a mismatch
// is caught before it reaches the app.
`;

const dartString = (value) => `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
const dartDoc = (text, indent = '  ') =>
  text ? String(text).split('\n').map((line) => `${indent}/// ${line}`).join('\n') + '\n' : '';

/** camelCase identifier for a snake_case or camelCase source name. */
export function dartIdentifier(name) {
  const camel = name.replace(/[_-]+([a-z0-9])/g, (_, c) => c.toUpperCase());
  return /^[0-9]/.test(camel) ? `n${camel}` : camel;
}

export function generateDartContract(rig, { rigFile = 'bear_rig.json' } = {}) {
  const vm = rig.viewModel;
  const numbers = vm.properties.filter((p) => p.type === 'number');
  const triggers = vm.properties.filter((p) => p.type === 'trigger');

  const lines = [HEADER(basename(rigFile))];

  lines.push(`/// Names and ranges taken from the rig spec, shared by the Rive file,`);
  lines.push(`/// the lab and this app.`);
  lines.push(`abstract final class BearRig {`);
  lines.push(`  BearRig._();\n`);
  lines.push(`  /// Spec version this contract was generated from.`);
  lines.push(`  static const int specVersion = ${rig.specVersion};\n`);
  lines.push(`  /// Flutter asset key for the exported Rive file.`);
  lines.push(`  static const String asset = ${dartString(rig.runtime.flutterAssetKey)};\n`);
  lines.push(`  /// Artboards, one per hero (KP 2.4 - server picks the gender).`);
  for (const [key, value] of Object.entries(rig.artboard.names)) {
    lines.push(`  static const String artboard${key[0].toUpperCase()}${key.slice(1)} = ${dartString(value)};`);
  }
  lines.push(`\n  /// Artboard used when the hero's gender is not known yet.`);
  lines.push(`  static const String artboardDefault = ${dartString(rig.artboard.primary)};\n`);
  lines.push(`  /// State machine to run.`);
  lines.push(`  static const String stateMachine = ${dartString(rig.stateMachine.name)};\n`);
  lines.push(`  /// View model backing the state machine.`);
  lines.push(`  static const String viewModel = ${dartString(vm.name)};`);
  lines.push(`}\n`);

  lines.push(`/// Number properties on the bear view model, with the ranges the rig expects.`);
  lines.push(`enum BearNumber {`);
  numbers.forEach((prop, i) => {
    const doc = [prop.doc, `Range ${prop.min}..${prop.max}, default ${prop.default}. (${prop.status}, ${prop.origin})`]
      .filter(Boolean)
      .join('\n');
    lines.push(dartDoc(doc).trimEnd());
    const end = i === numbers.length - 1 ? ';' : ',';
    lines.push(
      `  ${dartIdentifier(prop.name)}(${dartString(prop.name)}, ${prop.min.toFixed(1)}, ${prop.max.toFixed(1)}, ` +
        `${Number(prop.default).toFixed(1)}, ${Number(prop.safeFloor ?? prop.min).toFixed(1)})${end}`,
    );
  });
  lines.push('');
  lines.push(`  const BearNumber(this.path, this.min, this.max, this.initial, this.safeFloor);\n`);
  lines.push(`  /// Property path as it appears in the Rive view model.`);
  lines.push(`  final String path;`);
  lines.push(`  final double min;`);
  lines.push(`  final double max;`);
  lines.push(`  final double initial;\n`);
  lines.push(`  /// Floor that decay may not cross, so a long absence cannot empty the`);
  lines.push(`  /// meters (KP 6.3). Direct player action may still go lower.`);
  lines.push(`  final double safeFloor;\n`);
  lines.push(`  /// Clamps [value] into this property's declared range.`);
  lines.push(`  double clamp(double value) => value.clamp(min, max);\n`);
  lines.push(`  /// Clamps [value] but never below [safeFloor] - used by decay.`);
  lines.push(`  double clampWithFloor(double value) => value.clamp(safeFloor, max);`);
  lines.push(`}\n`);

  // --- enum-backed properties -------------------------------------------
  const enumProps = vm.properties.filter((p) => p.type === 'enum');
  for (const prop of enumProps) {
    const def = rig.enums[prop.enumName];
    const typeName = `Bear${prop.enumName[0].toUpperCase()}${prop.enumName.slice(1)}`;
    lines.push(`/// ${prop.doc ?? ''} (${prop.status}, ${prop.origin})`);
    lines.push(`///`);
    lines.push(`/// Bound to the Rive enum \`${prop.enumName}\` via property \`${prop.name}\`.`);
    lines.push(`enum ${typeName} {`);
    def.values.forEach((value, i) => {
      const label = def.labels?.[value];
      if (label) lines.push(`  /// ${label}`);
      lines.push(`  ${dartIdentifier(value)}(${dartString(value)})${i === def.values.length - 1 ? ';' : ','}`);
    });
    lines.push('');
    lines.push(`  const ${typeName}(this.wireName);\n`);
    lines.push(`  /// Exact spelling of the value inside the Rive file.`);
    lines.push(`  final String wireName;\n`);
    lines.push(`  /// The view model property this enum is bound to.`);
    lines.push(`  static const String property = ${dartString(prop.name)};\n`);
    lines.push(`  /// Value the rig starts at.`);
    lines.push(`  static const ${typeName} initial = ${typeName}.${dartIdentifier(prop.default)};\n`);
    lines.push(`  /// Parses a value coming back from Rive or the backend.`);
    lines.push(`  static ${typeName}? fromWire(String value) {`);
    lines.push(`    for (final candidate in values) {`);
    lines.push(`      if (candidate.wireName == value) return candidate;`);
    lines.push(`    }`);
    lines.push(`    return null;`);
    lines.push(`  }`);
    lines.push(`}\n`);
  }

  lines.push(`/// Trigger properties on the bear view model.`);
  lines.push(`enum BearTrigger {`);
  triggers.forEach((prop, i) => {
    const doc = [prop.doc, `(${prop.status}, ${prop.origin})`].filter(Boolean).join('\n');
    lines.push(dartDoc(doc).trimEnd());
    const end = i === triggers.length - 1 ? ';' : ',';
    lines.push(`  ${dartIdentifier(prop.name)}(${dartString(prop.name)})${end}`);
  });
  lines.push('');
  lines.push(`  const BearTrigger(this.path);\n`);
  lines.push(`  /// Property path as it appears in the Rive view model.`);
  lines.push(`  final String path;`);
  lines.push(`}\n`);

  const states = rig.stateMachine.states;
  lines.push(`/// States declared by the rig spec. Useful for assertions and debug overlays;`);
  lines.push(`/// the runtime drives transitions through the view model, not by name.`);
  lines.push(`enum BearState {`);
  states.forEach((state, i) => {
    lines.push(dartDoc(state.doc ?? '').trimEnd());
    const end = i === states.length - 1 ? ';' : ',';
    lines.push(`  ${dartIdentifier(state.name)}(${dartString(state.name)})${end}`);
  });
  lines.push('');
  lines.push(`  const BearState(this.stateName);\n`);
  lines.push(`  final String stateName;`);
  lines.push(`}\n`);

  const decay = rig.simulation.decayPerSecond;
  const boosts = rig.simulation.actionBoost;
  lines.push(`/// PLACEHOLDER tuning values. ${rig.simulation.note.replace(/\n/g, ' ')}`);
  lines.push(`abstract final class BearTuning {`);
  lines.push(`  BearTuning._();\n`);
  lines.push(`  /// Units lost per second while the app is in the foreground.`);
  lines.push(`  static const Map<BearNumber, double> decayPerSecond = {`);
  for (const [name, rate] of Object.entries(decay)) {
    lines.push(`    BearNumber.${dartIdentifier(name)}: ${Number(rate).toFixed(2)},`);
  }
  lines.push(`  };\n`);
  lines.push(`  /// Units gained when the matching trigger fires.`);
  lines.push(`  static const Map<BearTrigger, Map<BearNumber, double>> boost = {`);
  for (const [action, effect] of Object.entries(boosts)) {
    const inner = Object.entries(effect)
      .map(([target, amount]) => `BearNumber.${dartIdentifier(target)}: ${Number(amount).toFixed(1)}`)
      .join(', ');
    lines.push(`    BearTrigger.${dartIdentifier(action)}: {${inner}},`);
  }
  lines.push(`  };`);
  lines.push(`}`);

  return lines.join('\n') + '\n';
}

/** Emits the same spec as a JS module the lab imports, so both sides cannot drift. */
export function generateLabSpec(rig) {
  return `// GENERATED FILE - DO NOT EDIT BY HAND.
// Source of truth: rig/bear_rig.json   Regenerate: cd tools && npm run gen:dart
export const rigSpec = ${JSON.stringify(
    {
      specVersion: rig.specVersion,
      artboards: rig.artboard.names,
      artboard: rig.artboard.primary,
      enums: rig.enums,
      stateMachine: rig.stateMachine.name,
      viewModel: rig.viewModel.name,
      properties: rig.viewModel.properties,
      states: rig.stateMachine.states.map((s) => s.name),
      nodes: rig.nodes.map(({ name, kind, parent, artistLayer, optional }) => ({ name, kind, parent, artistLayer, optional: !!optional })),
      simulation: rig.simulation,
      riveAsset: rig.runtime.flutterAssetKey,
    },
    null,
    2,
  )};
`;
}
