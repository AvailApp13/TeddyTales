import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/shop_screen.dart';

/// Магазин — стеклянной панелью снизу (заказчик 10.10).
///
/// Открывается списком категорий; «Назад» из категории ведёт к списку, а не
/// закрывает магазин; купленное сразу встаёт в комнату, и магазин остаётся
/// в той же категории; закрывает его крестик (или свайп вниз).
void main() {
  late BearController bear;
  late GameState game;

  final categories = find.byKey(const ValueKey('shop.categories'));
  final back = find.byKey(const ValueKey('shop.back'));
  final close = find.byKey(const ValueKey('shop.close'));

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: const {},
      placed: const {},
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  Future<List<ShopItem>> open(WidgetTester tester) async {
    final applied = <ShopItem>[];
    await tester.binding.setSurfaceSize(const Size(430, 880));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showShopSheet(context, game: game, onApplied: applied.add),
                child: const Text('магазин'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('магазин'));
    await tester.pumpAndSettle();
    return applied;
  }

  testWidgets('открывается списком категорий', (tester) async {
    await open(tester);

    expect(categories, findsOneWidget);
    expect(find.text('Мебель'), findsOneWidget);
    expect(find.text('Декор'), findsOneWidget);
    expect(find.text('Игрушки'), findsOneWidget);
    // На верхнем уровне «назад» некуда.
    expect(back, findsNothing);
    expect(close, findsOneWidget);
  });

  testWidgets('«Назад» из категории — к списку, магазин открыт', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Мебель'));
    await tester.pumpAndSettle();
    expect(categories, findsNothing);
    expect(back, findsOneWidget);

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(categories, findsOneWidget);
    expect(back, findsNothing);
  });

  testWidgets('купленное встаёт в комнату, магазин остаётся в категории', (
    tester,
  ) async {
    final applied = await open(tester);

    await tester.tap(find.text('Мебель'));
    await tester.pumpAndSettle();
    // Столик ниже по витрине — долистать до него.
    await tester.ensureVisible(find.text('Стол'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Стол'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Купить'));
    await tester.pumpAndSettle();

    expect(game.isOwned('table'), isTrue);
    // Столик — в угол справа: место по его размеру, и оно свободно.
    expect(game.slotOf('table'), 'nursery.corner_right');
    expect(applied.map((i) => i.id), ['table']);
    // Магазин не закрылся и не ушёл из категории.
    expect(back, findsOneWidget);
    expect(find.text('Стол'), findsOneWidget);
  });

  testWidgets('короткий раздел — сверху панели, а не посередине', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Декор'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Картины'));
    await tester.pumpAndSettle();

    // Витрина занимает панель до низа: две картины не висят посередине.
    final view = tester.getRect(find.byType(SingleChildScrollView));
    final sheet = tester.getRect(find.byType(ShopScreen));
    expect(view.bottom, moreOrLessEquals(sheet.bottom, epsilon: 1));
  });

  testWidgets('крестик закрывает магазин с любого уровня', (tester) async {
    await open(tester);

    await tester.tap(find.text('Игрушки'));
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(close, findsNothing);
    expect(find.text('магазин'), findsOneWidget);
  });

  testWidgets('тап мимо панели не закрывает, свайп вниз — закрывает', (
    tester,
  ) async {
    await open(tester);

    // Над панелью — комната: тап туда магазин не прячет.
    await tester.tapAt(const Offset(215, 120));
    await tester.pumpAndSettle();
    expect(close, findsOneWidget);

    // Вверх за шапку — во весь рост.
    final title = find.text('Магазин');
    final half = tester.getTopLeft(title).dy;
    await tester.drag(title, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, lessThan(half - 200));

    // Вниз — закрыть.
    await tester.fling(title, const Offset(0, 500), 1500);
    await tester.pumpAndSettle();
    expect(close, findsNothing);
  });
}
