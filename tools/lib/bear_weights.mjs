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
 *  hood      : углы капюшона, лежащие на плечах, — root; всё остальное (остриё,
 *              кромка вокруг лица, обод под подбородком в колонках лица) —
 *              целиком с головой (root_body), переход к плечам плавный.
 *  shorts    : пояс — root, штанины — кости ног (левая/правая по оси).
 *  paw_*, face: целиком на кости (рука / голова) — без растяжения (D15).
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
  const sleeveW = (seam, arm) => (x, y) => {
    const w = smooth(6, SLEEVE_BAND, polyDist(seam, x, y));
    return { root: 1 - w, [arm]: w };
  };
  const HOOD_BAND = [12, 110];  // от основания капюшона на плечах: root -> голова
  const HOOD_RING = [15, 45];   // кромка вокруг лица — целиком с головой
  const HOOD_CHIN = [190, 300]; // по горизонтали от оси: в колонках лица — с головой, к плечам — root
  const hoodW = (x, y) => {
    const base = smooth(HOOD_BAND[0], HOOD_BAND[1], dist('hood_base', x, y));
    const ring = 1 - smooth(HOOD_RING[0], HOOD_RING[1], dist('face', x, y));
    // капюшон наклоняется с головой целиком, как у игрушки, — вместе с ободом под
    // подбородком (ось головы у шеи). Стоят только углы, лежащие на плечах.
    // Смешивать в тонком ободе «с головой» и «на месте» нельзя: он надламывается,
    // а подбородок отходит от обода серой щелью.
    const chin = 1 - smooth(HOOD_CHIN[0], HOOD_CHIN[1], Math.abs(x - AXIS));
    const h = Math.max(base, ring, chin);
    return { root: 1 - h, root_body: h };
  };
  const PLAN = {
    sleeve_left: { bones: ['root', 'root_arm_left'], w: sleeveW(SEAM_UP.left, 'root_arm_left') },
    sleeve_right: { bones: ['root', 'root_arm_right'], w: sleeveW(SEAM_UP.right, 'root_arm_right') },
    // лапы и лицо двигаются целиком — без растяжения (обратная связь: лапы раздувались, морда кривилась)
    paw_left: { bones: ['root', 'root_arm_left'], w: () => ({ root_arm_left: 1 }) },
    paw_right: { bones: ['root', 'root_arm_right'], w: () => ({ root_arm_right: 1 }) },
    face: { bones: ['root', 'root_body'], w: () => ({ root_body: 1 }) },
    hood: { bones: ['root', 'root_body'], w: hoodW },
    shorts: { bones: ['root', 'root_leg_left', 'root_leg_right'], w: (x, y) => {
      const leg = smooth(1520, 1640, y); const side = smooth(AXIS - 40, AXIS + 40, x);
      return { root: 1 - leg, root_leg_left: leg * (1 - side), root_leg_right: leg * side }; } },
  };
  return { PLAN, meta };
}
