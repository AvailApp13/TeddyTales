import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Адрес этого телефона для push с сервера (КП 13.1): «Событие» и
/// «Новинки магазина» знает только сервер, остальные типы телефон
/// считает сам ([NotificationService]).
///
/// iPhone отдаёт токен APNs через канал `teddytales/push`
/// (`ios/Runner/AppDelegate.swift`, `PushTokenPlugin`). ⚠ Android — после
/// проекта Firebase: пока `null`.
abstract final class PushRegistration {
  static const MethodChannel _channel = MethodChannel('teddytales/push');

  /// Токен устройства или `null`: не iPhone, Apple не ответила, нет права
  /// push в сборке. Игра от этого не ломается — просто без серверных
  /// уведомлений.
  static Future<String?> deviceToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      return await _channel
          .invokeMethod<String>('register')
          .timeout(const Duration(seconds: 15));
    } on Object catch (error) {
      debugPrint('Токен push не получен: $error');
      return null;
    }
  }
}
