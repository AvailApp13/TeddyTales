import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/profile_screen.dart';
import 'package:teddy_tales/screens/settings_screen.dart';

/// Выход из аккаунта (КП 14.2).
///
/// Проверяется не диалог сам по себе, а то, ради чего он существует:
/// случайное касание не должно выкидывать человека из игры, а осознанное —
/// должно, и ровно один раз.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

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

  Widget profile({VoidCallback? onSignOut}) => ProfileScreen(
    controller: bear,
    game: game,
    onOpenGrowth: () {},
    onOpenDiary: () {},
    onOpenSettings: () {},
    onSignOut: onSignOut,
  );

  group('Профиль', () {
    testWidgets('кнопка выхода есть', (tester) async {
      await tester.pumpWidget(wrap(profile(onSignOut: () {})));
      await tester.pumpAndSettle();

      // Мотив пункта 14.2: человек идёт разбираться с учётной записью в
      // профиль, а не на два экрана вглубь настроек.
      final button = find.widgetWithText(OutlinedButton, 'Выйти');
      await tester.scrollUntilVisible(button, 200);
      expect(button, findsOneWidget);
    });

    testWidgets('без обработчика кнопки нет', (tester) async {
      await tester.pumpWidget(wrap(profile()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsNothing);
    });

    testWidgets('выход требует подтверждения', (tester) async {
      var signedOut = 0;
      await tester.pumpWidget(wrap(profile(onSignOut: () => signedOut++)));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(OutlinedButton, 'Выйти');
      await tester.scrollUntilVisible(button, 200);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Одно касание не выбрасывает: сначала спрашиваем.
      expect(signedOut, 0);
      expect(find.text('Выйти из аккаунта?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();
      expect(signedOut, 0, reason: 'отмена не должна выкидывать из игры');

      await tester.scrollUntilVisible(button, 200);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Выйти'));
      await tester.pumpAndSettle();

      expect(signedOut, 1);
    });
  });

  group('Настройки', () {
    testWidgets('раздел «Аккаунт» показывается вместе с выходом', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            game: game,
            language: BearLanguage.ru,
            onLanguageChanged: (_) {},
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(ListTile, 'Выйти');
      await tester.scrollUntilVisible(tile, 200);
      expect(tile, findsOneWidget);
      expect(find.text('Версия'), findsOneWidget);
    });

    testWidgets('без обработчика раздела нет', (tester) async {
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            game: game,
            language: BearLanguage.ru,
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsNothing);
    });
  });
}
