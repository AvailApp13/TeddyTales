# TeddyTales — анимированный персонаж-медведь

Flutter-модуль анимированного мишки на Rive. Реализация первой итерации из
раздела 9 ТЗ (`TeddyTales Rive Animation TZ.pdf`, текстовая версия —
`docs/tz-rive-animation.md`).

Границы, заданные разделом 0 ТЗ, соблюдены: только риг, State Machine, data
binding и интеграция во Flutter. Магазина, мини-игр, обучения, e-commerce и
выбора backend здесь нет.

## Что уже есть

| Пункт ТЗ | Где |
| --- | --- |
| 9.1 Структура Flutter-проекта под виджет мишки | `pubspec.yaml`, `lib/`, `assets/rive/` |
| 9.2 Контроллер по образцу `teddy_controller.dart` | `lib/bear/bear_controller.dart` |
| 9.3 Пакет `rive` (не legacy) + загрузка `.riv` | `pubspec.yaml`, `lib/bear/bear_view.dart` |
| 9.4 Точка интеграции `stateMachineInputs` | `lib/bear/bear_rig_sink.dart`, `lib/bear/bear_rig_binding.dart` |
| 3. Конвенция именования | `lib/bear/bear_rig_spec.dart`, `docs/rig-naming.md` |

Чего нет: самого `assets/rive/bear.riv` — он появится после сборки рига в
редакторе (пункт 9.3). До этого `BearView` рисует плейсхолдер, приложение
собирается и запускается.

## Структура

```
lib/
  main.dart                     дев-харнесс: слайдеры hunger/mood + кнопки
  bear/
    bear.dart                   barrel-экспорт модуля
    bear_rig_spec.dart          имена из Rive Editor — единственное место
    bear_stats.dart             характеристики + decay (чистый Dart)
    bear_controller.dart        API для игровой логики (чистый Dart)
    bear_rig_sink.dart          интерфейс «передать в риг»
    bear_rig_binding.dart       единственный файл, знающий про API Rive
    bear_view.dart              виджет: загрузка .riv, подключение рига
docs/
  tz-rive-animation.md          текстовая версия ТЗ
  rig-naming.md                 чеклист именования слоёв для художника
  runtime-api-note.md           расхождение сниппета 6.2 ТЗ с актуальным API
test/                           тесты игровой логики (без нативного рантайма)
```

### Почему так разложено

`BearController` и `BearStats` не импортируют `package:rive`. Это даёт две
вещи: логику можно гонять в тестах без нативных библиотек `rive_native`, и
замена рантайма (например, откат на legacy-API) не задевает игровую логику —
переписывается только `bear_rig_binding.dart` + `bear_view.dart`.

Весь контакт с ригом идёт через интерфейс `BearRigSink` — это и есть «точка
интеграции» из пункта 9.4.

## Запуск

Платформенные папки в репозитории не хранятся — сгенерировать под себя:

```bash
flutter create .          # создаст android/ ios/ и т.д. под установленный SDK
flutter pub get
flutter run
```

Требования: Flutter >= 3.32, Dart SDK >= 3.8 (этого требует `rive` 0.14.x).

Нативные библиотеки `rive_native` скачиваются автоматически при сборке. Если
сборка падает:

```bash
flutter clean && flutter pub get
dart run rive_native:setup --verbose --clean --platform <macos|ios|android|...>
```

Про Impeller (раздел 6.5 ТЗ): мы рендерим через `Factory.rive`, поэтому
расхождений с редактором быть не должно. Если переключитесь на
`Factory.flutter` и увидите артефакты на iOS — сравните со Skia:

```bash
flutter run --no-enable-impeller
```

## Тесты

```bash
flutter test
```

Покрыты `BearStats`, `BearDecayConfig` и `BearController`. Тесты рига нет —
без реального `.riv` тестировать нечего.

## Как подключить готовый риг

1. Экспортировать `.riv` из редактора, положить в `assets/rive/bear.riv`.
2. Сверить имена артборда, State Machine и свойств View Model с
   `lib/bear/bear_rig_spec.dart`. Расходятся — править спецификацию, не код.
3. `flutter run`. Плейсхолдер сменится мишкой.

Если свойства в риге не найдётся ни как View Model property, ни как state
machine input — приложение не упадёт, а напишет в дев-лог, какое имя не нашлось.

## Использование из приложения

```dart
final bear = BearController();

// на экране
BearView(controller: bear);

// из игровой логики
bear.feedBear();
bear.petBear();
bear.setMood(80);
bear.setGrowthStage(BearGrowthStage.young);
```

## Открытые вопросы, которые упираются в код

Помечены в коде как ЗАГЛУШКА / ДОПУЩЕНИЕ. По разделу 8 ТЗ:

- **8.1** — набор характеристик и decay-таймеры. Сейчас `hunger`, `mood`,
  `growthStage` из шаблона раздела 5; скорости затухания взяты «чтобы было
  видно», не как баланс.
- **8.2** — механика пренебрежения/болезни не реализована.
- **8.3** — backend не выбран, состояние живёт только в памяти;
  `BearController.setStats` — готовая точка загрузки сохранения.
- **8.4** — `BearGrowthStage` содержит три стадии-заглушки.
- **8.5** — физика ушей/шарфа не трогалась (это работа в редакторе).

Отдельно: **где считать decay**. Раздел 5 ТЗ описывает его как Luau-скрипт
внутри Rive. Если оставим там — передавайте `BearDecayConfig.disabled()` в
`BearController`, чтобы затухание не считалось дважды.
