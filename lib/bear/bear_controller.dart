import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'bear_rig_spec.dart';
import 'bear_rig_sink.dart';
import 'bear_stats.dart';

/// Контроллер мишки — единственная точка, через которую игровая логика
/// приложения общается с персонажем.
///
/// Структура взята с `teddy_controller.dart` из референса
/// (`2d-inc/Flare-Flutter/example/teddy`), пункт 6.4 ТЗ: хранение состояния,
/// реакция на внешние события (`coverEyes()`/`submitPassword()` в референсе →
/// [feedBear]/[petBear] у нас), передача значений в риг.
///
/// Отличие от референса — контроллер не хранит прямых ссылок на control-узлы
/// рига. В актуальном рантайме Rive (0.14.x) узлами не управляют из кода:
/// значения уезжают в View Model / State Machine inputs, а State Machine сама
/// решает, что двигать. Ссылки на риг спрятаны за [BearRigSink], поэтому сам
/// контроллер о Rive ничего не знает и тестируется без нативных библиотек.
///
/// ЗАГЛУШКА: набор характеристик и величины изменений — плейсхолдеры до ответа
/// по открытому вопросу 8.1 ТЗ.
class BearController extends ChangeNotifier {
  BearController({
    BearStats initialStats = const BearStats(),
    BearDecayConfig decay = const BearDecayConfig(),
  }) : _stats = initialStats,
       _decay = decay;

  BearStats _stats;
  BearDecayConfig _decay;
  BearRigSink? _rig;
  Timer? _decayTimer;

  /// Момент последнего тика. Время берётся из `package:clock`, а не из
  /// `DateTime.now()`/`Stopwatch`: так decay-таймер можно прокручивать в тестах
  /// через `fakeAsync` — он подменяет и таймеры, и `clock`.
  DateTime? _lastTickAt;

  /// Текущие характеристики мишки.
  BearStats get stats => _stats;

  /// Настройки затухания. См. [BearDecayConfig] про то, где decay должен жить.
  BearDecayConfig get decay => _decay;

  /// Подключён ли риг. Пока `.riv` не загрузился — `false`, и вызовы
  /// [feedBear]/[petBear] просто меняют состояние без анимации.
  bool get isRigAttached => _rig != null;

  /// Идёт ли автоматическое затухание.
  bool get isDecayRunning => _decayTimer != null;

  // --- Связь с ригом ------------------------------------------------------

  /// Подключает риг и сразу заливает в него текущее состояние, чтобы мишка не
  /// появлялся со значениями по умолчанию из редактора.
  ///
  /// Вызывается из [BearView] по `onLoaded`. Повторный вызов заменяет
  /// предыдущий приёмник.
  void attachRig(BearRigSink rig) {
    _rig = rig;
    rig.applyStats(_stats);
  }

  /// Отключает риг (виджет ушёл с экрана / файл перезагружается).
  ///
  /// Владение приёмником остаётся за вызывающей стороной — контроллер его
  /// не освобождает.
  void detachRig() => _rig = null;

  // --- Внешние события (аналог coverEyes/submitPassword из референса) ------

  /// Покормить. Поднимает сытость и настроение, дёргает триггер `feed`
  /// (переход в состояние `eating`).
  void feedBear({double amount = 25}) {
    _update(
      _stats.copyWith(hunger: _stats.hunger + amount, mood: _stats.mood + 5),
    );
    _rig?.fireTrigger(BearRigSpec.feedTrigger);
  }

  /// Погладить. Поднимает настроение, дёргает триггер `pet`.
  void petBear({double amount = 15}) {
    _update(_stats.copyWith(mood: _stats.mood + amount));
    _rig?.fireTrigger(BearRigSpec.petTrigger);
  }

  /// Тап по мишке — состояние `tap_reaction`.
  ///
  /// По аналогии с примером Sasquatch из раздела 5 ТЗ, где тапы растили
  /// переменную, а та управляла blend state. Величина прибавки — плейсхолдер.
  void tapBear({double amount = 3}) {
    _update(_stats.copyWith(mood: _stats.mood + amount));
    _rig?.fireTrigger(BearRigSpec.tapTrigger);
  }

  // --- Прямая установка значений (для игровой логики и дев-панели) ---------

  void setHunger(double value) => _update(_stats.copyWith(hunger: value));

  void setMood(double value) => _update(_stats.copyWith(mood: value));

  void setGrowthStage(BearGrowthStage stage) =>
      _update(_stats.copyWith(growthStage: stage));

  /// Заменяет состояние целиком — например, при загрузке сохранения.
  ///
  /// Источник состояния (локальное хранилище или backend) намеренно не задан:
  /// бэкенд-стек не подтверждён, открытый вопрос 8.3 ТЗ.
  void setStats(BearStats stats) => _update(stats);

  // --- Decay --------------------------------------------------------------

  /// Запускает автоматическое затухание с шагом [interval].
  ///
  /// Ничего не делает, если decay выключен ([BearDecayConfig.disabled]) —
  /// например, когда затухание считает Luau-скрипт внутри рига.
  void startDecay({Duration interval = const Duration(seconds: 1)}) {
    if (!_decay.isEnabled || _decayTimer != null) return;
    _lastTickAt = clock.now();
    _decayTimer = Timer.periodic(interval, (_) {
      final now = clock.now();
      final last = _lastTickAt ?? now;
      _lastTickAt = now;
      tick(now.difference(last));
    });
  }

  void stopDecay() {
    _decayTimer?.cancel();
    _decayTimer = null;
    _lastTickAt = null;
  }

  /// Применяет затухание за [elapsed]. Отделено от таймера, чтобы decay можно
  /// было прогонять в тестах без ожидания реального времени.
  ///
  /// Считает по фактически прошедшему времени, а не по числу тиков: таймер
  /// Flutter не гарантирует точный интервал, а в фоне приложение и вовсе
  /// засыпает.
  void tick(Duration elapsed) => _update(_decay.apply(_stats, elapsed));

  /// Меняет настройки затухания на лету (дев-панель, эксперименты с балансом).
  void setDecayConfig(BearDecayConfig config) {
    _decay = config;
    if (!config.isEnabled) stopDecay();
  }

  // --- Внутреннее ---------------------------------------------------------

  void _update(BearStats next) {
    if (next == _stats) return;
    _stats = next;
    _rig?.applyStats(next);
    notifyListeners();
  }

  @override
  void dispose() {
    stopDecay();
    _rig = null;
    super.dispose();
  }
}
