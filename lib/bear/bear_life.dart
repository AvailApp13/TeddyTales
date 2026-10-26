import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'bear_controller.dart';
import 'bear_rig_spec.dart';
import 'bear_stats.dart';
import 'rive_bear_trial.dart';

/// Живой мишка в игровой (заказчик 27.09: «нужно простроить логической
/// цепочкой… как это работает в других приложениях»).
///
/// Одна цепочка: показатели → состояние → что показывает мишка. Состояние
/// одно в каждый момент, по приоритету: голод, сон, грязнуля (показатель
/// ниже 30, побеждает самый низкий), грусть (среднее ниже 40), радость
/// (среднее от 80), иначе обычное — и тогда играет покой характера.
///
/// Чтобы мишка не мельтешил на границе (показатель падает непрерывно):
/// - гистерезис — голод включается ниже 30, выключается только выше 38;
///   грусть 40 / 48; радость 80 / 72;
/// - в одном состоянии не меньше [minHold].
///
/// Однократные реакции — на события, а не на состояние
/// ([BearLife]): показатель упал ниже 30 при вас, покормили, проснулся,
/// вошли в игровую, показатель поднялся выше порога.
///
/// Уровни пузыря по процентам: ниже 40 — просьба (её даёт
/// `BearInitiativePolicy`), ниже 30 — та же просьба и покой нужды, ниже 15
/// — «Ты про меня забыл?» ([BearLife.forgotten]).
class BearLifePolicy {
  const BearLifePolicy({
    this.low = 30,
    this.lowRelease = 38,
    this.sad = 40,
    this.sadRelease = 48,
    this.happy = 80,
    this.happyRelease = 72,
    this.forgotten = 15,
    this.minHold = const Duration(seconds: 20),
  });

  final double low;
  final double lowRelease;
  final double sad;
  final double sadRelease;
  final double happy;
  final double happyRelease;
  final double forgotten;
  final Duration minHold;

  /// Показатель, который отвечает за нужду.
  static double needOf(BearCareStats stats, BearMood mood) => switch (mood) {
    BearMood.hungry => stats.food,
    BearMood.sleepy => stats.sleep,
    BearMood.dirty => stats.hygiene,
    _ => 100,
  };

  /// Следующее состояние по показателям с учётом текущего ([current]) и
  /// того, сколько оно уже держится ([held]).
  BearMood resolve(BearCareStats stats, BearMood current, Duration held) {
    if (held < minHold) return current;
    // Нужда: держится, пока её показатель не поднялся выше порога отпускания.
    if (current.isNeed && needOf(stats, current) < lowRelease) {
      // …но более острая нужда перебивает.
      final worse = _worstNeed(stats, low);
      if (worse != null && needOf(stats, worse) < needOf(stats, current)) {
        return worse;
      }
      return current;
    }
    final need = _worstNeed(stats, low);
    if (need != null) return need;
    final average = stats.average;
    switch (current) {
      case BearMood.sad:
        if (average < sadRelease) return BearMood.sad;
      case BearMood.happy:
        if (average >= happyRelease) return BearMood.happy;
      default:
        break;
    }
    if (average < sad) return BearMood.sad;
    if (average >= happy) return BearMood.happy;
    return BearMood.normal;
  }

  static BearMood? _worstNeed(BearCareStats stats, double below) {
    BearMood? worst;
    var value = below;
    for (final (v, mood) in [
      (stats.food, BearMood.hungry),
      (stats.sleep, BearMood.sleepy),
      (stats.hygiene, BearMood.dirty),
    ]) {
      if (v < value) {
        value = v;
        worst = mood;
      }
    }
    return worst;
  }
}

extension on BearMood {
  bool get isNeed =>
      this == BearMood.hungry ||
      this == BearMood.sleepy ||
      this == BearMood.dirty;
}

/// Событие, на которое мишка отвечает один раз.
enum BearLifeEvent {
  /// Показатель упал ниже порога нужды при вас.
  hungry,
  sleepy,
  dirty,

  /// Показатель поднялся выше порога — облегчение.
  relieved,

  /// Покормили (еда выросла).
  fed,

  /// Проснулся.
  woke,

  /// Вошли в игровую.
  entered,
}

/// Связывает показатели, сон и комнату с тем, что играет Rive-мишка:
/// состояние покоя ([mood]) с гистерезисом и однократные реакции через
/// [BearFaceCue].
class BearLife extends ChangeNotifier {
  BearLife({
    required this.controller,
    required this.cue,
    this.policy = const BearLifePolicy(),
  }) {
    _stats = controller.state.stats;
    _mood = _initialMood(_stats);
    _since = clock.now();
    controller.addListener(_onController);
  }

  final BearController controller;
  final BearFaceCue cue;
  final BearLifePolicy policy;

  late BearCareStats _stats;
  late BearMood _mood;
  late DateTime _since;
  bool _asleep = false;
  bool _present = false;
  Timer? _follow;

  /// Состояние покоя с гистерезисом.
  BearMood get mood => _mood;

  /// Ниже 15 по нужде — «Ты про меня забыл?».
  bool get forgotten =>
      _mood.isNeed && BearLifePolicy.needOf(_stats, _mood) < policy.forgotten;

  /// Последнее событие — для проверок.
  BearLifeEvent? lastEvent;

  bool get asleep => _asleep;
  set asleep(bool value) {
    if (value == _asleep) return;
    _asleep = value;
    if (!value) _react(BearLifeEvent.woke);
    _tick();
  }

  /// Мишка на экране — игровая или кухня (заказчик 27.09: мишка перенесён
  /// на кухню). Реакции на события — только когда он на экране.
  bool get present => _present;

  /// На кухне поел — там кухня сама играет «Жуёт» и реакцию; здесь
  /// «покормили» не дублируется.
  bool inKitchen = false;
  set present(bool value) {
    if (value == _present) return;
    _present = value;
    if (value) _react(BearLifeEvent.entered);
  }

  BearMood _initialMood(BearCareStats stats) =>
      policy.resolve(stats, BearMood.normal, policy.minHold);

  void _onController() {
    final prev = _stats;
    final next = controller.state.stats;
    _stats = next;
    // события по показателям — только при вас, чтобы не копились
    if (_present && !_asleep) {
      for (final (was, now, event) in [
        (prev.food, next.food, BearLifeEvent.hungry),
        (prev.sleep, next.sleep, BearLifeEvent.sleepy),
        (prev.hygiene, next.hygiene, BearLifeEvent.dirty),
      ]) {
        if (was >= policy.low && now < policy.low) _react(event);
        if (was < policy.lowRelease && now >= policy.lowRelease) {
          _react(BearLifeEvent.relieved);
        }
      }
      if (next.food - prev.food >= 10 && !inKitchen) {
        _react(BearLifeEvent.fed);
      }
    }
    _tick();
  }

  /// Пересчитать состояние — по таймеру приложения и после событий.
  void tick() => _tick();

  void _tick() {
    final now = clock.now();
    final next = policy.resolve(_stats, _mood, now.difference(_since));
    if (next != _mood) {
      _mood = next;
      _since = now;
      notifyListeners();
    }
  }

  /// Однократная реакция на событие — по состоянию и событию.
  void _react(BearLifeEvent event) {
    if (!_present || _asleep) return;
    lastEvent = event;
    final face = switch (event) {
      BearLifeEvent.hungry => BearFace.upset,
      BearLifeEvent.sleepy => BearFace.yawn,
      BearLifeEvent.dirty => BearFace.bonusShake,
      BearLifeEvent.relieved => BearFace.love,
      BearLifeEvent.fed => BearFace.treat,
      BearLifeEvent.woke => BearFace.bonusStretch,
      // при входе — только если есть что показать; в обычном состоянии
      // мишка просто стоит и дышит (заказчик 26.09)
      BearLifeEvent.entered => switch (_mood) {
        BearMood.happy => BearFace.love,
        BearMood.hungry => BearFace.lick,
        BearMood.sleepy => BearFace.yawn,
        BearMood.sad => BearFace.sad,
        BearMood.dirty => BearFace.bonusShake,
        BearMood.normal => null,
      },
    };
    if (face == null) return;
    cue.show(face);
    // покормили: угощение → облизнулся; проснулся: потянулся → и если ещё
    // не выспался, зевнул
    _follow?.cancel();
    final second = switch (event) {
      BearLifeEvent.fed => BearFace.lick,
      BearLifeEvent.woke when _stats.sleep < policy.low => BearFace.yawn,
      _ => null,
    };
    if (second != null) {
      _follow = Timer(const Duration(milliseconds: 3800), () {
        if (_present && !_asleep) cue.show(second);
      });
    }
  }

  @override
  void dispose() {
    _follow?.cancel();
    controller.removeListener(_onController);
    super.dispose();
  }
}
