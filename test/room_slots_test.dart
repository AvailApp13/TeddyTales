import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/room_slots.dart';
import 'package:teddy_tales/game/shop_items.dart';

/// Места в комнате (решение заказчика 18.09).
///
/// Проверяется обещание, которое слоты дают игроку: вещь не вылезает за
/// отведённое ей место, не стоит в двух местах разом и не пропадает, когда
/// её сменили другой.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'bed', 'armchair', 'rug', 'ball', 'pic_moon'},
      placed: const {},
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  group('Разметка', () {
    test('у каждого места свой ключ', () {
      final ids = roomSlots.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('без мест осталась только спальня, и то пока она заглушка', () {
      // Спальня пришла 20.09 картинкой с уже уложенным мишкой — обставлять
      // там пока нечего. Когда заказчик пришлёт её разметку, этот тест
      // напомнит, что список надо сократить.
      final empty = [
        for (final room in RoomKind.values)
          if (slotsOf(room).isEmpty) room,
      ];

      expect(empty, [RoomKind.bedroom]);
    });

    test('места не вылезают за кадр', () {
      for (final slot in roomSlots) {
        expect(slot.x - slot.maxW / 2, greaterThan(-0.15), reason: slot.id);
        expect(slot.x + slot.maxW / 2, lessThan(1.15), reason: slot.id);
        expect(slot.y, inInclusiveRange(0.0, 1.0), reason: slot.id);
      }
    });

    test('к каждому месту подходит хоть одна вещь каталога', () {
      for (final slot in roomSlots) {
        expect(
          ItemCatalog.all.any(slot.takes),
          isTrue,
          reason: 'в ${slot.id} нечего поставить',
        );
      }
    });
  });

  group('Размер вещи задаёт место', () {
    test('вещь вписывается в габарит и не выходит за него', () {
      for (final slot in roomSlots) {
        for (final item in ItemCatalog.all.where(slot.takes)) {
          final size = fitIntoSlot(slot, item);
          expect(size.w, lessThanOrEqualTo(slot.maxW + 1e-9), reason: item.id);
          expect(size.h, lessThanOrEqualTo(slot.maxH + 1e-9), reason: item.id);
        }
      }
    });

    test('пропорции вещи сохраняются', () {
      final slot = slotById('nursery.floor_left')!;
      final bed = ItemCatalog.byId('bed');
      final size = fitIntoSlot(slot, bed);

      // Кроватка 1.7 × 1.0 — вытянутая. Растянутая под квадратное место, она
      // перестала бы быть кроваткой.
      expect(size.w / size.h, closeTo(1.7, 0.01));
    });

    test('кроватка больше не занимает полкадра', () {
      final slot = slotById('nursery.floor_left')!;
      final size = fitIntoSlot(slot, ItemCatalog.byId('bed'));

      // Ровно та жалоба заказчика, с которой всё началось: «поставил туда
      // какую-то кровать большую».
      expect(size.w, lessThan(0.45));
    });
  });

  group('Что где стоит', () {
    test('вещь встаёт в место', () {
      game.placeInSlot('nursery.floor_left', 'bed');

      expect(game.itemInSlot('nursery.floor_left'), 'bed');
      expect(game.isPlaced('bed'), isTrue);
      expect(game.slotOf('bed'), 'nursery.floor_left');
    });

    test('новая вещь вытесняет прежнюю', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.floor_left', 'armchair');

      expect(game.itemInSlot('nursery.floor_left'), 'armchair');
      // Кроватка вернулась в инвентарь, а не растворилась.
      expect(game.isOwned('bed'), isTrue);
      expect(game.isPlaced('bed'), isFalse);
    });

    test('вещь не стоит в двух местах разом', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.back_left', 'bed');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
      expect(game.itemInSlot('nursery.back_left'), 'bed');
    });

    test('некупленное поставить нельзя', () {
      game.placeInSlot('nursery.floor_left', 'wardrobe');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
    });

    test('место освобождается', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.clearSlot('nursery.floor_left');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
      expect(game.isPlaced('bed'), isFalse);
      expect(game.isOwned('bed'), isTrue);
    });

    test('сервер узнаёт про обе половины замены', () {
      final events = <(String, bool)>[];
      game.onPlace = (id, {required placed}) => events.add((id, placed));

      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.floor_left', 'armchair');

      // Без первой записи на сервере остались бы стоять обе вещи разом.
      expect(events, [
        ('bed', true),
        ('bed', false),
        ('armchair', true),
      ]);
    });
  });
}
