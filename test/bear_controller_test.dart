import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/bear/bear_rig_sink.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_state.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

/// Подставной риг. Существует ровно потому, что [BearController] не зависит от
/// Rive: нативные библиотеки `rive_native` в тестах не поднимаются.
class FakeRig implements BearRigSink {
  final List<BearState> applied = <BearState>[];
  final List<({String name, int? variant})> fired = [];

  List<String> get firedNames => fired.map((e) => e.name).toList();

  @override
  void applyState(BearState state) => applied.add(state);

  @override
  void fireTrigger(String name, {int? variant}) =>
      fired.add((name: name, variant: variant));
}

/// Генератор с предсказуемой последовательностью — чтобы проверять `variant`.
class _FixedRandom implements Random {
  _FixedRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  int nextInt(int max) => _values[_index++ % _values.length];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  group('BearController — связь с ригом', () {
    test('attachRig сразу заливает текущее состояние', () {
      final controller = BearController(
        initialState: const BearState(stats: BearCareStats(food: 30)),
      );
      final rig = FakeRig();

      expect(controller.isRigAttached, isFalse);
      controller.attachRig(rig);

      expect(controller.isRigAttached, isTrue);
      expect(rig.applied.single.stats.food, 30);
    });

    test('detachRig прекращает отправку команд', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.detachRig();
      controller.setTrait(BearTrait.calm);
      controller.showHappy();

      expect(controller.state.trait, BearTrait.calm);
      expect(rig.applied, isEmpty);
      expect(rig.fired, isEmpty);
    });

    test('одинаковое состояние не гоняется в риг повторно', () {
      final controller = BearController(
        initialState: const BearState(trait: BearTrait.curious),
      );
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setTrait(BearTrait.curious);

      expect(rig.applied, isEmpty);
      expect(notifications, 0);
    });
  });

  group('BearController — действия ухода', () {
    test('feedBear поднимает еду и дёргает trg_eat', () {
      final controller = BearController(
        initialState: const BearState(stats: BearCareStats(food: 10)),
      );
      final rig = FakeRig();
      controller.attachRig(rig);

      controller.feedBear(amount: 35);

      expect(controller.stats.food, 45);
      expect(rig.firedNames, [BearRigSpec.trgEat]);
    });

    test('каждое действие поднимает свой показатель и свой триггер', () {
      final controller = BearController(
        initialState: const BearState(
          stats: BearCareStats(
            food: 0,
            hygiene: 0,
            sleep: 0,
            play: 0,
            love: 0,
          ),
        ),
      );
      final rig = FakeRig();
      controller.attachRig(rig);

      controller
        ..washBear(amount: 40)
        ..putToSleep(amount: 50)
        ..playWithBear(amount: 30)
        ..petBear(amount: 20);

      expect(controller.stats.hygiene, 40);
      expect(controller.stats.sleep, 50);
      expect(controller.stats.play, 30);
      expect(controller.stats.love, 20);
      expect(rig.firedNames, [
        BearRigSpec.trgWash,
        BearRigSpec.trgSleep,
        BearRigSpec.trgPlay,
        BearRigSpec.trgPet,
      ]);
    });

    test('укладывание спать выключает ходьбу', () {
      final controller = BearController(
        initialState: const BearState(
          stage: BearStage.adult,
          isWalking: true,
        ),
      );

      controller.putToSleep();

      expect(controller.state.isWalking, isFalse);
    });

    test('wakeBear только дёргает триггер, показатели не трогает', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.wakeBear();

      expect(rig.firedNames, [BearRigSpec.trgWake]);
      expect(rig.applied, isEmpty);
    });

    test('эмоции дёргают свои триггеры', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);

      controller
        ..showHappy()
        ..showSad()
        ..showSurprise()
        ..showLove();

      expect(rig.firedNames, [
        BearRigSpec.trgEmoHappy,
        BearRigSpec.trgEmoSad,
        BearRigSpec.trgEmoSurprise,
        BearRigSpec.trgEmoLove,
      ]);
    });
  });

  group('BearController — вариативность (раздел 7.6)', () {
    test('кормление и поглаживание передают вариант', () {
      final controller = BearController(random: _FixedRandom([1, 0]));
      final rig = FakeRig();
      controller.attachRig(rig);

      controller
        ..feedBear()
        ..petBear();

      expect(rig.fired.map((e) => e.variant), [1, 0]);
    });

    test('действия без второго варианта его не передают', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);

      controller
        ..washBear()
        ..playWithBear()
        ..showHappy();

      expect(rig.fired.map((e) => e.variant), [null, null, null]);
    });
  });

  group('BearController — стадии роста', () {
    test('growUp сначала триггер, потом новое значение stage', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      final grown = controller.growUp();

      expect(grown, isTrue);
      expect(controller.state.stage, BearStage.crawling);
      // Раздел 8.2: смена стадии только через trg_stage_up, никогда мгновенно.
      expect(rig.firedNames, [BearRigSpec.trgStageUp]);
      expect(rig.applied.single.stage, BearStage.crawling);
    });

    test('взрослый дальше не растёт', () {
      final controller = BearController(
        initialState: const BearState(stage: BearStage.adult),
      );
      final rig = FakeRig();
      controller.attachRig(rig);

      expect(controller.growUp(), isFalse);
      expect(controller.state.stage, BearStage.adult);
      expect(rig.fired, isEmpty);
    });

    test('новорождённый не ходит', () {
      final controller = BearController();

      controller.setWalking(true);

      expect(controller.state.canWalk, isFalse);
      expect(controller.state.isWalking, isFalse);
    });

    test('смена стадии на новорождённого сбрасывает ходьбу', () {
      final controller = BearController(
        initialState: const BearState(
          stage: BearStage.adult,
          isWalking: true,
        ),
      );

      controller.setStage(BearStage.newborn);

      expect(controller.state.isWalking, isFalse);
    });
  });

  group('BearController — одежда', () {
    test('слоты независимы и зажимаются по диапазонам раздела 8.1', () {
      final controller = BearController();

      controller.setOutfit(
        const BearOutfit().copyWith(outfitId: 99, headwearId: 2),
      );

      expect(controller.state.outfit.outfitId, BearOutfit.maxOutfitId);
      expect(controller.state.outfit.headwearId, 2);
      expect(controller.state.outfit.shoesId, 0);
      expect(controller.state.outfit.accessoryId, 0);
    });
  });

  group('BearController — затухание показателей', () {
    test('tick применяет decay и уведомляет слушателей', () {
      final controller = BearController(
        decay: const BearDecayConfig(foodPerSecond: 1, floor: 0),
      );
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.tick(const Duration(seconds: 10));

      expect(controller.stats.food, 90);
      expect(rig.applied, hasLength(1));
    });

    test('startDecay ничего не запускает при выключенном decay', () {
      final controller = BearController(decay: const BearDecayConfig.disabled())
        ..startDecay();

      expect(controller.isDecayRunning, isFalse);
      controller.dispose();
    });

    test('startDecay тикает по таймеру', () {
      fakeAsync((async) {
        final controller = BearController(
          decay: const BearDecayConfig(foodPerSecond: 1, floor: 0),
        )..startDecay(interval: const Duration(seconds: 1));

        async.elapse(const Duration(seconds: 5));

        expect(controller.stats.food, closeTo(95, 1e-6));
        controller.dispose();
      });
    });

    test('setDecayConfig на disabled останавливает таймер', () {
      final controller = BearController(
        decay: const BearDecayConfig(foodPerSecond: 1),
      )..startDecay();
      expect(controller.isDecayRunning, isTrue);

      controller.setDecayConfig(const BearDecayConfig.disabled());

      expect(controller.isDecayRunning, isFalse);
      controller.dispose();
    });

    test('dispose останавливает decay', () {
      final controller = BearController(
        decay: const BearDecayConfig(foodPerSecond: 1),
      )..startDecay();

      controller.dispose();

      expect(controller.isDecayRunning, isFalse);
    });
  });

  group('BearController — восстановление состояния', () {
    test('restoreState заменяет состояние целиком', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      const restored = BearState(
        stats: BearCareStats(food: 12, love: 88),
        stage: BearStage.growing,
        trait: BearTrait.reserved,
        skin: BearSkin.girl,
        outfit: BearOutfit(outfitId: 3, headwearId: 1),
      );
      controller.restoreState(restored);

      expect(controller.state, restored);
      expect(rig.applied.single, restored);
    });
  });
}
