import 'bear_rig_spec.dart';

/// Действие пользователя, из совокупности которых формируется характер
/// (КП 7.3) и начисляются монеты (КП 6.4).
///
/// Первые шесть — действия ухода, их эмитит сам [BearController]. Остальные
/// приходят снаружи: обучение и кастомизация живут в других модулях, но на
/// характер влияют, поэтому попадают сюда через
/// `BearController.recordAction`.
enum BearAction {
  /// Покормить (КП 6.4, `trg_eat`).
  feed,

  /// Умыть (`trg_wash`).
  wash,

  /// Уложить спать (`trg_sleep`).
  sleep,

  /// Разбудить (`trg_wake`).
  wake,

  /// Поиграть (`trg_play`).
  play,

  /// Погладить (`trg_pet`).
  pet,

  /// Пройти уровень обучения (КП 9.x).
  learn,

  /// Сменить образ в гардеробе (КП 10.6).
  dressUp,

  /// Переставить предметы в комнате (КП 10.7).
  decorate,
}

/// С какой стадии действие доступно (КП 3.5: недоступные по стадии разделы
/// показываются с замком).
extension BearActionAvailability on BearAction {
  /// Минимальная стадия, на которой действие имеет смысл.
  ///
  /// Уход разложен по клипам из раздела 7.2 ТЗ аниматора: `act_wash` и
  /// `act_play` есть только для стадий 2–5, остальные действия ухода — для
  /// всех пяти.
  ///
  /// Для обучения и кастомизации точных стадий в документах нет —
  /// ДОПУЩЕНИЕ по КП 5: младенческая одежда появляется у ползающего малыша
  /// (5.2), взаимодействие с комнатой — на «первых шагах» (5.3), все
  /// механики открываются у подрастающего (5.4).
  BearStage get minStage => switch (this) {
    BearAction.feed ||
    BearAction.sleep ||
    BearAction.wake ||
    BearAction.pet => BearStage.newborn,
    BearAction.wash || BearAction.play || BearAction.dressUp =>
      BearStage.crawling,
    BearAction.decorate => BearStage.firstSteps,
    BearAction.learn => BearStage.growing,
  };

  bool isAvailableOn(BearStage stage) =>
      stage.riveValue >= minStage.riveValue;
}

/// Действие с отметкой времени — единица истории, по которой считается
/// характер.
class BearActionRecord {
  const BearActionRecord(this.action, this.at);

  final BearAction action;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is BearActionRecord && other.action == action && other.at == at;

  @override
  int get hashCode => Object.hash(action, at);

  @override
  String toString() => 'BearActionRecord(${action.name}, $at)';
}
