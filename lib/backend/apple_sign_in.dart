import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Вход через Apple (КП 1.3).
///
/// ⚠ ЖДЁТ НАСТРОЙКИ (заказчик 26.09 — «код подготовить сейчас»). Пока
/// флаг выключен, кнопка Apple на стартовой странице показывает «в
/// разработке», как раньше, и привязки в настройках нет. Включить:
///
/// 1. developer.apple.com → Identifiers → `com.teddytales.app` →
///    галочка **Sign in with Apple**.
/// 2. Supabase → Authentication → Sign In / Providers → **Apple**:
///    Client IDs = `com.teddytales.app`; там же **Allow manual linking**
///    (привязка Apple к гостевому кабинету).
/// 3. В Xcode-проект — `ios/Runner/Runner.entitlements` с
///    `com.apple.developer.applesignin` = `[Default]` (файл лежит в
///    `docs/apple-sign-in.entitlements`, подключить — `docs/account.md`).
///    Раньше шага 1 нельзя: подпись в Codemagic упадёт.
/// 4. Сборка с `--dart-define=APPLE_SIGN_IN=true`.
const bool kAppleSignIn = bool.fromEnvironment('APPLE_SIGN_IN');

/// Можно ли входить через Apple на этом устройстве: флаг и iPhone/iPad.
bool get appleSignInReady =>
    kAppleSignIn && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Что Apple отдала: токен для Supabase и нонс, которым он подписан.
typedef AppleCredential = ({String idToken, String rawNonce});

/// Системное окно «Войти с Apple». `null` — человек передумал.
Future<AppleCredential?> requestAppleCredential() async {
  final rawNonce = _nonce();
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final token = credential.identityToken;
    if (token == null) return null;
    return (idToken: token, rawNonce: rawNonce);
  } on SignInWithAppleAuthorizationException catch (error) {
    if (error.code == AuthorizationErrorCode.canceled) return null;
    rethrow;
  }
}

String _nonce([int length = 32]) {
  const chars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}
