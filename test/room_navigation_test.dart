import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/game/room_kind.dart';

/// Комната как следствие действия (решение заказчика 20.09).
///
/// До этого комнату выбирали тремя кнопками — детская, кухня, ванная. Кнопки
/// оказались дублями: ванная и есть гигиена, кухня и есть еда, детская и есть
/// главная. Здесь проверяется, что связь одна и та же в обе стороны и что
/// дубль не заведётся заново.
void main() {
  group('Куда уводит действие', () {
    test('покормить — на кухню, помыть — в ванную', () {
      expect(roomForAction(BearAction.feed), RoomKind.kitchen);
      expect(roomForAction(BearAction.wash), RoomKind.bath);
    });

    test('уложить и поиграть — домой, в детскую', () {
      // Спальня появится, когда будет её фон: заказчик решил 20.09, что сон
      // получит свою комнату с кроваткой. До тех пор спим дома.
      expect(roomForAction(BearAction.sleep), RoomKind.nursery);
      expect(roomForAction(BearAction.play), RoomKind.nursery);
    });

    test('погладить можно где угодно — комната не меняется', () {
      // Иначе поглаживание в ванной телепортировало бы мокрого мишку домой.
      expect(roomForAction(BearAction.pet), isNull);
      expect(roomForAction(BearAction.wake), isNull);
    });

    test('разделы комнату не двигают', () {
      for (final action in [
        BearAction.learn,
        BearAction.dressUp,
        BearAction.decorate,
      ]) {
        expect(roomForAction(action), isNull, reason: action.name);
      }
    });

    test('в каждую нарисованную комнату есть чем попасть', () {
      // Комната, куда не ведёт ни одно действие, после отказа от кнопок
      // переключения стала бы недостижимой.
      final reachable = {
        for (final action in BearAction.values) roomForAction(action),
      }..remove(null);

      expect(reachable, RoomKind.values.toSet());
    });
  });
}
