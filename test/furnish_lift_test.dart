import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/room_slots.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/widgets/room_scene_backdrop.dart';
import 'package:teddy_tales/widgets/room_slot_layer.dart';

/// Обустройство: комната приподнимается над лентой (заказчик 10.10).
///
/// На iPhone место ковра лежало под лентой обустройства — ни рамки, ни
/// самого ковра не видно, заменить ковёр было нечем.
void main() {
  late BearController bear;
  late GameState game;

  // iPhone 14/15: экран 393×852, статус-бар 59, лента обустройства ~250.
  const screen = Size(393, 852);
  const topInset = 59.0;
  const barTop = 852.0 - 250;
  final frame = RoomFrame.of(screen, RoomKind.nursery).rect;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'rug', 'rug_cloud', 'pic_bear'},
      placed: const {},
    );
    game.placeInSlot('nursery.rug', 'rug');
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  List<RoomSlot> slotsFor(ShopItem? held) => [
    for (final slot in slotsOf(RoomKind.nursery))
      if (held == null || slot.takes(held)) slot,
  ];

  double centreY(RoomSlot slot, double lift) {
    final box = slotBoxIn(game, slot);
    return frame.top + (box.top + box.height / 2) * frame.height - lift;
  }

  double liftFor(ShopItem? held) => furnishLift(
    game: game,
    slots: slotsFor(held),
    frame: frame,
    barTop: barTop,
    topInset: topInset,
  );

  test('ковёр в руках: место ковра выходит из-под ленты', () {
    final rug = slotsOf(
      RoomKind.nursery,
    ).firstWhere((s) => s.id == 'nursery.rug');
    // Без подъёма середина ковра под лентой — это и была беда.
    expect(centreY(rug, 0), greaterThan(barTop));

    final lift = liftFor(ItemCatalog.byId('rug_cloud'));
    expect(lift, greaterThan(0));
    expect(centreY(rug, lift), lessThanOrEqualTo(barTop - 28 + 0.01));
  });

  test('картина в руках: комната стоит на месте', () {
    expect(liftFor(ItemCatalog.byId('pic_bear')), 0);
  });

  test('без вещи в руках видны и ковёр, и картины под статус-баром', () {
    final lift = liftFor(null);
    for (final slot in slotsOf(RoomKind.nursery)) {
      final y = centreY(slot, lift);
      expect(y, lessThan(barTop), reason: slot.id);
      expect(y, greaterThan(topInset), reason: slot.id);
    }
  });
}
