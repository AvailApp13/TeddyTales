import 'bear_action.dart';
import 'bear_rig_spec.dart';
import 'bear_state.dart';

/// Почему мишка попросил именно это.
enum BearInitiativeReason {
  /// Просел показатель ухода — мишка просит то, чего не хватает.
  need,

  /// Показатели в порядке, инициатива идёт от характера (КП 7.4).
  trait,
}

/// Предложение активности от питомца — содержимое «пузыря инициативы»
/// (КП 3.4).
class BearInitiative {
  const BearInitiative(this.action, this.reason);

  final BearAction action;
  final BearInitiativeReason reason;

  @override
  bool operator ==(Object other) =>
      other is BearInitiative &&
      other.action == action &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(action, reason);

  @override
  String toString() => 'BearInitiative(${action.name}, ${reason.name})';
}

/// Правило, по которому питомец сам предлагает активность (КП 3.4:
/// «Пузырь инициативы — питомец сам предлагает активность по своему
/// характеру»).
///
/// ДОПУЩЕНИЕ в части конкретных чисел: КП задаёт саму механику и говорит, что
/// характер влияет на частоту инициатив (7.4), но пороги и интервалы не
/// называет.
///
/// Логика:
///
/// 1. Сначала нужда. Если показатель ниже [needThreshold] — мишка просит то,
///    чего не хватает; берётся самый низкий из доступных на текущей стадии.
/// 2. Если всё в порядке — предложение по характеру: активный зовёт играть,
///    любознательный — учиться, ласковый — обниматься, спокойный — поспать.
/// 3. Самостоятельный и замкнутый сами ничего не предлагают, когда всё хорошо:
///    в этом и состоит их характер. Но о реальной нужде скажут — иначе за
///    таким питомцем нельзя было бы ухаживать.
/// 4. Частота — [cooldownFor]: чем самостоятельнее мишка, тем реже подаёт
///    голос.
class BearInitiativePolicy {
  const BearInitiativePolicy({
    this.needThreshold = 40,
    this.cooldowns = defaultCooldowns,
  });

  /// Ниже этого значения показатель считается просевшим.
  ///
  /// Порог выше, чем у [BearMoodPolicy] (30): мишка сначала просит, и только
  /// если не помогли — меняет состояние покоя на голодное или сонное.
  final double needThreshold;

  /// Как часто питомец подаёт голос — по характеру (КП 7.4).
  final Map<BearTrait, Duration> cooldowns;

  static const Map<BearTrait, Duration> defaultCooldowns = {
    BearTrait.active: Duration(minutes: 3),
    BearTrait.curious: Duration(minutes: 4),
    BearTrait.affectionate: Duration(minutes: 4),
    BearTrait.calm: Duration(minutes: 8),
    BearTrait.independent: Duration(minutes: 12),
    BearTrait.reserved: Duration(minutes: 20),
  };

  Duration cooldownFor(BearTrait trait) =>
      cooldowns[trait] ?? const Duration(minutes: 6);

  /// Что предложить сейчас, или `null`, если поводов нет.
  BearInitiative? propose(BearState state) {
    final need = _resolveNeed(state);
    if (need != null) return BearInitiative(need, BearInitiativeReason.need);

    final wish = _resolveWish(state);
    if (wish == null) return null;
    return BearInitiative(wish, BearInitiativeReason.trait);
  }

  /// Самый просевший показатель, для которого действие доступно на стадии.
  BearAction? _resolveNeed(BearState state) {
    final stats = state.stats;
    final candidates = <(double, BearAction)>[
      (stats.food, BearAction.feed),
      (stats.sleep, BearAction.sleep),
      (stats.hygiene, BearAction.wash),
      (stats.play, BearAction.play),
      (stats.love, BearAction.pet),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (value, action) in candidates) {
      if (value >= needThreshold) break;
      if (action.isAvailableOn(state.stage)) return action;
    }
    return null;
  }

  BearAction? _resolveWish(BearState state) {
    final wish = switch (state.trait) {
      BearTrait.active => BearAction.play,
      BearTrait.curious => BearAction.learn,
      BearTrait.affectionate => BearAction.pet,
      BearTrait.calm => BearAction.sleep,
      // Самостоятельный и замкнутый молчат, когда всё в порядке.
      BearTrait.independent || BearTrait.reserved => null,
    };

    if (wish == null) return null;
    return wish.isAvailableOn(state.stage) ? wish : null;
  }
}
