import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/referral_info.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/share_button.dart';
import 'package:teddy_tales/widgets/share_card.dart';

/// «Поделиться» (заказчик 25.09): кнопка в шапке, одно окно — карточка
/// мишки и код приглашения.
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
    home: Scaffold(body: child),
  );

  GameState game0() {
    final bear = BearController();
    final game = GameState(bear: bear, profile: born);
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    return game;
  }

  Future<void> open(
    WidgetTester tester,
    GameState game, {
    bool grown = false,
  }) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Center(
            child: ShareButton(
              onTap: () => showShareCard(
                context,
                game: game,
                stage: BearStage.firstSteps,
                grown: grown,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('header-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('кнопка в шапке открывает карточку с фото мишки', (tester) async {
    final game = game0();
    await open(tester, game);
    expect(find.byType(PetShareCard), findsOneWidget);
    expect(find.text('Знакомьтесь: Тедди'), findsOneWidget);
    expect(find.text('15,3 см'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/share_bear.jpg',
      ),
      findsOneWidget,
    );
    // Без сервера — только карточка, без кода.
    expect(find.byKey(const ValueKey('invite-code')), findsNothing);
    expect(find.byKey(const ValueKey('share-send')), findsOneWidget);
  });

  testWidgets('новая стадия — «подрос!»', (tester) async {
    final game = game0();
    await open(tester, game, grown: true);
    expect(find.text('Тедди подрос!'), findsOneWidget);
    expect(find.textContaining('Первые шаги'), findsOneWidget);
  });

  testWidgets('в том же окне — код приглашения и код друга', (tester) async {
    final game = game0();
    var redeemed = '';
    var canRedeem = true;
    game.onReferral = () async => ReferralInfo(
      code: 'ZP65BM',
      invited: 2,
      coins: 100,
      link: '',
      canRedeem: canRedeem,
    );
    game.onRedeemReferral = (code) async {
      redeemed = code;
      canRedeem = false;
      return RedeemResult.ok;
    };
    await open(tester, game);
    expect(find.text('ZP65BM'), findsOneWidget);
    expect(find.text('друзей пришло'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('invite-field')),
      'e576dr',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('invite-redeem')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('invite-redeem')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(redeemed, 'E576DR');
    expect(find.text('+100 монет — тебе и другу!'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-field')), findsNothing);
  });

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

  test('код друга находится в буфере', () {
    expect(ReferralInfo.codeFrom('TEDDY-ZP65BM'), 'ZP65BM');
    expect(ReferralInfo.codeFrom('teddy zp65bm'), 'ZP65BM');
    expect(
      ReferralInfo.codeFrom('https://x.io/TeddyTales/invite.html?ref=E576DR'),
      'E576DR',
    );
    expect(ReferralInfo.codeFrom('просто текст'), isNull);
    expect(ReferralInfo.codeFrom(null), isNull);
  });

  testWidgets('статистика: друзья, монеты, лестница бонусов', (tester) async {
    final game = game0();
    game.onReferral = () async => const ReferralInfo(
      code: 'ZP65BM',
      invited: 3,
      coins: 100,
      link: '',
      canRedeem: false,
      earned: 350,
      milestones: [
        (friends: 3, bonus: 50),
        (friends: 5, bonus: 100),
        (friends: 10, bonus: 250),
      ],
    );
    await open(tester, game);
    await tester.ensureVisible(find.byKey(const ValueKey('invite-earned')));
    expect(find.text('350'), findsOneWidget);
    expect(find.text('монет получено'), findsOneWidget);
    expect(find.text('+100'), findsOneWidget);
    expect(find.text('Ещё 2 — и бонус +100'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
