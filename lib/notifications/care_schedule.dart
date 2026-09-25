import '../bear/bear_stats.dart';

/// Когда напомнить об уходе (КП 13.1).
///
/// Уведомление не шлётся «раз в столько-то часов»: это раздражает того, кто
/// только что покормил мишку, и опаздывает к тому, кто не заходил сутки.
/// Момент считается из самих показателей — зная текущее значение и скорость
/// падения, видно, когда шкала дойдёт до порога.
///
/// Считается на устройстве по тем же числам, что у сервера: клиент получает
/// их в настройках (КП 5.6). Совпадение важно — иначе уведомление придёт не
/// тогда, когда игрок увидит грустного мишку.
class CareSchedule {
  const CareSchedule({
    this.threshold = 30,
    this.quietFrom = 22,
    this.quietUntil = 8,
    this.minGap = const Duration(hours: 3),
    this.maxPerDay = 4,
    this.bundleWindow = const Duration(minutes: 90),
  });

  /// Значение показателя, при котором пора напомнить. Не ноль: по КП 6.3
  /// показатели упираются в безопасный предел, и ждать нуля — значит не
  /// дождаться никогда.
  final double threshold;

  /// Тихие часы (КП 13.2): с какого часа и до какого не будить.
  final int quietFrom;
  final int quietUntil;

  /// Наименьший промежуток между уведомлениями. Три показателя могут дойти
  /// до порога почти одновременно — три звонка подряд читаются как
  /// назойливость, даже если каждый по делу.
  final Duration minGap;

  /// Ограничение частоты (КП 13.2): не больше стольких уведомлений за
  /// любые сутки. Лишние — самые поздние — не ставятся: к их времени
  /// приложение почти наверняка откроют, и расписание построится заново.
  final int maxPerDay;

  /// Причины, наступающие ближе этого друг к другу, уходят одним
  /// уведомлением: «проголодался и хочет спать» вместо двух звонков.
  final Duration bundleWindow;

  /// Момент, когда показатель дойдёт до порога.
  ///
  /// `null` — не дойдёт: либо уже ниже (напоминать поздно, игрок и так
  /// видит), либо скорость нулевая.
  DateTime? reaches(double value, double perHour, DateTime from) {
    if (perHour <= 0) return null;
    if (value <= threshold) return null;
    final hours = (value - threshold) / perHour;
    return from.add(Duration(milliseconds: (hours * 3600 * 1000).round()));
  }

  /// Сдвигает момент из тихих часов на утро (КП 13.2).
  ///
  /// Именно сдвигает, а не отменяет: мишка, проголодавшийся в полночь, к
  /// восьми утра голоден тем более, и промолчать было бы хуже.
  DateTime respectQuietHours(DateTime moment) {
    final hour = moment.hour;
    final isQuiet = quietFrom > quietUntil
        // Промежуток через полночь: 22–8.
        ? hour >= quietFrom || hour < quietUntil
        : hour >= quietFrom && hour < quietUntil;
    if (!isQuiet) return moment;

    final morning = DateTime(moment.year, moment.month, moment.day, quietUntil);
    return morning.isAfter(moment)
        ? morning
        : morning.add(const Duration(days: 1));
  }

  /// Раскладывает моменты так, чтобы между ними был промежуток.
  ///
  /// Список приходит отсортированным по времени; каждый следующий, если он
  /// ближе допустимого, отодвигается.
  List<DateTime> spread(List<DateTime> moments) {
    final out = <DateTime>[];
    for (final moment in moments) {
      if (out.isEmpty) {
        out.add(moment);
        continue;
      }
      final earliest = out.last.add(minGap);
      out.add(moment.isBefore(earliest) ? earliest : moment);
    }
    return out;
  }

  /// Полное расписание напоминаний об уходе от текущих показателей.
  ///
  /// Возвращает пары «тип уведомления — когда». Типы те же, что в КП 13.1.
  ///
  /// [extra] — уведомления, время которых известно заранее, а не из
  /// показателей: «Новая стадия» (прогноз сервера), «Задание» (КП 13.1).
  /// Они встают в общий ряд: тихие часы, промежутки и дневной предел для
  /// всех одни.
  Map<String, DateTime> planFrom(
    BearCareStats stats,
    BearDecayConfig decay,
    DateTime now, {
    Map<String, DateTime> extra = const {},
  }) {
    final raw = <String, DateTime>{};

    void add(String kind, double value, double perSecond) {
      final at = reaches(value, perSecond * 3600, now);
      if (at != null) raw[kind] = respectQuietHours(at);
    }

    add('hungry', stats.food, decay.foodPerSecond);
    add('play', stats.play, decay.playPerSecond);
    add('sleep', stats.sleep, decay.sleepPerSecond);

    for (final entry in extra.entries) {
      if (entry.value.isAfter(now)) {
        raw[entry.key] = respectQuietHours(entry.value);
      }
    }

    if (raw.isEmpty) return const {};

    // Сортируем по времени. Близкие причины ухода склеиваются в одно
    // уведомление с ключом «hungry+sleep», время — у первой.
    final sorted = raw.keys.toList()
      ..sort((a, b) => raw[a]!.compareTo(raw[b]!));
    const bundlable = {'hungry', 'play', 'sleep'};
    final groups = <List<String>>[];
    for (final kind in sorted) {
      final last = groups.isEmpty ? null : groups.last;
      if (last != null &&
          bundlable.contains(kind) &&
          last.every(bundlable.contains) &&
          raw[kind]!.difference(raw[last.first]!) < bundleWindow) {
        last.add(kind);
      } else {
        groups.add([kind]);
      }
    }
    final order = [for (final g in groups) g.join('+')];
    final starts = {for (final g in groups) g.join('+'): raw[g.first]!};
    final spreadOut = spread(order.map((k) => starts[k]!).toList());

    // Дневной предел (КП 13.2): в любые сутки — не больше [maxPerDay].
    final plan = <String, DateTime>{};
    final kept = <DateTime>[];
    for (var i = 0; i < order.length; i++) {
      final at = spreadOut[i];
      final sameDay = kept
          .where((k) => at.difference(k) < const Duration(days: 1))
          .length;
      if (sameDay >= maxPerDay) continue;
      kept.add(at);
      plan[order[i]] = at;
    }
    return plan;
  }

  /// Когда напомнить о задании (КП 13.1): завтра в [hour] — если игрок
  /// сегодня так и не зайдёт, мишка позовёт учиться. Приложение открыли —
  /// расписание строится заново, и напоминание уезжает на следующий день.
  DateTime nextTaskAt(DateTime now, {int hour = 18}) =>
      DateTime(now.year, now.month, now.day + 1, hour);
}
