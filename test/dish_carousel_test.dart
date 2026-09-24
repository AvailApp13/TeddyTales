import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/widgets/dish_carousel.dart';

/// Готовые блюда на столе кухни (заказчик 24.09): дуга, прокрутка пальцем
/// по кругу, покупка — нажатием на блюдо перед мишкой.
void main() {
  const dishes = FoodCatalog.dishes;
  final pasta = dishes.indexWhere((d) => d.id == 'pasta');

  // Кадр кухни 941 × 1672 в уменьшенном виде — влезает в тестовый экран.
  const frame = Size(300, 533);

  group('место на дуге', () {
    test('по кругу: за последним снова первое', () {
      expect(DishCarousel.slot(0, 0, 10), 0);
      expect(DishCarousel.slot(1, 0, 10), 1);
      expect(DishCarousel.slot(9, 0, 10), -1);
      expect(DishCarousel.slot(0, 9, 10), 1);
      expect(DishCarousel.slot(9, 9.5, 10), -0.5);
      expect(DishCarousel.slot(0, 9.5, 10), 0.5);
    });

    test('сдвиг на целый круг ничего не меняет', () {
      for (var i = 0; i < 10; i++) {
        expect(
          DishCarousel.slot(i, 3.25 + 10, 10),
          closeTo(DishCarousel.slot(i, 3.25, 10), 1e-9),
        );
      }
    });
  });

  group('на столе', () {
    late List<Dish> bought;
    late int elsewhere;

    setUp(() {
      bought = [];
      elsewhere = 0;
    });

    Future<void> pump(WidgetTester tester, {int? initial}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: frame,
                child: DishCarousel(
                  dishes: dishes,
                  initial: initial ?? pasta,
                  onBuy: bought.add,
                  onTapElsewhere: () => elsewhere++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    String current(WidgetTester tester) {
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>()
          .where((l) => dishes.any((d) => d.id == l));
      return labels.single;
    }

    Offset centerDish() => Offset(
      frame.width * DishCarousel.centerX,
      frame.height * DishCarousel.centerBottom - 25,
    );

    Offset sideDish(int side) => Offset(
      frame.width * (DishCarousel.centerX + DishCarousel.step * side),
      frame.height * DishCarousel.sideBottom - 18,
    );

    testWidgets('паста перед мишкой, соседи по бокам, у каждого цена', (
      tester,
    ) async {
      await pump(tester);
      expect(current(tester), 'pasta');
      expect(find.byKey(const ValueKey('dish-pasta')), findsOneWidget);
      expect(find.byKey(ValueKey('dish-${dishes[pasta - 1].id}')), findsOne);
      expect(find.byKey(ValueKey('dish-${dishes[pasta + 1].id}')), findsOne);
      expect(find.text('${dishes[pasta].price}'), findsWidgets);
    });

    testWidgets('центральное блюдо стоит ниже и крупнее боковых', (
      tester,
    ) async {
      await pump(tester);
      final mid = tester.getRect(find.byKey(const ValueKey('dish-pasta')));
      final side = tester.getRect(
        find.byKey(ValueKey('dish-${dishes[pasta + 1].id}')),
      );
      expect(mid.width, greaterThan(side.width));
      expect(mid.bottom, greaterThan(side.bottom));
    });

    testWidgets('нажатие на блюдо перед мишкой — покупка', (tester) async {
      await pump(tester);
      await tester.tapAt(centerDish());
      await tester.pump();
      expect(bought.map((d) => d.id), ['pasta']);
    });

    testWidgets('нажатие на боковое подкатывает его, не покупая', (
      tester,
    ) async {
      await pump(tester);
      await tester.tapAt(sideDish(1));
      await tester.pumpAndSettle();
      expect(bought, isEmpty);
      expect(current(tester), dishes[pasta + 1].id);

      await tester.tapAt(centerDish());
      await tester.pump();
      expect(bought.single.id, dishes[pasta + 1].id);
    });

    testWidgets('свайп влево — следующее блюдо, вправо — предыдущее', (
      tester,
    ) async {
      await pump(tester);
      final band = find.byKey(const ValueKey('dish-carousel-band'));
      final stepPx = frame.width * DishCarousel.step;

      await tester.timedDrag(
        band,
        Offset(-stepPx, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(current(tester), dishes[pasta + 1].id);

      await tester.timedDrag(
        band,
        Offset(stepPx * 2, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(current(tester), dishes[pasta - 1].id);
    });

    testWidgets('короткий бросок докручивает на одно блюдо', (tester) async {
      await pump(tester);
      // Быстрый короткий взмах: меньше половины шага, но с разгона.
      await tester.timedDrag(
        find.byKey(const ValueKey('dish-carousel-band')),
        const Offset(-40, 0),
        const Duration(milliseconds: 40),
      );
      await tester.pumpAndSettle();
      expect(current(tester), dishes[pasta + 1].id);
    });

    testWidgets('по кругу: с последнего блюда на первое', (tester) async {
      await pump(tester, initial: dishes.length - 1);
      expect(current(tester), dishes.last.id);
      // Первое уже видно справа — круг замкнут.
      expect(find.byKey(ValueKey('dish-${dishes.first.id}')), findsOneWidget);

      await tester.timedDrag(
        find.byKey(const ValueKey('dish-carousel-band')),
        Offset(-frame.width * DishCarousel.step, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(current(tester), dishes.first.id);
    });

    testWidgets('нажатие мимо блюд уходит мишке', (tester) async {
      await pump(tester);
      await tester.tapAt(
        Offset(frame.width * 0.5, frame.height * DishCarousel.bandBottom - 4),
      );
      await tester.pump();
      expect(bought, isEmpty);
      expect(elsewhere, 1);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('картинки всех блюд лежат в ассетах', () async {
    for (final dish in dishes) {
      final data = await rootBundle.load(dish.image);
      expect(data.lengthInBytes, greaterThan(1000), reason: dish.id);
    }
  });
}
