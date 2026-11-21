import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/sleeping_elsewhere.dart';

/// Мишка спит, а мы в другой комнате (заказчик 26.09).
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
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('кухня: позвать по времени суток', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox();
          },
        ),
      ),
    );
    String at(RoomKind room, int hour) =>
        SleepingElsewhere.wakeLabel(l10n, room, hour);
    expect(at(RoomKind.kitchen, 8), 'Разбудить и позвать завтракать');
    expect(at(RoomKind.kitchen, 13), 'Разбудить и позвать обедать');
    expect(at(RoomKind.kitchen, 19), 'Разбудить и позвать ужинать');
    expect(at(RoomKind.kitchen, 23), 'Разбудить и позвать перекусить');
    expect(at(RoomKind.kitchen, 3), 'Разбудить и позвать перекусить');
    expect(at(RoomKind.nursery, 12), 'Разбудить и позвать играть');
    expect(at(RoomKind.bath, 12), 'Разбудить и позвать купаться');
  });

  testWidgets('кнопки: разбудить и «Пусть спит»', (tester) async {
    var woke = 0;
    var let = 0;
    await tester.pumpWidget(
      wrap(
        SleepingElsewhere(
          room: RoomKind.kitchen,
          sleep: 45,
          now: DateTime(2026, 9, 26, 9),
          onWake: () => woke++,
          onLetSleep: () => let++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Мишка спит'), findsOneWidget);
    expect(find.text('Ещё не выспался — Сон 45 %'), findsOneWidget);
    await tester.tap(find.text('Разбудить и позвать завтракать'));
    await tester.tap(find.text('Пусть спит'));
    expect(woke, 1);
    expect(let, 1);
  });

  testWidgets('ночь — своя подсказка; выспался днём — без неё', (tester) async {
    await tester.pumpWidget(
      wrap(
        SleepingElsewhere(
          room: RoomKind.nursery,
          sleep: 95,
          now: DateTime(2026, 9, 26, 23),
          onWake: () {},
          onLetSleep: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сейчас ночь — мишке лучше поспать.'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        SleepingElsewhere(
          room: RoomKind.nursery,
          sleep: 95,
          now: DateTime(2026, 9, 26, 12),
          onWake: () {},
          onLetSleep: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleeping-warning')), findsNothing);
  });
}
