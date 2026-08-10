import 'package:clock/clock.dart';

import '../bear/bear_phrases.dart' show BearLanguage;

/// Возраст питомца в игровых единицах.
class GameAge {
  const GameAge({required this.months, required this.days});

  final int months;
  final int days;

  /// «3 месяца 12 дней» — формат из шапки главного экрана на макете.
  String format(BearLanguage language) => switch (language) {
    BearLanguage.ru => _formatRu(),
    BearLanguage.en => _formatEn(),
    BearLanguage.zh => '$months个月$days天',
  };

  String _formatRu() {
    if (months == 0) return _plural(days, 'день', 'дня', 'дней');
    if (days == 0) return _plural(months, 'месяц', 'месяца', 'месяцев');
    return '${_plural(months, 'месяц', 'месяца', 'месяцев')} '
        '${_plural(days, 'день', 'дня', 'дней')}';
  }

  String _formatEn() {
    final m = months == 1 ? '1 month' : '$months months';
    final d = days == 1 ? '1 day' : '$days days';
    if (months == 0) return d;
    if (days == 0) return m;
    return '$m $d';
  }

  /// Русские числительные: 1 день, 2 дня, 5 дней, 11 дней, 21 день.
  static String _plural(int n, String one, String few, String many) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    final form = (mod100 >= 11 && mod100 <= 14)
        ? many
        : mod10 == 1
        ? one
        : (mod10 >= 2 && mod10 <= 4)
        ? few
        : many;
    return '$n $form';
  }

  @override
  bool operator ==(Object other) =>
      other is GameAge && other.months == months && other.days == days;

  @override
  int get hashCode => Object.hash(months, days);

  @override
  String toString() => 'GameAge($months мес, $days дн)';
}

/// Перевод реального времени в игровой возраст питомца.
///
/// **ДОПУЩЕНИЕ.** Прямой формулы нет ни в КП, ни в ТЗ; она выведена из двух
/// фактов, которые надо было свести:
///
/// - КП 1 обещает вырастить питомца от новорождённого до взрослого **за две
///   недели реального времени**;
/// - макет показывает возраст в игровых месяцах и ставит взрослую стадию на
///   «12+ месяцев», а в шапке пишет «3 месяца 12 дней».
///
/// Отсюда: **один игровой месяц ≈ одни реальные сутки**. Тогда 12+ игровых
/// месяцев набегают примерно за две недели, как и обещано. Игровой месяц взят в
/// 30 игровых дней, то есть игровой день — 48 реальных минут.
///
/// Обе величины настраиваемые: по КП 5.6 и 15.4 тайминги стадий и скорости
/// настраиваются из панели управления, значит и календарь должен приезжать с
/// сервера, а не жить в коде.
///
/// Время берётся из `package:clock`. По КП 1.5 игровое время серверное —
/// перевод часов на телефоне не должен ускорять игру, поэтому в бою `now`
/// обязан приходить с сервера, а не из системных часов.
class GameCalendar {
  const GameCalendar({
    this.realTimePerGameMonth = const Duration(days: 1),
    this.gameDaysPerMonth = 30,
  });

  /// Сколько реального времени длится один игровой месяц.
  final Duration realTimePerGameMonth;

  /// Сколько игровых дней в игровом месяце.
  final int gameDaysPerMonth;

  /// Сколько реального времени длится один игровой день.
  Duration get realTimePerGameDay => Duration(
    microseconds: realTimePerGameMonth.inMicroseconds ~/ gameDaysPerMonth,
  );

  /// Возраст питомца, рождённого в [birth], на момент [now].
  GameAge ageAt(DateTime birth, {DateTime? now}) {
    final elapsed = (now ?? clock.now()).difference(birth);
    if (elapsed.isNegative) return const GameAge(months: 0, days: 0);

    final totalGameDays =
        elapsed.inMicroseconds ~/ realTimePerGameDay.inMicroseconds;

    return GameAge(
      months: totalGameDays ~/ gameDaysPerMonth,
      days: totalGameDays % gameDaysPerMonth,
    );
  }
}
