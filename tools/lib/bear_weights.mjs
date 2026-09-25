/**
 * Веса сеток мишки v2 — один источник для записи в Rive (scripts/skin_layers.mjs)
 * и для офлайн-проверки поз (scripts/simulate_pose.py через scripts/dump_weights.mjs).
 *
 * Функция веса: (x, y кадра 1333×2000) -> { кость: вес }. Кости — ключи
 * editor_state.bones (root, root_body, root_arm_*, root_leg_*).
 *
 *  sleeve_*  : шов реглана от шеи до подмышки держится за туловище (root),
 *              всё дальше ~90 px от шва — целиком на кости руки. Тянется только
 *              узкая полоса у шва и подмышки: подмышка остаётся на месте, рукав у
 *              плеча остаётся широким, манжета и лапа не меняют размер (D16).
 *  hood      : нижний край (на толстовке и плечах) — root, кромка у лица, стенки и
 *              остриё — с головой (root_body); обод между ними тянется
 *              пропорционально. Из-под капюшона при наклоне ничего не открывается.
 *  shorts    : пояс — root, штанины — кости ног (левая/правая по оси).
 *  shirt     : дыхание животом (D21): живот — кость root_belly (её масштаб от центра
 *              живота), вес спадает к груди и плечам. На вдохе живот только
 *              расширяется (масштаб ≥ 1): бока и низ толстовки уходят наружу — на
 *              фон и на шорты, которые лежат за толстовкой, дыр не бывает.
 *  paw_*, face: целиком на кости (рука / голова) — без растяжения (D15).
 *  ear_*     : у капюшона — как капюшон в этой точке, в 60 px от него ухо целиком на
 *              кости root_ear_* (D20); поворот и масштаб кости — переход к
 *              нарисованным положениям ушей ear_*_cup / ear_*_droop (D24).
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { repoRoot } from './rig.mjs';

export const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// верхняя часть шва реглана (кадр): от шеи под капюшоном до подмышки —
// те же точки, что в split_full_bear.py (SLEEVE_L / SLEEVE_R)
export const SEAM_UP = {
  left: [[472, 1040], [466, 1110], [452, 1180], [440, 1240]],
  right: [[893, 1040], [893, 1120], [905, 1190], [918, 1250]],
};
const segDist = (px, py, [ax, ay], [bx, by]) => {
  const dx = bx - ax, dy = by - ay; const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
};
export const polyDist = (pts, x, y) => { let d = Infinity; for (let i = 1; i < pts.length; i++) d = Math.min(d, segDist(x, y, pts[i - 1], pts[i])); return d; };

export function loadWeights() {
  const D = resolve(repoRoot, 'handoff', 'layers_v2');
  const meta = JSON.parse(readFileSync(resolve(D, 'layers.json'), 'utf8'));
  const F = JSON.parse(readFileSync(resolve(D, 'weight_fields.json'), 'utf8'));
  const AXIS = meta.axisX;
  // карты расстояний (scripts/weight_fields.py), шаг F.step px
  const dist = (name, x, y) => { const r = F[name][Math.min(F[name].length - 1, Math.max(0, Math.round(y / F.step)))]; return r[Math.min(r.length - 1, Math.max(0, Math.round(x / F.step)))]; };

  const SLEEVE_BAND = 90;   // ширина полосы растяжения у шва, px кадра
  const NECK_BAND = (process.env.NECK_BAND ?? '40,140').split(',').map(Number);   // от верха шва: туловище -> рука
  const sleeveW = (seam, arm) => (x, y) => {
    // ниже подмышки край рукава (он лежит вдоль бока) сразу идёт с рукой:
    // иначе он почти стоит и при подъёме тянется вдоль бока тонкой «лентой»
    const armpitY = seam.at(-1)[1];
    // у шеи (верх шва реглана) рукав держится за туловище: иначе верх рукава при
    // подъёме руки поворачивался и заступал треугольником на воротник
    const neck = smooth(NECK_BAND[0], NECK_BAND[1], Math.hypot(x - seam[0][0], y - seam[0][1]));
    const w = Math.max(smooth(6, SLEEVE_BAND, polyDist(seam, x, y)) * neck, smooth(armpitY - 10, armpitY + 70, y));
    return { root: 1 - w, [arm]: w };
  };
  const HOOD_BAND = [12, 110];  // от основания капюшона: root -> голова (стенки, остриё)
  const hoodW = (x, y) => {
    const db = dist('hood_base', x, y), df = dist('face', x, y);
    const walls = smooth(HOOD_BAND[0], HOOD_BAND[1], db);
    // обод между лицом и основанием: нижний край лежит на толстовке и плечах
    // (root), верхний идёт с подбородком (голова); ткань обода между ними
    // тянется/сжимается пропорционально (доля пути от основания к лицу).
    // Из-под капюшона при наклоне ничего не открывается — ни ворот, ни фон.
    const rim = db / (db + df + 1e-6);
    const h = Math.max(walls, rim);
    return { root: 1 - h, root_body: h };
  };
  // ухо (D20, D24): основание у капюшона берёт веса капюшона в этой точке (нижний конец
  // стыка лежит у плеча, где капюшон частично на root), уже в 60 px от капюшона ухо
  // целиком идёт с костью уха — поворот и масштаб кости двигают ухо целиком при
  // переходе к нарисованным положениям (ear_states.py)
  const EAR_BAND = (process.env.EAR_BAND ?? '3,60').split(',').map(Number);
  const earW = (bone) => (x, y) => {
    const w = smooth(EAR_BAND[0], EAR_BAND[1], dist('hood', x, y)); const h = hoodW(x, y);
    return { root: (1 - w) * h.root, root_body: (1 - w) * h.root_body, [bone]: w };
  };
  // живот: вес — близость к центру живота; силуэт (бока, низ) дышит вместе с ним
  const [BX, BY] = F.belly;
  const BELLY_R = (process.env.BELLY_R ?? '160,380').split(',').map(Number);   // ядро и край зоны живота, px кадра
  const bellyW = (x, y) => {
    const w = 1 - smooth(BELLY_R[0], BELLY_R[1], Math.hypot(x - BX, (y - BY) * 1.25));   // по высоте зона чуть ниже
    return { root: 1 - w, root_belly: w };
  };
  const PLAN = {
    shirt: { bones: ['root', 'root_belly'], w: bellyW },
    sleeve_left: { bones: ['root', 'root_arm_left'], w: sleeveW(SEAM_UP.left, 'root_arm_left') },
    sleeve_right: { bones: ['root', 'root_arm_right'], w: sleeveW(SEAM_UP.right, 'root_arm_right') },
    // лапы и лицо двигаются целиком — без растяжения (обратная связь: лапы раздувались, морда кривилась)
    paw_left: { bones: ['root', 'root_arm_left'], w: () => ({ root_arm_left: 1 }) },
    paw_right: { bones: ['root', 'root_arm_right'], w: () => ({ root_arm_right: 1 }) },
    face: { bones: ['root', 'root_body'], w: () => ({ root_body: 1 }) },
    hood: { bones: ['root', 'root_body'], w: hoodW },
    ear_left: { bones: ['root', 'root_body', 'root_ear_left'], w: earW('root_ear_left') },
    ear_right: { bones: ['root', 'root_body', 'root_ear_right'], w: earW('root_ear_right') },
    // нарисованные положения ушей (D24) — те же веса, каждое на своей кости
    ...Object.fromEntries(Object.keys(meta.ear_states ?? {}).flatMap((st) => ['left', 'right'].map((sd) =>
      [`ear_${sd}_${st}`, { bones: ['root', 'root_body', `root_ear_${sd}_${st}`], w: earW(`root_ear_${sd}_${st}`) }]))),
    shorts: { bones: ['root', 'root_leg_left', 'root_leg_right'], w: (x, y) => {
      const leg = smooth(1520, 1640, y); const side = smooth(AXIS - 40, AXIS + 40, x);
      return { root: 1 - leg, root_leg_left: leg * (1 - side), root_leg_right: leg * side }; } },
  };
  return { PLAN, meta };
}
