/// Модуль анимированного персонажа-медведя (Rive + Flutter).
///
/// Границы: риг, State Machine и её входы, состояние персонажа и показатели
/// ухода. Магазина, мини-игр, обучения, каталога и платежей здесь нет — они
/// описаны в КП и живут вне этого модуля.
///
/// Точка входа для остального приложения — [BearController]; на экране —
/// [BearView]. Контракт с ригом — [BearRigSpec] (раздел 8.1 ТЗ аниматора).
library;

export 'bear_controller.dart';
export 'bear_mood_policy.dart';
export 'bear_rig_binding.dart';
export 'bear_rig_sink.dart';
export 'bear_rig_spec.dart';
export 'bear_state.dart';
export 'bear_stats.dart';
export 'bear_view.dart';
