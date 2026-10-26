import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/email_auth.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/email_auth_screen.dart';
import 'package:teddy_tales/screens/profile_screen.dart';
import 'package:teddy_tales/screens/sign_in_screen.dart';

/// Учётная запись понарошку: запоминает, что просили, отвечает как велено.
class _FakeAuth implements AccountAuth {
  SignUpOutcome outcome = SignUpOutcome.signedIn;
  EmailAuthError? fail;
  final List<String> calls = [];

  @override
  bool get isSignedIn => false;

  @override
  Future<SignUpOutcome> signUpWithEmail(String email, String password) async {
    calls.add('up:$email');
    if (fail case final error?) throw EmailAuthException(error);
    return outcome;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    calls.add('in:$email');
    if (fail case final error?) throw EmailAuthException(error);
  }

  @override
  Future<void> verifySignUpCode(String email, String code) async {
    calls.add('code:$email:$code');
    if (code != '123456') {
      throw const EmailAuthException(EmailAuthError.badCode);
    }
  }

  @override
  Future<void> resendConfirmation(String email) async =>
      calls.add('resend:$email');

  @override
  Future<void> signOut() async => calls.add('out');

  @override
  Future<bool> signInWithApple() async {
    calls.add('apple');
    return true;
  }

  @override
  bool get hasApple => false;
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  group('Проверка формы на телефоне', () {
    test('почта', () {
      expect(checkEmail('mama@example.com'), isNull);
      expect(checkEmail('  mama@example.com '), isNull);
      expect(checkEmail('mama@example'), EmailAuthError.invalidEmail);
      expect(checkEmail('mama example.com'), EmailAuthError.invalidEmail);
      expect(checkEmail(''), EmailAuthError.invalidEmail);
    });

    test('пароль не короче шести знаков', () {
      expect(checkPassword('12345'), EmailAuthError.weakPassword);
      expect(checkPassword('123456'), isNull);
    });

    test('коды Supabase переводятся в понятные причины', () {
      expect(
        emailErrorFromCode('user_already_exists', statusCode: '422'),
        EmailAuthError.alreadyRegistered,
      );
      expect(
        emailErrorFromCode('invalid_credentials', statusCode: '400'),
        EmailAuthError.wrongCredentials,
      );
      expect(
        emailErrorFromCode('email_not_confirmed', statusCode: '400'),
        EmailAuthError.notConfirmed,
      );
      expect(
        emailErrorFromCode('email_provider_disabled', statusCode: '422'),
        EmailAuthError.disabled,
      );
      expect(
        emailErrorFromCode('over_email_send_rate_limit', statusCode: '429'),
        EmailAuthError.rateLimited,
      );
      expect(emailErrorFromCode(null), EmailAuthError.network);
      expect(
        emailErrorFromCode('x', statusCode: '500'),
        EmailAuthError.unknown,
      );
    });
  });

  group('Экран почты', () {
    Future<(_FakeAuth, List<int>)> open(
      WidgetTester tester, {
      _FakeAuth? auth,
    }) async {
      final fake = auth ?? _FakeAuth();
      final entered = <int>[];
      await tester.pumpWidget(
        _app(
          EmailAuthScreen(auth: fake, onSignedIn: () async => entered.add(1)),
        ),
      );
      await tester.pumpAndSettle();
      return (fake, entered);
    }

    Future<void> fill(
      WidgetTester tester,
      String email,
      String password,
    ) async {
      await tester.enterText(find.byKey(const ValueKey('email')), email);
      await tester.enterText(find.byKey(const ValueKey('password')), password);
      await tester.pump();
    }

    testWidgets('регистрация без подтверждения пускает сразу', (tester) async {
      final (auth, entered) = await open(tester);
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.text('Зарегистрироваться'));
      // Дальше приложение перезапускается от нового кабинета, а до тех пор
      // крутится колесо — ждать его остановки нечего.
      await tester.pump();
      await tester.pump();

      expect(auth.calls, ['up:mama@example.com']);
      expect(entered, [1]);
    });

    testWidgets('после регистрации — код из письма, без него не пускает', (
      tester,
    ) async {
      final (auth, entered) = await open(
        tester,
        auth: _FakeAuth()..outcome = SignUpOutcome.confirmEmail,
      );
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();

      expect(entered, isEmpty, reason: 'без кода не пускает');
      expect(find.text('Введите код из письма'), findsOneWidget);
      expect(find.textContaining('mama@example.com'), findsOneWidget);
      expect(find.text('Отправить ещё раз через 60 с'), findsOneWidget);

      // Неверный код: проверка сразу по шестой цифре, человек остаётся.
      await tester.enterText(find.byKey(const ValueKey('code')), '000000');
      await tester.pumpAndSettle();
      expect(auth.calls.last, 'code:mama@example.com:000000');
      expect(
        find.text('Код неверный или устарел — запросите новый'),
        findsOneWidget,
      );
      expect(entered, isEmpty);

      // Через минуту можно попросить новый код.
      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Отправить код ещё раз'));
      await tester.pump();
      expect(auth.calls.last, 'resend:mama@example.com');

      // Верный код — вошли.
      await tester.enterText(find.byKey(const ValueKey('code')), '123456');
      await tester.pump();
      await tester.pump();
      expect(auth.calls.last, 'code:mama@example.com:123456');
      expect(entered, [1]);

      // Досчитать паузу повторной отправки, чтобы не осталось таймеров.
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('вход с неподтверждённой почтой ведёт к вводу кода', (
      tester,
    ) async {
      await open(tester, auth: _FakeAuth()..fail = EmailAuthError.notConfirmed);
      await tester.tap(find.text('Вход'));
      await tester.pumpAndSettle();
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(
        find.text('Почта не подтверждена — введите код из письма'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ввести код из письма'));
      await tester.pumpAndSettle();
      expect(find.text('Введите код из письма'), findsOneWidget);
      // Письмо не отправляли только что — повторная отправка доступна сразу.
      expect(find.text('Отправить код ещё раз'), findsOneWidget);
    });

    testWidgets('неверная форма на сервер не уходит', (tester) async {
      final (auth, _) = await open(tester);
      await fill(tester, 'mama@', '123');
      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();

      expect(auth.calls, isEmpty);
      expect(find.text('Проверьте адрес почты'), findsOneWidget);
      expect(find.text('Пароль не короче 6 знаков'), findsOneWidget);
    });

    testWidgets('занятая почта — подсказка войти', (tester) async {
      final (auth, _) = await open(
        tester,
        auth: _FakeAuth()..fail = EmailAuthError.alreadyRegistered,
      );
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();

      expect(
        find.text('Эта почта уже зарегистрирована — войдите'),
        findsOneWidget,
      );
      auth.fail = null;
      await tester.tap(find.widgetWithText(TextButton, 'Войти'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();
      await tester.pump();
      expect(auth.calls.last, 'in:mama@example.com');
    });

    testWidgets('вход с неверным паролем', (tester) async {
      final (auth, entered) = await open(
        tester,
        auth: _FakeAuth()..fail = EmailAuthError.wrongCredentials,
      );
      await tester.tap(find.text('Вход'));
      await tester.pumpAndSettle();
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['in:mama@example.com']);
      expect(entered, isEmpty);
      expect(find.text('Неверная почта или пароль'), findsOneWidget);
    });

    testWidgets('без сервера — честно «нет связи»', (tester) async {
      await tester.pumpWidget(
        _app(EmailAuthScreen(auth: null, onSignedIn: () async {})),
      );
      await tester.pumpAndSettle();
      await fill(tester, 'mama@example.com', 'secret1');
      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();
      expect(
        find.text('Нет связи с сервером — попробуйте ещё раз'),
        findsOneWidget,
      );
    });
  });

  group('Стартовая страница', () {
    testWidgets('Apple, Google, ниже почта; китайских способов нет', (
      tester,
    ) async {
      var email = 0;
      await tester.pumpWidget(
        _app(SignInScreen(onSignedIn: () {}, onEmail: (_) => email++)),
      );
      await tester.pumpAndSettle();

      final apple = tester.getCenter(find.text('Войти через Apple')).dy;
      final google = tester.getCenter(find.text('Войти через Google')).dy;
      final mail = tester.getCenter(find.text('Регистрация по почте')).dy;
      expect(apple < google && google < mail, isTrue, reason: 'порядок');

      expect(find.textContaining('WeChat'), findsNothing);
      expect(find.textContaining('Alipay'), findsNothing);
      expect(find.textContaining('QQ'), findsNothing);

      await tester.tap(find.text('Регистрация по почте'));
      await tester.pump();
      expect(email, 1);
    });

    testWidgets('Apple и Google: «в разработке» сверху, внутрь не пускают', (
      tester,
    ) async {
      var entered = 0;
      await tester.pumpWidget(
        _app(SignInScreen(onSignedIn: () => entered++, onEmail: (_) {})),
      );
      await tester.pumpAndSettle();

      for (final button in ['Войти через Apple', 'Войти через Google']) {
        await tester.tap(find.text(button));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Данная функция ещё в разработке'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Данная функция ещё в разработке'), findsNothing);
      }
      expect(entered, 0, reason: 'вход только по почте');

      await tester.tap(find.text('Пропустить и посмотреть приложение'));
      await tester.pump();
      expect(entered, 1);
    });
  });

  group('Личный кабинет в профиле', () {
    testWidgets('почта, день рождения, знак, кошелёк', (tester) async {
      final bear = BearController();
      final game = GameState(
        bear: bear,
        profile: PetProfile(
          name: 'Тедди',
          birthAt: DateTime(2026, 9, 24, 12),
          zodiac: BearZodiac.libra,
        ),
        walletFloor: 0,
        account: AccountInfo(
          isAnonymous: false,
          email: 'mama@example.com',
          providers: const {'email'},
          registeredAt: DateTime(2026, 9, 24, 12),
        ),
      )..earn(5000);
      addTearDown(() {
        game.dispose();
        bear.dispose();
      });

      await tester.pumpWidget(
        _app(
          ProfileScreen(
            controller: bear,
            game: game,
            onOpenGrowth: () {},
            onOpenDiary: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('♎ Весы'), findsOneWidget);
      // «г.» intl отделяет неразрывным пробелом — сверяем начало.
      expect(find.textContaining('24 сентября 2026'), findsWidgets);

      // Лист длинный: смотрим и то, что ниже края экрана.
      expect(find.text('Личный кабинет', skipOffstage: false), findsOneWidget);
      expect(
        find.text('mama@example.com · не подтверждена', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('5000', skipOffstage: false), findsOneWidget);
    });
  });
}
