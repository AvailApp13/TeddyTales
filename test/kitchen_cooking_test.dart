import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/dish_carousel.dart';
import 'package:teddy_tales/widgets/kitchen_cooking.dart';

/// Готовка прямо на кухне (вариант A, заказчик 24.09): рецепт выбирается
/// на столе, продукты стоят под столом, нужный растворяется и закрашивает
/// кружок, не тот возвращается, а в конце блюдо появляется на столе.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Телефон 390 × 844, кадр кухни шире экрана — как в приложении.
  const screen = Size(390, 844);
  final frame = Rect.fromLTWH(-39, 6, 470.5, 836);

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Iterable<String> labels(WidgetTester tester) => tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((s) => s.properties.label)
      .whereType<String>();

  int filled(WidgetTester tester) =>
      labels(tester).where((l) => l == '●').length;

  group('рецепты на столе', () {
    testWidgets('сэндвич перед мишкой, на табло шаги и награда', (
      tester,
    ) async {
      phone(tester);
      const recipes = FoodCatalog.recipes;
      final arc = DishArc(
        count: recipes.length,
        initial: recipes.indexWhere((r) => r.id == 'sandwich'),
      );
      addTearDown(arc.dispose);
      final started = <Recipe>[];
      await tester.pumpWidget(
        app(
          Stack(
            children: [
              Positioned.fromRect(
                rect: frame,
                child: DishPlates<Recipe>(
                  arc: arc,
                  dishes: recipes,
                  board: recipeBoard,
                  tag: 'recipe',
                ),
              ),
              Positioned.fromRect(
                rect: frame,
                child: DishCarousel<Recipe>(
                  arc: arc,
                  dishes: recipes,
                  onBuy: started.add,
                  onClose: () {},
                  tag: 'recipe',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(DishPlates.appearDuration);

      expect(find.byKey(const ValueKey('recipe-sandwich')), findsOneWidget);
      expect(find.byKey(const ValueKey('recipe-price-board')), findsOneWidget);
      expect(labels(tester), contains('Сэндвич  3 шага'));
      expect(find.text('+9'), findsOneWidget);

      // Нажатие на рецепт перед мишкой — начать готовку.
      await tester.tapAt(
        frame.topLeft +
            Offset(
              frame.width * DishArcGeometry.centerX,
              frame.height * DishArcGeometry.centerBottom - 30,
            ),
      );
      await tester.pump();
      expect(started.map((r) => r.id), ['sandwich']);
      await tester.pumpAndSettle();
    });

    test('у всех рецептов есть картинка блюда', () {
      for (final recipe in FoodCatalog.recipes) {
        expect(recipe.image, endsWith('.webp'));
      }
      expect(
        FoodCatalog.recipeById('meat').image,
        'assets/rooms/kitchen/recipes/meat.webp',
      );
      expect(
        FoodCatalog.recipeById('fruit_salad').image,
        'assets/rooms/kitchen/dishes/fruit.webp',
      );
    });
  });

  group('готовка', () {
    late int wrong;
    late int closed;
    late List<Recipe> cooked;
    late List<Recipe> served;
    late int finished;

    setUp(() {
      wrong = 0;
      closed = 0;
      cooked = [];
      served = [];
      finished = 0;
    });

    Future<void> pump(WidgetTester tester, Recipe recipe) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          KitchenCooking(
            frame: frame,
            recipe: recipe,
            random: math.Random(7),
            onClose: () => closed++,
            onWrong: () => wrong++,
            onCooked: cooked.add,
            onServe: served.add,
            onFinished: () => finished++,
          ),
        ),
      );
      await tester.pump();
    }

    Finder item(String id) => find.byKey(ValueKey('cook-item-$id'));

    testWidgets('стол пустой, продукты под столом с подписями', (tester) async {
      final recipe = FoodCatalog.recipeById('sandwich');
      await pump(tester, recipe);

      expect(find.byKey(const ValueKey('cook-dish')), findsNothing);
      for (final ingredient in recipe.allChoices) {
        expect(item(ingredient.id), findsOneWidget);
        expect(labels(tester), contains('Положить: ${ingredient.title}'));
        // Продукт — под столом: ниже свисающей скатерти.
        final box = tester.getRect(item(ingredient.id));
        expect(box.top, greaterThan(frame.top + frame.height * 0.75));
        expect(box.bottom, lessThan(screen.height - 70));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(screen.width));
      }
      // На табло — название, три пустых кружка и награда.
      expect(find.text('Сэндвич'), findsOneWidget);
      expect(labels(tester).where((l) => l == '○').length, 3);
      expect(find.text('+9'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('не тот продукт возвращается, мишка мотает головой', (
      tester,
    ) async {
      final recipe = FoodCatalog.recipeById('sandwich');
      await pump(tester, recipe);

      await tester.tap(item('chocolate'));
      await tester.pump();
      expect(wrong, 1);
      await tester.pump(KitchenCooking.hop);
      await tester.pump(const Duration(milliseconds: 500));
      expect(item('chocolate'), findsOneWidget);
      expect(filled(tester), 0);

      // Правильный, но не по порядку, — тоже «не то»: порядок важен.
      await tester.tap(item('tomato'));
      await tester.pump();
      expect(wrong, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('нужный растворяется и закрашивает кружок', (tester) async {
      final recipe = FoodCatalog.recipeById('sandwich');
      await pump(tester, recipe);

      await tester.tap(item('bread'));
      await tester.pump();
      // Ещё в прыжке — виден.
      await tester.pump(const Duration(milliseconds: 200));
      expect(item('bread'), findsOneWidget);
      await tester.pump(KitchenCooking.hop);
      expect(item('bread'), findsNothing);
      expect(filled(tester), 1);
      expect(wrong, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('всё собрано — блюдо на столе, мишка ест, тарелка уходит', (
      tester,
    ) async {
      final recipe = FoodCatalog.recipeById('sandwich');
      await pump(tester, recipe);

      for (final step in recipe.steps) {
        await tester.tap(item(step.id));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(KitchenCooking.popDelay);
      expect(cooked.map((r) => r.id), ['sandwich']);
      await tester.pump(KitchenCooking.pop);
      final dish = find.byKey(const ValueKey('cook-dish-sandwich'));
      expect(dish, findsOneWidget);
      // На месте и в размере готового блюда перед мишкой.
      final place = DishArcGeometry.plate(
        'sandwich',
        0,
        frame.size,
      ).shift(frame.topLeft);
      expect(tester.getRect(find.byKey(const ValueKey('cook-dish'))), place);
      // Табло и продукты ушли, крестика нет.
      expect(find.byKey(const ValueKey('cook-close')), findsNothing);
      expect(find.byKey(const ValueKey('cook-board')), findsNothing);

      await tester.pump(KitchenCooking.serveDelay);
      expect(served.map((r) => r.id), ['sandwich']);
      expect(finished, 0);
      await tester.pump(KitchenCooking.eatHold);
      await tester.pump();
      await tester.pump(
        KitchenCooking.leave + const Duration(milliseconds: 50),
      );
      expect(finished, 1);
      expect(cooked, hasLength(1));
    });

    testWidgets('долго не выбирают — нужный продукт подсказывает', (
      tester,
    ) async {
      final recipe = FoodCatalog.recipeById('cookie');
      await pump(tester, recipe);
      final flour = find.descendant(
        of: find.byType(KitchenCooking),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.endsWith('/flour.webp'),
        ),
      );
      final rest = tester.getRect(flour).top;
      await tester.pump(KitchenCooking.idleHint);
      await tester.pump(const Duration(milliseconds: 550));
      expect(tester.getRect(flour).top, lessThan(rest));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('девять продуктов: подписи через одну ниже, ничего не '
        'налезает', (tester) async {
      final recipe = FoodCatalog.recipeById('veggie');
      expect(recipe.allChoices, hasLength(9));
      await pump(tester, recipe);

      final boxes = [
        for (final ingredient in recipe.allChoices)
          tester.getRect(item(ingredient.id)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      for (var i = 1; i < boxes.length; i++) {
        expect(boxes[i].left, greaterThanOrEqualTo(boxes[i - 1].right - 0.01));
      }
      // Каждое касание попадает в свой продукт: лишние — «не то»,
      // шаги по порядку закрашивают кружки.
      for (final extra in recipe.distractors) {
        await tester.tap(item(extra.id));
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(wrong, recipe.distractors.length);
      for (final step in recipe.steps) {
        await tester.tap(item(step.id));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(wrong, recipe.distractors.length);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(filled(tester), recipe.steps.length);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('крестик бросает готовку', (tester) async {
      await pump(tester, FoodCatalog.recipeById('fruit_salad'));
      await tester.tap(find.byKey(const ValueKey('cook-close')));
      await tester.pump();
      expect(closed, 1);
      expect(cooked, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
