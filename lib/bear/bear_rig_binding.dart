// Единственный файл проекта, знающий про API рантайма Rive. Всё остальное
// общается с ригом через `BearRigSink`.
//
// State machine inputs объявлены в 0.14.x deprecated в пользу data binding, но
// пункт 6.3 ТЗ прямо требует поддержать `stateMachineInputs` — поэтому оба пути
// живут рядом, и `ignore: deprecated_member_use` здесь осознанный.
// Подробности — в `docs/runtime-api-note.md`.
import 'package:flutter/foundation.dart';
import 'package:rive/rive.dart';

import 'bear_rig_sink.dart';
import 'bear_rig_spec.dart';
import 'bear_stats.dart';

/// Мост между [BearController] и загруженным ригом.
///
/// Для каждого свойства сначала пробуется **data binding** (View Model,
/// раздел 5 ТЗ), и только если такого свойства в View Model нет — идёт откат на
/// **state machine input** с тем же именем (раздел 6.3 ТЗ). Так риг можно
/// собирать любым из двух способов, а код остаётся тем же.
///
/// Если свойства нет ни там, ни там — пишется одно предупреждение в лог, и
/// канал молча игнорирует дальнейшие записи. Приложение не падает из-за того,
/// что художник ещё не завёл поле в редакторе.
class BearRigBinding implements BearRigSink {
  BearRigBinding._({
    required _NumberChannel hunger,
    required _NumberChannel mood,
    required _NumberChannel growthStage,
    required Map<String, _TriggerChannel> triggers,
    required StateMachine stateMachine,
    required ViewModelInstance? viewModelInstance,
  }) : _hunger = hunger,
       _mood = mood,
       _growthStage = growthStage,
       _triggers = triggers,
       _stateMachine = stateMachine,
       _viewModelInstance = viewModelInstance;

  /// Собирает биндинг поверх уже созданного [controller].
  ///
  /// Data binding подключается здесь, а не через параметр `dataBind`
  /// у `RiveWidgetBuilder`, намеренно: `DataBind.auto()` бросает исключение,
  /// если в артборде нет экспортированного view model instance, и весь виджет
  /// уходит в `RiveFailed`. Для рига, собранного на state machine inputs
  /// (путь из раздела 6.3 ТЗ), это ложное падение. Здесь же отсутствие view
  /// model — просто повод откатиться на инпуты.
  factory BearRigBinding.attach(RiveWidgetController controller) {
    final stateMachine = controller.stateMachine;
    final vmi = _tryDataBind(controller);

    return BearRigBinding._(
      hunger: _NumberChannel.resolve(BearRigSpec.hunger, vmi, stateMachine),
      mood: _NumberChannel.resolve(BearRigSpec.mood, vmi, stateMachine),
      growthStage: _NumberChannel.resolve(
        BearRigSpec.growthStage,
        vmi,
        stateMachine,
      ),
      triggers: <String, _TriggerChannel>{
        for (final name in const [
          BearRigSpec.feedTrigger,
          BearRigSpec.petTrigger,
          BearRigSpec.tapTrigger,
        ])
          name: _TriggerChannel.resolve(name, vmi, stateMachine),
      },
      stateMachine: stateMachine,
      viewModelInstance: vmi,
    );
  }

  final _NumberChannel _hunger;
  final _NumberChannel _mood;
  final _NumberChannel _growthStage;
  final Map<String, _TriggerChannel> _triggers;
  final StateMachine _stateMachine;

  /// View model instance, привязанный в [BearRigBinding.attach]. `null`, если
  /// в артборде его нет и работаем через state machine inputs.
  ///
  /// Создан здесь — значит, освобождается тоже здесь, в [dispose].
  final ViewModelInstance? _viewModelInstance;

  bool _disposed = false;

  @override
  void applyStats(BearStats stats) {
    if (_disposed) return;
    _hunger.value = stats.hunger;
    _mood.value = stats.mood;
    _growthStage.value = stats.growthStage.riveValue;
  }

  @override
  void fireTrigger(String name) {
    if (_disposed) return;
    final trigger = _triggers[name];
    if (trigger == null) {
      // Триггер не из BearRigSpec — резолвим на лету и кэшируем.
      _triggers[name] =
          _TriggerChannel.resolve(name, _viewModelInstance, _stateMachine)
            ..fire();
      return;
    }
    trigger.fire();
  }

  /// Аналог `play(String animationName)` из референсного
  /// `teddy_controller.dart` (пункт 6.4 ТЗ).
  ///
  /// В актуальном рантайме нельзя «проиграть анимацию по имени» в обход State
  /// Machine: состояние выбирает сама машина. Поэтому здесь — дёрганье
  /// одноимённого триггера, то есть просьба к State Machine перейти в это
  /// состояние, если такой переход в ней заведён.
  ///
  /// Имена состояний — в [BearRigSpec.states].
  void play(String stateName) => fireTrigger(stateName);

  /// Освобождает нативные хэндлы свойств, инпутов и view model instance.
  ///
  /// Сам `RiveWidgetController` и загруженный `File` освобождает
  /// `RiveWidgetBuilder` — трогать их отсюда нельзя.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hunger.dispose();
    _mood.dispose();
    _growthStage.dispose();
    for (final trigger in _triggers.values) {
      trigger.dispose();
    }
    _triggers.clear();
    _viewModelInstance?.dispose();
  }
}

/// Пробует привязать view model instance по умолчанию.
///
/// Возвращает `null`, если в артборде его нет — тогда каналы уйдут на state
/// machine inputs.
ViewModelInstance? _tryDataBind(RiveWidgetController controller) {
  try {
    return controller.dataBind(DataBind.auto());
  } on RiveDataBindException catch (error) {
    if (kDebugMode) {
      debugPrint(
        '[TeddyTales] Data binding недоступен ($error). '
        'Откатываемся на state machine inputs.',
      );
    }
    return null;
  }
}

/// Канал записи числа: View Model property → state machine input → пустышка.
class _NumberChannel {
  _NumberChannel._(this._property, this._input, this._name);

  factory _NumberChannel.resolve(
    String name,
    ViewModelInstance? vmi,
    StateMachine stateMachine,
  ) {
    final property = vmi?.number(name);
    if (property != null) return _NumberChannel._(property, null, name);

    // ignore: deprecated_member_use
    final input = stateMachine.number(name);
    if (input != null) return _NumberChannel._(null, input, name);

    _warnMissing('number', name);
    return _NumberChannel._(null, null, name);
  }

  final ViewModelInstanceNumber? _property;
  // ignore: deprecated_member_use
  final NumberInput? _input;
  final String _name;

  double? _lastWritten;

  set value(double next) {
    // Запись в нативный слой не бесплатна, а applyStats зовётся на каждый тик
    // decay — отсекаем повторы.
    if (_lastWritten == next) return;
    _lastWritten = next;
    _property?.value = next;
    _input?.value = next;
  }

  void dispose() {
    _property?.dispose();
    _input?.dispose();
  }

  @override
  String toString() => '_NumberChannel($_name)';
}

/// Канал триггера: View Model trigger → state machine input → пустышка.
class _TriggerChannel {
  _TriggerChannel._(this._property, this._input, this._name);

  factory _TriggerChannel.resolve(
    String name,
    ViewModelInstance? vmi,
    StateMachine stateMachine,
  ) {
    final property = vmi?.trigger(name);
    if (property != null) return _TriggerChannel._(property, null, name);

    // ignore: deprecated_member_use
    final input = stateMachine.trigger(name);
    if (input != null) return _TriggerChannel._(null, input, name);

    _warnMissing('trigger', name);
    return _TriggerChannel._(null, null, name);
  }

  final ViewModelInstanceTrigger? _property;
  // ignore: deprecated_member_use
  final TriggerInput? _input;
  final String _name;

  void fire() {
    _property?.trigger();
    _input?.fire();
  }

  void dispose() {
    _property?.dispose();
    _input?.dispose();
  }

  @override
  String toString() => '_TriggerChannel($_name)';
}

void _warnMissing(String kind, String name) {
  if (!kDebugMode) return;
  debugPrint(
    '[TeddyTales] В риге нет $kind «$name» — ни как свойства View Model, '
    'ни как state machine input. Значения по этому каналу игнорируются. '
    'Сверьте имена: lib/bear/bear_rig_spec.dart и docs/rig-naming.md.',
  );
}
