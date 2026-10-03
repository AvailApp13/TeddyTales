import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/notify_prompt.dart';
import 'package:teddy_tales/widgets/sign_out_dialog.dart';

/// Разрешение на уведомления (КП 13.1) и удаление аккаунта (App Store
/// 5.1.1) — заказчик 26.09.
void main() {
  final born = DateTime(2026, 9, 20);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  GameState game0() {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: born),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    return game;
  }

  Future<void> ask(WidgetTester tester, GameState game, DateTime now) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => maybeAskNotifications(context, game, now: now),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  group('переключатель в настройках', () {
    test('включение спрашивает разрешение, отказ — назад', () async {
      final game = game0();
      var asked = 0;
      game.onAskNotifications = () async {
        asked++;
        return false;
      };
      final id = NotificationKind.event.id;
      expect(game.isNotificationOn(id), isFalse);
      expect(await game.toggleNotification(id), isFalse);
      expect(asked, 1);
      expect(game.isNotificationOn(id), isFalse);
    });

    test('разрешили — остаётся включённым; выключение не спрашивает', () async {
      final game = game0();
      var asked = 0;
      game.onAskNotifications = () async {
        asked++;
        return true;
      };
      final id = NotificationKind.event.id;
      expect(await game.toggleNotification(id), isTrue);
      expect(game.isNotificationOn(id), isTrue);
      expect(await game.toggleNotification(id), isTrue);
      expect(game.isNotificationOn(id), isFalse);
      expect(asked, 1);
    });
  });

  group('«Напоминать о малыше?»', () {
    testWidgets('в первый день не спрашивает', (tester) async {
      final game = game0()..onAskNotifications = () async => true;
      await ask(tester, game, born.add(const Duration(hours: 5)));
      expect(find.byKey(const ValueKey('notify-yes')), findsNothing);
    });

    testWidgets('без уведомлений на платформе не спрашивает', (tester) async {
      final game = game0();
      await ask(tester, game, born.add(const Duration(days: 2)));
      expect(find.byKey(const ValueKey('notify-yes')), findsNothing);
    });

    testWidgets('«Да» — системный запрос, напоминания включены, один раз', (
      tester,
    ) async {
      final game = game0();
      var asked = 0;
      game
        ..onAskNotifications = () async {
          asked++;
          return true;
        }
        ..toggleNotification(NotificationKind.hungry.id);
      expect(game.isNotificationOn(NotificationKind.hungry.id), isFalse);
      asked = 0;

      final now = born.add(const Duration(days: 2));
      await ask(tester, game, now);
      expect(find.text('Напоминать о малыше?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notify-yes')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(game.isNotificationOn(NotificationKind.hungry.id), isTrue);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notify-yes')), findsNothing);
    });

    testWidgets('«Не сейчас» — подсказка про настройки', (tester) async {
      final game = game0()..onAskNotifications = () async => true;
      await ask(tester, game, born.add(const Duration(days: 2)));
      await tester.tap(find.byKey(const ValueKey('notify-later')));
      await tester.pumpAndSettle();
      expect(find.textContaining('настройках'), findsOneWidget);
    });
  });

  group('удаление аккаунта', () {
    Future<void> open(WidgetTester tester, GameState game) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmDeleteAccount(context, game),
              child: const Text('delete'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('«Оставить» ничего не удаляет', (tester) async {
      final game = game0();
      var deleted = 0;
      game.onDeleteAccount = () async {
        deleted++;
        return true;
      };
      await open(tester, game);
      expect(find.text('Удалить аккаунт?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-account-keep')));
      await tester.pumpAndSettle();
      expect(deleted, 0);
    });

    testWidgets('«Удалить навсегда» удаляет; ошибка — подсказка', (
      tester,
    ) async {
      final game = game0();
      var deleted = 0;
      game.onDeleteAccount = () async {
        deleted++;
        return false;
      };
      await open(tester, game);
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(deleted, 1);
      expect(find.textContaining('Не получилось удалить'), findsOneWidget);
    });
  });
}
