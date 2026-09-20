import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/care_stats_panel.dart';

/// Показатели прячутся в одну кнопку (решение заказчика 20.09).
///
/// «Вместо любви мы делаем эту кнопку, она будет прятать все». Здесь
/// проверяется само поведение: что кольца достижимы, что сами они не
/// разворачиваются и не сворачиваются, что любви среди них больше нет и что
/// её показатель при этом не потерялся — он в общем проценте на кнопке.
final button = find.byIcon(Icons.menu_rounded);
final closeButton = find.byIcon(Icons.close_rounded);
final food = find.byIcon(Icons.restaurant);
final love = find.byIcon(Icons.favorite);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<BearAction> tapped,
    BearCareStats stats = const BearCareStats(),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: CareStatsPanel(
            stats: stats,
            stage: BearStage.adult,
            onAction: tapped.add,
          ),
        ),
      ),
    );
  }

  group('Кнопка ухода', () {
    testWidgets('пока её не нажали, колец на экране нет', (tester) async {
      await pump(tester, tapped: []);

      expect(button, findsOneWidget);
      expect(food, findsNothing);
    });

    testWidgets('по нажатию ряд выезжает, по второму — прячется', (
      tester,
    ) async {
      await pump(tester, tapped: []);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(food, findsOneWidget);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      expect(food, findsNothing);
      expect(button, findsOneWidget);
    });

    testWidgets('сам ряд не сворачивается — только по нажатию', (tester) async {
      // В отличие от лапы внизу, у этой кнопки таймера нет: так решил
      // заказчик. Если однажды заведут авто-сбор, тест об этом скажет.
      await pump(tester, tapped: []);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(food, findsOneWidget);
    });

    testWidgets('выбор показателя уводит в комнату и закрывает ряд', (
      tester,
    ) async {
      final tapped = <BearAction>[];
      await pump(tester, tapped: tapped);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(food);
      await tester.pumpAndSettle();

      expect(tapped, [BearAction.feed]);
      expect(food, findsNothing);
    });
  });

  group('Что на экране осталось', () {
    testWidgets('любви среди колец нет', (tester) async {
      // Кольцо «Любовь» никуда не вело: ласка происходит там, где мишка
      // стоит. Заказчик 20.09: «любовь мы вообще убираем, она не нужна».
      await pump(tester, tapped: []);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(love, findsNothing);
      expect(find.text('Любовь'), findsNothing);
    });

    testWidgets('подписи остались, а процентов цифрами больше нет', (
      tester,
    ) async {
      await pump(tester, tapped: []);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Еда'), findsWidgets);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('Общий уход', () {
    test('считается по всем пяти показателям, включая любовь', () {
      // Любви нет на экране, но заброшенная ласка так же тормозит рост
      // (КП 5.7), как несъеденный обед. Если её однажды выкинут из счёта,
      // кнопка станет врать: мишке плохо, а по ней всё хорошо.
      const stats = BearCareStats(
        food: 100,
        hygiene: 100,
        sleep: 100,
        play: 100,
        love: 0,
      );

      expect(CareStatsPanel.totalCare(stats), 80);
      expect(CareStatsPanel.totalCare(const BearCareStats()), 100);
    });
  });
}
