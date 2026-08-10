import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_initiative.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_state.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

void main() {
  const policy = BearInitiativePolicy();

  group('BearInitiativePolicy — нужда', () {
    test('просевшая еда → просит покормить', () {
      const state = BearState(
        stage: BearStage.adult,
        stats: BearCareStats(food: 20),
      );

      expect(
        policy.propose(state),
        const BearInitiative(BearAction.feed, BearInitiativeReason.need),
      );
    });

    test('из нескольких нужд берётся самая острая', () {
      const state = BearState(
        stage: BearStage.adult,
        stats: BearCareStats(food: 35, hygiene: 5, sleep: 20),
      );

      expect(policy.propose(state)?.action, BearAction.wash);
    });

    test('недоступное на стадии действие пропускается', () {
      // Умывание есть только со стадии 2 (act_wash 2–5).
      const state = BearState(
        stage: BearStage.newborn,
        stats: BearCareStats(hygiene: 5, sleep: 20),
      );

      expect(policy.propose(state)?.action, BearAction.sleep);
    });

    test('нужда важнее характера', () {
      const state = BearState(
        stage: BearStage.adult,
        trait: BearTrait.calm,
        stats: BearCareStats(food: 10),
      );

      final initiative = policy.propose(state)!;
      expect(initiative.reason, BearInitiativeReason.need);
      expect(initiative.action, BearAction.feed);
    });
  });

  group('BearInitiativePolicy — характер', () {
    test('когда всё хорошо, предложение идёт от характера', () {
      const base = BearState(stage: BearStage.adult);

      expect(
        policy.propose(base.copyWith(trait: BearTrait.active))?.action,
        BearAction.play,
      );
      expect(
        policy.propose(base.copyWith(trait: BearTrait.curious))?.action,
        BearAction.learn,
      );
      expect(
        policy.propose(base.copyWith(trait: BearTrait.affectionate))?.action,
        BearAction.pet,
      );
      expect(
        policy.propose(base.copyWith(trait: BearTrait.calm))?.action,
        BearAction.sleep,
      );
    });

    test('самостоятельный и замкнутый молчат, когда всё в порядке', () {
      const base = BearState(stage: BearStage.adult);

      expect(policy.propose(base.copyWith(trait: BearTrait.independent)),
          isNull);
      expect(policy.propose(base.copyWith(trait: BearTrait.reserved)), isNull);
    });

    test('но о реальной нужде скажут и они', () {
      const state = BearState(
        stage: BearStage.adult,
        trait: BearTrait.reserved,
        stats: BearCareStats(food: 10),
      );

      expect(policy.propose(state)?.action, BearAction.feed);
    });

    test('пожелание, недоступное на стадии, не предлагается', () {
      // Обучение открывается только у подрастающего.
      const state = BearState(
        stage: BearStage.crawling,
        trait: BearTrait.curious,
      );

      expect(policy.propose(state), isNull);
    });

    test('частота зависит от характера (КП 7.4)', () {
      expect(
        policy.cooldownFor(BearTrait.active),
        lessThan(policy.cooldownFor(BearTrait.calm)),
      );
      expect(
        policy.cooldownFor(BearTrait.calm),
        lessThan(policy.cooldownFor(BearTrait.reserved)),
      );
    });
  });

  group('Доступность действий по стадиям', () {
    test('уход за новорождённым ограничен', () {
      const stage = BearStage.newborn;

      expect(BearAction.feed.isAvailableOn(stage), isTrue);
      expect(BearAction.sleep.isAvailableOn(stage), isTrue);
      expect(BearAction.wake.isAvailableOn(stage), isTrue);
      expect(BearAction.pet.isAvailableOn(stage), isTrue);
      expect(BearAction.wash.isAvailableOn(stage), isFalse);
      expect(BearAction.play.isAvailableOn(stage), isFalse);
    });

    test('у взрослого доступно всё', () {
      for (final action in BearAction.values) {
        expect(action.isAvailableOn(BearStage.adult), isTrue);
      }
    });
  });
}
