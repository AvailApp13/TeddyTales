/**
 * Дополнительные кости мишки в открытом файле Rive (через MCP): уши (D20), живот (D21).
 * MCP не создаёт кости, поэтому кость получается копией root_leg_left: копия (с копией
 * ноги внутри) -> потомки удаляются -> имя -> группа rig (мировые координаты артборда)
 * -> начало, угол, длина -> перенос в свою группу (мировое положение сохраняется).
 * Масштаб кости в редакторе — в процентах (100 = 1:1).
 */
import { restWorld, toLocal } from './rest_pose.mjs';

/**
 * Создаёт или переставляет кость `name` от точки `from` к `to` (артборд) в группе `groupId`.
 * file — запись editor_state для открытого файла (file.bones обновляется), save — запись состояния.
 */
export async function ensureBone(call, file, save, { name, groupId, from, to }) {
  const find = async () => (await call('find_objects', { artboardId: file.artboards.Bear_Boy.id })).objects ?? [];
  let objs = await find();
  const rigId = objs.find((o) => o.name === 'rig' && o.type === 'Node')?.id;
  let bone = objs.some((o) => o.id === file.bones[name]) ? file.bones[name] : objs.find((o) => o.name === name && o.type === 'RootBone')?.id;
  if (!bone) {
    const before = new Set(objs.filter((o) => o.type === 'RootBone').map((o) => o.id));
    await call('duplicate_objects', { objectIds: [file.bones.root_leg_left] });
    objs = await find();
    bone = objs.find((o) => o.type === 'RootBone' && !before.has(o.id))?.id;
    if (!bone) throw new Error(`${name}: копия кости не появилась`);
    const kids = (await call('query_objects', { objectIds: [bone] })).objects.filter((o) => o.id !== bone).map((o) => o.id);
    if (kids.length) await call('delete_objects', { objectIds: kids });   // копия ноги
    await call('rename_objects', { renames: [{ id: bone, name }] });
    file.bones[name] = bone; save();
    console.log(`${name}: создана ${bone}`);
  }
  // начало и направление — в rig (артборд), затем в свою группу
  await call('reparent_objects', { operations: [{ objectId: bone, newParentId: rigId, position: 'end' }] });
  const [x0, y0] = from, [x1, y1] = to;
  const rot = (Math.atan2(y1 - y0, x1 - x0) * 180) / Math.PI, len = Math.hypot(x1 - x0, y1 - y0);
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [bone]: { 90: x0, 91: y0, 15: rot, 89: len, 16: 100, 17: 100 } } });
    await new Promise((r) => setTimeout(r, 400 * (t + 1)));            // редактор применяет запись не сразу
    const v = (await call('query_property_values', { propertyKeys: { [bone]: [90, 91, 89, 16, 17] } })).values?.[bone] ?? {};
    if (Math.abs(v['90'] - x0) < 1e-2 && Math.abs(v['91'] - y0) < 1e-2 && Math.abs(v['89'] - len) < 1e-2
      && Math.abs(v['16'] - 100) < 1e-2 && Math.abs(v['17'] - 100) < 1e-2) break;
    if (t >= 5) throw new Error(`${name}: положение не записывается (прочитано ${JSON.stringify(v)}, нужно ${x0}, ${y0}, ${len})`);
  }
  for (let t = 0; ; t++) {
    const rr = await call('reparent_objects', { operations: [{ objectId: bone, newParentId: groupId, position: 'end' }] });
    if ((rr.reparented ?? []).some((o) => o.id === bone)) break;
    if (t >= 8) throw new Error(`${name}: не переносится в группу ${groupId}`);
    await new Promise((r) => setTimeout(r, 1500 * (1 + (t >> 1))));
  }
  // перенос в группу пересчитывает локальное положение неверно (кости ушей уезжали на 34–37 px,
  // D25): локальные начало и угол — заново, из мировой матрицы группы в покое
  const G = await restWorld(call, file, groupId); const [lx, ly] = toLocal(G, from);
  const lr = rot - Math.atan2(G[1], G[0]) * 180 / Math.PI;
  for (let t = 0; ; t++) {
    await call('set_property_values', { propertyValues: { [bone]: { 90: lx, 91: ly, 15: lr } } });
    await new Promise((r) => setTimeout(r, 400 * (t + 1)));
    const v = (await call('query_property_values', { propertyKeys: { [bone]: [90, 91, 15] } })).values?.[bone] ?? {};
    if (Math.abs(v['90'] - lx) < 1e-2 && Math.abs(v['91'] - ly) < 1e-2 && Math.abs(v['15'] - lr) < 1e-2) break;
    if (t >= 5) throw new Error(`${name}: локальное положение в группе не записывается (${JSON.stringify(v)})`);
  }
  console.log(`${name}: начало (${x0.toFixed(1)}, ${y0.toFixed(1)}), ${rot.toFixed(1)}°, длина ${len.toFixed(1)}`);
  return bone;
}
