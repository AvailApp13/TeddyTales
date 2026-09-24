/// Регистрация и вход по почте (КП 1.3).
///
/// Заказчик 24.09: «пока до подключения App Store и Google Play — чтобы люди
/// могли регистрироваться по почте… тестировать каждого пользователя, его
/// регистрацию, привязку личного кабинета». Кабинет с мишкой, кошельком и
/// знаком зодиака заводит сервер в момент регистрации (миграции 0010, 0011).
library;

/// Что не так. Экран переводит это на язык интерфейса.
enum EmailAuthError {
  /// Адрес не похож на почту.
  invalidEmail,

  /// Пароль короче [minPasswordLength] или сервер счёл его слабым.
  weakPassword,

  /// Такая почта уже зарегистрирована — надо войти.
  alreadyRegistered,

  /// Неверная почта или пароль.
  wrongCredentials,

  /// Почта не подтверждена: человек не открыл письмо со ссылкой.
  notConfirmed,

  /// Регистрация по почте выключена в настройках Supabase.
  disabled,

  /// Слишком много писем подряд — лимит почтового сервиса.
  rateLimited,

  /// До сервера не достучались.
  network,

  /// Остальное.
  unknown,
}

/// Наименьшая длина пароля — как в настройках Supabase по умолчанию.
const int minPasswordLength = 6;

/// Проверка адреса на устройстве. Настоящую проверку делает письмо.
EmailAuthError? checkEmail(String raw) {
  final email = raw.trim();
  final shape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  return shape.hasMatch(email) ? null : EmailAuthError.invalidEmail;
}

EmailAuthError? checkPassword(String password) =>
    password.length < minPasswordLength ? EmailAuthError.weakPassword : null;

/// Чем кончилась регистрация.
enum SignUpOutcome {
  /// Вошли сразу: подтверждение почты в Supabase выключено.
  signedIn,

  /// Ушло письмо со ссылкой; войти можно после подтверждения.
  confirmEmail,
}

class EmailAuthException implements Exception {
  const EmailAuthException(this.error, {this.cause});

  final EmailAuthError error;
  final Object? cause;

  @override
  String toString() =>
      'EmailAuthException(${error.name}${cause == null ? '' : ': $cause'})';
}

/// Учётная запись: вход, регистрация, выход.
///
/// Отдельно от [ProgressStore]: прогресс бывает и в памяти (без сети), а
/// учётная запись — только на сервере.
abstract interface class AccountAuth {
  /// Есть ли сессия на этом устройстве.
  bool get isSignedIn;

  /// Бросает [EmailAuthException].
  Future<SignUpOutcome> signUpWithEmail(String email, String password);

  /// Бросает [EmailAuthException].
  Future<void> signInWithEmail(String email, String password);

  /// Отправить письмо подтверждения ещё раз.
  Future<void> resendConfirmation(String email);

  /// Выйти на этом устройстве.
  Future<void> signOut();
}

/// Код ошибки Supabase Auth → наша причина.
EmailAuthError emailErrorFromCode(String? code, {String? statusCode}) =>
    switch (code) {
      'user_already_exists' ||
      'email_exists' => EmailAuthError.alreadyRegistered,
      'invalid_credentials' => EmailAuthError.wrongCredentials,
      'email_not_confirmed' => EmailAuthError.notConfirmed,
      'weak_password' => EmailAuthError.weakPassword,
      'email_address_invalid' => EmailAuthError.invalidEmail,
      'email_provider_disabled' || 'signup_disabled' => EmailAuthError.disabled,
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => EmailAuthError.rateLimited,
      _ when statusCode == null => EmailAuthError.network,
      _ => EmailAuthError.unknown,
    };
