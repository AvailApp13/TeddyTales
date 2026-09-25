import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/referral_info.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/referral_card.dart';

/// «Пригласи друга» (сверх ТЗ, заказчик 25.09; миграция 0021).
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
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  GameState game0() {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 9, 20)),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    return game;
  }

  test('ссылка приглашения несёт код', () {
    const info = ReferralInfo(
      code: 'ZP65BM',
      invited: 0,
      coins: 100,
      link: 'https://availapp13.github.io/TeddyTales/',
      canRedeem: true,
    );
    expect(
      info.inviteLink,
      'https://availapp13.github.io/TeddyTales/?ref=ZP65BM',
    );
  });

  testWidgets('без сервера блока нет', (tester) async {
    final game = game0();
    await tester.pumpWidget(
      wrap(ReferralCard(game: game, title: const Text('Пригласи друга'))),
    );
    await tester.pump();
    expect(find.text('Пригласи друга'), findsNothing);
  });

  testWidgets('код, счёт друзей и ввод кода друга', (tester) async {
    final game = game0();
    var redeemed = '';
    var info = const ReferralInfo(
      code: 'ZP65BM',
      invited: 2,
      coins: 100,
      link: '',
      canRedeem: true,
    );
    game.onReferral = () async => info;
    game.onRedeemReferral = (code) async {
      redeemed = code;
      info = const ReferralInfo(
        code: 'ZP65BM',
        invited: 2,
        coins: 100,
        link: '',
        canRedeem: false,
      );
      return RedeemResult.ok;
    };
    await tester.pumpWidget(
      wrap(ReferralCard(game: game, title: const Text('Пригласи друга'))),
    );
    await tester.pump();
    expect(find.text('ZP65BM'), findsOneWidget);
    expect(find.text('Друзей пришло: 2'), findsOneWidget);
    expect(find.textContaining('по 100 монет'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('invite-field')),
      'e576dr',
    );
    await tester.tap(find.byKey(const ValueKey('invite-redeem')));
    await tester.pumpAndSettle();
    expect(redeemed, 'E576DR');
    expect(find.text('+100 монет — тебе и другу!'), findsOneWidget);
    // Второй раз ввести нельзя — поля больше нет.
    expect(find.byKey(const ValueKey('invite-field')), findsNothing);
  });

  testWidgets('неверный код — подсказка, поле остаётся', (tester) async {
    final game = game0();
    game.onReferral = () async => const ReferralInfo(
      code: 'ZP65BM',
      invited: 0,
      coins: 100,
      link: '',
      canRedeem: true,
    );
    game.onRedeemReferral = (code) async => RedeemResult.notFound;
    await tester.pumpWidget(
      wrap(ReferralCard(game: game, title: const Text('Пригласи друга'))),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('invite-field')),
      'AAAAAA',
    );
    await tester.tap(find.byKey(const ValueKey('invite-redeem')));
    await tester.pumpAndSettle();
    expect(find.text('Такого кода нет. Проверь буквы.'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-field')), findsOneWidget);
  });
}
