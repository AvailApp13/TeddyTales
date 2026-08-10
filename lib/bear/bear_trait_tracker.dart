import 'package:clock/clock.dart';

import 'bear_action.dart';
import 'bear_rig_spec.dart';
import 'bear_zodiac.dart';

/// Формирование характера из действий пользователя (КП 7.3).
///
/// КП формулирует требование, но не механику: «Формирование характера — из
/// совокупности действий за период, а не из одного действия». Всё, что ниже, —
/// **ДОПУЩЕНИЕ**, вынесенное в отдельный класс, чтобы менялось в одном месте.
///
/// Модель:
///
/// 1. Действия копятся в скользящем окне [window]; всё, что старше, забывается.
/// 2. Судить о характере можно не раньше, чем через [minObservation] после
///    первого действия — это и есть «за период, а не из одного действия».
/// 3. Четыре черты набираются весами действий ([weights]): активный,
///    любознательный, ласковый, спокойный.
/// 4. «Самостоятельный» и «замкнутый» — про **отсутствие** взаимодействия, а
///    не про его характер. Поэтому они считаются не весами, а вовлечённостью
///    ([engagement]): заходишь редко — мишка растёт самостоятельным, почти не
///    заходишь — замкнутым. Гейт по количеству действий к ним не применяется:
///    малое число действий и есть их признак.
/// 5. Знак зодиака добавляет стартовую склонность ([BearZodiacInfluence]),
///    но не перебивает действия.
///
/// Класс — чистый Dart: тестируется без Rive и без Flutter.
class BearTraitTracker {
  BearTraitTracker({
    this.window = const Duration(days: 3),
    this.minObservation = const Duration(days: 1),
    this.minActions = 6,
    this.expectedActionsPerDay = 8,
    this.reservedBelow = 0.25,
    this.independentBelow = 0.5,
    this.zodiac,
    this.zodiacInfluence = BearZodiacInfluence.neutral,
    Map<BearAction, Map<BearTrait, double>>? weights,
    List<BearActionRecord> history = const [],
  }) : weights = weights ?? defaultWeights,
       _history = List<BearActionRecord>.of(history);

  /// Скользящее окно, за которое считается характер.
  ///
  /// Три дня — ЗАГЛУШКА: «период» в КП не определён. Величина соотнесена с
  /// таймингами роста (КП 5: стадии 1–3 занимают 4–5 дней суммарно), чтобы
  /// характер успел проявиться до взросления.
  final Duration window;

  /// Сколько времени должно пройти с первого действия, прежде чем судить о
  /// характере.
  final Duration minObservation;

  /// Сколько действий нужно, чтобы выбирать черту по весам. На «замкнутого» и
  /// «самостоятельного» не влияет.
  final int minActions;

  /// Сколько действий в сутки считается «полной» вовлечённостью.
  final double expectedActionsPerDay;

  /// Вовлечённость ниже этого — «замкнутый».
  final double reservedBelow;

  /// Вовлечённость ниже этого (но выше [reservedBelow]) — «самостоятельный».
  final double independentBelow;

  /// Знак зодиака питомца, приходит с сервера при рождении (КП 2.5).
  final BearZodiac? zodiac;

  /// Таблица стартовых склонностей. По умолчанию пустая — таблица за
  /// Заказчиком.
  final BearZodiacInfluence zodiacInfluence;

  /// Вклад действий в черты характера.
  final Map<BearAction, Map<BearTrait, double>> weights;

  final List<BearActionRecord> _history;

  /// Вклад по умолчанию. Логика простая и намеренно читаемая:
  /// играем — активный, учимся и наряжаемся — любознательный, гладим и
  /// кормим — ласковый, укладываем и умываем — спокойный.
  static const Map<BearAction, Map<BearTrait, double>> defaultWeights = {
    BearAction.play: {BearTrait.active: 1.0},
    BearAction.wake: {BearTrait.active: 0.5},
    BearAction.learn: {BearTrait.curious: 1.0},
    BearAction.dressUp: {BearTrait.curious: 0.5},
    BearAction.decorate: {BearTrait.curious: 0.5},
    BearAction.pet: {BearTrait.affectionate: 1.0},
    BearAction.feed: {BearTrait.affectionate: 0.5},
    BearAction.sleep: {BearTrait.calm: 1.0},
    BearAction.wash: {BearTrait.calm: 0.5},
  };

  /// История в пределах окна — для сохранения на сервере и для отладки.
  List<BearActionRecord> get history => List.unmodifiable(_history);

  /// Записывает действие. [at] по умолчанию — текущее время (`package:clock`,
  /// чтобы прокручивалось в тестах).
  void record(BearAction action, {DateTime? at}) {
    final now = at ?? clock.now();
    _history.add(BearActionRecord(action, now));
    _forget(now);
  }

  /// Восстанавливает историю, например из сохранения на сервере (КП 1.4).
  void restore(Iterable<BearActionRecord> records) {
    _history
      ..clear()
      ..addAll(records);
    _forget(clock.now());
  }

  void clear() => _history.clear();

  /// Сколько времени наблюдаем пользователя — от первого действия в окне,
  /// но не дольше самого окна.
  Duration observedFor({DateTime? now}) {
    if (_history.isEmpty) return Duration.zero;

    final at = now ?? clock.now();
    final earliest = _history
        .map((r) => r.at)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final observed = at.difference(earliest);

    if (observed.isNegative) return Duration.zero;
    return observed > window ? window : observed;
  }

  /// Доля от ожидаемой активности, 0–1.
  double engagement({DateTime? now}) {
    final observed = observedFor(now: now);
    final days = observed.inMicroseconds / Duration.microsecondsPerDay;
    if (days <= 0 || expectedActionsPerDay <= 0) return 0;

    final perDay = _history.length / days;
    return (perDay / expectedActionsPerDay).clamp(0.0, 1.0);
  }

  /// Счёт по каждой черте. «Активные» черты нормализованы так, что их сумма
  /// равна 1; «самостоятельный» и «замкнутый» добираются из недостающей
  /// вовлечённости. Годится для прогресс-баров в профиле питомца (КП 14.1).
  Map<BearTrait, double> scores({DateTime? now}) {
    final raw = <BearTrait, double>{for (final t in BearTrait.values) t: 0};

    for (final record in _history) {
      final contribution = weights[record.action];
      if (contribution == null) continue;
      contribution.forEach((trait, value) => raw[trait] = raw[trait]! + value);
    }

    final total = raw.values.fold<double>(0, (sum, v) => sum + v);
    final normalized = <BearTrait, double>{
      for (final entry in raw.entries)
        entry.key: total == 0 ? 0 : entry.value / total,
    };

    final withdrawal = 1 - engagement(now: now);
    normalized[BearTrait.independent] =
        normalized[BearTrait.independent]! + withdrawal * 0.5;
    normalized[BearTrait.reserved] =
        normalized[BearTrait.reserved]! + withdrawal * 0.5;

    if (!zodiacInfluence.isEmpty) {
      for (final trait in BearTrait.values) {
        normalized[trait] =
            normalized[trait]! + zodiacInfluence.bonus(zodiac, trait);
      }
    }

    return normalized;
  }

  /// Итоговый характер или `null`, если судить ещё рано.
  ///
  /// Порядок проверок важен: сначала вовлечённость (замкнутый /
  /// самостоятельный), потом победитель по весам. Иначе мишка активного
  /// игрока и мишка человека, заходящего раз в два дня, получились бы
  /// одинаковыми — а по КП 7.4 характер должен различать поведение.
  BearTrait? resolve({DateTime? now}) {
    final at = now ?? clock.now();
    if (observedFor(now: at) < minObservation) return null;

    final level = engagement(now: at);
    if (level < reservedBelow) return BearTrait.reserved;
    if (level < independentBelow) return BearTrait.independent;

    if (_history.length < minActions) return null;

    final ranked =
        scores(now: at).entries
            .where(
              (e) =>
                  e.key != BearTrait.independent &&
                  e.key != BearTrait.reserved,
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final best = ranked.first;
    if (best.value == 0) return null;

    // Ничья — не повод менять характер: пусть остаётся неопределённым, пока
    // действия не разойдутся.
    if (ranked.length > 1 && ranked[1].value == best.value) return null;

    return best.key;
  }

  void _forget(DateTime now) {
    final cutoff = now.subtract(window);
    _history.removeWhere((record) => record.at.isBefore(cutoff));
  }
}
