import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/email_auth.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Регистрация и вход по почте (КП 1.3).
///
/// Заказчик 24.09: пока нет App Store и Google Play, люди регистрируются по
/// почте, и на этом проверяется весь путь — учётная запись, личный кабинет,
/// день рождения мишки и знак зодиака. Всё это заводит сервер в момент
/// регистрации; экран только собирает почту с паролем и объясняет, что
/// дальше.
///
/// После регистрации на почту приходит код из шести цифр; войти можно,
/// только введя его (заказчик 24.09). Для этого в Supabase включено
/// подтверждение почты, а в письме стоит код (`docs/account.md`). Если
/// подтверждение выключено, сервер пускает сразу — экран это тоже умеет.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({
    super.key,
    required this.auth,
    required this.onSignedIn,
    this.startWithSignIn = false,
  });

  /// `null` — сервер не поднялся: экран честно скажет «нет связи».
  final AccountAuth? auth;

  /// Вошли: приложение перезапускается от нового кабинета.
  final Future<void> Function() onSignedIn;

  final bool startWithSignIn;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// Сколько секунд ждать до повторной отправки кода. Supabase не шлёт
  /// письма чаще раза в минуту — кнопка не обещает то, чего не будет.
  static const int _resendPause = 60;
  int _resendIn = 0;
  Timer? _resendTimer;

  late bool _signIn = widget.startWithSignIn;
  bool _busy = false;
  bool _showPassword = false;

  /// Пробовали отправить — с этого момента подсвечиваем ошибки формы.
  bool _tried = false;

  /// Ответ сервера. Сбрасывается правкой любого поля.
  EmailAuthError? _serverError;

  /// Почта, на которую ушло письмо с кодом. Не `null` — экран ввода кода.
  String? _sentTo;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Перейти к вводу кода для [email]. [justSent] — письмо только что ушло,
  /// повторная отправка откроется через минуту.
  void _askCode(String email, {required bool justSent}) {
    _code.clear();
    setState(() {
      _busy = false;
      _serverError = null;
      _sentTo = email;
    });
    if (justSent) _startResendPause();
  }

  void _startResendPause() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendPause);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final email = _sentTo;
    final auth = widget.auth;
    if (email == null || _busy || !isSignUpCode(_code.text)) return;
    if (auth == null) {
      setState(() => _serverError = EmailAuthError.network);
      return;
    }
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await auth.verifySignUpCode(email, _code.text);
      await widget.onSignedIn();
    } on EmailAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = error.error;
      });
    }
  }

  EmailAuthError? get _emailError => checkEmail(_email.text);
  EmailAuthError? get _passwordError => checkPassword(_password.text);

  void _edited(String _) => setState(() => _serverError = null);

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (_emailError != null || _passwordError != null || _busy) return;

    final auth = widget.auth;
    if (auth == null) {
      setState(() => _serverError = EmailAuthError.network);
      return;
    }

    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      final email = _email.text.trim();
      if (_signIn) {
        await auth.signInWithEmail(email, _password.text);
      } else {
        final outcome = await auth.signUpWithEmail(email, _password.text);
        if (outcome == SignUpOutcome.confirmEmail) {
          if (!mounted) return;
          _askCode(email, justSent: true);
          return;
        }
      }
      await widget.onSignedIn();
    } on EmailAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = error.error;
      });
    }
  }

  Future<void> _resend() async {
    final email = _sentTo;
    final auth = widget.auth;
    if (email == null || auth == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    _startResendPause();
    try {
      await auth.resendConfirmation(email);
      messenger.showSnackBar(SnackBar(content: Text(l10n.emailCodeSent)));
    } on EmailAuthException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorText(l10n, error.error))),
      );
    }
  }

  static String _errorText(AppLocalizations l10n, EmailAuthError error) =>
      switch (error) {
        EmailAuthError.invalidEmail => l10n.emailErrorInvalid,
        EmailAuthError.weakPassword => l10n.emailErrorPassword(
          minPasswordLength,
        ),
        EmailAuthError.alreadyRegistered => l10n.emailErrorExists,
        EmailAuthError.wrongCredentials => l10n.emailErrorCredentials,
        EmailAuthError.notConfirmed => l10n.emailErrorNotConfirmed,
        EmailAuthError.badCode => l10n.emailErrorCode,
        EmailAuthError.disabled => l10n.emailErrorDisabled,
        EmailAuthError.rateLimited => l10n.emailErrorRateLimit,
        EmailAuthError.network => l10n.emailErrorNetwork,
        EmailAuthError.unknown => l10n.emailErrorUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.emailTitle),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sentTo == null ? _form(l10n) : _sent(l10n, _sentTo!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l10n) {
    final emailError = _tried && _emailError != null
        ? _errorText(l10n, _emailError!)
        : null;
    final passwordError = _tried && _passwordError != null
        ? _errorText(l10n, _passwordError!)
        : null;
    final serverError = _serverError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l10n.emailTabSignUp)),
            ButtonSegment(value: true, label: Text(l10n.emailTabSignIn)),
          ],
          selected: {_signIn},
          showSelectedIcon: false,
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() {
                  _signIn = value.first;
                  _serverError = null;
                }),
        ),
        const SizedBox(height: 16),
        Text(
          _signIn ? l10n.emailLeadSignIn : l10n.emailLeadSignUp,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('email'),
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.emailField,
            errorText: emailError,
            border: const OutlineInputBorder(),
          ),
          onChanged: _edited,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('password'),
          controller: _password,
          enabled: !_busy,
          obscureText: !_showPassword,
          autofillHints: [
            _signIn ? AutofillHints.password : AutofillHints.newPassword,
          ],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.emailPassword,
            helperText: _signIn
                ? null
                : l10n.emailPasswordHint(minPasswordLength),
            errorText: passwordError,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onChanged: _edited,
          onSubmitted: (_) => _submit(),
        ),
        if (serverError != null) ...[
          const SizedBox(height: 14),
          Text(
            _errorText(l10n, serverError),
            key: const ValueKey('server-error'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (serverError == EmailAuthError.notConfirmed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _askCode(_email.text.trim(), justSent: false),
                child: Text(l10n.emailEnterCode),
              ),
            ),
          if (serverError == EmailAuthError.alreadyRegistered && !_signIn)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _signIn = true;
                  _serverError = null;
                }),
                child: Text(l10n.emailSubmitSignIn),
              ),
            ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.sageDark,
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _signIn ? l10n.emailSubmitSignIn : l10n.emailSubmitSignUp,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sent(AppLocalizations l10n, String email) {
    final serverError = _serverError;
    final ready = isSignUpCode(_code.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 56,
          color: AppColors.sageDark,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.emailCodeTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.emailCodeBody(email, signUpCodeLength),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 22),
        TextField(
          key: const ValueKey('code'),
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          style: const TextStyle(
            fontSize: 28,
            letterSpacing: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: '•' * signUpCodeLength,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() => _serverError = null);
            // Код вставили или набрали целиком — проверяем сразу, без
            // лишнего нажатия. Длиннее шести тоже бывает: длина кода
            // настраивается в Supabase.
            if (value.length == signUpCodeLength) _verify();
          },
          onSubmitted: (_) => _verify(),
        ),
        if (serverError != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText(l10n, serverError),
            key: const ValueKey('code-error'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || !ready ? null : _verify,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.sageDark,
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  l10n.emailCodeSubmit,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendIn > 0 || _busy ? null : _resend,
          child: Text(
            _resendIn > 0
                ? l10n.emailCodeResendIn(_resendIn)
                : l10n.emailCodeResend,
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _sentTo = null;
                  _serverError = null;
                }),
          child: Text(l10n.emailCodeChangeEmail),
        ),
      ],
    );
  }
}
