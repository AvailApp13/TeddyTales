import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/sleep_countdown.dart';

/// «Уложить спать» (заказчик 25.09): на одеяле секунды до сна.
void main() {
  Widget wrap(bool shown) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SleepCountdown(shown: shown)),
  );

  testWidgets('уложили — отсчёт до сна, потом кружок уходит', (tester) async {
    await tester.pumpWidget(wrap(false));
    expect(find.byKey(const ValueKey('sleep-countdown')), findsNothing);

    await tester.pumpWidget(wrap(true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('sleep-countdown')), findsOneWidget);
    // Засыпает за 4 секунды (заказчик 26.09; было 7,5).
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Засыпает'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('2'), findsOneWidget);

    // Уснул: кружок растворяется, дальше «zzz» и облако.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-countdown')), findsNothing);
  });

  testWidgets('зашли, а мишка уже спит — отсчёта нет', (tester) async {
    await tester.pumpWidget(wrap(true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('sleep-countdown')), findsNothing);
  });

  testWidgets('разбудили раньше — кружок уходит', (tester) async {
    await tester.pumpWidget(wrap(false));
    await tester.pumpWidget(wrap(true));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(wrap(false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleep-countdown')), findsNothing);
  });
}
