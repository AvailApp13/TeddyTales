import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'bear_action.dart';
import 'bear_initiative.dart';
import 'bear_rig_sink.dart';
import 'bear_rig_spec.dart';
import 'bear_state.dart';
import 'bear_stats.dart';
import 'bear_trait_tracker.dart';

/// Контроллер мишки — единственная точка, через которую игровая логика
/// приложения общается с персонажем.
///
/// Держит состояние ([BearState]) и переводит действия пользователя в команды
/// рига по контракту раздела 8.1 ТЗ аниматора. Прямых ссылок на узлы рига не
/// хранит: State Machine сама решает, что двигать, — приложение только
/// выставляет входы.
///
/// Про Rive контроллер не знает: риг спрятан за [BearRigSink], поэтому логика
/// тестируется без нативных библиотек.
class BearController extends ChangeNotifier {
  BearController({
    BearState initialState = const BearState(),
    BearDecayConfig decay = const BearDecayConfig(),
    BearTraitTracker? traitTracker,
    this.initiativePolicy = const BearInitiativePolicy(),
    this.autoTrait = true,
    Random? random,
  }) : _state = initialState,
       _decay = decay,
       traitTracker = traitTracker ?? BearTraitTracker(),
       _random = random ?? Random();

  /// Накопитель действий, из которых формируется характер (КП 7.3).
  final BearTraitTracker traitTracker;

  /// Правило пузыря инициативы (КП 3.4).
  final BearInitiativePolicy initiativePolicy;

  /// Применять ли характер, посчитанный из действий, автоматически.
  ///
  /// Выключить, если характер приходит с сервера и клиент только показывает
  /// результат.
  final bool autoTrait;

  BearState _state;
  BearDecayConfig _decay;
  BearRigSink? _rig;
  Timer? _decayTimer;

  /// Момент последнего тика. Время берётся из `package:clock`, а не из
  /// `DateTime.now()`/`Stopwatch`: так decay-таймер прокручивается в тестах
  /// через `fakeAsync`.
  ///
  /// Отдельно: по КП 1.5 игровое время серверное — перевод часов на телефоне
  /// не должен ускорять игру. Локальный таймер годится только для сессии;
  /// отыгрыш «сколько прошло, пока приложение было закрыто» обязан считаться
  /// на сервере.
  DateTime? _lastTickAt;

  final Random _random;

  BearState get state => _state;
  BearCareStats get stats => _state.stats;
  BearDecayConfig get decay => _decay;

  bool get isRigAttached => _rig != null;
  bool get isDecayRunning => _decayTimer != null;

  /// Что питомец хочет предложить прямо сейчас, или `null`, если поводов нет
  /// (КП 3.4). Как часто показывать пузырь — [initiativeCooldown].
  BearInitiative? get initiative => initiativePolicy.propose(_state);

  /// Пауза между пузырями инициативы — зависит от характера (КП 7.4).
  Duration get initiativeCooldown =>
      initiativePolicy.cooldownFor(_state.trait);

  // --- Связь с ригом ------------------------------------------------------

  /// Подключает риг и сразу заливает в него текущее состояние, чтобы мишка не
  /// появился со значениями по умолчанию из редактора.
  void attachRig(BearRigSink rig) {
    _rig = rig;
    rig.applyState(_state);
  }

  /// Отключает риг. Владение приёмником остаётся за вызывающей стороной.
  void detachRig() => _rig = null;

  // --- Действия ухода (КП 6.4) --------------------------------------------

  /// Покормить. Раздел 7.2: `act_eat`, два варианта (7.6).
  void feedBear({double amount = 35}) {
    _update(_state.copyWith(stats: stats.copyWith(food: stats.food + amount)));
    _fire(BearRigSpec.trgEat, varied: true);
    recordAction(BearAction.feed);
  }

  /// Умыть. `act_wash`, стадии 2–5.
  void washBear({double amount = 40}) {
    _update(
      _state.copyWith(stats: stats.copyWith(hygiene: stats.hygiene + amount)),
    );
    _fire(BearRigSpec.trgWash);
    recordAction(BearAction.wash);
  }

  /// Уложить спать. `act_sleep` — укладывается и засыпает (фаза сна зациклена).
  void putToSleep({double amount = 50}) {
    _update(
      _state.copyWith(
        stats: stats.copyWith(sleep: stats.sleep + amount),
        isWalking: false,
      ),
    );
    _fire(BearRigSpec.trgSleep);
    recordAction(BearAction.sleep);
  }

  /// Разбудить. `act_wake`.
  void wakeBear() {
    _fire(BearRigSpec.trgWake);
    recordAction(BearAction.wake);
  }

  /// Поиграть. `act_play`, стадии 2–5.
  void playWithBear({double amount = 30}) {
    _update(_state.copyWith(stats: stats.copyWith(play: stats.play + amount)));
    _fire(BearRigSpec.trgPlay);
    recordAction(BearAction.play);
  }

  /// Погладить — касание экрана. `act_pet`, два варианта (7.6).
  void petBear({double amount = 20}) {
    _update(_state.copyWith(stats: stats.copyWith(love: stats.love + amount)));
    _fire(BearRigSpec.trgPet, varied: true);
    recordAction(BearAction.pet);
  }

  // --- Эмоциональные акценты (раздел 7.7) ---------------------------------

  /// Радость — например, после верного ответа в обучении (КП 9.3).
  void showHappy() => _fire(BearRigSpec.trgEmoHappy);

  void showSad() => _fire(BearRigSpec.trgEmoSad);

  void showSurprise() => _fire(BearRigSpec.trgEmoSurprise);

  void showLove() => _fire(BearRigSpec.trgEmoLove);

  // --- Стадии роста -------------------------------------------------------

  /// Переводит мишку на следующую стадию.
  ///
  /// По разделу 8.2 ТЗ аниматора смена стадии идёт только через
  /// `trg_stage_up`, никогда мгновенно: сначала триггер, и лишь потом новое
  /// значение `stage`, иначе State Machine перескочит переход взросления.
  ///
  /// Когда именно взрослеть — решает сервер (КП 5.6, 5.7: скорость роста
  /// зависит от общего ухода и настраивается с панели). Контроллер только
  /// исполняет.
  ///
  /// Возвращает `false`, если мишка уже взрослый.
  bool growUp() {
    final next = _state.stage.next;
    if (next == null) return false;

    _fire(BearRigSpec.trgStageUp);
    _update(_state.copyWith(stage: next));
    return true;
  }

  // --- Прямая установка (загрузка сохранения, дев-панель, гардероб) --------

  void setStats(BearCareStats stats) => _update(_state.copyWith(stats: stats));

  void setStage(BearStage stage) => _update(_state.copyWith(stage: stage));

  void setTrait(BearTrait trait) => _update(_state.copyWith(trait: trait));

  void setSkin(BearSkin skin) => _update(_state.copyWith(skin: skin));

  /// Смена образа из гардероба (КП 10.6) — слоты независимы.
  void setOutfit(BearOutfit outfit) => _update(_state.copyWith(outfit: outfit));

  /// Включает или выключает цикл ходьбы. Для новорождённого игнорируется.
  void setWalking(bool value) => _update(_state.copyWith(isWalking: value));

  /// Заменяет состояние целиком — например, при загрузке прогресса с сервера
  /// (КП 1.4).
  void restoreState(BearState state) => _update(state);

  // --- Формирование характера (КП 7.3) ------------------------------------

  /// Записывает действие в историю, из которой считается характер.
  ///
  /// Действия ухода контроллер записывает сам. Снаружи метод нужен модулям,
  /// которые тоже влияют на характер, но живут отдельно: обучение (КП 9),
  /// гардероб (10.6), редактор комнаты (10.7).
  ///
  /// При [autoTrait] характер применяется сразу, как только накопится
  /// достаточно данных.
  void recordAction(BearAction action, {DateTime? at}) {
    traitTracker.record(action, at: at);
    if (!autoTrait) return;

    final resolved = traitTracker.resolve();
    if (resolved != null) _update(_state.copyWith(trait: resolved));
  }

  // --- Затухание показателей ----------------------------------------------

  /// Запускает локальное затухание с шагом [interval].
  ///
  /// Ничего не делает при [BearDecayConfig.disabled].
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
  void tick(Duration elapsed) =>
      _update(_state.copyWith(stats: _decay.apply(stats, elapsed)));

  void setDecayConfig(BearDecayConfig config) {
    _decay = config;
    if (!config.isEnabled) stopDecay();
  }

  // --- Внутреннее ---------------------------------------------------------

  /// Дёргает триггер. При [varied] заранее выбирает случайный вариант
  /// анимации — раздел 7.6: повторное действие не должно выглядеть одинаково.
  void _fire(String trigger, {bool varied = false}) {
    _rig?.fireTrigger(trigger, variant: varied ? _random.nextInt(2) : null);
  }

  void _update(BearState next) {
    if (next == _state) return;
    _state = next;
    _rig?.applyState(next);
    notifyListeners();
  }

  @override
  void dispose() {
    stopDecay();
    _rig = null;
    super.dispose();
  }
}
