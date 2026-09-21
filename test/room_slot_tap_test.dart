import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/room_slots.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/room_slot_layer.dart';

/// Тап по месту, когда вещь уже в руках.
///
/// Заказчик 21.09: «ошибка, если ставлю коврик» — на весь экран подсвечено
/// место под ковёр, палец попадает в подсвеченную рамку, а в ответ «для
/// этой вещи здесь нет места».
///
/// Разгадка в том, что места перекрываются. Ковёр лежит под ногами и занимает
/// 0.11–0.89 по ширине, а поверх него, ближе к зрителю, лежат места игрушек —
/// и они забирали тап себе, хотя ковёр в них не встаёт и подсвечены они не
/// были. Пальцу было некуда попасть: больше половины ковра отвечало отказом.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'rug', 'teddy'},
      placed: const {},
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  /// Слой во весь «кадр» 400 × 800 — как он и лежит на сцене.
  Future<List<RoomSlot>> tapAt(
    WidgetTester tester,
    Offset point, {
    required ShopItem picked,
  }) async {
    final taps = <RoomSlot>[];
    // Кадр сцены — весь экран, поэтому окно теста ровно под него.
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: RoomSlotLayer(
              game: game,
              room: RoomKind.nursery,
              depth: SlotDepth.behind,
              hint: true,
              picked: picked,
              onTapItem: (slot, _) => taps.add(slot),
              onTapEmpty: taps.add,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(point);
    await tester.pump();
    return taps;
  }

  testWidgets('ковёр ставится там, где подсвечено, а не через раз', (
    tester,
  ) async {
    // Точка внутри рамки ковра — и заодно внутри места игрушки справа.
    // Именно туда и попадал палец заказчика.
    final taps = await tapAt(
      tester,
      const Offset(300, 560),
      picked: ItemCatalog.byId('rug'),
    );

    expect(taps.map((slot) => slot.id), ['nursery.rug']);
  });

  testWidgets('по всей подсвеченной рамке, а не только в середине', (
    tester,
  ) async {
    // Ковёр 0.153–0.847 по ширине и 0.662–0.898 по высоте. Проверяем оба
    // края, где его перекрывают места игрушек, и середину.
    for (final point in const [
      Offset(100, 560), // левый край, под местом игрушки слева
      Offset(200, 600), // середина
      Offset(300, 590), // правый край, под игрушкой справа
    ]) {
      final taps = await tapAt(
        tester,
        point,
        picked: ItemCatalog.byId('rug'),
      );
      expect(taps.map((slot) => slot.id), ['nursery.rug'], reason: '$point');
    }
  });

  testWidgets('место игрушки по-прежнему ловит игрушку', (tester) async {
    // Обратная проверка: лишив места чужих тапов, нельзя отнять у них свои.
    final taps = await tapAt(
      tester,
      const Offset(300, 545),
      picked: ItemCatalog.byId('teddy'),
    );

    expect(taps.map((slot) => slot.id), ['nursery.toy_right']);
  });
}
