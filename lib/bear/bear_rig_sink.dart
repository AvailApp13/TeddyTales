import 'bear_state.dart';

/// Приёмник команд на стороне рига.
///
/// Игровая логика приложения разговаривает с персонажем только через этот
/// интерфейс — это и есть граница между приложением и анимацией.
///
/// Интерфейс не зависит от Rive: благодаря этому [BearController] тестируется
/// без нативных библиотек `rive_native`, а смена рантайма не задевает игровую
/// логику. Единственная боевая реализация — `BearRigBinding`.
abstract interface class BearRigSink {
  /// Заливает в риг все Number/Boolean входы контракта: `stage`, `mood`,
  /// `trait`, `skin`, `is_walking`, `outfit_id`, `headwear_id`, `shoes_id`,
  /// `accessory_id`.
  void applyState(BearState state);

  /// Дёргает Trigger по имени (константы `BearRigSpec.trg*`).
  ///
  /// Если передан [variant], значение входа `variant` выставляется **до**
  /// триггера — порядок важен: State Machine читает его в момент перехода
  /// (раздел 7.6 ТЗ аниматора: варианты выбирает приложение).
  void fireTrigger(String name, {int? variant});
}
