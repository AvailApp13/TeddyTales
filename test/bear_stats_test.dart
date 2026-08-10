import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

void main() {
  group('BearStats', () {
    test('copyWith зажимает значения в 0–100', () {
      const stats = BearStats(hunger: 50, mood: 50);

      expect(stats.copyWith(hunger: 500).hunger, BearStats.max);
      expect(stats.copyWith(hunger: -20).hunger, BearStats.min);
      expect(stats.copyWith(mood: 1000).mood, BearStats.max);
      expect(stats.copyWith(mood: -1).mood, BearStats.min);
    });

    test('copyWith без аргументов не меняет состояние', () {
      const stats = BearStats(
        hunger: 42,
        mood: 17,
        growthStage: BearGrowthStage.young,
      );

      expect(stats.copyWith(), stats);
    });
  });

  group('BearDecayConfig', () {
    test('disabled ничего не меняет', () {
      const stats = BearStats(hunger: 80, mood: 80);
      const decay = BearDecayConfig.disabled();

      expect(decay.isEnabled, isFalse);
      expect(decay.apply(stats, const Duration(hours: 10)), stats);
    });

    test('голод падает по заданной скорости', () {
      const stats = BearStats(hunger: 100, mood: 100);
      const decay = BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 0);

      final next = decay.apply(stats, const Duration(seconds: 10));

      expect(next.hunger, 90);
      expect(next.mood, 100);
    });

    test('считает дробные интервалы, а не только целые секунды', () {
      const stats = BearStats(hunger: 100);
      const decay = BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 0);

      final next = decay.apply(stats, const Duration(milliseconds: 500));

      expect(next.hunger, closeTo(99.5, 1e-9));
    });

    test('при голоде ниже 25 настроение падает вдвое быстрее', () {
      const decay = BearDecayConfig(hungerPerSecond: 0, moodPerSecond: 1);
      const fed = BearStats(hunger: 100, mood: 100);
      const hungry = BearStats(hunger: 10, mood: 100);

      const elapsed = Duration(seconds: 10);

      expect(decay.apply(fed, elapsed).mood, 90);
      expect(decay.apply(hungry, elapsed).mood, 80);
    });

    test('не уходит ниже нуля', () {
      const stats = BearStats(hunger: 1, mood: 1);
      const decay = BearDecayConfig(hungerPerSecond: 10, moodPerSecond: 10);

      final next = decay.apply(stats, const Duration(seconds: 100));

      expect(next.hunger, BearStats.min);
      expect(next.mood, BearStats.min);
    });

    test('нулевой и отрицательный интервал игнорируются', () {
      const stats = BearStats(hunger: 50, mood: 50);
      const decay = BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 1);

      expect(decay.apply(stats, Duration.zero), stats);
      expect(decay.apply(stats, const Duration(seconds: -5)), stats);
    });
  });

  group('BearGrowthStage', () {
    test('round-trip через riveValue', () {
      for (final stage in BearGrowthStage.values) {
        expect(BearGrowthStage.fromRiveValue(stage.riveValue), stage);
      }
    });

    test('неизвестное значение из рига откатывается на cub', () {
      expect(BearGrowthStage.fromRiveValue(99), BearGrowthStage.cub);
    });
  });
}
