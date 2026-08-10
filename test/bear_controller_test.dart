import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/bear/bear_rig_sink.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

/// Подставной риг. Существует ровно потому, что [BearController] не зависит от
/// Rive: нативные библиотеки `rive_native` в тестах не поднимаются.
class FakeRig implements BearRigSink {
  final List<BearStats> applied = <BearStats>[];
  final List<String> fired = <String>[];

  @override
  void applyStats(BearStats stats) => applied.add(stats);

  @override
  void fireTrigger(String name) => fired.add(name);
}

void main() {
  group('BearController', () {
    test('attachRig сразу заливает текущее состояние', () {
      final controller = BearController(
        initialStats: const BearStats(hunger: 30, mood: 70),
      );
      final rig = FakeRig();

      expect(controller.isRigAttached, isFalse);
      controller.attachRig(rig);

      expect(controller.isRigAttached, isTrue);
      expect(rig.applied.single.hunger, 30);
      expect(rig.applied.single.mood, 70);
    });

    test('feedBear поднимает сытость и дёргает триггер feed', () {
      final controller = BearController(
        initialStats: const BearStats(hunger: 10, mood: 50),
      );
      final rig = FakeRig();
      controller.attachRig(rig);

      controller.feedBear(amount: 25);

      expect(controller.stats.hunger, 35);
      expect(controller.stats.mood, 55);
      expect(rig.fired, [BearRigSpec.feedTrigger]);
    });

    test('petBear поднимает настроение и дёргает триггер pet', () {
      final controller = BearController(
        initialStats: const BearStats(mood: 50),
      );
      final rig = FakeRig();
      controller.attachRig(rig);

      controller.petBear(amount: 15);

      expect(controller.stats.mood, 65);
      expect(rig.fired, [BearRigSpec.petTrigger]);
    });

    test('tapBear дёргает триггер tap даже без изменения состояния', () {
      final controller = BearController(
        initialStats: const BearStats(mood: BearStats.max),
      );
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.tapBear();

      // Настроение уже на максимуме — значения не поехали, но реакция нужна.
      expect(rig.applied, isEmpty);
      expect(rig.fired, [BearRigSpec.tapTrigger]);
    });

    test('одинаковое значение не гоняется в риг повторно', () {
      final controller = BearController(
        initialStats: const BearStats(hunger: 50),
      );
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setHunger(50);

      expect(rig.applied, isEmpty);
      expect(notifications, 0);
    });

    test('detachRig прекращает отправку значений', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.detachRig();
      controller.setMood(10);

      expect(controller.isRigAttached, isFalse);
      expect(controller.stats.mood, 10);
      expect(rig.applied, isEmpty);
    });

    test('tick применяет decay и уведомляет слушателей', () {
      final controller = BearController(
        initialStats: const BearStats(hunger: 100, mood: 100),
        decay: const BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 1),
      );
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      controller.tick(const Duration(seconds: 10));

      expect(controller.stats.hunger, 90);
      expect(controller.stats.mood, 90);
      expect(rig.applied, hasLength(1));
    });

    test('startDecay ничего не запускает при выключенном decay', () {
      final controller = BearController(
        decay: const BearDecayConfig.disabled(),
      );

      controller.startDecay();

      expect(controller.isDecayRunning, isFalse);
      controller.dispose();
    });

    test('setDecayConfig на disabled останавливает таймер', () {
      final controller = BearController(
        decay: const BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 1),
      );
      controller.startDecay();
      expect(controller.isDecayRunning, isTrue);

      controller.setDecayConfig(const BearDecayConfig.disabled());

      expect(controller.isDecayRunning, isFalse);
      controller.dispose();
    });

    test('startDecay действительно тикает по таймеру', () {
      fakeAsync((async) {
        final controller = BearController(
          initialStats: const BearStats(hunger: 100, mood: 100),
          decay: const BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 0),
        );
        controller.startDecay(interval: const Duration(seconds: 1));

        async.elapse(const Duration(seconds: 5));

        expect(controller.stats.hunger, closeTo(95, 1e-6));
        controller.dispose();
      });
    });

    test('dispose останавливает decay', () {
      final controller = BearController(
        decay: const BearDecayConfig(hungerPerSecond: 1, moodPerSecond: 1),
      );
      controller.startDecay();

      controller.dispose();

      expect(controller.isDecayRunning, isFalse);
    });

    test('setStats заменяет состояние целиком', () {
      final controller = BearController();
      final rig = FakeRig();
      controller.attachRig(rig);
      rig.applied.clear();

      const restored = BearStats(
        hunger: 12,
        mood: 88,
        growthStage: BearGrowthStage.adult,
      );
      controller.setStats(restored);

      expect(controller.stats, restored);
      expect(rig.applied.single, restored);
    });
  });
}
