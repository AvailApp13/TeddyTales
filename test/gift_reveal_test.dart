import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/gift_reveal.dart';

/// Открытие подарка дня (заказчик 25.09): конверт — монеты, коробка
/// седьмого дня — вещь. Подарок забирается на сервере в момент касания.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  Future<void> openAndRun(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('конверт: касание забирает подарок, показывает монеты', (
    tester,
  ) async {
    var claims = 0;
    GiftOutcome? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showGiftReveal(
                context,
                box: false,
                claim: () async {
                  claims++;
                  return const GiftOutcome(coins: 20);
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Нажми на конверт, чтобы открыть'), findsOneWidget);
    expect(claims, 0, reason: 'подарок забирается касанием, не открытием окна');

    await openAndRun(tester);
    expect(claims, 1);
    expect(find.text('+20 монет!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gift-collect')));
    await tester.pumpAndSettle();
    expect(result?.coins, 20);
  });

  testWidgets('коробка седьмого дня: 70 монет, никаких вещей', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showGiftReveal(
                context,
                box: true,
                claim: () async => const GiftOutcome(coins: 70),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Нажми на коробку — там сюрприз!'), findsOneWidget);
    await openAndRun(tester);
    expect(find.text('+70 монет!'), findsOneWidget);
    expect(find.text('+70'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gift-collect')));
    await tester.pumpAndSettle();
  });

  testWidgets('сервер отказал — окно закрывается', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showGiftReveal(context, box: false, claim: () async => null),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.byType(GiftReveal), findsNothing);
  });

  test('последний подарок с сервера разбирается', () {
    final coins = DailyInfo.fromJson(const {
      'gift': {
        'available': false,
        'last': {'day': 3, 'coins': 20},
      },
    });
    expect(coins.lastCoins, 20);
    expect(DailyInfo.fromJson(coins.toJson()).lastCoins, 20);
  });
}
