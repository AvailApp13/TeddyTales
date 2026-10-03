import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_life.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';

void main() {
  const policy = BearLifePolicy();
  const hold = Duration(seconds: 30);
  BearCareStats stats({
    double food = 90,
    double sleep = 90,
    double hygiene = 90,
    double play = 90,
    double love = 90,
  }) => BearCareStats(
    food: food,
    hygiene: hygiene,
    sleep: sleep,
    play: play,
    love: love,
  );

  group('BearLifePolicy', () {
    test('нужда ниже 30, отпускает только выше 38', () {
      expect(
        policy.resolve(stats(food: 29), BearMood.normal, hold),
        BearMood.hungry,
      );
      expect(
        policy.resolve(stats(food: 34), BearMood.hungry, hold),
        BearMood.hungry,
      );
      // отпустило: среднее 79,8 — обычное, не радость
      expect(
        policy.resolve(stats(food: 39), BearMood.hungry, hold),
        BearMood.normal,
      );
      expect(
        policy.resolve(stats(food: 34), BearMood.normal, hold),
        BearMood.normal,
      );
    });

    test('самая острая нужда побеждает', () {
      expect(
        policy.resolve(stats(food: 25, sleep: 10), BearMood.hungry, hold),
        BearMood.sleepy,
      );
    });

    test('грусть и радость с гистерезисом', () {
      expect(
        policy.resolve(
          stats(food: 30, sleep: 30, hygiene: 30, play: 30, love: 30),
          BearMood.normal,
          hold,
        ),
        BearMood.sad,
      );
      expect(
        policy.resolve(
          stats(food: 45, sleep: 45, hygiene: 45, play: 45, love: 45),
          BearMood.sad,
          hold,
        ),
        BearMood.sad,
      );
      expect(
        policy.resolve(
          stats(food: 45, sleep: 45, hygiene: 45, play: 45, love: 45),
          BearMood.normal,
          hold,
        ),
        BearMood.normal,
      );
      expect(policy.resolve(stats(), BearMood.normal, hold), BearMood.happy);
      expect(
        policy.resolve(
          stats(food: 75, sleep: 75, hygiene: 75, play: 75, love: 75),
          BearMood.happy,
          hold,
        ),
        BearMood.happy,
      );
      expect(
        policy.resolve(
          stats(food: 70, sleep: 70, hygiene: 70, play: 70, love: 70),
          BearMood.happy,
          hold,
        ),
        BearMood.normal,
      );
    });

    test('состояние держится не меньше 20 с', () {
      expect(
        policy.resolve(
          stats(food: 10),
          BearMood.normal,
          const Duration(seconds: 5),
        ),
        BearMood.normal,
      );
    });
  });
}
