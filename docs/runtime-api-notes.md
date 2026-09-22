# Расхождения PDF-ТЗ и актуального рантайма Rive

Проверено по исходникам `rive: 0.14.11` / `rive_native: 0.1.11` и
`@rive-app/webgl2: 2.42.2`, а не по памяти. Важно, потому что PDF-ТЗ (раздел 6)
описывает API, которого в текущем пакете уже нет.

## 1. `RiveAnimation.asset` больше не существует

PDF 6.2 предлагает:

```dart
RiveAnimation.asset('assets/bear.riv', stateMachines: 'State Machine 1')
```

Это API legacy-рантайма (последний релиз `rive: 0.13.20`, репозиторий
`rive-flutter-legacy`). В `rive: 0.14.x` весь рантайм переписан поверх
`rive_native`. Актуально:

```dart
final file = await File.asset(BearRig.asset, riveFactory: Factory.rive);
final controller = RiveWidgetController(
  file,
  artboardSelector: ArtboardNamed(BearRig.artboardBoy),
  stateMachineSelector: StateMachineNamed(BearRig.stateMachine),
);
RiveWidget(controller: controller, fit: Fit.contain);
```

PDF 6.1 при этом прав: нужен именно `rive`, а не `rive-flutter-legacy`.

## 2. State Machine Inputs объявлены устаревшими

PDF 6.3 предлагает управлять мишкой через `stateMachineInputs`. В текущем
рантайме это помечено `@deprecated` в обоих runtime'ах, а в примере самого Rive
написано прямым текстом: *"We strongly recommend using Data Binding instead of
Rive Inputs for better runtime control."*

Поэтому управление построено на Data Binding — тем более что PDF 4.3 сам
относит View Models и data binding к тому, что MCP умеет надёжно:

```dart
final vm = controller.dataBind(DataBind.auto());
vm.number('food')!.value = 82;
vm.trigger('pet')!.trigger();
vm.enumerator('stage')!.value = 'crawler';
```

Лаборатория показывает legacy-инпуты отдельной секцией — только чтобы
обнаружить их в чужом файле, не для работы.

## 3. Обращение к вложенным View Model — через путь со слэшем

PDF 4.3 упоминает «relative data binding через вложенные view model'и».
На практике адресация плоская, через путь:

```dart
vm.number('Energy_Bar/Lives')!.value = 3;
```

Лаборатория рекурсивно обходит вложенные View Model и показывает ровно такие
пути, так что имя, работающее в лаборатории, работает и в Dart.

## 4. `enableFPSCounter` до загрузки файла падает

В web-рантайме метод дёргает `this.runtime`, которого до загрузки ещё нет.
Вызывать только внутри `onLoad` — в лаборатории так и сделано.

## 5. Impeller

PDF 6.5 актуален: с Flutter 3.10 на iOS Impeller заменил Skia, возможны
визуальные расхождения с редактором. При подозрении — сравнить со Skia
(`flutter run --no-enable-impeller`) прежде чем заводить баг.

Отдельно: `Factory` объявлен и во Flutter (`foundation`), и в Rive. При импорте
обоих нужен точечный `show`/`hide`, иначе `ambiguous_import`.
