import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_phrases.dart' show BearLanguage;
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/notifications/care_schedule.dart';
import 'package:teddy_tales/notifications/smart_texts.dart';

/// «Мишка заботится о тебе» (сверх ТЗ, заказчик 25.09): вода и сон.
void main() {
  test('вода днём, сон за четверть часа до тихих часов', () {
    const schedule = CareSchedule();
    expect(CareSchedule.waterHours, [11, 14, 17]);
    for (final hour in CareSchedule.waterHours) {
      expect(
        schedule.respectQuietHours(DateTime(2026, 9, 25, hour)).hour,
        hour,
      );
    }
    expect(schedule.restTime, (hour: 21, minute: 45));
    expect(const CareSchedule(quietFrom: 0).restTime, (hour: 23, minute: 45));
  });

  test('ближайший момент — сегодня или завтра', () {
    final now = DateTime(2026, 9, 25, 15, 30);
    expect(CareSchedule.nextAt(now, 17), DateTime(2026, 9, 25, 17));
    expect(CareSchedule.nextAt(now, 11), DateTime(2026, 9, 26, 11));
    expect(CareSchedule.nextAt(now, 21, 45), DateTime(2026, 9, 25, 21, 45));
  });

  test('тексты от имени мишки на трёх языках', () {
    for (final lang in BearLanguage.values) {
      for (final kind in ['water', 'rest']) {
        final copy = composeNotification(kind, name: 'Тедди', lang: lang);
        expect('${copy.title} ${copy.body}', contains('Тедди'));
        expect(copy.title, isNot(contains('{name}')));
      }
    }
    expect(
      composeNotification('water', name: 'Тедди', lang: BearLanguage.ru).title,
      'Тедди пьёт водичку',
    );
  });

  test('по умолчанию включены, переключаются отдельно', () {
    expect(GameState.selfCareKinds, ['water', 'rest']);
  });
}
