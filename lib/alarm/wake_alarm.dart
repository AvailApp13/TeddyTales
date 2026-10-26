import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';

/// Чем закончилась попытка поставить будильник «проснёмся вместе».
enum WakeAlarmOutcome {
  /// Android: будильник стоит в системных «Часах».
  clock,

  /// iPhone с iOS 26: системный будильник AlarmKit — звонит и в
  /// беззвучном режиме, на заблокированном экране во весь экран.
  alarmKit,

  /// Системного будильника нет (iPhone до iOS 26, Android без «Часов»,
  /// разрешение AlarmKit не дали) — стоит уведомление со звуком.
  notification,

  /// Веб-версия для просмотра: будильник на телефоне поставится, здесь нет.
  preview,

  /// Человек не разрешил ни будильник, ни уведомления.
  denied,

  /// Что-то пошло не так на стороне телефона.
  failed,
}

/// Запасное уведомление: запланировать на [at]. `true` — поставлено.
typedef WakeFallback =
    Future<bool> Function(DateTime at, String title, String body);

/// Будильник «проснёмся вместе» из спальни.
///
/// Приложение само не звонит: время уходит в будильник телефона —
/// Android получает его в «Часы» (`AlarmClock.ACTION_SET_ALARM`), iPhone с
/// iOS 26 ставит системный будильник AlarmKit. Там, где этого нет, ставится
/// уведомление со звуком ([fallback]). Нативная часть — канал
/// `teddytales/wake_alarm` в `MainActivity.kt` и `AppDelegate.swift`.
///
/// Заказчик 24.09: «при нажатии ОК переходить на будильник мобильного
/// устройства и будить хозяина»; сделать для айфонов разных iOS и для
/// андроидов.
class WakeAlarm {
  WakeAlarm({
    this.fallback,
    this.cancelFallback,
    MethodChannel? channel,
    bool? web,
  }) : _channel = channel ?? const MethodChannel('teddytales/wake_alarm'),
       _web = web ?? kIsWeb;

  final WakeFallback? fallback;
  final Future<void> Function()? cancelFallback;
  final MethodChannel _channel;
  final bool _web;

  /// Поставить будильник на [time]. [label] — подпись будильника, [stop] —
  /// кнопка «выключить» на iPhone, [body] — текст запасного уведомления.
  Future<WakeAlarmOutcome> set(
    TimeOfDay time, {
    required String label,
    required String stop,
    required String body,
    DateTime? now,
  }) async {
    if (_web) return WakeAlarmOutcome.preview;

    String native;
    try {
      native =
          await _channel.invokeMethod<String>('set', {
            'hour': time.hour,
            'minute': time.minute,
            'label': label,
            'stop': stop,
          }) ??
          'failed';
    } on MissingPluginException {
      native = 'unavailable';
    } on PlatformException catch (error) {
      debugPrint('[TeddyTales] будильник: ${error.code} ${error.message}');
      native = 'failed';
    }

    switch (native) {
      case 'clock':
        await cancelFallback?.call();
        return WakeAlarmOutcome.clock;
      case 'alarmKit':
        await cancelFallback?.call();
        return WakeAlarmOutcome.alarmKit;
    }

    // Системного будильника нет или его не разрешили — хотя бы уведомление.
    final schedule = fallback;
    if (schedule == null) {
      return native == 'denied'
          ? WakeAlarmOutcome.denied
          : WakeAlarmOutcome.failed;
    }
    final ok = await schedule(
      nextOccurrence(time, now ?? DateTime.now()),
      label,
      body,
    );
    return ok ? WakeAlarmOutcome.notification : WakeAlarmOutcome.denied;
  }

  /// Снять будильник: системный на iPhone и запасное уведомление. Из
  /// «Часов» Android чужое приложение будильник убрать не может.
  Future<void> cancel() async {
    if (_web) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Нет нативной части — снимать нечего.
    } on PlatformException catch (error) {
      debugPrint('[TeddyTales] будильник не снят: ${error.code}');
    }
    await cancelFallback?.call();
  }

  /// Открыть список будильников в «Часах» (только Android).
  Future<bool> openClock() async {
    if (_web) return false;
    try {
      return await _channel.invokeMethod<bool>('openClock') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Ближайший момент [time] после [now]: сегодня, если ещё не прошло,
  /// иначе завтра. Как у будильника в «Часах».
  static DateTime nextOccurrence(TimeOfDay time, DateTime now) {
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, time.hour, time.minute);
  }
}
