import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/referral_info.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/friend_code_dialog.dart';

/// «Тебя пригласил друг?» после имени (заказчик 26.09).
void main() {
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.hasStrings':
              return {'value': clipboard != null};
            case 'Clipboard.getData':
              return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
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
    home: Scaffold(body: child),
  );

  GameState game0({bool canRedeem = true}) {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 9, 26)),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    game.onReferral = () async => ReferralInfo(
      code: 'AAAAAA',
      invited: 0,
      coins: 100,
      link: '',
      canRedeem: canRedeem,
    );
    return game;
  }

  Future<void> open(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showFriendCodeDialog(context, game),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('код из ссылки в буфере — один тап, монеты обоим', (
    tester,
  ) async {
    clipboard = 'TEDDY-ZP65BM';
    final game = game0();
    var redeemed = '';
    game.onRedeemReferral = (code) async {
      redeemed = code;
      return RedeemResult.ok;
    };
    await open(tester, game);
    expect(find.text('Тебя пригласил друг?'), findsOneWidget);
    expect(find.textContaining('ZP65BM'), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-code-field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('friend-code-claim')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 900));
    expect(redeemed, 'ZP65BM');
    expect(find.text('Тебя пригласил друг?'), findsNothing);
    // Праздник монет на экране.
    expect(find.byKey(const ValueKey('coin-reward')), findsOneWidget);
    expect(find.text('+100'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coin-reward')), findsNothing);
  });

  testWidgets('кода нет — поле и «Пропустить»', (tester) async {
    final game = game0();
    await open(tester, game);
    expect(find.byKey(const ValueKey('friend-code-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('friend-code-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Тебя пригласил друг?'), findsNothing);
  });

  testWidgets('вводить уже поздно — окна нет', (tester) async {
    clipboard = 'TEDDY-ZP65BM';
    await open(tester, game0(canRedeem: false));
    expect(find.text('Тебя пригласил друг?'), findsNothing);
  });
}
