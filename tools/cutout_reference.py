"""
Вырезает мишку из референсного фото (handoff/reference/bear_boy_front.jpg)
и режет на слои по цветовым классам. Запуск из корня репозитория:

    ./venv/bin/python tools/cutout_reference.py   # нужны pillow, numpy, scipy

Результат: cutout/_full.png (целый мишка с прозрачным фоном) и по слою на
часть. Полный вырез — годится «один в один»; нарезка по цвету — черновая,
границы частей под одеждой из одного фото не восстанавливаются.
"""
import numpy as np, json
from PIL import Image
from scipy import ndimage

src = Image.open('/home/user/TeddyTales/handoff/reference/bear_boy_front.jpg').convert('RGB')
rgb = np.asarray(src).astype(float)
hsv = np.asarray(src.convert('HSV')).astype(float)
H, S, V = hsv[...,0]*360/255, hsv[...,1]/255, hsv[...,2]/255
Yg, Xg = np.mgrid[0:S.shape[0], 0:S.shape[1]]
box = (Xg > 135) & (Xg < 405) & (Yg > 260) & (Yg < 668)
op = lambda m, n: ndimage.binary_opening(m, iterations=n)
cl = lambda m, n: ndimage.binary_closing(m, iterations=n)

figure = box & ((S > 0.10) | (V < 0.35))
figure = ndimage.binary_fill_holes(cl(figure, 4))
figure = op(figure, 1)
lab, n = ndimage.label(figure)
sizes = ndimage.sum(figure, lab, range(1, n+1))
figure = np.isin(lab, [i+1 for i, s in enumerate(sizes) if s > 300])
alpha = np.clip((ndimage.gaussian_filter(figure.astype(float), 1.0) - 0.3) / 0.4, 0, 1)

blue   = cl(op(figure & (H > 180) & (H < 230) & (S > 0.15) & (V > 0.45), 1), 3)
yellow = cl(op(figure & (H > 35) & (H < 70) & (S > 0.22) & (V > 0.55), 1), 3)
fur = op(figure & ~blue & ~yellow, 1)

parts = {
  'head':        fur & (Yg < 468),
  'outfit_head': blue & (Yg < 462),
  'outfit_body': blue & (Yg >= 440),
  'hand_left':   fur & (Yg > 478) & (Yg < 565) & (Xg < 205),
  'hand_right':  fur & (Yg > 478) & (Yg < 565) & (Xg > 335),
  'outfit_feet': yellow,
  'leg_left':    fur & (Yg > 552) & (Xg < 268),
  'leg_right':   fur & (Yg > 552) & (Xg >= 268),
}
meta = {}
for name, m in parts.items():
    m = cl(m, 2)
    if m.sum() < 30: print('пусто:', name); continue
    a = alpha * np.clip((ndimage.gaussian_filter(m.astype(float), 0.8) - 0.25) / 0.5, 0, 1)
    ys, xs = np.where(a > 0.05)
    x0, x1, y0, y1 = xs.min(), xs.max()+1, ys.min(), ys.max()+1
    tile = np.dstack([rgb[y0:y1, x0:x1], a[y0:y1, x0:x1]*255]).astype('uint8')
    Image.fromarray(tile, 'RGBA').resize(((x1-x0)*2, (y1-y0)*2), Image.LANCZOS).save(f'cutout/{name}.png')
    meta[name] = {'cx': float((x0+x1)/2), 'cy': float((y0+y1)/2), 'w': int(x1-x0), 'h': int(y1-y0)}
    print(f'{name:12s} центр ({meta[name]["cx"]:.0f},{meta[name]["cy"]:.0f})  {x1-x0}x{y1-y0}  px={int(m.sum())}')
json.dump(meta, open('cutout/meta.json', 'w'), indent=1)
full = Image.fromarray(np.dstack([rgb, alpha*255]).astype('uint8'), 'RGBA'); full.save('cutout/_full.png')
sheet = Image.new('RGBA', (533*2, 800), (40,40,46,255)); sheet.paste(full, (0,0), full)
for i, name in enumerate(meta):
    t = Image.open(f'cutout/{name}.png'); t.thumbnail((170,170)); sheet.paste(t, (533+(i%3)*175, (i//3)*195), t)
sheet.save('cutout/_sheet.png'); print('лист сохранён')
