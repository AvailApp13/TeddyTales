import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/audio/sounds.dart';
import 'package:teddy_tales/widgets/feed_burst.dart';

/// Пузырь сытости (заказчик 24.09): съеденное летит пузырьком с «+N» в
/// кружок «Еда»; до удара на экране прежние числа, после — проценты бегут
/// вверх, кружок подпрыгивает, монеты делают «у-у».
void main() {
  late FeedFx fx;
  late double food;
  late int coins;

  setUp(() {
    fx = FeedFx();
    food = 62;
    coins = 5009;
  });
  tearDown(() => fx.dispose());

  Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

  /// Прокрутить время кадрами по 1/60 с — как на телефоне.
  Future<void> run(WidgetTester tester, double seconds) async {
    final frames = (seconds * 60).round();
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  Future<void> pump(WidgetTester tester, {bool still = false}) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: 100,
                top: 80,
                child: SizedBox(key: fx.foodRing, width: 58, height: 58),
              ),
              Positioned.fill(
                child: FeedBurstLayer(
                  fx: fx,
                  liveFood: () => food,
                  liveCoins: () => coins,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Съели блюдо: в игре числа уже новые, на экране — прежние.
  void eat({int gain = 25, int price = 7}) {
    fx.hold(food: food, coins: coins);
    food += gain;
    coins -= price;
    fx.launch(
      FeedLaunch(
        origin: (size) => const Offset(200, 560),
        gain: gain,
        coins: -price,
      ),
    );
  }

  testWidgets('до удара — прежние числа, после — бегут к новым', (
    tester,
  ) async {
    await pump(tester);
    eat();
    await tester.pump();
    expect(fx.food(food), 62);
    expect(fx.coins(coins), 5009);

    // Летит — числа стоят.
    await tester.pump(secs(FeedBurstLayer.impactAt - 0.1));
    expect(fx.food(food), 62);
    expect(fx.coins(coins), 5009);
    expect(fx.foodBump, isNull);

    // Ударил — кружок подпрыгнул, монеты «у-у», под ними «−7».
    await tester.pump(secs(0.15));
    expect(fx.foodBump, isNotNull);
    expect(fx.coinBump, isNotNull);
    expect(fx.coinDelta, -7);
    expect(fx.counting, isTrue);

    // Числа бегут и приходят к настоящим.
    await tester.pump(secs(0.3));
    expect(fx.food(food), inExclusiveRange(62, 87));
    await tester.pump(secs(FeedBurstLayer.chip));
    await tester.pump(secs(0.5));
    expect(fx.food(food), 87);
    expect(fx.coins(coins), 5002);
    expect(fx.counting, isFalse);
    expect(fx.foodBump, isNull);
    expect(fx.coinChip, isNull);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('два пузыря подряд — каждый добавляет своё', (tester) async {
    await pump(tester);
    eat(gain: 12, price: 5);
    await tester.pump();
    await run(tester, 0.2);
    eat(gain: 20, price: 8);
    await tester.pump();
    // Первый ударил и досчитал, второй ещё летит: на экране прибавка
    // первого.
    await run(tester, FeedBurstLayer.impactAt - 0.2 + 0.05);
    await run(tester, 0.1);
    expect(fx.counting, isTrue);
    await run(tester, 0.05);
    expect(fx.food(food), inInclusiveRange(62, 74));
    await run(tester, 3);
    expect(fx.food(food), 94);
    expect(fx.coins(coins), 4996);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('пузырь не нужен — числа просто добегают', (tester) async {
    await pump(tester);
    fx.hold(food: food, coins: coins);
    food = 90;
    coins = 5018;
    await tester.pump();
    expect(fx.food(food), 62);
    fx.settle();
    await tester.pump();
    await tester.pump(secs(FeedBurstLayer.count + 0.1));
    expect(fx.food(food), 90);
    expect(fx.coins(coins), 5018);
    expect(fx.foodBump, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('без анимаций — сразу итог', (tester) async {
    await pump(tester, still: true);
    eat();
    await tester.pump();
    expect(fx.food(food), 87);
    expect(fx.coins(coins), 5002);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('звуки: «блоп», свист в полёте, у кружка «пуньк», перелив и '
      'монеты', (tester) async {
    final played = <Sfx>[];
    Sounds.debugOnPlay = played.add;
    addTearDown(() => Sounds.debugOnPlay = null);
    await pump(tester);
    eat();
    await tester.pump();
    await run(tester, 0.1);
    expect(played, [Sfx.bubbleBorn]);
    await run(tester, FeedBurstLayer.birth);
    expect(played, [Sfx.bubbleBorn, Sfx.bubbleFly]);
    await run(tester, FeedBurstLayer.impactAt - FeedBurstLayer.birth);
    expect(played, [
      Sfx.bubbleBorn,
      Sfx.bubbleFly,
      Sfx.bubblePop,
      Sfx.fill,
      Sfx.coinsSpend,
    ]);

    // Звук выключен в настройках — тишина.
    played.clear();
    Sounds.on.value = false;
    addTearDown(() => Sounds.on.value = true);
    eat();
    await tester.pump();
    await run(tester, 3);
    expect(played, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test('удар: подскок и затухание к покою', () {
    expect(FeedFx.bounce(0), 0);
    expect(FeedFx.bounce(0.12), closeTo(1, 0.01));
    expect(FeedFx.bounce(0.99).abs(), lessThan(0.05));
  });
}
