import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_mood_policy.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

void main() {
  const policy = BearMoodPolicy();

  group('BearMoodPolicy', () {
    test('всё в порядке и уход высокий → happy', () {
      const stats = BearCareStats();

      expect(policy.resolve(stats, BearStage.adult), BearMood.happy);
    });

    test('средний уход → normal', () {
      const stats = BearCareStats(
        food: 60,
        hygiene: 60,
        sleep: 60,
        play: 60,
        love: 60,
      );

      expect(policy.resolve(stats, BearStage.adult), BearMood.normal);
    });

    test('низкая еда → hungry', () {
      const stats = BearCareStats(food: 10);

      expect(policy.resolve(stats, BearStage.adult), BearMood.hungry);
    });

    test('низкий сон → sleepy', () {
      const stats = BearCareStats(sleep: 10);

      expect(policy.resolve(stats, BearStage.adult), BearMood.sleepy);
    });

    test('низкая гигиена → dirty', () {
      const stats = BearCareStats(hygiene: 10);

      expect(policy.resolve(stats, BearStage.adult), BearMood.dirty);
    });

    test('побеждает самый низкий из показателей с собственным idle', () {
      const stats = BearCareStats(food: 25, hygiene: 5, sleep: 15);

      expect(policy.resolve(stats, BearStage.adult), BearMood.dirty);
    });

    test('dirty недоступен на стадиях 1–2 — берётся следующий кандидат', () {
      const stats = BearCareStats(hygiene: 5, sleep: 15);

      // idle_dirty есть только для стадий 3–5 (раздел 7.1 ТЗ аниматора).
      expect(policy.resolve(stats, BearStage.crawling), BearMood.sleepy);
      expect(policy.resolve(stats, BearStage.firstSteps), BearMood.dirty);
    });

    test('только грязный и стадия ранняя → падаем в общий фон, не в dirty', () {
      const stats = BearCareStats(hygiene: 5);

      final mood = policy.resolve(stats, BearStage.newborn);

      // Один просевший показатель из пяти не портит среднее (81), поэтому
      // мишка остаётся радостным. Малыш и не должен выглядеть неухоженным —
      // клипа idle_dirty для стадий 1–2 в риге нет.
      expect(mood, isNot(BearMood.dirty));
      expect(mood, BearMood.happy);
    });

    test('общий низкий уход без острых нужд → sad', () {
      const stats = BearCareStats(
        food: 35,
        hygiene: 35,
        sleep: 35,
        play: 35,
        love: 35,
      );

      expect(policy.resolve(stats, BearStage.adult), BearMood.sad);
    });

    test('игра и любовь своих idle не имеют — только через среднее', () {
      const stats = BearCareStats(play: 0, love: 0);

      final mood = policy.resolve(stats, BearStage.adult);

      expect(mood, isNot(BearMood.hungry));
      expect(mood, BearMood.normal); // среднее 60
    });

    test('пороги настраиваются', () {
      const strict = BearMoodPolicy(happyThreshold: 100);
      const stats = BearCareStats();

      expect(policy.resolve(stats, BearStage.adult), BearMood.happy);
      expect(strict.resolve(stats, BearStage.adult), BearMood.happy);

      const almost = BearCareStats(food: 90);
      expect(strict.resolve(almost, BearStage.adult), BearMood.normal);
    });
  });

  group('BearMood.isAvailableOn', () {
    test('dirty только со стадии 3', () {
      expect(BearMood.dirty.isAvailableOn(BearStage.newborn), isFalse);
      expect(BearMood.dirty.isAvailableOn(BearStage.crawling), isFalse);
      expect(BearMood.dirty.isAvailableOn(BearStage.firstSteps), isTrue);
      expect(BearMood.dirty.isAvailableOn(BearStage.adult), isTrue);
    });

    test('остальные состояния доступны на всех стадиях', () {
      for (final mood in BearMood.values.where((m) => m != BearMood.dirty)) {
        for (final stage in BearStage.values) {
          expect(mood.isAvailableOn(stage), isTrue);
        }
      }
    });
  });

  group('Значения входов совпадают с разделом 8.1 ТЗ', () {
    test('mood 0–5 в заданном порядке', () {
      expect(BearMood.normal.riveValue, 0);
      expect(BearMood.happy.riveValue, 1);
      expect(BearMood.sad.riveValue, 2);
      expect(BearMood.hungry.riveValue, 3);
      expect(BearMood.sleepy.riveValue, 4);
      expect(BearMood.dirty.riveValue, 5);
    });

    test('stage 1–5', () {
      expect(BearStage.values.map((s) => s.riveValue), [1, 2, 3, 4, 5]);
    });

    test('trait 0–5, активный первый, замкнутый последний', () {
      expect(BearTrait.values.map((t) => t.riveValue), [0, 1, 2, 3, 4, 5]);
      expect(BearTrait.active.riveValue, 0);
      expect(BearTrait.reserved.riveValue, 5);
    });

    test('skin 0 мальчик, 1 девочка', () {
      expect(BearSkin.boy.riveValue, 0);
      expect(BearSkin.girl.riveValue, 1);
    });

    test('имена входов не переименованы случайно', () {
      expect(BearRigSpec.stateMachine, 'bear_main');
      expect(BearRigSpec.artboard, 'bear_main');
      expect(BearRigSpec.trgEmoSurprise, 'trg_emo_surpr');
      expect(BearRigSpec.isWalking, 'is_walking');
      expect(BearRigSpec.triggers, hasLength(11));
    });
  });
}
