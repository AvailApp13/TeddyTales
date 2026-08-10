# Расхождение между сниппетом в ТЗ и актуальным API rive-flutter

Короткое, но важное для реализации место. Читать перед правкой `lib/bear/`.

## Что в ТЗ

Раздел 6.1 требует использовать официальный `rive-app/rive-flutter`,
**НЕ** `rive-flutter-legacy`. Это и сделано.

Раздел 6.2 приводит сниппет:

```dart
RiveAnimation.asset(
  'assets/bear.riv',
  stateMachines: 'State Machine 1',
)
```

## В чём проблема

`RiveAnimation` — виджет **legacy**-рантайма. Rive разделил пакеты:

| Что | Репозиторий | Последняя версия на pub.dev |
| --- | --- | --- |
| Legacy-рантайм (`RiveAnimation`, `SMIInput`, `StateMachineController`) | `rive-app/rive-flutter-legacy` | `rive: 0.13.20` |
| Актуальный рантайм (`RiveWidget`, `RiveWidgetController`, data binding) | `rive-app/rive-flutter` | `rive: 0.14.11` |

То есть два требования ТЗ противоречат друг другу: сниппет 6.2 работает только
на том пакете, который 6.1 запрещает.

## Как разрешено

Приоритет отдан явному требованию 6.1 (не-legacy пакет) — это архитектурное
решение, а сниппет 6.2 выглядит как копипаста из старой документации. Сниппет
заменён на его актуальный эквивалент:

```dart
// было (legacy, rive <= 0.13.x)
RiveAnimation.asset('assets/bear.riv', stateMachines: 'State Machine 1')

// стало (rive 0.14.x) — lib/bear/bear_view.dart
RiveWidgetBuilder(
  fileLoader: FileLoader.fromAsset(BearRigSpec.assetPath, riveFactory: Factory.rive),
  controller: (file) => RiveWidgetController(
    file,
    stateMachineSelector: StateMachineNamed(BearRigSpec.stateMachine),
  ),
  onLoaded: (state) => controller.attachRig(BearRigBinding.attach(state.controller)),
  builder: (context, state) => switch (state) { ... },
)
```

Data binding подключается не параметром `dataBind:` у `RiveWidgetBuilder`, а
внутри `BearRigBinding.attach`. Причина: `DataBind.auto()` бросает
`RiveDataBindException`, если в артборде нет экспортированного view model
instance, и весь виджет уходит в `RiveFailed`. Для рига, собранного на state
machine inputs, это ложное падение — внутри биндинга отсутствие view model
просто переключает каналы на инпуты.

Имя State Machine из ТЗ (`State Machine 1`) сохранено — см.
`BearRigSpec.stateMachine`.

**Если решение неверное и нужен именно legacy-API** — откатывается точечно:
меняется зависимость в `pubspec.yaml` на `rive: ^0.13.20` и переписывается один
файл `lib/bear/bear_rig_binding.dart` + `lib/bear/bear_view.dart`.
`BearController` и `BearStats` не зависят от Rive и остаются как есть.

## Что ещё поменялось в 0.14.x

1. **Нужна инициализация.** `await RiveNative.init()` до `runApp` — см.
   `lib/main.dart`.
2. **Нативные библиотеки.** Пакет `rive` тянет `rive_native`; бинарники
   скачиваются автоматически на `flutter run` / `flutter build`. Если сборка
   падает — `flutter clean && flutter pub get`, затем при необходимости
   `dart run rive_native:setup --verbose --clean --platform <platform>`.
3. **Выбор рендерера.** `Factory.rive` (собственный рендерер Rive) или
   `Factory.flutter` (Skia/Impeller). Мы используем `Factory.rive` — это, помимо
   прочего, снимает часть рисков из раздела 6.5 ТЗ (расхождения Impeller vs
   Editor), потому что растеризация больше не идёт через Impeller.
   Переключается одной константой `BearView.riveFactory`.
4. **State Machine inputs объявлены deprecated** в пользу data binding
   (View Model). Поэтому `BearRigBinding` работает в двух режимах: сначала
   пробует View Model, при отсутствии свойства падает обратно на
   `stateMachineInputs` (требование 6.3 ТЗ). Оба пути живут за одним API.

## Проверить при появлении реального .riv

Ничего из этого не проверено на живом файле — `bear.riv` ещё не собран.
Первый прогон с настоящим ригом должен подтвердить:

- имя артборда / State Machine / свойств View Model совпадает с `BearRigSpec`;
- `DataBind.auto()` действительно цепляет нужный view model instance;
- значения `hunger`/`mood` доезжают до blend state.
