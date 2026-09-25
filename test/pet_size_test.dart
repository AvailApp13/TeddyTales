import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/growth_screen.dart';
import 'package:teddy_tales/screens/profile_screen.dart';

/// Рост и вес (КП 2.2): при рождении назначает сервер, дальше растут по
/// стадиям (заказчик 25.09). В карточке рождения — цифры при рождении, в
/// «Росте и развитии» — текущие.
void main() {
  final born = PetProfile(
    name: 'Тедди',
    birthAt: DateTime(2026, 6, 1),
    // Знак тоже с сервера — иначе ярлык «заглушка» стоит у него.
    zodiac: BearZodiac.leo,
    birthHeightCm: 15.3,
    birthWeightG: 184,
  );

  test('к взрослому «Карманный мишка» дорастает до ~25 см и ~400 г', () {
    expect(born.heightAt(BearStage.newborn), 15.3);
    expect(born.weightAt(BearStage.newborn), 184);
    expect(born.heightAt(BearStage.adult), closeTo(25.2, 0.1));
    expect(born.weightAt(BearStage.adult), closeTo(405, 1));
    // Растёт монотонно.
    var h = 0.0;
    for (final stage in BearStage.values) {
      expect(born.heightAt(stage)!, greaterThan(h));
      h = born.heightAt(stage)!;
    }
  });

  test('без чисел с сервера размера нет', () {
    final unknown = PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1));
    expect(unknown.heightAt(BearStage.adult), isNull);
    expect(unknown.weightAt(BearStage.adult), isNull);
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

  testWidgets('карточка рождения показывает рост и вес с сервера', (
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
    expect(find.text('15,3 см'), findsOneWidget);
    expect(find.text('184 г'), findsOneWidget);
    expect(find.text('заглушка'), findsNothing);
  });

  testWidgets('без чисел с сервера — заглушка с пометкой', (tester) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
    );
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
    expect(find.text('15 см'), findsOneWidget);
    expect(find.text('180 г'), findsOneWidget);
    expect(find.text('заглушка'), findsWidgets);
  });

  testWidgets('«Рост и развитие» — текущий размер по стадии', (tester) async {
    final bear = BearController();
    addTearDown(bear.dispose);
    bear.restoreState(const BearState(stage: BearStage.growing));
    await tester.pumpWidget(
      wrap(GrowthScreen(controller: bear, profile: born)),
    );
    await tester.pump();
    final line = tester.widget<Text>(find.byKey(const ValueKey('growth-size')));
    // 15,3 × 1,5 = 23,0 см; 184 × 1,9 = 350 г.
    expect(line.data, contains('23,0 см'));
    expect(line.data, contains('350 г'));
    expect(line.data, contains('15,3 см и 184 г'));
  });
}
