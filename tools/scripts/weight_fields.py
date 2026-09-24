#!/usr/bin/env python3
"""
Карты расстояний для весов сеток (tools/lib/bear_weights.mjs): от каждого пикселя
кадра 1333×2000 до лица, до лап, до основания капюшона (там, где капюшон лежит
на толстовке и рукавах) и до капюшона (изгиб ушей), в пикселях кадра, с шагом 4 px.
    python3 tools/scripts/weight_fields.py   # -> handoff/layers_v2/weight_fields.json
"""
import json
import numpy as np
from PIL import Image
from scipy import ndimage
D = '/home/user/TeddyTales/handoff/layers_v2'
STEP = 4
out = {'step': STEP}
for name in ('face', 'paw_left', 'paw_right'):
    a = np.asarray(Image.open(f'{D}/{name}.png'))[..., 3] > 128
    dist = ndimage.distance_transform_edt(~a)[::STEP, ::STEP]
    out[name] = np.round(np.minimum(dist, 400)).astype(int).tolist()
# основание капюшона: пиксели капюшона, соседние с тканью под ним (толстовка,
# рукава) — не с лицом, ушами и не с фоном
src = np.asarray(Image.open('/home/user/TeddyTales/handoff/reference/bear_boy_v2_full.png').convert('RGBA'))[..., 3] > 128
hood = np.asarray(Image.open(f'{D}/hood.png'))[..., 3] > 128
face = np.asarray(Image.open(f'{D}/face.png'))[..., 3] > 128
ears = (np.asarray(Image.open(f'{D}/ear_left.png'))[..., 3] > 128) | (np.asarray(Image.open(f'{D}/ear_right.png'))[..., 3] > 128)
under = src & ~hood & ~face & ~ears
base = hood & ndimage.binary_dilation(under, iterations=3)
out['hood_base'] = np.round(np.minimum(ndimage.distance_transform_edt(~base)[::STEP, ::STEP], 400)).astype(int).tolist()
# от капюшона — для изгиба ушей: основание уха (под капюшоном и у кромки) стоит
out['hood'] = np.round(np.minimum(ndimage.distance_transform_edt(~hood)[::STEP, ::STEP], 400)).astype(int).tolist()
json.dump(out, open(f'{D}/weight_fields.json', 'w'), separators=(',', ':'))
print('ok', len(out['face']), 'x', len(out['face'][0]))
