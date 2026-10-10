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
/// раскрыто». С 10.10 ряд сам сворачивается через 3 с без касаний, а общий
/// круг ещё через 5 с уезжает к краю «язычком»; тап по нему раскрывает ряд
/// и подсвечивает самый низкий показатель. Здесь проверяется само
/// поведение, а ещё — что любви среди колец больше нет и что её показатель
/// не потерялся: он в общем проценте на кнопке.
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
    Listenable? activity,
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
            activity: activity,
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

    testWidgets('ряд сам сворачивается через 3 с без касаний', (tester) async {
      // Заказчик 10.10: «ряд из 4 кругов при бездействии ~3 сек
      // сворачивается анимацией обратно в один общий круг».
      await pump(tester, tapped: []);

      await tester.pump(const Duration(seconds: 2));
      expect(food, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(food, findsNothing);
      expect(button, findsOneWidget);
    });

    testWidgets('любое касание экрана откладывает сворачивание', (
      tester,
    ) async {
      final activity = ChangeNotifier();
      addTearDown(activity.dispose);
      await pump(tester, tapped: [], activity: activity);

      await tester.pump(const Duration(seconds: 2));
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      activity.notifyListeners();
      await tester.pump(const Duration(seconds: 2));
      expect(food, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(food, findsNothing);
    });

    testWidgets('свёрнутый круг уезжает к краю, тап раскрывает ряд', (
      tester,
    ) async {
      // Заказчик 10.10: общий круг перекрывал картины и потолок — через
      // 5 с он уменьшается и уезжает наполовину за край; тап по нему —
      // выезжает и раскрывает показатели, самый низкий подсвечен.
      await pump(
        tester,
        tapped: [],
        stats: const BearCareStats(food: 70, hygiene: 20, sleep: 90, play: 60),
      );
      await tester.pump(const Duration(milliseconds: 3100));
      await tester.pumpAndSettle();
      final before = tester.getCenter(button).dx;

      await tester.pump(const Duration(milliseconds: 5100));
      await tester.pumpAndSettle();
      final width = tester.getSize(find.byType(Scaffold)).width;
      expect(tester.getCenter(button).dx, greaterThan(before));
      expect(tester.getCenter(button).dx, closeTo(width, 1));

      // Видна половина — по ней и жмём.
      await tester.tapAt(tester.getCenter(button) - const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(food, findsOneWidget);
      expect(tester.getCenter(button).dx, closeTo(before, 1));
      // Подсвечен самый низкий — гигиена.
      final lit = find.byWidgetPredicate(
        (w) => w is AnimatedScale && w.scale > 1,
      );
      expect(lit, findsOneWidget);
      expect(
        find.descendant(of: lit, matching: find.byIcon(Icons.bathtub_outlined)),
        findsOneWidget,
      );
    });

    testWidgets('выбор показателя уводит в комнату, но ряд остаётся', (
      tester,
    ) async {
      // До 21.09 ряд после выбора уезжал. Заказчик: «как он поел, сколько
      // ему нужно поесть ещё — должно быть видно сразу», а видеть это можно
      // только по тем самым кольцам. Сворачивается он сам — через 3 с.
      final tapped = <BearAction>[];
      await pump(tester, tapped: tapped);

      await tester.tap(food);
      await tester.pump(const Duration(milliseconds: 500));

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
