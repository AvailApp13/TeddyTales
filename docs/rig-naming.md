# Конвенция именования рига — чеклист

Источник: раздел 3 ТЗ (`docs/tz-rive-animation.md`). Этот файл — рабочий чеклист
для художника и для сборки рига в Rive Editor.

## Общее

- Naming convention в файле Rive: `Workspace → Admin → Options → Naming convention → snake_case`.
- Художник поставляет **раздельные слои**, не готовую анимацию.
- Каждая перечисленная часть — отдельный слой с именем из списка (или максимально
  близким аналогом).

## Слои от художника

### Тело

- [ ] `body`, `body_base`
- [ ] `head`, `head_shadow`
- [ ] `forearm`, `forearm_light` (левая/правая)
- [ ] `hand`, `hand_light` (левая/правая)
- [ ] `finger_1_nail`, `finger_2_nail`, `finger_3_nail`

### Уши

- [ ] `ear_left` / `ear_right`
- [ ] `ear_in_left` / `ear_in_right` — внутренняя часть, отдельный слой
- [ ] `ear_light_left` / `ear_light_right` — блик, отдельный слой

### Лицо

- [ ] `eye_left` / `eye_right`
- [ ] `pupil_left` / `pupil_right`
- [ ] `pupil_light_left` / `pupil_light_right`
- [ ] `eyebrow_left` / `eyebrow_right`
- [ ] `eyelid_top_left` / `eyelid_top_right`
- [ ] `eyelid_bottom_left` / `eyelid_bottom_right`
- [ ] `nose`, `mouth`, `teeth`, `tongue`, `lips`

### Аксессуары

- [ ] `scarf_1` / `scarf_2` / `scarf_3` — посегментно, под физику покачивания
      (нужна ли физика на MVP — открытый вопрос 8.5)

## Иерархия костей (собирается в редакторе вручную)

```
root
└── root_body
    ├── body
    ├── body_base
    ├── head
    └── head_shadow
root_arm_left  → forearm → forearm_light → hand → hand_light → finger_*_nail
root_arm_right → forearm → forearm_light → hand → hand_light → finger_*_nail
```

Bone rigging делается руками: MCP не подтверждён как надёжно расставляющий кости
(раздел 4.4 ТЗ). MCP подключается уже поверх готового рига — для View Model,
State Machine и поведенческой логики.

## Control-узлы

Невидимые «рычаги» для управления группами частей:

- [ ] `ctrl_face` — общий контроль лица
- [ ] `ctrl_eyes` — направление взгляда (двигает оба глаза разом)
- [ ] `ctrl_pupils` — контроль зрачков
- [ ] `ctrl_mouth` — управление ртом
- [ ] `ctrl_nose` — управление носом
- [ ] `ctrl_eyebrow_left` / `ctrl_eyebrow_right`

Имена control-узлов продублированы в коде: `BearRigSpec.controlNodes`
(`lib/bear/bear_rig_spec.dart`). В актуальном рантайме код не дёргает узлы
напрямую — влияние идёт через State Machine и View Model, — но список нужен для
сверки рига и как документация контракта.

## Связь с кодом

Всё, что код ожидает от `.riv`, собрано в одном файле —
`lib/bear/bear_rig_spec.dart`:

| В редакторе Rive | Константа |
| --- | --- |
| Имя файла экспорта | `BearRigSpec.assetPath` → `assets/rive/bear.riv` |
| Артборд | `BearRigSpec.artboard` |
| State Machine | `BearRigSpec.stateMachine` |
| View Model свойства | `BearRigSpec.hunger` / `mood` / `growthStage` |
| Триггеры | `BearRigSpec.feedTrigger` / `petTrigger` / `tapTrigger` |
| Состояния SM | `BearRigSpec.states` |

Если в редакторе имена другие — правится только этот файл.
