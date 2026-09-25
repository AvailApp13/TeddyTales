import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/profile_screen.dart';
import 'package:teddy_tales/widgets/share_card.dart';

/// «Поделиться» (сверх ТЗ, заказчик 25.09): карточка мишки картинкой.
void main() {
  final born = PetProfile(
    name: 'Тедди',
    birthAt: DateTime(2026, 6, 1),
    zodiac: BearZodiac.leo,
    birthHeightCm: 15.3,
    birthWeightG: 184,
  );

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

  testWidgets('в профиле «Поделиться» открывает карточку мишки', (
    tester,
  ) async {
    final bear = BearController();
    final game = GameState(bear: bear, profile: born);
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    await tester.pumpWidget(
      wrap(
        ProfileScreen(
          controller: bear,
          game: game,
          onOpenGrowth: () {},
          onOpenDiary: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-share')));
    await tester.pumpAndSettle();

    expect(find.byType(PetShareCard), findsOneWidget);
    expect(find.text('Знакомьтесь: Тедди'), findsOneWidget);
    expect(find.text('15,3 см'), findsWidgets);
    expect(find.text('TeddyTales'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-send')), findsOneWidget);
  });

  testWidgets('новая стадия — «подрос!»', (tester) async {
    final bear = BearController();
    final game = GameState(bear: bear, profile: born);
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showShareCard(
              context,
              game: game,
              stage: BearStage.firstSteps,
              grown: true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Тедди подрос!'), findsOneWidget);
    expect(find.textContaining('Первые шаги'), findsOneWidget);
  });
}
