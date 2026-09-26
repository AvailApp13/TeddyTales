import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/alarm/wake_alarm.dart';

/// Будильник «проснёмся вместе» (заказчик 24.09): по «ОК» время уходит в
/// будильник телефона, а где его нет — ставится уведомление со звуком.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('teddytales/wake_alarm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<DateTime> fallbackAt;
  late int fallbackCancels;
  late bool fallbackResult;

  WakeAlarm make({bool web = false}) => WakeAlarm(
    web: web,
    fallback: (at, title, body) async {
      fallbackAt.add(at);
      return fallbackResult;
    },
    cancelFallback: () async => fallbackCancels++,
  );

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(() {
    calls = [];
    fallbackAt = [];
    fallbackCancels = 0;
    fallbackResult = true;
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final now = DateTime(2026, 9, 24, 22, 15);
  const morning = TimeOfDay(hour: 7, minute: 30);

  Future<WakeAlarmOutcome> set(WakeAlarm alarm) => alarm.set(
    morning,
    label: 'Проснёмся вместе с Тишкой',
    stop: 'Проснулись',
    body: 'Тишка уже не спит',
    now: now,
  );

  test(
    'Android: будильник уходит в «Часы» с часом, минутой и подписью',
    () async {
      answer((_) => 'clock');
      expect(await set(make()), WakeAlarmOutcome.clock);
      expect(calls.single.method, 'set');
      expect(calls.single.arguments, {
        'hour': 7,
        'minute': 30,
        'label': 'Проснёмся вместе с Тишкой',
        'stop': 'Проснулись',
      });
      expect(fallbackAt, isEmpty, reason: 'запасное уведомление не нужно');
      expect(fallbackCancels, 1, reason: 'прежнее запасное снимается');
    },
  );

  test('iPhone с iOS 26: системный будильник AlarmKit', () async {
    answer((_) => 'alarmKit');
    expect(await set(make()), WakeAlarmOutcome.alarmKit);
    expect(fallbackAt, isEmpty);
  });

  test('iPhone до iOS 26: уведомление со звуком на ближайшие 7:30', () async {
    answer((_) => 'unavailable');
    expect(await set(make()), WakeAlarmOutcome.notification);
    expect(fallbackAt, [DateTime(2026, 9, 25, 7, 30)]);
  });

  test('будильник AlarmKit не разрешили — хотя бы уведомление', () async {
    answer((_) => 'denied');
    expect(await set(make()), WakeAlarmOutcome.notification);
    expect(fallbackAt, hasLength(1));
  });

  test('не разрешили ни будильник, ни уведомления — честно говорим', () async {
    answer((_) => 'denied');
    fallbackResult = false;
    expect(await set(make()), WakeAlarmOutcome.denied);
  });

  test('нативной части нет — запасной путь, без падения', () async {
    // Обработчик не задан: MissingPluginException.
    expect(await set(make()), WakeAlarmOutcome.notification);
  });

  test('ошибка телефона — запасной путь', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    expect(await set(make()), WakeAlarmOutcome.notification);
  });

  test('веб-версия для просмотра: телефон не трогаем', () async {
    answer((_) => 'clock');
    expect(await set(make(web: true)), WakeAlarmOutcome.preview);
    expect(calls, isEmpty);
    expect(fallbackAt, isEmpty);
  });

  test('снять: системный будильник и запасное уведомление', () async {
    answer((_) => null);
    await make().cancel();
    expect(calls.single.method, 'cancel');
    expect(fallbackCancels, 1);
  });

  group('ближайшее время будильника', () {
    test('ещё не наступило — сегодня', () {
      expect(
        WakeAlarm.nextOccurrence(morning, DateTime(2026, 9, 24, 6, 0)),
        DateTime(2026, 9, 24, 7, 30),
      );
    });
    test('уже прошло — завтра', () {
      expect(
        WakeAlarm.nextOccurrence(morning, DateTime(2026, 9, 24, 7, 31)),
        DateTime(2026, 9, 25, 7, 30),
      );
    });
    test('ровно сейчас — завтра, а не мгновенный звонок', () {
      expect(
        WakeAlarm.nextOccurrence(morning, DateTime(2026, 9, 24, 7, 30)),
        DateTime(2026, 9, 25, 7, 30),
      );
    });
    test('конец месяца переходит на следующий', () {
      expect(
        WakeAlarm.nextOccurrence(morning, DateTime(2026, 9, 30, 23, 0)),
        DateTime(2026, 10, 1, 7, 30),
      );
    });
  });
}
