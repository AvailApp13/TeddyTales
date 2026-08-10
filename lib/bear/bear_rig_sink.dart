import 'bear_stats.dart';

/// Приёмник команд на стороне рига.
///
/// Это и есть «точка интеграции» из пункта 9.4 ТЗ: игровая логика приложения
/// разговаривает с ригом только через этот интерфейс.
///
/// Интерфейс не зависит от Rive — благодаря этому [BearController] тестируется
/// без нативных библиотек `rive_native`, а замена рантайма (например, откат на
/// legacy-API, см. `docs/runtime-api-note.md`) не задевает игровую логику.
/// Единственная боевая реализация — `BearRigBinding` в `bear_rig_binding.dart`.
abstract interface class BearRigSink {
  /// Передаёт текущие характеристики в риг: `hunger`, `mood`, `growthStage`.
  void applyStats(BearStats stats);

  /// Дёргает триггер State Machine по имени (см. `BearRigSpec.feedTrigger` и
  /// соседние константы). Неизвестное имя игнорируется с предупреждением в лог.
  void fireTrigger(String name);
}
