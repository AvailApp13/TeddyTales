import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/purchase_confirm.dart';

/// Покупка без корзины (заказчик 24.09): каждая вещь и каждое блюдо —
/// отдельно, через окно подтверждения, на трёх языках.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 9, 1)),
      walletFloor: 0,
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  Future<void> openBuy(
    WidgetTester tester,
    String itemId, {
    String lang = 'ru',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => buyItemConfirmed(
                context: context,
                game: game,
                item: ItemCatalog.byId(itemId),
              ),
              child: const Text('buy'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buy'));
    await tester.pumpAndSettle();
  }

  testWidgets('окно показывает вещь, цену и сколько останется', (tester) async {
    game.earn(500);
    await openBuy(tester, 'table');

    expect(find.text('Подтвердите покупку'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('На счету 500 · останется 410'), findsOneWidget);
    expect(find.text('Купить'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
  });

  testWidgets('«Отмена» — ничего не куплено, монеты целы', (tester) async {
    game.earn(500);
    await openBuy(tester, 'table');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(game.isOwned('table'), isFalse);
    expect(game.coins, 500);
  });

  testWidgets('«Купить» — вещь куплена ровно по цене', (tester) async {
    game.earn(500);
    await openBuy(tester, 'dollhouse');
    await tester.tap(find.text('Купить'));
    await tester.pumpAndSettle();

    expect(game.isOwned('dollhouse'), isTrue);
    expect(game.coins, 500 - ItemCatalog.byId('dollhouse').price);
  });

  testWidgets('не хватает — «Купить» нет, сказано сколько', (tester) async {
    game.earn(50);
    await openBuy(tester, 'table');

    expect(find.text('Не хватает монет'), findsOneWidget);
    expect(find.text('Не хватает 40 монет'), findsOneWidget);
    expect(find.text('Купить'), findsNothing);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(game.isOwned('table'), isFalse);
    expect(game.coins, 50);
  });

  testWidgets('английский', (tester) async {
    game.earn(500);
    await openBuy(tester, 'table', lang: 'en');
    expect(find.text('Confirm your purchase'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('You have 500 · 410 left after'), findsOneWidget);
  });

  testWidgets('китайский', (tester) async {
    game.earn(500);
    await openBuy(tester, 'table', lang: 'zh');
    expect(find.text('确认购买'), findsOneWidget);
    expect(find.text('购买'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });
}
