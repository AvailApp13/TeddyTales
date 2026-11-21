import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/birth_intro.dart';

/// «Родился малыш!» при первом запуске (КП 2.1, 2.2; заказчик 26.09).
void main() {
  testWidgets('карточка рождения и заглушка видео, «Дать имя» закрывает', (
    tester,
  ) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(
        name: PetProfile.defaultName,
        birthAt: DateTime(2026, 9, 26),
        skin: BearSkin.girl,
        zodiac: BearZodiac.libra,
        birthHeightCm: 16.6,
        birthWeightG: 186,
      ),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);

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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBirthIntro(
                context,
                game: game,
                trait: BearTrait.affectionate,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Родился малыш!'), findsOneWidget);
    // Видео ждёт согласования — на его месте заглушка.
    expect(birthVideos, isEmpty);
    expect(
      find.byKey(const ValueKey('birth-video-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Видео рождения'), findsOneWidget);
    expect(find.text('девочка · JOY'), findsOneWidget);
    expect(find.text('16,6 см'), findsOneWidget);
    expect(find.text('186 г'), findsOneWidget);
    expect(find.textContaining('Весы'), findsOneWidget);
    expect(find.text('Ласковый'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('birth-intro-name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('birth-intro-name')));
    await tester.pumpAndSettle();
    expect(find.text('Родился малыш!'), findsNothing);
  });
}
