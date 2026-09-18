# Бриф на генерацию листов персонажа

Рабочая выжимка из раздела 2 `docs/tz-animator-v2.md` — то, что можно взять и
сразу генерировать. ТЗ остаётся источником требований; здесь готовые промпты
и измеримый чеклист приёмки листа.

Промпты на английском: модели заметно точнее держат ограничения на нём,
особенно отрицания («no cast shadows»).

## Что генерируем

На героя **SLOW** (Milk Tea) — четыре листа:

| Лист | Что на нём | Для чего |
| --- | --- | --- |
| `slow_baby` | полный рост, пропорции 1 : 2,6 | группа `baby`, стадии 1–2 |
| `slow_toddler` | полный рост, 1 : 3,2 | группа `toddler`, стадия 3 |
| `slow_child` | полный рост, 1 : 3,8 | группа `child`, стадии 4–5 |
| `slow_head` | голова крупным планом | глаза, зрачки, брови, рот, спрайты лица |

Герой **JOY** (White) отдельно не генерируется — он делается перекраской
готовых и утверждённых листов SLOW. Силуэт обязан совпасть: нарезка идёт
одними масками на обоих героев.

Отдельный лист головы нужен потому, что на полном росте голова занимает
около четверти высоты — при 2048 px это ~500 px на голову, а из неё режутся
глаза, зрачки, блики и брови. Разрешения не хватит.

## Настройки

- Соотношение **1:1**, разрешение **не менее 2048×2048 нативно**.
- Апскейлеры запрещены, в том числе нейросетевые: они дорисовывают фактуру
  меха по-разному на соседних частях, и стык потом читается.
- Seed записывать. Без него не воспроизвести недостающую часть.

## Промпт 1 — базовый лист (группа `child`)

```
A plush teddy bear character, full body, standing, strictly front view,
orthographic projection — no perspective distortion, no camera tilt, no
foreshortening. Soft 3D render look, smooth matte plush fur with subtle
fabric texture, rounded friendly proportions, large head, big glossy eyes.
Fur color: warm milk tea beige.

Head-to-body ratio 1:3.8.

Neutral A-pose: arms held away from the torso at 15-20 degrees, paws fully
separated from the body, legs apart, feet fully separated from each other.
No body part overlaps any other body part. Every limb fully visible along
its whole length.

Soft diffuse light from above and slightly in front, even illumination.
No cast shadow from one body part onto another. No contact shadow under
the feet. No shadow anywhere outside the silhouette.

Exactly one small round highlight per eye, placed entirely inside the pupil.
Perfectly symmetrical left and right.

Flat mid-grey background, single flat color #808080, no gradient, no
vignette, no floor, no props, no text, no watermark, no logo.

Square composition, character centered, 5% empty margin on all sides.
```

## Промпт 2 — другие возрасты

Не новая генерация, а **правка первого листа**, чтобы персонаж остался тем же:

```
Keep the exact same character, fur color, art style, lighting, camera angle
and background. Change only the body proportions to a younger age:
head-to-body ratio 1:2.6, noticeably larger head, shorter and stubbier
limbs, rounder torso, infant proportions.

Keep the same A-pose with limbs separated. Keep exactly one highlight per
eye inside the pupil. Keep the flat #808080 background with no shadows.
```

Для `toddler` — то же с соотношением **1 : 3.2**.

## Промпт 3 — второй герой (перекраска)

Правка утверждённого листа SLOW. Ключевое требование — не тронуть контур:

```
Keep the exact same pose, silhouette, outline, proportions, lighting,
camera and background — do not move or reshape anything by a single pixel.

Change only the fur color: soft warm white, the brightest point no lighter
than #F0EAE2. Keep the inner ears and muzzle slightly warmer and pinker
than the fur so they stay readable. Keep the eyes, pupils and highlights
unchanged.
```

Ограничение по яркости не декоративное: фон приложения кремовый `#F6F1EB`,
и слишком белый мишка на нём теряет силуэт.

## Промпт 4 — лист головы

```
Same character, head and shoulders only, strictly front view, orthographic.
Same fur color, same art style, same soft diffuse lighting, same flat
#808080 background.

Neutral expression, mouth closed, eyes open and looking straight ahead,
eyebrows in neutral position. Ears fully visible and separated from the
head outline. Exactly one small round highlight per eye inside the pupil.

Square composition, head centered, filling most of the frame.
```

## Чеклист приёмки листа

Проверяется до нарезки. Лист, не прошедший проверку, перегенерируется —
чинить это после нарезки нельзя.

| Что | Допуск | Чем проверить |
| --- | --- | --- |
| Симметрия силуэта | разница площадей левой и правой половин ≤ 2% | `tool/sheet_check.py` |
| Парные конечности | разница длин ≤ 3% | глазом по маске |
| Уши на одной горизонтали | ≤ 1% высоты листа | `tool/sheet_check.py` |
| Фон ровно `#808080` | угловые пиксели, без градиента | `tool/sheet_check.py` |
| Нет контактной тени | нет непрозрачных пикселей ниже нижней точки стоп | `tool/sheet_check.py` |
| Нет теней между частями | визуально | глазом |
| Части не перекрываются | контур каждой восстанавливается без дорисовки | глазом |
| Один блик на глаз, внутри зрачка | — | глазом |
| Нет текста и водяных знаков | — | глазом |
| JOY: самая светлая точка меха | не светлее `#F0EAE2` | `tool/sheet_check.py` |

```
python3 tool/sheet_check.py graphics/source/slow_child.png
```

## Что дальше — нарезка

Лист режется на **50 изображений** по номенклатуре из раздела 2.3 ТЗ:
14 частей тела, 9 головы, 11 лица, 8 спрайтов глаз, 4 рта, 4 бровей.

Три вещи, на которых обычно горит нарезка:

**Перехлёст.** На каждом стыке части должны заходить друг на друга не менее
чем на 10% длины стыка и не менее 24 единиц артборда (шея — 48). Без запаса
при повороте кости на стыке появится щель.

**Дорисовка закрытых зон.** То, что спрятано под перекрытием — подмышка,
участок под ухом, кусок торса за лапой, — в исходнике не нарисовано. При
разведении конечностей в анимации там будет дыра. Это ручная работа, и
именно в неё уходит основное время: у разобранного демо-рига экспорт 14
частей занял 4 минуты, а весь арт — полтора-два дня.

**Зачистка метаданных.** Обязательна, иначе файл распухнет в пять раз:

```
cwebp -metadata none -q 82 -alpha_q 100 part.png -o part.webp
```

Именование: `bear_slow_child_arm_left_lower.webp`, `wear_top_03_toddler.webp`.
Токены групп только `baby`, `toddler`, `child` — имя ассета единственное, что
переживает экспорт из Rive, и переименовать его потом можно только
перезаливкой всех картинок.

## Пилот

Прежде чем заказывать все шесть комплектов, стоит прогнать один: сгенерировать
`slow_child`, нарезать его, собрать минимальный риг с одним `idle` и прогнать
`tool/riv_lint.py`. Если конвейер где-то ломается, это выяснится на одном
комплекте, а не на шестом.
