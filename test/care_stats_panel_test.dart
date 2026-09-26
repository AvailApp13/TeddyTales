import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_stats.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/care_stats_panel.dart';

/// Показатели и кнопка, которая их прячет (решение заказчика 20.09).
///
/// «Вместо любви мы делаем эту кнопку, она будет прятать все». С 21.09 ряд
/// открыт с запуска: «при открытии приложения это меню должно быть всегда
/// раскрыто, по желанию человек нажимает крестик, тогда оно только
/// прячется». Здесь проверяется само поведение: что при запуске показатели
/// на виду, что прячет их только крестик, что любви среди них больше нет и
/// что её показатель не потерялся — он в общем проценте на кнопке.
// Полоски и крест на кнопке рисуются кистью, а не иконкой, — ищем её по
// ключу. Открыта она или нет, видно по самим кольцам.
final button = find.byKey(const ValueKey('care.toggle'));
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
    testWidgets('при запуске показатели на виду', (tester) async {
      // Главное требование заказчика 21.09: «они должны быть видны сразу».
      await pump(tester, tapped: []);

      expect(button, findsOneWidget);
      expect(food, findsOneWidget);
    });

    testWidgets('крестик прячет ряд, второе нажатие возвращает', (
      tester,
    ) async {
      await pump(tester, tapped: []);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(food, findsNothing);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(food, findsOneWidget);
    });

    testWidgets('сам ряд не сворачивается — только по нажатию', (tester) async {
      // В отличие от лапы внизу, у этой кнопки таймера нет: так решил
      // заказчик. Если однажды заведут авто-сбор, тест об этом скажет.
      await pump(tester, tapped: []);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(food, findsOneWidget);
    });

    testWidgets('выбор показателя уводит в комнату, но ряд остаётся', (
      tester,
    ) async {
      // До 21.09 ряд после выбора уезжал. Заказчик: «как он поел, сколько
      // ему нужно поесть ещё — должно быть видно сразу», а видеть это можно
      // только по тем самым кольцам.
      final tapped = <BearAction>[];
      await pump(tester, tapped: tapped);

      await tester.tap(food);
      await tester.pumpAndSettle();

      expect(tapped, [BearAction.feed]);
      expect(food, findsOneWidget);
    });
  });

  group('Что на экране осталось', () {
    testWidgets('любви среди колец нет', (tester) async {
      // Кольцо «Любовь» никуда не вело: ласка происходит там, где мишка
      // стоит. Заказчик 20.09: «любовь мы вообще убираем, она не нужна».
      await pump(tester, tapped: []);

      expect(love, findsNothing);
      expect(find.textContaining('Любовь'), findsNothing);
    });

    testWidgets('подпись и процент стоят одной строкой', (tester) async {
      // Заказчик 20.09: проценты сохраняем, но мелко и не громоздко.
      await pump(tester, tapped: [], stats: const BearCareStats(food: 60));

      expect(find.textContaining('Еда'), findsWidgets);
      expect(find.textContaining('60%'), findsWidgets);
    });

    testWidgets('общий уход подписан под самой кнопкой', (tester) async {
      await pump(
        tester,
        tapped: [],
        stats: const BearCareStats(
          food: 100,
          hygiene: 100,
          sleep: 100,
          play: 100,
          love: 0,
        ),
      );

      expect(find.textContaining('80%'), findsWidgets);
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
