import { rigSpec } from '/lab/rig_spec.generated.js';

// The runtime is loaded as a UMD bundle by index.html so the wasm resolves
// relative to /vendor/.
const Rive = window.rive;

// Serve the wasm from tools/node_modules via /vendor/ instead of the CDN the
// runtime defaults to. The lab has to work with no network: the Rive Editor and
// its MCP server are already local, and a CDN hiccup should not block rig work.
Rive.RuntimeLoader.setWasmUrl('/vendor/rive.wasm');
Rive.RuntimeLoader.setWasmFallbackUrl(null);

const el = (id) => document.getElementById(id);
const ui = {
  specVersion: el('specVersion'),
  filePicker: el('filePicker'),
  loadRepo: el('loadRepo'),
  reload: el('reload'),
  canvasWrap: el('canvasWrap'),
  canvas: el('stage'),
  dropHint: el('dropHint'),
  fit: el('fit'),
  artboard: el('artboard'),
  stateMachine: el('stateMachine'),
  showGrid: el('showGrid'),
  fps: el('fps'),
  statusMsg: el('statusMsg'),
  contract: el('contract'),
  contents: el('contents'),
  bindings: el('bindings'),
  inputs: el('inputs'),
  simToggle: el('simToggle'),
  simReset: el('simReset'),
  simSpeed: el('simSpeed'),
  simSpeedOut: el('simSpeedOut'),
  simNote: el('simNote'),
  log: el('log'),
};

/** Everything that must be torn down between loads lives here. */
const session = {
  riveInstance: null,
  buffer: null,
  sourceLabel: null,
  vmi: null,
  /** name -> { spec, handle, type, setValue } */
  bound: new Map(),
  numberControls: [],
  simTimer: null,
  simLast: 0,
  lastStates: [],
};

ui.specVersion.textContent = `rig spec v${rigSpec.specVersion} · ${rigSpec.viewModel}`;
ui.simNote.textContent = rigSpec.simulation.note;

function log(message, kind = '') {
  const line = document.createElement('div');
  if (kind) line.className = kind;
  const time = new Date().toLocaleTimeString([], { hour12: false });
  line.textContent = `${time}  ${message}`;
  ui.log.prepend(line);
  while (ui.log.childElementCount > 200) ui.log.lastElementChild.remove();
}

function status(message) {
  ui.statusMsg.textContent = message;
}

// ---------------------------------------------------------------- file loading

ui.filePicker.addEventListener('change', async (event) => {
  const file = event.target.files?.[0];
  if (file) loadBuffer(await file.arrayBuffer(), file.name);
});

ui.loadRepo.addEventListener('click', async () => {
  const path = `/${rigSpec.riveAsset.replace(/^assets\//, 'app/assets/')}`;
  try {
    const response = await fetch(path, { cache: 'no-store' });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    loadBuffer(await response.arrayBuffer(), path);
  } catch (error) {
    log(`Could not load ${path}: ${error.message}`, 'bad');
    status(`No .riv in the repo yet — export one from the Rive Editor to ${rigSpec.riveAsset}.`);
  }
});

ui.reload.addEventListener('click', () => {
  if (session.buffer) loadBuffer(session.buffer, session.sourceLabel);
});

for (const type of ['dragenter', 'dragover']) {
  ui.canvasWrap.addEventListener(type, (event) => {
    event.preventDefault();
    ui.canvasWrap.classList.add('dragging');
  });
}
for (const type of ['dragleave', 'drop']) {
  ui.canvasWrap.addEventListener(type, () => ui.canvasWrap.classList.remove('dragging'));
}
ui.canvasWrap.addEventListener('drop', async (event) => {
  event.preventDefault();
  const file = event.dataTransfer?.files?.[0];
  if (!file) return;
  if (!file.name.toLowerCase().endsWith('.riv')) {
    log(`${file.name} is not a .riv file`, 'bad');
    return;
  }
  loadBuffer(await file.arrayBuffer(), file.name);
});

function teardown() {
  stopSim();
  if (session.riveInstance) {
    try {
      session.riveInstance.cleanup();
    } catch (error) {
      log(`cleanup(): ${error.message}`, 'bad');
    }
  }
  session.riveInstance = null;
  session.vmi = null;
  session.bound.clear();
  session.numberControls = [];
}

/**
 * The buffer is kept so Reload and an artboard/state-machine switch can rebuild
 * the instance without asking for the file again. Rive keeps a copy internally,
 * so we hand it a fresh slice each time.
 */
function loadBuffer(buffer, label, { artboard, stateMachine } = {}) {
  teardown();
  session.buffer = buffer;
  session.sourceLabel = label;
  ui.dropHint.classList.add('hidden');
  status(`Loading ${label}…`);

  const instance = new Rive.Rive({
    canvas: ui.canvas,
    buffer: buffer.slice(0),
    autoplay: true,
    // Binds the artboard's default view model instance, matching
    // DataBind.auto() in the Flutter runtime.
    autoBind: true,
    artboard,
    stateMachine,
    layout: new Rive.Layout({ fit: ui.fit.value, alignment: Rive.Alignment.Center }),
    onLoad: () => {
      // Без явного stateMachine рантайм играет первый линейный таймлайн, а
      // State Machine стоит: ни data binding, ни листенеры не работают, хотя
      // картинка есть. Имена известны только после загрузки, поэтому первый
      // раз перезагружаемся с настоящим именем.
      if (!stateMachine && instance.stateMachineNames.length) {
        const preferred = instance.stateMachineNames.includes(rigSpec.stateMachine)
          ? rigSpec.stateMachine
          : instance.stateMachineNames[0];
        instance.cleanup();
        loadBuffer(buffer, label, { artboard, stateMachine: preferred });
        return;
      }
      instance.resizeDrawingSurfaceToCanvas();
      session.riveInstance = instance;
      ui.reload.disabled = false;
      // enableFPSCounter reaches into the wasm runtime handle, which only
      // exists once the file has loaded - calling it earlier throws.
      instance.enableFPSCounter((fps) => {
        ui.fps.textContent = `${fps.toFixed(0)} fps`;
      });
      onLoaded(instance, label);
    },
    onStateChange: (event) => {
      const names = Array.isArray(event?.data) ? event.data : [event?.data];
      for (const name of names.filter(Boolean)) log(`state \u2192 ${name}`, 'ok');
      session.lastStates = names.filter(Boolean);
    },
    onLoadError: (error) => {
      log(`Failed to load ${label}: ${describeError(error)}`, 'bad');
      status('Load failed \u2014 see the log.');
    },
  });

}

function onLoaded(instance, label) {
  const artboards = instance.contents?.artboards ?? [];
  const activeArtboard = artboards.find((a) => a.name === ui.artboard.value) ?? artboards[0];

  fillSelect(ui.artboard, artboards.map((a) => a.name), activeArtboard?.name);
  fillSelect(ui.stateMachine, instance.stateMachineNames, instance.playingStateMachineNames[0]);

  session.vmi = instance.viewModelInstance;
  renderContents(instance, artboards);
  renderContract(instance, artboards, activeArtboard);
  renderBindings();
  renderInputs(instance);

  const simulable = session.numberControls.length > 0;
  ui.simToggle.disabled = !simulable;
  ui.simReset.disabled = !simulable;

  status(`${label} · ${artboards.length} artboard(s) · ${instance.stateMachineNames.length} state machine(s)`);
  log(`Loaded ${label}`, 'ok');
}

function fillSelect(select, values, selected) {
  select.innerHTML = '';
  for (const value of values) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = value;
    if (value === selected) option.selected = true;
    select.append(option);
  }
  select.disabled = values.length < 1;
}

ui.artboard.addEventListener('change', rebuild);
ui.stateMachine.addEventListener('change', rebuild);
function rebuild() {
  if (!session.buffer) return;
  loadBuffer(session.buffer, session.sourceLabel, {
    artboard: ui.artboard.value || undefined,
    stateMachine: ui.stateMachine.value || undefined,
  });
}

ui.fit.addEventListener('change', () => {
  if (!session.riveInstance) return;
  session.riveInstance.layout = new Rive.Layout({ fit: ui.fit.value, alignment: Rive.Alignment.Center });
});

ui.showGrid.addEventListener('change', () => {
  ui.canvasWrap.classList.toggle('grid', ui.showGrid.checked);
});

const resizeObserver = new ResizeObserver(() => session.riveInstance?.resizeDrawingSurfaceToCanvas());
resizeObserver.observe(ui.canvasWrap);

// ------------------------------------------------------------------- contract

/**
 * Walks a view model instance and its nested view models into a flat list of
 * slash-separated paths - the same addressing the Flutter runtime uses
 * (`viewModelInstance.number('Energy_Bar/Lives')`). Depth is capped because a
 * view model may legally reference itself.
 */
function flattenProperties(vmi, { maxDepth = 4 } = {}) {
  const out = [];
  const walk = (node, prefix, depth) => {
    if (!node || depth > maxDepth) return;
    for (const property of node.properties ?? []) {
      const path = prefix ? `${prefix}/${property.name}` : property.name;
      if (property.type === 'viewModel') {
        out.push({ ...property, path, depth, container: true });
        walk(node.viewModel(property.name), path, depth + 1);
      } else {
        out.push({ ...property, path, depth, container: false });
      }
    }
  };
  walk(vmi, '', 0);
  return out;
}

/** Maps a rig spec property type onto the runtime's DataType strings. */
const TYPE_ALIASES = {
  number: ['number', 'integer'],
  trigger: ['trigger'],
  boolean: ['boolean'],
  string: ['string'],
  color: ['color'],
  enum: ['enumType'],
};

function renderContract(instance, artboards, activeArtboard) {
  const rows = [];
  let failures = 0;

  const mark = (ok, name, note, level = ok ? 'ok' : 'bad') => {
    if (!ok && level === 'bad') failures += 1;
    rows.push(
      `<div class="row"><span class="mark ${level}">${ok ? '✓' : level === 'warn' ? '!' : '✕'}</span>` +
        `<span class="name">${escapeHtml(name)}</span>` +
        (note ? `<span class="note">${escapeHtml(note)}</span>` : '') +
        `</div>`,
    );
  };

  rows.push('<h3>Artboard &amp; state machine</h3>');
  const artboardNames = new Set(artboards.map((a) => a.name));
  // Two heroes (KP 2.4): each gender is its own artboard, and both must carry
  // the same view model and state machine names.
  for (const [gender, name] of Object.entries(rigSpec.artboards)) {
    const present = artboardNames.has(name);
    mark(present, `artboard "${name}" (${gender})`, present ? '' : `found: ${[...artboardNames].join(', ') || 'none'}`);
  }
  const smNames = instance.stateMachineNames;
  mark(smNames.includes(rigSpec.stateMachine), `state machine "${rigSpec.stateMachine}"`, smNames.includes(rigSpec.stateMachine) ? '' : `found: ${smNames.join(', ') || 'none'}`);

  rows.push('<h3>View model properties</h3>');
  const vmi = session.vmi;
  if (!vmi) {
    mark(false, 'default view model instance', 'not bound — mark the instance as exported in the Rive Editor');
  } else {
    const actual = new Map(flattenProperties(vmi).filter((p) => !p.container).map((p) => [p.path, p.type]));
    mark(vmi.viewModelName === rigSpec.viewModel, `view model "${rigSpec.viewModel}"`, vmi.viewModelName === rigSpec.viewModel ? '' : `found: "${vmi.viewModelName}"`, vmi.viewModelName === rigSpec.viewModel ? 'ok' : 'warn');

    for (const spec of rigSpec.properties) {
      const found = actual.get(spec.name);
      if (!found) {
        mark(false, spec.name, `missing (${spec.type})`);
      } else {
        const compatible = (TYPE_ALIASES[spec.type] ?? [spec.type]).includes(found);
        mark(compatible, spec.name, compatible ? spec.type : `expected ${spec.type}, found ${found}`);
      }
    }

    const expected = new Set(rigSpec.properties.map((p) => p.name));
    for (const [name, type] of actual) {
      if (!expected.has(name)) mark(false, name, `extra (${type}) — not in the rig spec`, 'warn');
    }
  }

  rows.push('<h3>States declared in the spec</h3>');
  rows.push(
    `<div class="row"><span class="mark warn">i</span><span class="name">${rigSpec.states.length} states</span>` +
      `<span class="note">${escapeHtml(rigSpec.states.join(', '))}</span></div>` +
      `<p class="hint">State names are not readable from a .riv at runtime — verify these by eye in the editor.</p>`,
  );

  const summary = failures
    ? `<p class="summary bad"><strong>${failures} problem${failures === 1 ? '' : 's'}</strong> — the Flutter app will not bind correctly.</p>`
    : `<p class="summary ok"><strong>Contract satisfied.</strong> Safe to wire into the app.</p>`;

  ui.contract.innerHTML = summary + rows.join('');
}

function renderContents(instance, artboards) {
  const parts = [];
  for (const artboard of artboards) {
    parts.push(`<h3>${escapeHtml(artboard.name)}</h3>`);
    parts.push('<ul>');
    parts.push(`<li>state machines: ${artboard.stateMachines.map((sm) => escapeHtml(sm.name)).join(', ') || '—'}</li>`);
    parts.push(`<li>animations: ${artboard.animations.map(escapeHtml).join(', ') || '—'}</li>`);
    parts.push('</ul>');
  }
  parts.push(`<p class="hint">${instance.viewModelCount} view model(s) in the file.</p>`);
  ui.contents.innerHTML = parts.join('');
}

// ------------------------------------------------------------------- bindings

function renderBindings() {
  const vmi = session.vmi;
  session.bound.clear();
  session.numberControls = [];

  if (!vmi) {
    ui.bindings.innerHTML =
      '<p class="empty">No view model instance bound. In the Rive Editor, mark the view model instance as exported.</p>';
    return;
  }

  const specPaths = new Set(rigSpec.properties.map((p) => p.name));
  const properties = flattenProperties(vmi);
  ui.bindings.innerHTML = '';

  const triggers = properties.filter((p) => p.type === 'trigger');
  if (triggers.length) {
    const heading = document.createElement('p');
    heading.className = 'hint';
    heading.textContent = 'Triggers';
    const row = document.createElement('div');
    row.className = 'triggerRow';
    for (const property of triggers) {
      const handle = vmi.trigger(property.path);
      const button = document.createElement('button');
      button.className = 'btn';
      button.textContent = property.path;
      button.disabled = !handle;
      if (!specPaths.has(property.path)) button.title = 'Not in the rig spec';
      button.addEventListener('click', () => {
        handle.trigger();
        applyBoost(property.path);
        log(`trigger ${property.path}`);
      });
      row.append(button);
    }
    ui.bindings.append(heading, row);
  }

  const container = document.createElement('div');
  let rendered = 0;
  for (const property of properties) {
    if (property.type === 'trigger') continue;
    if (property.container) {
      const heading = document.createElement('p');
      heading.className = 'hint';
      heading.textContent = `\u21b3 ${property.path}`;
      container.append(heading);
      continue;
    }
    const control = buildValueControl(vmi, property, specPaths.has(property.path) ? rigSpec.properties.find((p) => p.name === property.path) : null);
    if (control) {
      container.append(control);
      rendered += 1;
    }
  }
  ui.bindings.append(container);

  if (!properties.length) ui.bindings.innerHTML = '<p class="empty">The view model has no properties.</p>';
  else log(`${properties.length} view model properties (${rendered} editable, ${triggers.length} triggers)`);
}

function buildValueControl(vmi, property, spec) {
  const wrap = document.createElement('div');
  wrap.className = 'prop' + (spec ? '' : ' unexpected');

  const head = document.createElement('div');
  head.className = 'head';
  head.innerHTML =
    `<span class="label">${escapeHtml(property.path)}</span>` +
    `<span class="type">${escapeHtml(property.type)}${spec ? '' : ' · unexpected'}</span>`;
  const readout = document.createElement('span');
  readout.className = 'val';
  head.append(readout);
  wrap.append(head);

  if (property.type === 'number' || property.type === 'integer') {
    const handle = vmi.number(property.path);
    if (!handle) return null;
    const min = spec?.min ?? 0;
    const max = spec?.max ?? 100;
    const slider = document.createElement('input');
    slider.type = 'range';
    slider.min = String(min);
    slider.max = String(max);
    slider.step = property.type === 'integer' ? '1' : String((max - min) / 200);
    slider.value = String(handle.value);
    readout.textContent = format(handle.value);
    slider.addEventListener('input', () => {
      handle.value = Number(slider.value);
      readout.textContent = format(handle.value);
    });
    wrap.append(slider);
    const control = {
      name: property.path,
      handle,
      min,
      max,
      initial: spec?.default ?? handle.value,
      sync: () => {
        slider.value = String(handle.value);
        readout.textContent = format(handle.value);
      },
    };
    session.numberControls.push(control);
    session.bound.set(property.path, control);
    return wrap;
  }

  if (property.type === 'boolean') {
    const handle = vmi.boolean(property.path);
    if (!handle) return null;
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = handle.value;
    readout.textContent = String(handle.value);
    box.addEventListener('change', () => {
      handle.value = box.checked;
      readout.textContent = String(handle.value);
    });
    const label = document.createElement('label');
    label.className = 'check';
    label.append(box, document.createTextNode(' on'));
    wrap.append(label);
    return wrap;
  }

  if (property.type === 'string') {
    const handle = vmi.string(property.path);
    if (!handle) return null;
    const field = document.createElement('input');
    field.type = 'text';
    field.value = handle.value;
    field.addEventListener('input', () => {
      handle.value = field.value;
    });
    wrap.append(field);
    return wrap;
  }

  if (property.type === 'enumType') {
    const handle = vmi.enum(property.path);
    if (!handle) return null;
    const select = document.createElement('select');
    const values = enumValues(property.enumName);
    for (const value of values.length ? values : [handle.value]) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      if (value === handle.value) option.selected = true;
      select.append(option);
    }
    readout.textContent = handle.value;
    select.addEventListener('change', () => {
      handle.value = select.value;
      readout.textContent = handle.value;
    });
    wrap.append(select);
    return wrap;
  }

  if (property.type === 'color') {
    const handle = vmi.color(property.path);
    if (!handle) return null;
    const field = document.createElement('input');
    field.type = 'color';
    field.addEventListener('input', () => {
      const [r, g, b] = [1, 3, 5].map((i) => parseInt(field.value.slice(i, i + 2), 16));
      handle.rgb(r, g, b);
    });
    wrap.append(field);
    return wrap;
  }

  readout.textContent = 'not editable here';
  return wrap;
}

function enumValues(enumName) {
  if (!enumName) return [];
  const fromFile = (session.riveInstance?.enums?.() ?? []).find((e) => e.name === enumName);
  if (fromFile?.values?.length) return fromFile.values;
  // Fall back to the rig spec so a half-built file still offers the right choices.
  return rigSpec.enums?.[enumName]?.values ?? [];
}

// --------------------------------------------------------- legacy SM inputs

function renderInputs(instance) {
  const name = ui.stateMachine.value;
  const inputs = name ? instance.stateMachineInputs(name) ?? [] : [];
  if (!inputs.length) {
    ui.inputs.innerHTML = '<p class="empty">None — this rig uses data binding. Good.</p>';
    return;
  }
  ui.inputs.innerHTML = '';
  const warning = document.createElement('p');
  warning.className = 'hint warn';
  warning.textContent = `${inputs.length} legacy input(s) found. Migrate these to view model properties.`;
  ui.inputs.append(warning);

  for (const input of inputs) {
    const wrap = document.createElement('div');
    wrap.className = 'prop';
    wrap.innerHTML = `<div class="head"><span class="label">${escapeHtml(input.name)}</span><span class="type">${Rive.StateMachineInputType[input.type] ?? input.type}</span></div>`;
    if (input.type === Rive.StateMachineInputType.Trigger) {
      const button = document.createElement('button');
      button.className = 'btn';
      button.textContent = 'fire';
      button.addEventListener('click', () => {
        input.fire();
        log(`input ${input.name}.fire()`);
      });
      wrap.append(button);
    } else if (input.type === Rive.StateMachineInputType.Boolean) {
      const box = document.createElement('input');
      box.type = 'checkbox';
      box.checked = Boolean(input.value);
      box.addEventListener('change', () => {
        input.value = box.checked;
      });
      wrap.append(box);
    } else {
      const slider = document.createElement('input');
      slider.type = 'range';
      slider.min = '0';
      slider.max = '100';
      slider.value = String(input.value ?? 0);
      slider.addEventListener('input', () => {
        input.value = Number(slider.value);
      });
      wrap.append(slider);
    }
    ui.inputs.append(wrap);
  }
}

// -------------------------------------------------------------- decay sim

ui.simSpeed.addEventListener('input', () => {
  ui.simSpeedOut.value = `${ui.simSpeed.value}x`;
});
ui.simSpeedOut.value = `${ui.simSpeed.value}x`;

ui.simToggle.addEventListener('click', () => (session.simTimer ? stopSim() : startSim()));
ui.simReset.addEventListener('click', () => {
  for (const control of session.numberControls) {
    control.handle.value = control.initial;
    control.sync();
  }
  log('vitals reset to spec defaults');
});

function startSim() {
  session.simLast = performance.now();
  session.simTimer = setInterval(tickSim, 100);
  ui.simToggle.textContent = 'Pause decay';
  ui.simToggle.classList.add('primary');
  log('decay started', 'ok');
}

function stopSim() {
  if (session.simTimer) clearInterval(session.simTimer);
  session.simTimer = null;
  ui.simToggle.textContent = 'Start decay';
  ui.simToggle.classList.remove('primary');
}

/**
 * Applies the placeholder decay rates from the rig spec so the idle -> sad
 * transition can be watched without waiting out a real timer.
 */
function tickSim() {
  const now = performance.now();
  const seconds = ((now - session.simLast) / 1000) * Number(ui.simSpeed.value);
  session.simLast = now;

  for (const [name, rate] of Object.entries(rigSpec.simulation.decayPerSecond)) {
    const control = session.bound.get(name);
    if (!control) continue;
    control.handle.value = clamp(control.handle.value - rate * seconds, control.min, control.max);
    control.sync();
  }
}

function applyBoost(triggerName) {
  const boosts = rigSpec.simulation.actionBoost[triggerName];
  if (!boosts) return;
  for (const [target, amount] of Object.entries(boosts)) {
    const control = session.bound.get(target);
    if (!control) continue;
    control.handle.value = clamp(control.handle.value + amount, control.min, control.max);
    control.sync();
  }
}

// ----------------------------------------------------------------- helpers

/** Rive reports load failures as an event object, an Error, or a bare string. */
function describeError(error) {
  if (!error) return 'unknown error';
  if (typeof error === 'string') return error;
  return error.message ?? error.data?.message ?? error.type ?? JSON.stringify(error);
}

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const format = (value) => (Number.isInteger(value) ? String(value) : value.toFixed(1));

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

log('Lab ready. Open a .riv to begin.');
