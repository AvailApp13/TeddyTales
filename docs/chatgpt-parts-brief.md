# Задание для ChatGPT: нарисовать мишку в разборе на части

Этот документ самодостаточен: его целиком отправляют в чат ChatGPT вместе с
одной фотографией. Ничего больше ChatGPT знать не нужно.

---

## Контекст для тебя, ChatGPT

Мы делаем детское мобильное приложение с анимированным персонажем — плюшевым
мишкой. Анимация собирается из отдельных растровых картинок-частей: каждая
часть тела рисуется отдельным изображением, потом части складываются обратно
в персонажа и двигаются независимо (так устроена скелетная 2D-анимация).

Твоя задача — по приложенной фотографии реальной игрушки нарисовать этого
мишку: сначала целиком (эталон), потом «в разборе» — как набор деталей
конструктора. Критично: все части должны быть в одном стиле, с одного
ракурса, при одном свете, потому что потом они соединяются в одно тело.

К этому сообщению приложена фотография: плюшевый мишка с бежевым мехом
в голубой кофте с надетым капюшоном (уши торчат наружу через прорези в
капюшоне) и в светло-жёлтых шортах. Это герой. Его внешность менять
нельзя — это реальный продукт бренда.

## Какие части нужны — ровно 14

Размеры даны в пропорциях готового персонажа (замерены с эталонного
образца) — соблюдай их соотношения на листе. Итоговое разрешение каждого
листа — 2048×2048.

| # | Часть | Что рисовать | Пропорция (ш×в, у эталона) |
| --- | --- | --- | --- |
| 1 | голова | голова в надетом голубом капюшоне, с мордой и носом, но БЕЗ глаз, бровей, рта и ушей; прорези капюшона для ушей пустые | 264×291 — самая крупная деталь; с капюшоном габарит выйдет больше табличного, это ожидаемо |
| 2 | торс | туловище в голубой кофте БЕЗ капюшона (капюшон рисуется вместе с головой), без рук и ног | 183×140 |
| 3 | руки | обе руки в спокойной позе, чуть отведены | 303×140 (обе вместе) |
| 4 | ноги | обе ноги в жёлтых шортах, со ступнями | 184×82 |
| 5 | уши | оба уха | 337×73 (оба вместе) |
| 6 | белки глаз | два простых овала-белка | 184×73 |
| 7 | радужки | две тёмные радужки со зрачком и одним бликом в каждой | 145×47 |
| 8 | брови | обе брови | 161×24 |
| 9 | рот | открытый рот — тёмная полость с мягким контуром | 123×58 |
| 10 | язык | маленький язык | 70×26 |
| 11 | верхние веки | форма закрытых сверху глаз, цветом меха | 180×46 |
| 12 | нижние веки | тонкие нижние веки | 176×25 |
| 13 | левая рука-смех | левая рука, согнутая, лапа прижата к животу | 91×89 |
| 14 | правая рука-смех | то же зеркально | 86×85 |

## Порядок работы — три запроса, строго в одном чате

### Запрос 1 — эталон (сначала утверждается внешность)

Это НЕ задача «нарисуй красивого мишку». Это задача точного переноса:
приложенная фотография — единственный источник правды по внешности,
менять в ней можно только ракурс, позу, свет и фон. Любая «дизайнерская
интерпретация» — брак.

```
TASK TYPE: photo-faithful character render for animation. NOT a redesign,
NOT a stylization, NOT "inspired by". The attached photo is the single
source of truth for the character's appearance. Treat this as carefully
re-rendering THE SAME toy, not creating a similar one.

COPY FROM THE PHOTO 1:1 — every point is mandatory:
- head: wide rounded head, flat face, short muzzle, same proportions as
  the toy in the photo;
- muzzle and nose: small fluffy muzzle, small dark-brown nose, short
  stitched line under the nose; mouth CLOSED, neutral slightly serious
  expression exactly as in the photo — NO smile;
- eyes: two SMALL round glossy black bead eyes, same size and spacing as
  in the photo (not bigger, not cartoon-styled), one tiny highlight each;
- ears: two round fluffy ears sticking OUT through the slits in the hood,
  exactly as in the photo;
- fur: cream-beige, short dense plush, slightly fluffy silhouette edges;
- hoodie: light blue, hood UP with a soft pointed top, light inner lining
  visible around the face opening, one pale-blue round button on the chest
  placket, loose hem over the hips. NOTHING ELSE: no drawstrings, no
  laces, no cuffs, no pockets, no zippers, no extra seams;
- shorts: light yellow, loose, exactly as in the photo;
- paws and feet: bare cream-beige fur, no shoes, no clothing on arms;
- proportions: as the real toy — big head nearly as wide as the body,
  short arms, short legs, overall height ≈ 2.5 head heights.

CHANGE ONLY THIS (nothing else):
- view: strictly frontal, orthographic, camera at chest height, both ears
  and both feet fully visible, no perspective distortion;
- pose: A-pose — standing upright, arms slightly away from the body,
  legs slightly apart, head level, eyes straight ahead;
- light: soft even diffuse light, NO cast shadows, NO contact shadow
  under the feet, no rim light;
- background: one flat uniform color #808080 across the whole frame —
  zero gradient, zero vignette, zero floor line.

FORBIDDEN: redesigning or "improving" the toy; adding clothing details
absent from the photo; open mouth or smile; enlarged or stylized eyes;
gradient or white background; any shadow; text, watermark, logo.

OUTPUT: one square PNG, 2048×2048, character centered, ~10% margin
around the silhouette.

SELF-CHECK BEFORE SHOWING THE RESULT — verify every line; if any fails,
regenerate silently and only then present:
[ ] side-by-side with the photo it reads as THE SAME toy, not similar
[ ] eyes are small black beads, not enlarged cartoon eyes
[ ] mouth closed, expression matches the photo
[ ] ears pass through the hood slits
[ ] no drawstrings / laces / cuffs / pockets on the hoodie
[ ] hood is UP with a pointed top; yellow shorts present
[ ] background is one flat #808080, no gradient
[ ] no shadow of any kind, including under the feet
```

Если результат ушёл от фото — не описывать словами «что не так», а слать
список номерами: «1) глаза меньше, как на фото; 2) убери шнурки; …» и
требовать перегенерацию В ТОМ ЖЕ чате. Дальше не начинать, пока эталон
не утверждён.

### Запрос 2 — крупные части (детали 1–5 из таблицы)

```
Now draw the SAME character disassembled into separate body parts, laid out
on the same flat #808080 background like a toy assembly kit. Same colors,
same lighting, same style, same relative scale as in the approved image.
Parts must NOT touch or overlap, generous spacing.

Draw exactly five parts: (1) the head wearing the blue hood, with muzzle
and nose but WITHOUT eyes, eyebrows, mouth and ears — the ear slits in the
hood stay empty; (2) the torso in the blue hoodie WITHOUT the hood (the
hood belongs to the head part), no arms or legs; (3) both arms in relaxed
pose; (4) both legs wearing the light-yellow shorts, with feet; (5) both
ears.

Every part must be complete, including areas that were hidden behind other
parts in the full pose. No text, no labels, no numbers. Square, 2048px.
```

### Запрос 3 — лицо и состояния (детали 6–14)

```
Same character, same background, same style, one more parts sheet, spaced
apart, larger scale since these are small parts:

(1) both eye whites as simple ovals; (2) both dark irises with pupil and
one small highlight each; (3) both eyebrows; (4) an open mouth — dark inner
mouth with a soft outline; (5) a small tongue; (6) upper eyelids — the
shape of both eyes fully closed, in the fur color; (7) thin lower eyelids;
(8) the left arm bent with the paw pressed to the belly, as if giggling;
(9) the right arm bent the same way, mirrored.

No text, no labels, no numbers. Square, 2048px.
```

## Правила — не нарушать

- Все запросы в ОДНОМ чате, после утверждённого эталона: иначе фактура
  меха разойдётся между частями, и стыки будут видны.
- Фон всегда ровный `#808080`, без градиента и виньетки.
- Свет ровный рассеянный; никаких теней от одной части на другую и никакой
  тени под деталями.
- Никакого текста, подписей и номеров на изображениях.
- Часть вышла неудачно — перегенерировать только её, тем же чатом:
  «redraw only the <часть>, same style, same background».
- Блик в глазу ровно один и строго внутри радужки.

## Что вернуть

Три изображения: эталон целиком, лист крупных частей, лист мелких частей.
PNG, 2048×2048. Вырезкой частей из листов занимается наша сторона —
резать ничего не нужно.
