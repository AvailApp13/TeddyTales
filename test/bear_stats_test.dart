import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

void main() {
  group('BearCareStats', () {
    test('copyWith зажимает значения в 0–100', () {
      const stats = BearCareStats(food: 50, hygiene: 50);

      expect(stats.copyWith(food: 500).food, BearCareStats.max);
      expect(stats.copyWith(food: -20).food, BearCareStats.min);
      expect(stats.copyWith(hygiene: 1000).hygiene, BearCareStats.max);
      expect(stats.copyWith(love: -1).love, BearCareStats.min);
    });

    test('average считает по всем пяти показателям', () {
      const stats = BearCareStats(
        food: 100,
        hygiene: 0,
        sleep: 50,
        play: 50,
        love: 50,
      );

      expect(stats.all, hasLength(5));
      expect(stats.average, 50);
    });

    test('copyWith без аргументов не меняет состояние', () {
      const stats = BearCareStats(food: 42, hygiene: 17, love: 3);

      expect(stats.copyWith(), stats);
    });
  });

  group('BearDecayConfig', () {
    test('disabled ничего не меняет', () {
      const stats = BearCareStats(food: 80, hygiene: 80);
      const decay = BearDecayConfig.disabled();

      expect(decay.isEnabled, isFalse);
      expect(decay.apply(stats, const Duration(hours: 10)), stats);
    });

    test('каждый показатель падает по своей скорости', () {
      const stats = BearCareStats();
      const decay = BearDecayConfig(
        foodPerSecond: 1,
        hygienePerSecond: 2,
        sleepPerSecond: 0,
        playPerSecond: 0,
        lovePerSecond: 0,
        floor: 0,
      );

      final next = decay.apply(stats, const Duration(seconds: 10));

      expect(next.food, 90);
      expect(next.hygiene, 80);
      expect(next.sleep, 100);
    });

    test('считает дробные интервалы, а не только целые секунды', () {
      const stats = BearCareStats();
      const decay = BearDecayConfig(foodPerSecond: 1, floor: 0);

      final next = decay.apply(stats, const Duration(milliseconds: 500));

      expect(next.food, closeTo(99.5, 1e-9));
    });

    test('безопасный предел не даёт упасть ниже floor (КП 6.3)', () {
      const stats = BearCareStats();
      const decay = BearDecayConfig(foodPerSecond: 1, floor: 20);

      final next = decay.apply(stats, const Duration(hours: 10));

      expect(next.food, 20);
    });

    test('показатель ниже floor не поднимается предела ради', () {
      const stats = BearCareStats(food: 5);
      const decay = BearDecayConfig(foodPerSecond: 1, floor: 20);

      final next = decay.apply(stats, const Duration(seconds: 10));

      expect(next.food, 5);
    });

    test('нулевой и отрицательный интервал игнорируются', () {
      const stats = BearCareStats(food: 50);
      const decay = BearDecayConfig(foodPerSecond: 1, floor: 0);

      expect(decay.apply(stats, Duration.zero), stats);
      expect(decay.apply(stats, const Duration(seconds: -5)), stats);
    });
  });
}
