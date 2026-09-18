import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_stats.dart';
import 'package:teddy_tales/notifications/care_schedule.dart';

void main() {
  const schedule = CareSchedule();
  final noon = DateTime(2026, 9, 16, 12);

  group('Когда напомнить (КП 13.1)', () {
    test('момент считается из показателя и скорости', () {
      // Сытость 80, падает на 25 в час, порог 30: до порога 50, то есть
      // ровно два часа.
      final at = schedule.reaches(80, 25, noon);
      expect(at, DateTime(2026, 9, 16, 14));
    });

    test('уже ниже порога — напоминать поздно', () {
      // Игрок и так видит грустного мишку, открыв приложение.
      expect(schedule.reaches(20, 25, noon), isNull);
      expect(schedule.reaches(30, 25, noon), isNull);
    });

    test('нулевая скорость — никогда', () {
      expect(schedule.reaches(90, 0, noon), isNull);
    });
  });

  group('Тихие часы (КП 13.2)', () {
    test('ночное сдвигается на утро, а не отменяется', () {
      // Мишка, проголодавшийся в час ночи, к восьми утра голоден тем более.
      final at = schedule.respectQuietHours(DateTime(2026, 9, 16, 1, 30));
      expect(at, DateTime(2026, 9, 16, 8));
    });

    test('позднее вечернее уезжает на утро следующего дня', () {
      final at = schedule.respectQuietHours(DateTime(2026, 9, 16, 23, 10));
      expect(at, DateTime(2026, 9, 17, 8));
    });

    test('дневное не трогается', () {
      final at = DateTime(2026, 9, 16, 15, 20);
      expect(schedule.respectQuietHours(at), at);
    });

    test('граничные часы: 22:00 тихо, 08:00 уже нет', () {
      expect(
        schedule.respectQuietHours(DateTime(2026, 9, 16, 22)),
        DateTime(2026, 9, 17, 8),
      );
      final morning = DateTime(2026, 9, 16, 8);
      expect(schedule.respectQuietHours(morning), morning);
    });
  });

  group('Промежуток между напоминаниями', () {
    test('совпавшие по времени разводятся', () {
      final same = [noon, noon, noon];
      final out = schedule.spread(same);

      expect(out[0], noon);
      expect(out[1], noon.add(const Duration(hours: 3)));
      expect(out[2], noon.add(const Duration(hours: 6)));
    });

    test('далеко отстоящие остаются как есть', () {
      final far = [noon, noon.add(const Duration(hours: 9))];
      expect(schedule.spread(far), far);
    });
  });

  group('Полное расписание', () {
    test('три показателя дают три напоминания в верном порядке', () {
      const stats = BearCareStats(food: 90, play: 50, sleep: 70, love: 100);
      const decay = BearDecayConfig();

      final plan = schedule.planFrom(stats, decay, noon);

      expect(plan.keys.toSet(), {'hungry', 'play', 'sleep'});
      // Игра падает медленнее еды, но её значение ниже — она и наступит
      // первой. Порядок должен считаться, а не браться из порядка полей.
      final times = plan.values.toList()..sort();
      expect(times.first, plan['play']);
    });

    test('между напоминаниями выдержан промежуток', () {
      const stats = BearCareStats(food: 40, play: 40, sleep: 40, love: 100);
      const decay = BearDecayConfig();

      final plan = schedule.planFrom(stats, decay, noon);
      final times = plan.values.toList()..sort();

      for (var i = 1; i < times.length; i++) {
        expect(
          times[i].difference(times[i - 1]).inMinutes,
          greaterThanOrEqualTo(180),
          reason: 'три звонка подряд читаются как назойливость',
        );
      }
    });

    test('при выключенном затухании расписания нет', () {
      const stats = BearCareStats();
      const decay = BearDecayConfig.disabled();
      expect(schedule.planFrom(stats, decay, noon), isEmpty);
    });

    test('показатели ниже порога в расписание не попадают', () {
      const stats = BearCareStats(food: 15, play: 15, sleep: 90, love: 100);
      const decay = BearDecayConfig();

      final plan = schedule.planFrom(stats, decay, noon);
      expect(plan.keys, ['sleep']);
    });
  });
}
