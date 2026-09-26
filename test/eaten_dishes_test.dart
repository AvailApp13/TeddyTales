import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teddy_tales/game/eaten_dishes.dart';

/// Съеденное блюдо уходит со стола до следующего голода (заказчик 24.09).
void main() {
  var now = DateTime(2026, 9, 24, 12);
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 9, 24, 12));

  test('съеденное блюдо пропадает, остальные на месте', () {
    final eaten = EatenDishes(clock: clock, returnAfter: null)..eat('pasta');
    expect(eaten.isEaten('pasta'), isTrue);
    expect(eaten.isEaten('soup'), isFalse);
  });

  test('сытый мишка — блюдо не возвращается', () {
    final eaten = EatenDishes(clock: clock, returnAfter: null)..eat('pasta');
    now = now.add(const Duration(hours: 5));
    eaten.refresh(food: 87);
    expect(eaten.isEaten('pasta'), isTrue);
  });

  test('проголодался — возвращаются все съеденные', () {
    final eaten = EatenDishes(clock: clock, returnAfter: null)
      ..eat('pasta')
      ..eat('pie');
    var changes = 0;
    eaten.addListener(() => changes++);
    eaten.refresh(food: EatenDishes.hungryAt);
    expect(eaten.eaten, isEmpty);
    expect(changes, 1);
  });

  test('на испытаниях блюдо возвращается само через заданное время', () {
    final eaten = EatenDishes(
      clock: clock,
      returnAfter: const Duration(minutes: 3),
    )..eat('pasta');
    now = now.add(const Duration(minutes: 2));
    eaten
      ..eat('soup')
      ..refresh(food: 87);
    expect(eaten.eaten, {'pasta', 'soup'});

    now = now.add(const Duration(minutes: 1));
    eaten.refresh(food: 87);
    expect(eaten.eaten, {'soup'});
  });

  test('список переживает перезапуск приложения', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await EatenDishes.open(clock: clock);
    first.eat('omelette');
    await Future<void>.delayed(Duration.zero);

    final second = await EatenDishes.open(clock: clock);
    expect(second.isEaten('omelette'), isTrue);
    expect(second.isEaten('pasta'), isFalse);
  });
}
