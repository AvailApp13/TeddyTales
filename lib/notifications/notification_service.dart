import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../bear/bear_phrases.dart' show BearLanguage;
import '../bear/bear_stats.dart';
import 'care_schedule.dart';
import 'notification_texts.dart';

/// Напоминания об уходе (КП 13).
///
/// Уведомления здесь **локальные**: телефон показывает их сам, по заранее
/// рассчитанному времени. Так они работают без сети и без серверной части —
/// а серверные пуши (новинки магазина, события, подарки) добавятся рядом,
/// когда будут ключи, и займут те же восемь типов.
///
/// Разделение не временное, а правильное: «проголодался» телефон знает сам,
/// потому что скорость падения показателей ему известна, и гонять ради
/// этого запрос на сервер незачем. А «сегодня акция» знает только сервер.
///
/// ## Как считается время
///
/// Не «через шесть часов», а «когда сытость дойдёт до тридцати процентов» —
/// расчёт в [CareSchedule]. Поэтому напоминание не приходит тому, кто минуту
/// назад покормил, и не опаздывает к тому, кто не заходил сутки.
///
/// ## Почему перепланируем целиком
///
/// После каждого действия расписание отменяется и строится заново. Покормил —
/// прежнее «проголодался» уже неверно, и подправить его нельзя: сдвинулось
/// не только оно, но и порядок остальных, которые разводятся по времени.
class NotificationService {
  NotificationService(this._plugin, {this.schedule = const CareSchedule()});

  final FlutterLocalNotificationsPlugin _plugin;
  final CareSchedule schedule;

  bool _ready = false;

  /// Включённые типы (КП 13.2). Пустое множество — молчим совсем.
  Set<String> enabled = {'hungry', 'play', 'sleep'};

  /// Поднимает механизм уведомлений.
  ///
  /// Возвращает `null`, если не вышло: разрешение не дали, платформа не
  /// поддерживает, что-то ещё. Игра при этом обязана работать — молча, без
  /// напоминаний, но работать.
  static Future<NotificationService?> create() async {
    try {
      tz_data.initializeTimeZones();

      final plugin = FlutterLocalNotificationsPlugin();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Разрешение спрашиваем не при запуске, а когда игрок включает
          // напоминания в настройках: просьба в первую секунду знакомства
          // отклоняется чаще, чем принимается, а второго раза система не даёт.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );

      final ok = await plugin.initialize(settings: settings);
      final service = NotificationService(plugin);
      service._ready = ok ?? false;
      return service;
    } on Object catch (error) {
      debugPrint('[TeddyTales] уведомления недоступны: $error');
      return null;
    }
  }

  /// Спрашивает разрешение. Зовётся из настроек, когда игрок сам включает
  /// напоминания (КП 13.2).
  Future<bool> requestPermission() async {
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      return false;
    } on Object catch (error) {
      debugPrint('[TeddyTales] разрешение не получено: $error');
      return false;
    }
  }

  /// Перестраивает расписание под текущее состояние питомца.
  Future<void> reschedule({
    required BearCareStats stats,
    required BearDecayConfig decay,
    required BearLanguage language,
    DateTime? now,
  }) async {
    if (!_ready) return;

    await cancelAll();
    if (enabled.isEmpty) return;

    final plan = schedule.planFrom(stats, decay, now ?? DateTime.now());
    for (final entry in plan.entries) {
      if (!enabled.contains(entry.key)) continue;
      await _schedule(entry.key, entry.value, language);
    }
  }

  Future<void> _schedule(
    String kind,
    DateTime at,
    BearLanguage language,
  ) async {
    final text = notificationTexts[kind];
    if (text == null) return;

    try {
      await _plugin.zonedSchedule(
        id: _idOf(kind),
        title: text.title(language),
        body: text.body(language),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'care',
            'Напоминания об уходе',
            channelDescription: 'Малыш проголодался, хочет играть или спать',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on Object catch (error) {
      debugPrint('[TeddyTales] $kind не запланирован: $error');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } on Object catch (error) {
      debugPrint('[TeddyTales] не удалось снять уведомления: $error');
    }
  }

  /// Постоянный номер на тип: перепланирование должно заменять прежнее
  /// уведомление того же типа, а не добавлять второе.
  static int _idOf(String kind) => switch (kind) {
    'hungry' => 1,
    'play' => 2,
    'sleep' => 3,
    'task' => 4,
    'gift' => 5,
    'stage' => 6,
    'event' => 7,
    'shop' => 8,
    _ => 99,
  };
}
