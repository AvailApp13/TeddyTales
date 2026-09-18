# Рецепт: повторить демо-риг монстра с нашим мишкой

Пошаговая инструкция, как собрать точную копию `demo_monster.riv` по движениям
и поведению, но с мишкой SLOW в голубой кофте. Все числа — из побайтового
разбора монстра, не из головы.

Что получится: персонаж дышит, моргает, следит взглядом за пальцем,
смеётся по нажатию на живот и сам возвращается в покой. Ровно то, что сейчас
делает монстр в приложении.

---

## Часть 1. Картинки — генерируются, 14 штук

У монстра 17 частей. У мишки нет рогов и отдельных зубов, итого **14**:

| # | Имя файла | Что это | Размер у монстра (ориентир) |
| --- | --- | --- | --- |
| 1 | `head` | голова целиком с мордой и носом, БЕЗ глаз, рта, бровей и ушей | 264×291 |
| 2 | `torso` | туловище в голубой кофте | 183×140 |
| 3 | `arms` | обе руки в спокойной позе, лист один | 303×140 |
| 4 | `legs` | обе ноги со ступнями | 184×82 |
| 5 | `ears` | оба уха | 337×73 |
| 6 | `eyeballs` | белки обоих глаз | 184×73 |
| 7 | `iris` | обе радужки со зрачками и бликами | 145×47 |
| 8 | `eyebrows` | обе брови | 161×24 |
| 9 | `mouth` | открытый рот (тёмная полость с контуром) | 123×58 |
| 10 | `tongue` | язык | 70×26 |
| 11 | `eyesblink_up` | верхние веки (глаза прикрыты сверху) | 180×46 |
| 12 | `eyesblink_down` | нижние веки | 176×25 |
| 13 | `giggle_arm_l` | левая рука в позе смеха (прижата к животу) | 91×89 |
| 14 | `giggle_arm_r` | правая рука в позе смеха | 86×85 |

Размеры даны при артборде 500×559 — генерировать надо крупнее (в 2–3 раза),
в редакторе уменьшится без потерь.

### Промт 1 — референс персонажа (сначала утвердить внешность)

Приложите к нему фото нашего мишки в голубой кофте.

```
A cute plush teddy bear character based on the attached photo: cream-beige
fur, wearing the same light blue hoodie with the hood down, soft 3D render,
smooth plush texture. Full body, standing, strictly front view, orthographic,
no perspective. A-pose: arms held slightly away from the body, legs apart.
Big glossy dark eyes looking straight ahead, one small highlight per eye
inside the pupil. Friendly neutral expression, mouth closed.
Soft diffuse light from above-front, no cast shadows, no contact shadow.
Flat mid-grey background #808080, no text, no watermark. Square, 2048px.
```

Перегенерируйте, пока внешность не понравится. Этот кадр — эталон: все
части дальше должны совпадать с ним по цвету и свету.

### Промт 2 — разобранный лист частей (главный трюк)

Части генерируются НЕ вырезанием из целого, а сразу «в разборе» — тогда
скрытые зоны (подмышки, участок за ушами) дорисованы самой моделью и дырок
при анимации не будет. В том же чате, следом за утверждённым референсом:

```
Now draw the SAME character disassembled into separate body parts, laid out
on the same flat #808080 background like a toy assembly kit / sprite sheet.
Same colors, same lighting, same style, same scale. Parts must NOT touch or
overlap each other, generous spacing between them.

Parts to draw, each complete including areas that were hidden in the full
pose: (1) head with muzzle and nose but WITHOUT eyes, eyebrows, mouth and
ears — smooth fur where they would be; (2) torso in the blue hoodie;
(3) both arms in relaxed pose; (4) both legs with feet; (5) both ears;
(6) both eye whites as simple ovals; (7) both irises with pupils and one
highlight each; (8) both eyebrows; (9) an open mouth shape (dark inner
mouth with outline); (10) a small tongue.

No text, no labels, no numbers on the image. Square, 2048px.
```

### Промт 3 — лист состояний (тем же чатом)

```
Same character, same background, same style. Draw on one sheet, spaced
apart: (1) both eyes fully closed — soft upper eyelids in the fur color,
the shape of the closed upper lids only; (2) the lower eyelids only, thin;
(3) the left arm bent, paw pressed to the belly, as if giggling; (4) the
right arm bent the same way, mirrored.
No text, no labels. Square, 2048px.
```

### Правила приёмки листов

- Все части в одном чате с одним референсом — иначе разойдётся фактура.
- Свет ровный, теней между частями нет, фон строго один тон.
- Если какая-то часть вышла плохо — перегенерировать только её, тем же чатом:
  «redraw part N, same style».
- Дальше: вырезать каждую часть (по ровному фону это делает даже автоматика),
  сохранить PNG с прозрачностью, прогнать через
  `cwebp -metadata none -q 82 -alpha_q 100` — без этого файл распухнет
  в пять раз (у монстра 80% веса — мусор Photoshop).

---

## Часть 2. Сборка в Rive Editor

Редактор: rive.app, работа в браузере. Для экспорта `.riv` нужен тариф
Cadet ($9/мес). Артборд 500×559, fps 60, фон артборда — ПРОЗРАЧНЫЙ
(никакой заливки: заливку артборда рантайм честно рисует, и она закроет
комнату приложения — проверено на монстре).

### 2.1 Слои (снизу вверх)

legs → arms → torso → ears → head → eyesblink_down → eyeballs → iris →
eyesblink_up → eyebrows → mouth → tongue → giggle_arm_l → giggle_arm_r.

`giggle_arm_*` по умолчанию скрыты через **Solo** с обычными руками:
Solo «arms_state» с двумя детьми — `arms_normal` (обычные) и `arms_giggle`
(парные giggle-руки). Активен `arms_normal`.

Рот и язык режутся маской: векторная фигура без заливки поверх зоны рта,
на `mouth` и `tongue` — ClippingShape этой фигурой. То же для глаз: фигура
по контуру глазниц режет `eyesblink_*` и `iris`. Это единственное законное
применение вектора в файле.

### 2.2 Кости — 18 штук, одно дерево

```
b_root (у пола, корень)
└─ b_hip (таз)
   ├─ b_spine (торс, длинная ~124)
   │  └─ b_chest (грудь/шея, самая длинная ~192)
   │     ├─ b_head (голова)
   │     │  ├─ b_ear_l, b_ear_r (уши)
   │     │  ├─ b_brow_l, b_brow_r (брови)
   │     │  └─ b_pupils (зрачки — их водит джойстик)
   │     ├─ b_arm_l_up → b_arm_l_low (левая рука, два звена)
   │     └─ b_arm_r_up → b_arm_r_low (правая)
   ├─ b_leg_l_up → b_leg_l_low (левая нога)
   └─ b_leg_r_up → b_leg_r_low (правая)
```

Привязка (Bind) каждой картинки к своей кости. У монстра скиннинг жёсткий —
каждая вершина на 100% к одной кости; для реплики этого достаточно, швы
прячутся перекрытием частей.

### 2.3 Меши — только там, где гнётся

У монстра 12 из 18 мешей — простые четырёхугольники, их трогать не надо
(Rive создаёт их сам). Настоящая сетка только на пяти частях:

| Часть | Вершин у монстра | Зачем |
| --- | --- | --- |
| `eyebrows` | 23 | изгиб брови — главная мимика |
| `head` | 18 | мягкий сквош при смехе |
| `arms` | 14–15 | изгиб в локтях |
| `legs` | 12 | изгиб в коленях |
| `ears` | 8 | подрагивание |

### 2.4 Анимации — 8 таймлайнов

| Имя | Кадров | Режим | Что внутри |
| --- | --- | --- | --- |
| `idle` | 180, work area 60–120 | Loop | дыхание: лёгкий масштаб торса, покачивание головы, микродвижения ушей. Играет только зона 60–120 (1 секунда) |
| `giggle` | 180, work area 60–120 | Loop | смех: сквош головы и торса, Solo «arms_state» ключом переключён на `arms_giggle`. На кадре ~113 — **Rive Event** `idleEvent` (см. 2.6) |
| `blink_on` | 600 | Loop | три моргания за 10 секунд: `eyesblink_up/down` быстро опускаются-поднимаются, каждое моргание 6–8 кадров, последнее двойное |
| `blink_off` | 1 | One Shot | веки убраны (для сна/зажмуривания) |
| `look_x` | 60, 2 ключа | — | не анимация, а диапазон: `b_pupils` и чуть-чуть уши из крайнего левого в крайнее правое положение, ключи только на кадрах 0 и 60, линейно |
| `look_y` | 60, 2 ключа | — | то же по вертикали |
| `look_on` | 1 | One Shot | включает хит-зону взгляда (масштаб 1) |
| `look_off` | 1 | One Shot | выключает (масштаб 0) |

Важно: рабочую область (work area) выставить обязательно и мусорные ключи
за её пределами удалить перед экспортом — у монстра 425 из 1659 ключей
никогда не играют и просто возят вес.

### 2.5 Вью-модель — управление позой

- Enum `posesEnum` со значениями `giggle` и `idle`.
- View Model «ViewModel1» с одним свойством `poses` типа `posesEnum`.
- Один экземпляр (Instance), значение по умолчанию `idle`.
  **Ровно один экземпляр** — приложение берёт первый попавшийся.

### 2.6 State Machine — 3 слоя

Машина одна, слоёв три, все переходы — по условию «`poses` равно …»:

- **Слой body:** Entry → `idle` (speed 0.75). Any State → `giggle`
  (speed 0.85) при `poses == giggle`; `giggle` → `idle` при `poses == idle`.
  Длительность переходов ~200 мс.
- **Слой eyes:** Entry → `blink_on`. Any State → `blink_off` при
  `poses == giggle`; `blink_off` → `blink_on` при `poses == idle`.
- **Слой look:** Entry → `look_on`. Any State → `look_off` при
  `poses == giggle`; обратно при `poses == idle`.

### 2.7 Интерактив — три слушателя и джойстик

1. **Кнопка-живот.** Невидимая фигура (эллипс ~133×117, Fill выключен)
   поверх живота, привязана к `b_spine`. Listener типа **Pointer Down** на
   эту фигуру → действие: установить `poses = giggle`.
2. **Самовозврат.** В анимации `giggle` на кадре ~113 стоит Event
   `idleEvent`. Listener типа **Event** на `idleEvent` → действие:
   `poses = idle`. Персонаж сам заканчивает смеяться, приложению таймер
   не нужен.
3. **Взгляд за пальцем.** Невидимая фигура во весь артборд. Listener типа
   **Pointer Move** → действие Align Target: тянуть служебный Node
   «look_target» к указателю. **Joystick** (область ~531×531 по центру
   артборда) читает позицию этого Node и скрабит `look_x` / `look_y`.
   Ни одного входа State Machine на это не тратится.

### 2.8 Экспорт и проверка

Export → `.riv` (для рантайма). Положить в `assets/rive/` и прогнать:

```
python3 tool/riv_lint.py assets/rive/<файл>.riv
```

Линтер проверит вес, отсутствие заливки артборда, метаданные в картинках,
единственность экземпляра вью-модели и прочее. Ожидаемый вес после зачистки
метаданных — меньше 100 КБ.

В приложении файл подключается одной строкой: `BearRigSpec.demoAssetPath`
в `lib/bear/bear_rig_spec.dart`. Привязка данных и нажатия заработают сами —
код это уже умеет, проверено на монстре.

---

## Честная оценка трудоёмкости

| Этап | Времени |
| --- | --- |
| Генерация и утверждение листов | 1–3 часа |
| Вырезание частей и зачистка | 1–2 часа |
| Кости, привязка, меши | 0,5–1 день |
| 8 анимаций | 0,5–1,5 дня |
| State Machine, слушатели, джойстик | 2–4 часа |
| Итого для знакомого с Rive | **1,5–2,5 дня** |
| Итого для новичка в Rive | **3–5 дней** |

Это копия демо-объёма: 8 клипов, одна поза, без стадий и одежды. Боевой
`bear_main.riv` по `docs/tz-animator-v2.md` — отдельная, в разы большая
работа; этот рецепт — её пилот и учебная сборка.
