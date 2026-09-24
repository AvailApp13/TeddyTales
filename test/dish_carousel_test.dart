import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/dish_carousel.dart';
import 'package:teddy_tales/widgets/kitchen_scene.dart';

/// Готовые блюда на столе кухни (заказчик 24.09): дуга, прокрутка пальцем
/// по кругу, покупка — нажатием на блюдо перед мишкой. Ни одно блюдо не
/// закрывает лапки.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dishes = FoodCatalog.dishes;
  final pasta = dishes.indexWhere((d) => d.id == 'pasta');

  // Кадр кухни 941 × 1672 в уменьшенном виде — влезает в тестовый экран.
  const frame = Size(300, 533);

  group('место на дуге', () {
    test('по кругу: за последним снова первое', () {
      expect(DishArcGeometry.slot(0, 0, 10), 0);
      expect(DishArcGeometry.slot(1, 0, 10), 1);
      expect(DishArcGeometry.slot(9, 0, 10), -1);
      expect(DishArcGeometry.slot(0, 9, 10), 1);
      expect(DishArcGeometry.slot(9, 9.5, 10), -0.5);
      expect(DishArcGeometry.slot(0, 9.5, 10), 0.5);
    });

    test('сдвиг на целый круг ничего не меняет', () {
      for (var i = 0; i < 10; i++) {
        expect(
          DishArcGeometry.slot(i, 3.25 + 10, 10),
          closeTo(DishArcGeometry.slot(i, 3.25, 10), 1e-9),
        );
      }
    });

    test('блюдо перед мишкой на 15–20 % меньше первого, миски — ещё', () {
      const size = Size(941, 1672);
      final mid = DishArcGeometry.plate('pasta', 0, size);
      final ratio = mid.width / size.width / 0.261;
      expect(ratio, inInclusiveRange(0.80, 0.85));
      // Боковые — на 6 % меньше первых 0.168.
      expect(
        DishArcGeometry.plate('pasta', 1, size).width / size.width,
        closeTo(0.168 * 0.94, 0.001),
      );
      for (final bowl in ['soup', 'yogurt', 'porridge']) {
        expect(DishArcGeometry.plate(bowl, 0, size).width, lessThan(mid.width));
      }
    });

    test('едет к мишке по столу и только у края поднимается', () {
      const size = Size(941, 1672);
      final rest = DishArcGeometry.plate('pasta', 0, size).bottom;
      // Полпути — ещё на столе, на одной высоте с центральным.
      expect(DishArcGeometry.plate('pasta', 0.5, size).bottom, rest);
      // К краю — поднялось.
      expect(DishArcGeometry.plate('pasta', 1, size).bottom, lessThan(rest));
      // Подъём плавный: без скачков между соседними положениями.
      var prev = rest;
      for (var i = 1; i <= 100; i++) {
        final b = DishArcGeometry.plate('pasta', i / 100, size).bottom;
        expect((b - prev).abs(), lessThan(size.height * 0.004));
        prev = b;
      }
    });
  });

  group('лапки не закрыты', () {
    Future<(ByteData, int, int)> rgba(String asset) async {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData();
      return (bytes!, image.width, image.height);
    }

    int alpha((ByteData, int, int) img, int x, int y) {
      final (bytes, w, h) = img;
      if (x < 0 || y < 0 || x >= w || y >= h) return 0;
      return bytes.getUint8((y * w + x) * 4 + 3);
    }

    test('ни одно блюдо в покое не заходит на лапки', () async {
      const size = Size(941, 1672);
      final paws = [
        (KitchenScene.pawLeft, await rgba('assets/rooms/kitchen/paw_left.png')),
        (
          KitchenScene.pawRight,
          await rgba('assets/rooms/kitchen/paw_right.png'),
        ),
      ];

      for (final dish in dishes) {
        final img = await rgba(dish.image);
        final (_, iw, ih) = img;
        for (final s in [0.0, 1.0, -1.0]) {
          final rect = DishArcGeometry.plate(dish.id, s, size);
          // Картинка вписана по ширине и прижата к низу квадрата.
          final scale = rect.width / iw;
          final top = rect.bottom - ih * scale;
          var overlap = 0;
          for (final (box, paw) in paws) {
            final (_, pw, ph) = paw;
            final r = Rect.fromLTWH(
              box.left * size.width,
              box.top * size.height,
              box.width * size.width,
              box.height * size.height,
            );
            for (var y = r.top.floor(); y < r.bottom.ceil(); y++) {
              for (var x = r.left.floor(); x < r.right.ceil(); x++) {
                final pa = alpha(
                  paw,
                  ((x - r.left) / r.width * pw).floor(),
                  ((y - r.top) / r.height * ph).floor(),
                );
                if (pa <= 60) continue;
                final da = alpha(
                  img,
                  ((x - rect.left) / scale).floor(),
                  ((y - top) / scale).floor(),
                );
                if (da > 60) overlap++;
              }
            }
          }
          expect(overlap, 0, reason: '${dish.id} при s=$s');
        }
      }
    });
  });

  group('на столе', () {
    late List<Dish> bought;
    late int elsewhere;
    late DishArc arc;
    late int closed;

    setUp(() {
      bought = [];
      elsewhere = 0;
      closed = 0;
    });

    tearDown(() => arc.dispose());

    Future<void> pump(WidgetTester tester, {int? initial}) async {
      arc = DishArc(count: dishes.length, initial: initial ?? pasta);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: frame,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DishPlates(arc: arc, dishes: dishes),
                    ),
                    Positioned.fill(
                      child: DishCarousel(
                        arc: arc,
                        dishes: dishes,
                        onBuy: bought.add,
                        onTapElsewhere: () => elsewhere++,
                        onClose: () => closed++,
                      ),
                    ),
                  ],
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
      frame.width * DishArcGeometry.centerX,
      frame.height * DishArcGeometry.centerBottom - 25,
    );

    Offset sideDish(int side) => Offset(
      frame.width * (DishArcGeometry.centerX + DishArcGeometry.step * side),
      frame.height * DishArcGeometry.sideBottom - 18,
    );

    testWidgets('паста перед мишкой, соседи по бокам, цена — на табло', (
      tester,
    ) async {
      await pump(tester);
      expect(current(tester), 'pasta');
      expect(find.byKey(const ValueKey('dish-pasta')), findsOneWidget);
      expect(find.byKey(ValueKey('dish-${dishes[pasta - 1].id}')), findsOne);
      expect(find.byKey(ValueKey('dish-${dishes[pasta + 1].id}')), findsOne);
      // Одно табло: название, описание и цена блюда перед мишкой.
      expect(find.byKey(const ValueKey('dish-price-board')), findsOneWidget);
      final board = find.byKey(const ValueKey('dish-board-pasta'));
      expect(board, findsOneWidget);
      expect(
        find.descendant(
          of: board,
          matching: find.textContaining('Паста', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: board,
          matching: find.textContaining(
            'с томатным соусом',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: board, matching: find.text('12')),
        findsOneWidget,
      );
      // Под самими блюдами цен больше нет.
      expect(find.text('${dishes[pasta - 1].price}'), findsNothing);
    });

    testWidgets('табло меняет надпись вслед за прокруткой', (tester) async {
      await pump(tester);
      // Полпути к омлету: на табло катятся обе надписи.
      arc.offset = pasta + 0.5;
      await tester.pump();
      expect(find.byKey(const ValueKey('dish-board-pasta')), findsOneWidget);
      expect(
        find.byKey(ValueKey('dish-board-${dishes[pasta + 1].id}')),
        findsOneWidget,
      );
      // Доехали — осталась одна, новая.
      arc.offset = pasta + 1.0;
      await tester.pump();
      expect(find.byKey(const ValueKey('dish-board-pasta')), findsNothing);
      expect(
        find.byKey(ValueKey('dish-board-${dishes[pasta + 1].id}')),
        findsOneWidget,
      );
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
      final stepPx = frame.width * DishArcGeometry.step;

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

    testWidgets('доводка мягкая: блюдо доезжает, а не щёлкает', (tester) async {
      await pump(tester);
      await tester.tapAt(sideDish(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Через 200 мс блюдо ещё в пути.
      expect(arc.offset, greaterThan(pasta));
      expect(arc.offset, lessThan(pasta + 1));
      await tester.pumpAndSettle();
      expect(arc.offset, pasta + 1);
    });

    testWidgets('нажатие сразу после свайпа — окно покупки нового блюда', (
      tester,
    ) async {
      await pump(tester);
      await tester.timedDrag(
        find.byKey(const ValueKey('dish-carousel-band')),
        // Шаг плюс порог, с которого жест считается свайпом.
        Offset(-frame.width * DishArcGeometry.step * 0.8 - 18, 0),
        const Duration(milliseconds: 300),
      );
      // Блюдо ещё доезжает — а человек уже жмёт на него.
      await tester.pump(const Duration(milliseconds: 100));
      expect(arc.offset, isNot(pasta + 1.0));
      await tester.tapAt(centerDish());
      await tester.pump();
      expect(bought.map((d) => d.id), [dishes[pasta + 1].id]);
      expect(elsewhere, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('крестик под табло убирает блюда', (tester) async {
      await pump(tester);
      final close = find.byKey(const ValueKey('dish-close'));
      expect(close, findsOneWidget);
      // Крестик ниже табло, по центру.
      final board = tester.getRect(
        find.byKey(const ValueKey('dish-price-board')),
      );
      final rect = tester.getRect(close);
      expect(rect.center.dx, closeTo(board.center.dx, 1));
      expect(rect.top, greaterThan(board.center.dy));
      await tester.tap(close);
      await tester.pump();
      expect(closed, 1);
      expect(bought, isEmpty);
      expect(elsewhere, 0);
    });

    testWidgets('дуга из меньшего числа блюд крутится по кругу', (
      tester,
    ) async {
      // Три блюда осталось — прокрутка всё так же замкнута.
      final three = [dishes[0], dishes[1], dishes[2]];
      arc = DishArc(count: 3, initial: 2);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: frame,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DishPlates(arc: arc, dishes: three),
                    ),
                    Positioned.fill(
                      child: DishCarousel(
                        arc: arc,
                        dishes: three,
                        onBuy: bought.add,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(current(tester), three[2].id);
      await tester.timedDrag(
        find.byKey(const ValueKey('dish-carousel-band')),
        Offset(-frame.width * DishArcGeometry.step, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(current(tester), three[0].id);
    });

    testWidgets('съели центральное — правые блюда съезжают на его место', (
      tester,
    ) async {
      await pump(tester);
      final key = ValueKey('dish-${dishes[pasta + 1].id}');
      final side = tester.getRect(find.byKey(key));
      // Пустое место ещё не закрыто: блюдо стоит там, где стояло справа,
      // хотя по счёту оно уже «перед мишкой».
      arc
        ..reset(count: dishes.length, current: pasta + 1)
        ..gap = 1;
      await tester.pump();
      expect(
        tester.getRect(find.byKey(key)).center.dx,
        closeTo(side.center.dx, 1),
      );
      // Закрылось — оно в центре.
      arc.gap = 0;
      await tester.pump();
      expect(
        tester.getRect(find.byKey(key)).center.dx,
        closeTo(frame.width * DishArcGeometry.centerX, 1),
      );
    });

    testWidgets('по кругу: с последнего блюда на первое', (tester) async {
      await pump(tester, initial: dishes.length - 1);
      expect(current(tester), dishes.last.id);
      // Первое уже видно справа — круг замкнут.
      expect(find.byKey(ValueKey('dish-${dishes.first.id}')), findsOneWidget);

      await tester.timedDrag(
        find.byKey(const ValueKey('dish-carousel-band')),
        Offset(-frame.width * DishArcGeometry.step, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(current(tester), dishes.first.id);
    });

    testWidgets('нажатие мимо блюд уходит мишке', (tester) async {
      await pump(tester);
      await tester.tapAt(
        Offset(
          frame.width * 0.5,
          frame.height * DishArcGeometry.bandBottom - 2,
        ),
      );
      await tester.pump();
      expect(bought, isEmpty);
      expect(elsewhere, 1);
    });
  });

  test('картинки всех блюд лежат в ассетах', () async {
    for (final dish in dishes) {
      final data = await rootBundle.load(dish.image);
      expect(data.lengthInBytes, greaterThan(1000), reason: dish.id);
    }
  });
}
