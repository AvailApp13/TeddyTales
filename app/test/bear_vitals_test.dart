import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_bear/teddy_bear.dart';

void main() {
  group('BearVitals', () {
    test('стартует со значениями из спецификации рига', () {
      final vitals = BearVitals.initial();
      for (final number in BearNumber.values) {
        expect(vitals[number], number.initial, reason: number.path);
      }
    });

    test('клампит значения в объявленный диапазон', () {
      final vitals = BearVitals({
        BearNumber.food: 999,
        BearNumber.love: -50,
      });
      expect(vitals[BearNumber.food], BearNumber.food.max);
      expect(vitals[BearNumber.love], BearNumber.love.min);
    });

    test('careIndex — среднее пяти показателей ухода', () {
      final vitals = BearVitals({
        BearNumber.food: 100,
        BearNumber.hygiene: 50,
        BearNumber.sleep: 50,
        BearNumber.play: 50,
        BearNumber.love: 0,
      });
      expect(vitals.careIndex, closeTo(50, 1e-9));
    });

    test('затухание пропорционально прошедшему времени', () {
      final start = BearVitals.initial();
      final rate = BearTuning.decayPerSecond[BearNumber.food]!;
      final after = start.decayed(const Duration(seconds: 10));
      expect(
        after[BearNumber.food],
        closeTo(start[BearNumber.food] - rate * 10, 1e-6),
      );
    });

    test('один шаг в 10с равен десяти шагам по 1с', () {
      final start = BearVitals.initial();
      final oneStep = start.decayed(const Duration(seconds: 10));

      var stepwise = start;
      for (var i = 0; i < 10; i++) {
        stepwise = stepwise.decayed(const Duration(seconds: 1));
      }
      for (final meter in BearVitals.careMeters) {
        expect(stepwise[meter], closeTo(oneStep[meter], 1e-6), reason: meter.path);
      }
    });

    test('затухание не опускает показатель ниже безопасного предела (КП 6.3)', () {
      var vitals = BearVitals.initial();
      // Заведомо дольше любого разумного отсутствия.
      vitals = vitals.decayed(const Duration(days: 30));
      for (final meter in BearVitals.careMeters) {
        expect(
          vitals[meter],
          greaterThanOrEqualTo(meter.safeFloor),
          reason: '${meter.path} пробил безопасный предел',
        );
      }
    });

    test('нулевой и отрицательный интервал ничего не меняют', () {
      final start = BearVitals.initial();
      expect(start.decayed(Duration.zero), start);
      expect(start.decayed(const Duration(seconds: -5)), start);
    });

    test('кормление поднимает еду, но не выше максимума', () {
      final hungry = BearVitals({BearNumber.food: 10});
      final fed = hungry.boosted(BearTrigger.feed);
      final boost = BearTuning.boost[BearTrigger.feed]![BearNumber.food]!;
      expect(fed[BearNumber.food], closeTo(10 + boost, 1e-9));

      final full = BearVitals({BearNumber.food: 100}).boosted(BearTrigger.feed);
      expect(full[BearNumber.food], BearNumber.food.max);
    });

    test('триггер без прибавки оставляет показатели как есть', () {
      final start = BearVitals.initial();
      expect(start.boosted(BearTrigger.grow), start);
    });

    test('настроение выводится из показателей с приоритетом голода', () {
      expect(BearVitals({BearNumber.food: 5}).mood, BearMood.hungry);
      expect(
        BearVitals({BearNumber.food: 100, BearNumber.sleep: 5}).mood,
        BearMood.sleepy,
      );
      expect(
        BearVitals({
          BearNumber.food: 100,
          BearNumber.sleep: 100,
          BearNumber.hygiene: 5,
        }).mood,
        BearMood.messy,
      );
      expect(
        BearVitals({
          for (final m in BearVitals.careMeters) m: 100,
        }).mood,
        BearMood.happy,
      );
    });

    test('normalized возвращает долю диапазона', () {
      final vitals = BearVitals({BearNumber.food: 25});
      expect(vitals.normalized(BearNumber.food), closeTo(0.25, 1e-9));
    });
  });

  group('контракт рига', () {
    test('каждое перечисление парсится из своего значения', () {
      for (final stage in BearStage.values) {
        expect(BearStage.fromWire(stage.wireName), stage);
      }
      for (final trait in BearTrait.values) {
        expect(BearTrait.fromWire(trait.wireName), trait);
      }
      for (final mood in BearMood.values) {
        expect(BearMood.fromWire(mood.wireName), mood);
      }
      expect(BearStage.fromWire('нет такой стадии'), isNull);
    });

    test('пять показателей ухода из КП 6.1 на месте', () {
      expect(
        BearVitals.careMeters.map((m) => m.path).toSet(),
        {'food', 'hygiene', 'sleep', 'play', 'love'},
      );
    });

    test('каждый триггер с прибавкой ссылается на существующий показатель', () {
      for (final entry in BearTuning.boost.entries) {
        for (final target in entry.value.keys) {
          expect(BearNumber.values, contains(target));
        }
      }
    });

    test('безопасный предел лежит внутри диапазона показателя', () {
      for (final number in BearNumber.values) {
        expect(number.safeFloor, greaterThanOrEqualTo(number.min));
        expect(number.safeFloor, lessThanOrEqualTo(number.max));
      }
    });
  });
}
