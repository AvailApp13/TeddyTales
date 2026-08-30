# Rive-рантайм: расхождения документов и как они разрешены

Читать перед правкой `lib/bear/bear_rig_binding.dart` и `bear_view.dart`.

## Расхождение 1 — legacy vs актуальный пакет

Черновой PDF (раздел 6.1) требует официальный `rive-app/rive-flutter`,
**НЕ** `rive-flutter-legacy` — это и сделано. Но в разделе 6.2 он же приводит
сниппет `RiveAnimation.asset(...)`, а это виджет **legacy**-рантайма:

| Что | Репозиторий | Последняя версия |
| --- | --- | --- |
| Legacy (`RiveAnimation`, `SMIInput`, `StateMachineController`) | `rive-flutter-legacy` | `rive: 0.13.20` |
| Актуальный (`RiveWidget`, `RiveWidgetController`) | `rive-flutter` | `rive: 0.14.11` |

Приоритет отдан явному требованию 6.1: сниппет 6.2 выглядит копипастой из
старой документации. Используется актуальный API:

```dart
// было (legacy, rive <= 0.13.x)
RiveAnimation.asset('assets/bear.riv', stateMachines: 'State Machine 1')

// стало (rive 0.14.x) — lib/bear/bear_view.dart
RiveWidgetBuilder(
  fileLoader: FileLoader.fromAsset(BearRigSpec.assetPath, riveFactory: Factory.rive),
  controller: (file) => RiveWidgetController(
    file,
    artboardSelector: const ArtboardNamed(BearRigSpec.artboard),
    stateMachineSelector: const StateMachineNamed(BearRigSpec.stateMachine),
  ),
  onLoaded: (state) => controller.attachRig(BearRigBinding.attach(state.controller)),
  builder: (context, state) => switch (state) { ... },
)
```

Откат, если решение неверное: `rive: ^0.13.20` в `pubspec.yaml` + переписать
`bear_rig_binding.dart` и `bear_view.dart`. Игровая логика (`BearController`,
`BearState`, `BearCareStats`) от Rive не зависит и остаётся как есть.

## Расхождение 2 — Data Binding vs State Machine Inputs

Черновой PDF (раздел 5) описывал управление через View Model properties.
**ТЗ для аниматора (раздел 8) говорит обратное и однозначно:**

> Все анимации собираются в State Machine с именем `bear_main`. Приложение
> управляет персонажем только через перечисленные ниже входы. Никаких других
> способов запуска анимаций быть не должно.

Дальше идёт таблица 8.1 с типами `Number` / `Boolean` / `Trigger` — это именно
State Machine Inputs, не View Model. Поэтому `BearRigBinding` работает через
inputs, а data binding не используется вовсе.

Нюанс: в `rive` 0.14.x inputs помечены `@Deprecated` в пользу data binding.
Мы сознательно идём против рекомендации рантайма — контракт с аниматором
важнее, и inputs полностью работоспособны. Отсюда `// ignore:
deprecated_member_use` в `bear_rig_binding.dart`.

Если риг однажды переедет на View Model, меняется только этот файл: интерфейс
`BearRigSink` останется прежним.

## Расхождение 3 — имена

| | Черновой PDF | ТЗ аниматора | В коде |
| --- | --- | --- | --- |
| State Machine | `State Machine 1` | `bear_main` | `bear_main` |
| Файл | `bear.riv` | `bear_main.riv` | `bear_main.riv` |
| Части тела | `eyebrow_*`, `eyelid_top_*`, `forearm`, `hand` | `brow_*`, `eyelid_*`, `arm_*_upper/lower`, `paw_*` | не используются |
| Control-узлы | `ctrl_face`, `ctrl_eyes`, … | не упоминаются | не используются |

Control-узлы из черновика убраны: приложение не трогает узлы напрямую, а в
контракте аниматора их нет.

## Что ещё важно знать про 0.14.x

1. **Инициализация.** `await RiveNative.init()` до `runApp` — см. `lib/main.dart`.
2. **Нативные библиотеки.** Пакет `rive` тянет `rive_native`; бинарники
   скачиваются на `flutter run` / `flutter build`. Если сборка падает —
   `flutter clean && flutter pub get`, затем при необходимости
   `dart run rive_native:setup --verbose --clean --platform <platform>`.
3. **Рендерер.** `Factory.rive` (собственный рендерер) или `Factory.flutter`
   (Skia/Impeller). Используем `Factory.rive` — это снимает риск расхождений
   Impeller vs Editor (раздел 6.5 чернового PDF), потому что растеризация не
   идёт через Impeller. Переключается константой `BearView.riveFactory`.
4. **Откат по артборду и машине.** Если `bear_main` в файле не найден,
   `BearView` берёт артборд и State Machine по умолчанию и пишет
   предупреждение. Это нужно на время поэтапной сдачи рига (6 этапов, раздел 11
   ТЗ), чтобы промежуточные файлы всё равно показывались.

## Что проверить на первом реальном `.riv`

Ничего из этого не проверено на живом файле — `bear_main.riv` ещё не собран.
Первый прогон должен подтвердить:

- артборд и State Machine называются `bear_main`;
- в машине есть все входы, которых ждёт код: 21 из раздела 8.1 плюс `top_id` и
  `bottom_id` из `docs/rig-change-request.md`, итого 23 (дев-лог сообщит о
  недостающих, а `tool/riv_lint.py` — перечислит их поимённо);
- `variant` действительно читается в момент срабатывания триггера, а не позже —
  от этого зависит, будет ли работать вариативность из раздела 7.6;
- `mood` переключает idle без рывков (blend не менее 0,15 с).
