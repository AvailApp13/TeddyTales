// Единственный файл проекта, знающий про API рантайма Rive. Всё остальное
// общается с ригом через `BearRigSink`.
//
// Управление идёт через State Machine Inputs — так требует раздел 8.1 ТЗ
// аниматора: «Приложение управляет персонажем только через перечисленные ниже
// входы. Никаких других способов запуска анимаций быть не должно».
//
// В rive 0.14.x inputs помечены deprecated в пользу data binding, поэтому
// `ignore: deprecated_member_use` здесь осознанный: контракт с аниматором
// важнее рекомендации рантайма. Если риг однажды переедет на View Model,
// переписывается только этот файл. Подробности — в docs/runtime-api-note.md.
import 'package:flutter/foundation.dart';
import 'package:rive/rive.dart';

import 'bear_rig_sink.dart';
import 'bear_rig_spec.dart';
import 'bear_state.dart';

/// Мост между [BearRigSink] и загруженным ригом.
///
/// Отсутствующий в файле вход не роняет приложение: канал один раз пишет
/// предупреждение в дев-лог и дальше молча игнорирует записи. Это важно, пока
/// риг собирается поэтапно (раздел 11 ТЗ аниматора — шесть этапов приёмки).
class BearRigBinding implements BearRigSink {
  BearRigBinding._({
    required Map<String, _NumberChannel> numbers,
    required _BooleanChannel isWalking,
    required Map<String, _TriggerChannel> triggers,
    required StateMachine stateMachine,
  }) : _numbers = numbers,
       _isWalking = isWalking,
       _triggers = triggers,
       _stateMachine = stateMachine;

  /// Собирает биндинг поверх созданного рантаймом контроллера.
  factory BearRigBinding.attach(RiveWidgetController controller) {
    final stateMachine = controller.stateMachine;

    return BearRigBinding._(
      numbers: <String, _NumberChannel>{
        for (final name in const [
          BearRigSpec.stage,
          BearRigSpec.mood,
          BearRigSpec.trait,
          BearRigSpec.variant,
          BearRigSpec.skin,
          BearRigSpec.outfitId,
          BearRigSpec.headwearId,
          BearRigSpec.shoesId,
          BearRigSpec.accessoryId,
        ])
          name: _NumberChannel.resolve(name, stateMachine),
      },
      isWalking: _BooleanChannel.resolve(BearRigSpec.isWalking, stateMachine),
      triggers: <String, _TriggerChannel>{
        for (final name in BearRigSpec.triggers)
          name: _TriggerChannel.resolve(name, stateMachine),
      },
      stateMachine: stateMachine,
    );
  }

  final Map<String, _NumberChannel> _numbers;
  final _BooleanChannel _isWalking;
  final Map<String, _TriggerChannel> _triggers;
  final StateMachine _stateMachine;

  bool _disposed = false;

  @override
  void applyState(BearState state) {
    if (_disposed) return;

    _setNumber(BearRigSpec.stage, state.stage.riveValue);
    _setNumber(BearRigSpec.mood, state.mood.riveValue);
    _setNumber(BearRigSpec.trait, state.trait.riveValue);
    _setNumber(BearRigSpec.skin, state.skin.riveValue);

    final outfit = state.outfit;
    _setNumber(BearRigSpec.outfitId, outfit.outfitId);
    _setNumber(BearRigSpec.headwearId, outfit.headwearId);
    _setNumber(BearRigSpec.shoesId, outfit.shoesId);
    _setNumber(BearRigSpec.accessoryId, outfit.accessoryId);

    _isWalking.value = state.isWalking;
  }

  @override
  void fireTrigger(String name, {int? variant}) {
    if (_disposed) return;

    // Порядок обязателен: `variant` читается State Machine в момент перехода,
    // поэтому выставляется до триггера.
    if (variant != null) _setNumber(BearRigSpec.variant, variant);

    final trigger =
        _triggers[name] ??= _TriggerChannel.resolve(name, _stateMachine);
    trigger.fire();
  }

  void _setNumber(String name, int value) {
    final channel =
        _numbers[name] ??= _NumberChannel.resolve(name, _stateMachine);
    channel.value = value.toDouble();
  }

  /// Освобождает нативные хэндлы инпутов.
  ///
  /// Сам `RiveWidgetController` и загруженный `File` освобождает
  /// `RiveWidgetBuilder` — трогать их отсюда нельзя.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final channel in _numbers.values) {
      channel.dispose();
    }
    _numbers.clear();
    _isWalking.dispose();
    for (final trigger in _triggers.values) {
      trigger.dispose();
    }
    _triggers.clear();
  }
}

/// Number input с отсечкой повторных записей.
class _NumberChannel {
  _NumberChannel._(this._input);

  factory _NumberChannel.resolve(String name, StateMachine stateMachine) {
    // ignore: deprecated_member_use
    final input = stateMachine.number(name);
    if (input == null) _warnMissing('Number input', name);
    return _NumberChannel._(input);
  }

  // ignore: deprecated_member_use
  final NumberInput? _input;

  double? _lastWritten;

  set value(double next) {
    // applyState зовётся на каждый тик затухания, а запись в нативный слой не
    // бесплатна — отсекаем повторы.
    if (_lastWritten == next) return;
    _lastWritten = next;
    _input?.value = next;
  }

  void dispose() => _input?.dispose();
}

/// Boolean input с отсечкой повторных записей.
class _BooleanChannel {
  _BooleanChannel._(this._input);

  factory _BooleanChannel.resolve(String name, StateMachine stateMachine) {
    // ignore: deprecated_member_use
    final input = stateMachine.boolean(name);
    if (input == null) _warnMissing('Boolean input', name);
    return _BooleanChannel._(input);
  }

  // ignore: deprecated_member_use
  final BooleanInput? _input;

  bool? _lastWritten;

  set value(bool next) {
    if (_lastWritten == next) return;
    _lastWritten = next;
    _input?.value = next;
  }

  void dispose() => _input?.dispose();
}

class _TriggerChannel {
  _TriggerChannel._(this._input);

  factory _TriggerChannel.resolve(String name, StateMachine stateMachine) {
    // ignore: deprecated_member_use
    final input = stateMachine.trigger(name);
    if (input == null) _warnMissing('Trigger', name);
    return _TriggerChannel._(input);
  }

  // ignore: deprecated_member_use
  final TriggerInput? _input;

  void fire() => _input?.fire();

  void dispose() => _input?.dispose();
}

void _warnMissing(String kind, String name) {
  if (!kDebugMode) return;
  debugPrint(
    '[TeddyTales] В State Machine «${BearRigSpec.stateMachine}» нет входа '
    '$kind «$name». Команды по этому каналу игнорируются. Сверьте риг с '
    'разделом 8.1 ТЗ аниматора и с lib/bear/bear_rig_spec.dart.',
  );
}
