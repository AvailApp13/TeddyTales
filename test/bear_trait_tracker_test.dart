import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_trait_tracker.dart';
import 'package:teddy_tales/bear/bear_zodiac.dart';

/// Фиксированная точка отсчёта — тесты про характер целиком про время.
final DateTime t0 = DateTime.utc(2026, 8, 10, 12);

/// Раскладывает [count] действий равномерно по [span], начиная с [t0].
void spread(
  BearTraitTracker tracker,
  BearAction action,
  int count,
  Duration span,
) {
  for (var i = 0; i < count; i++) {
    tracker.record(
      action,
      at: t0.add(
        Duration(microseconds: span.inMicroseconds * i ~/ (count == 1 ? 1 : count)),
      ),
    );
  }
}

void main() {
  group('BearTraitTracker — период наблюдения', () {
    test('одно действие характер не определяет (КП 7.3)', () {
      final tracker = BearTraitTracker();
      tracker.record(BearAction.play, at: t0);

      expect(tracker.resolve(now: t0), isNull);
    });

    test('пока не прошёл minObservation, характер не определён', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.play, 20, const Duration(hours: 20));

      expect(
        tracker.resolve(now: t0.add(const Duration(hours: 20))),
        isNull,
      );
    });

    test('пустая история — ничего не определено', () {
      final tracker = BearTraitTracker();

      expect(tracker.observedFor(now: t0), Duration.zero);
      expect(tracker.engagement(now: t0), 0);
      expect(tracker.resolve(now: t0), isNull);
    });
  });

  group('BearTraitTracker — вовлечённость', () {
    test('редкие заходы → замкнутый', () {
      final tracker = BearTraitTracker();
      // 3 действия за 3 дня — 1 в сутки при ожидаемых 8.
      spread(tracker, BearAction.play, 3, const Duration(days: 3));

      final now = t0.add(const Duration(days: 3));
      expect(tracker.engagement(now: now), lessThan(0.25));
      expect(tracker.resolve(now: now), BearTrait.reserved);
    });

    test('умеренные заходы → самостоятельный', () {
      final tracker = BearTraitTracker();
      // 9 действий за 3 дня — 3 в сутки, между 0,25 и 0,5.
      spread(tracker, BearAction.play, 9, const Duration(days: 3));

      final now = t0.add(const Duration(days: 3));
      final level = tracker.engagement(now: now);
      expect(level, greaterThanOrEqualTo(0.25));
      expect(level, lessThan(0.5));
      expect(tracker.resolve(now: now), BearTrait.independent);
    });

    test('вовлечённость не превышает единицы', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.play, 100, const Duration(days: 3));

      expect(tracker.engagement(now: t0.add(const Duration(days: 3))), 1.0);
    });
  });

  group('BearTraitTracker — черты по действиям', () {
    test('много играем → активный', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.play, 24, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))),
          BearTrait.active);
    });

    test('много учимся → любознательный', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.learn, 24, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))),
          BearTrait.curious);
    });

    test('много гладим → ласковый', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.pet, 24, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))),
          BearTrait.affectionate);
    });

    test('много укладываем → спокойный', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.sleep, 24, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))),
          BearTrait.calm);
    });

    test('ничья между чертами характер не меняет', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.play, 12, const Duration(days: 3));
      spread(tracker, BearAction.pet, 12, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))), isNull);
    });
  });

  group('BearTraitTracker — окно', () {
    test('действия старше окна забываются', () {
      final tracker = BearTraitTracker(window: const Duration(days: 3));

      tracker.record(BearAction.play, at: t0);
      tracker.record(BearAction.play, at: t0.add(const Duration(days: 5)));

      expect(tracker.history, hasLength(1));
      expect(tracker.history.single.at, t0.add(const Duration(days: 5)));
    });

    test('restore подтягивает историю и обрезает старое', () {
      final tracker = BearTraitTracker(window: const Duration(days: 3));

      withClock(Clock.fixed(t0.add(const Duration(days: 4))), () {
        tracker.restore([
          BearActionRecord(BearAction.play, t0),
          BearActionRecord(
            BearAction.pet,
            t0.add(const Duration(days: 4)),
          ),
        ]);
      });

      expect(tracker.history, hasLength(1));
      expect(tracker.history.single.action, BearAction.pet);
    });

    test('clear очищает всё', () {
      final tracker = BearTraitTracker();
      spread(tracker, BearAction.play, 10, const Duration(days: 3));

      tracker.clear();

      expect(tracker.history, isEmpty);
      expect(tracker.resolve(now: t0.add(const Duration(days: 3))), isNull);
    });
  });

  group('BearTraitTracker — зодиак', () {
    test('без таблицы Заказчика знак ни на что не влияет', () {
      final neutral = BearTraitTracker(zodiac: BearZodiac.leo);
      spread(neutral, BearAction.play, 24, const Duration(days: 3));

      final scores = neutral.scores(now: t0.add(const Duration(days: 3)));
      expect(scores[BearTrait.curious], 0);
    });

    test('таблица смещает счёт', () {
      final tracker = BearTraitTracker(
        zodiac: BearZodiac.gemini,
        zodiacInfluence: const BearZodiacInfluence({
          BearZodiac.gemini: {BearTrait.curious: 0.3},
        }),
      );
      spread(tracker, BearAction.play, 24, const Duration(days: 3));

      final scores = tracker.scores(now: t0.add(const Duration(days: 3)));
      expect(scores[BearTrait.curious], 0.3);
      expect(scores[BearTrait.active], 1.0);
    });

    test('склонность не перебивает действия', () {
      final tracker = BearTraitTracker(
        zodiac: BearZodiac.gemini,
        zodiacInfluence: const BearZodiacInfluence({
          BearZodiac.gemini: {BearTrait.curious: 0.3},
        }),
      );
      spread(tracker, BearAction.play, 24, const Duration(days: 3));

      expect(tracker.resolve(now: t0.add(const Duration(days: 3))),
          BearTrait.active);
    });

    test('знак есть, а таблицы нет — bonus нулевой', () {
      expect(
        BearZodiacInfluence.neutral.bonus(BearZodiac.aries, BearTrait.active),
        0,
      );
      expect(BearZodiacInfluence.neutral.isEmpty, isTrue);
    });

    test('двенадцать знаков', () {
      expect(BearZodiac.values, hasLength(12));
    });
  });
}
