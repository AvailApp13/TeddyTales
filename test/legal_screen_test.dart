import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/legal_screen.dart';
import 'package:teddy_tales/screens/settings_screen.dart';
import 'package:teddy_tales/screens/sign_in_screen.dart';

/// Правовые документы (КП 14.2): условия и политика открываются со
/// стартовой страницы и из настроек, текст берётся из assets/legal по
/// языку интерфейса.
void main() {
  Widget wrap(Widget child, {String lang = 'ru'}) => MaterialApp(
    locale: Locale(lang),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  /// Экран крутит индикатор, пока файл читается, а стартовая страница
  /// живёт своей анимацией — pumpAndSettle не дождётся покоя. Даём файлу
  /// прочитаться и проматываем переход.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Нажать ссылку внутри строки: у неё свой распознаватель касаний.
  void tapLink(WidgetTester tester, String text) {
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      TapGestureRecognizer? found;
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == text &&
            span.recognizer is TapGestureRecognizer) {
          found = span.recognizer! as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (found != null) {
        found!.onTap!();
        return;
      }
    }
    fail('нет ссылки «$text»');
  }

  group('тексты', () {
    test('есть на трёх языках для обоих документов', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final doc in LegalDoc.values) {
        for (final lang in ['ru', 'en', 'zh']) {
          final text = await loadLegalText(doc, lang);
          expect(text, startsWith('# '), reason: '${doc.file}_$lang');
        }
      }
    });

    test('нет языка — английский', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final text = await loadLegalText(LegalDoc.terms, 'fr');
      expect(text, startsWith('# Terms of Use'));
    });
  });

  testWidgets('экран показывает заголовок и текст документа', (tester) async {
    await tester.pumpWidget(wrap(const LegalScreen(doc: LegalDoc.privacy)));
    await settle(tester);
    expect(find.text('Политика конфиденциальности'), findsNWidgets(2));
    expect(find.textContaining('Связь с нами'), findsOneWidget);
  });

  testWidgets('со стартовой страницы открываются оба документа', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(SignInScreen(onSignedIn: () {})));
    await settle(tester);

    tapLink(tester, 'условия использования');
    await settle(tester);
    expect(find.byType(LegalScreen), findsOneWidget);
    expect(find.text('Условия использования'), findsWidgets);
    Navigator.of(tester.element(find.byType(LegalScreen))).pop();
    await settle(tester);

    tapLink(tester, 'политику конфиденциальности');
    await settle(tester);
    expect(find.text('Политика конфиденциальности'), findsWidgets);
  });

  testWidgets('в настройках — раздел с обоими документами', (tester) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          game: game,
          language: BearLanguage.ru,
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await settle(tester);
    final terms = find.byKey(const ValueKey('legal-terms'));
    await tester.ensureVisible(terms);
    await tester.tap(terms);
    await settle(tester);
    expect(find.byType(LegalScreen), findsOneWidget);
  });
}
