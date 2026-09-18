import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/app_section.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/learning_screen.dart';

/// Что открыто и когда (решение заказчика от 17.09).
///
/// Таблица КП 5 открывала комнату, магазин и обучение со второй-четвёртой
/// стадии. Проверяем обратное: разделы доступны с рождения, а прогрессия
/// переехала внутрь — в категории обучения.
void main() {
  group('Разделы нижней навигации', () {
    test('все открыты с первого дня', () {
      for (final section in AppSection.values) {
        expect(
          section.isUnlockedAt(BearStage.newborn),
          isTrue,
          reason:
              '${section.title} закрыт на старте: игроку нечем заняться в '
              'первый день, а бесплатные предметы некуда ставить (КП 10.8)',
        );
      }
    });
  });

  group('Обучение по стадиям', () {
    late BearController bear;
    late GameState game;

    Future<void> openLearning(WidgetTester tester, BearStage stage) async {
      bear = BearController(
        initialState: BearState(stage: stage, stats: const BearCareStats()),
      );
      game = GameState(
        bear: bear,
        profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      );
      // Возрастная развилка спрашивается один раз; детский набор — тот, где
      // живут три категории КП 9.1.
      game.setPlayerAge(6);
      addTearDown(() {
        game.dispose();
        bear.dispose();
      });

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
          home: LearningScreen(game: game),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('новорождённому доступны только цвета и формы', (tester) async {
      await openLearning(tester, BearStage.newborn);

      // Все три категории видны — закрытые не прячем, иначе не видно, ради
      // чего мишку растить.
      expect(find.text('Цвета и формы'), findsOneWidget);
      expect(find.text('Счёт и простая логика'), findsOneWidget);
      expect(find.text('Окружающий мир'), findsOneWidget);

      // Но две из них с замком и объяснением, когда откроются.
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      expect(
        find.text('Откроется на стадии «Ползающий малыш»'),
        findsOneWidget,
      );
      expect(find.text('Откроется на стадии «Первые шаги»'), findsOneWidget);
    });

    testWidgets('счёт открывается, когда малыш пополз', (tester) async {
      await openLearning(tester, BearStage.crawling);

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Откроется на стадии «Первые шаги»'), findsOneWidget);
    });

    testWidgets('с первых шагов замков не остаётся', (tester) async {
      await openLearning(tester, BearStage.firstSteps);

      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });

    testWidgets('закрытая категория не открывается по тапу', (tester) async {
      await openLearning(tester, BearStage.newborn);

      await tester.tap(find.text('Счёт и простая логика'));
      await tester.pumpAndSettle();

      // Остались на списке категорий: заголовок сетки уровней — это название
      // категории в шапке, а его быть не должно.
      expect(find.text('Цвета и формы'), findsOneWidget);
      // Зато сказали, когда придёт очередь.
      expect(find.text('Откроется на стадии «Ползающий малыш»'), findsWidgets);
    });
  });

  group('Витрина магазина', () {
    test('новорождённому подходит обстановка, а не письменный стол', () {
      const stage = BearStage.newborn;

      // Кроватка, светильник, ковёр и корзина — то, с чего начинается
      // комната малыша, и они же входят в бесплатный набор КП 10.8.
      for (final id in ['bed', 'lamp', 'rug', 'basket']) {
        expect(
          ItemCatalog.byId(id).suitsAt(stage),
          isTrue,
          reason: '$id нужен в первый же день',
        );
      }

      // А эти вещи ребёнку, который ещё не сидит, не нужны.
      for (final id in ['table', 'chair', 'wardrobe', 'puzzle']) {
        expect(ItemCatalog.byId(id).suitsAt(stage), isFalse, reason: id);
      }
    });

    test('к взрослой стадии подходит весь каталог', () {
      for (final item in ItemCatalog.all) {
        expect(
          item.suitsAt(BearStage.adult),
          isTrue,
          reason: '${item.id} не должен оставаться «на потом» навсегда',
        );
      }
    });

    test('одежда появляется с третьей стадии', () {
      // ТЗ аниматора v2: одежда доступна с 3-й стадии — на младенце её
      // просто нет в риге. Витрина обязана совпадать с тем, что умеет
      // показать мишка.
      for (final item in ItemCatalog.clothes) {
        expect(item.suitsAt(BearStage.crawling), isFalse, reason: item.id);
        expect(item.suitsAt(BearStage.firstSteps), isTrue, reason: item.id);
      }
    });
  });
}
