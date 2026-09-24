#!/usr/bin/env python3
"""
Карты расстояний для весов сеток (skin_layers.mjs): от каждого пикселя кадра
1333×2000 до лица и до лап, в пикселях кадра, с шагом 4 px.
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
json.dump(out, open(f'{D}/weight_fields.json', 'w'), separators=(',', ':'))
print('ok', len(out['face']), 'x', len(out['face'][0]))
