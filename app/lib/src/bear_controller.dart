import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rive/rive.dart';

import 'bear_rig_contract.dart';
import 'bear_vitals.dart';

/// Единственная точка, через которую игровая логика управляет мишкой.
///
/// По образцу `teddy_controller.dart` из референса 2d-inc/Flare-Flutter
/// (PDF 6.4), но на текущем рантайме: `RiveAnimation.asset` и
/// `stateMachineInputs` из PDF 6.2-6.3 относятся к legacy-рантайму, в
/// `rive: ^0.14` их нет. Управление идёт через Data Binding — см.
/// docs/runtime-api-notes.md.
///
/// Владение ресурсами: контроллер владеет [RiveWidgetController] и
/// привязанными свойствами, но НЕ владеет [File] — файл переживает виджет и
/// кэшируется на уровне приложения.
class BearController extends ChangeNotifier {
  BearController({
    required File file,
    BearVitals? vitals,
    String artboard = BearRig.artboardDefault,
    BearStage stage = BearStage.initial,
    BearTrait trait = BearTrait.initial,
  })  : _vitals = vitals ?? BearVitals.initial(),
        _stage = stage,
        _trait = trait {
    _controller = RiveWidgetController(
      file,
      artboardSelector: ArtboardNamed(artboard),
      stateMachineSelector: const StateMachineNamed(BearRig.stateMachine),
    );
    _viewModel = _controller.dataBind(DataBind.auto());
    _bindProperties();
    _pushAll();
  }

  late final RiveWidgetController _controller;
  late final ViewModelInstance _viewModel;

  final Map<BearNumber, ViewModelInstanceNumber> _numbers = {};
  final Map<BearTrigger, ViewModelInstanceTrigger> _triggers = {};
  final Map<String, ViewModelInstanceEnum> _enums = {};

  /// Контроллер для [RiveWidget].
  RiveWidgetController get riveController => _controller;

  BearVitals _vitals;
  BearVitals get vitals => _vitals;

  BearStage _stage;
  BearStage get stage => _stage;

  BearTrait _trait;
  BearTrait get trait => _trait;

  Timer? _decayTimer;
  DateTime? _lastTick;
  bool _disposed = false;

  /// Разбирает недостающие имена один раз при старте.
  ///
  /// Пропущенное свойство не роняет приложение — мишка просто не отработает эту
  /// часть анимации, что лучше падения на главном экране. В отладке это
  /// сообщение; лаборатория (`tools` → `npm run lab`) ловит такие расхождения
  /// до сборки.
  void _bindProperties() {
    for (final number in BearNumber.values) {
      final handle = _viewModel.number(number.path);
      if (handle == null) {
        _warnMissing('number', number.path);
        continue;
      }
      _numbers[number] = handle;
    }
    for (final trigger in BearTrigger.values) {
      final handle = _viewModel.trigger(trigger.path);
      if (handle == null) {
        _warnMissing('trigger', trigger.path);
        continue;
      }
      _triggers[trigger] = handle;
    }
    for (final property in [BearStage.property, BearTrait.property, BearMood.property]) {
      final handle = _viewModel.enumerator(property);
      if (handle == null) {
        _warnMissing('enum', property);
        continue;
      }
      _enums[property] = handle;
    }
  }

  void _warnMissing(String kind, String path) {
    assert(() {
      debugPrint(
        'BearController: в .riv нет $kind "$path". '
        'Сверьте файл со спецификацией: cd tools && npm run lab',
      );
      return true;
    }());
  }

  // ---------------------------------------------------------------- действия

  /// Кормление (КП 4.3, 6.4).
  void feedBear() => _act(BearTrigger.feed);

  /// Умывание (КП 4.3).
  void washBear() => _act(BearTrigger.wash);

  /// Укладывание спать (КП 4.3).
  void putToSleep() => _act(BearTrigger.sleepAction);

  /// Пробуждение (КП 4.3).
  void wakeBear() => _act(BearTrigger.wake);

  /// Игра (КП 4.3).
  void playWithBear() => _act(BearTrigger.playAction);

  /// Поглаживание (КП 4.3).
  void petBear() => _act(BearTrigger.pet);

  /// Касание питомца на главном экране (КП 3.1).
  void tapBear() => _act(BearTrigger.tap);

  /// Эмоциональный акцент, не меняющий показатели (КП 4.8).
  void emote(BearTrigger emotion) {
    assert(
      emotion.path.startsWith('emote_'),
      'emote() ждёт эмоциональный триггер, получен ${emotion.path}',
    );
    _act(emotion);
  }

  /// Пузырь инициативы — питомец сам предлагает активность (КП 3.4).
  void offerInitiative() => _fire(BearTrigger.initiative);

  void _act(BearTrigger trigger) {
    _fire(trigger);
    _setVitals(_vitals.boosted(trigger));
  }

  void _fire(BearTrigger trigger) {
    if (_disposed) return;
    _triggers[trigger]?.trigger();
  }

  // ------------------------------------------------------------------ состояние

  /// Задаёт показатели целиком — так их приносит сервер (КП 1.4).
  void setVitals(BearVitals vitals) => _setVitals(vitals);

  void _setVitals(BearVitals next) {
    if (_disposed || next == _vitals) return;
    _vitals = next;
    _pushVitals();
    notifyListeners();
  }

  /// Переводит мишку на следующую стадию с анимацией взросления (КП 4.5, 5.6).
  void growTo(BearStage stage) {
    if (_disposed || stage == _stage) return;
    _stage = stage;
    _enums[BearStage.property]?.value = stage.wireName;
    _fire(BearTrigger.grow);
    notifyListeners();
  }

  /// Характер складывается из действий за период, а не из одного (КП 7.3),
  /// поэтому значение приходит из игровой логики уже посчитанным.
  void setTrait(BearTrait trait) {
    if (_disposed || trait == _trait) return;
    _trait = trait;
    _enums[BearTrait.property]?.value = trait.wireName;
    notifyListeners();
  }

  /// Надевает предмет в слот (КП 4.9). `0` — слот пуст.
  void setOutfit(BearNumber slot, int itemId) {
    assert(
      slot.path.startsWith('outfit_'),
      'setOutfit() ждёт слот одежды, получен ${slot.path}',
    );
    _numbers[slot]?.value = slot.clamp(itemId.toDouble());
  }

  void _pushAll() {
    _enums[BearStage.property]?.value = _stage.wireName;
    _enums[BearTrait.property]?.value = _trait.wireName;
    _pushVitals();
  }

  void _pushVitals() {
    for (final entry in _numbers.entries) {
      if (entry.key == BearNumber.careIndex) continue;
      entry.value.value = _vitals[entry.key];
    }
    _numbers[BearNumber.careIndex]?.value = _vitals.careIndex;
    _enums[BearMood.property]?.value = _vitals.mood.wireName;
  }

  // -------------------------------------------------------------- затухание

  /// Запускает затухание показателей на переднем плане.
  ///
  /// Шаг считается от реального времени, поэтому длинный кадр не ускоряет и не
  /// замедляет игру. Авторитетное время всё равно серверное (КП 1.5) — этот
  /// таймер только сглаживает шкалы между синхронизациями и не должен
  /// становиться источником истины.
  void startDecay({Duration interval = const Duration(seconds: 1)}) {
    stopDecay();
    _lastTick = DateTime.now();
    _decayTimer = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastTick ?? now);
      _lastTick = now;
      _setVitals(_vitals.decayed(elapsed));
    });
  }

  void stopDecay() {
    _decayTimer?.cancel();
    _decayTimer = null;
    _lastTick = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopDecay();
    for (final handle in _numbers.values) {
      handle.dispose();
    }
    for (final handle in _triggers.values) {
      handle.dispose();
    }
    for (final handle in _enums.values) {
      handle.dispose();
    }
    _numbers.clear();
    _triggers.clear();
    _enums.clear();
    _viewModel.dispose();
    _controller.dispose();
    super.dispose();
  }
}
