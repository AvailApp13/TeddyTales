import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/room_slot_layer.dart';

/// Нажатие по вещам игровой (проверка интерьера 09.10).
///
/// Было: нажатие по комоду, ковру и полу у ног мишки открывало кресло —
/// прямоугольник 3D-слоя кресла вместе с тенью накрывал полкомнаты и
/// забирал касание себе. Нажимается только сама вещь.
void main() {
  testWidgets('нажатие доходит до той вещи, по которой нажали', (tester) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'armchair', 'dresser', 'rug'},
      placed: const {},
    );
    game.placeInSlot('nursery.floor_left', 'armchair');
    game.placeInSlot('nursery.floor_right', 'dresser');
    game.placeInSlot('nursery.rug', 'rug');

    final taps = <String>[];
    // Кадр комнаты 941 × 1672 в половину.
    const scale = 0.5;
    const size = Size(941 * scale, 1672 * scale);
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: SizedBox.fromSize(
          size: size,
          child: RoomSlotLayer(
            game: game,
            room: RoomKind.nursery,
            depth: SlotDepth.behind,
            onTapItem: (slot, item) => taps.add('${slot.id}/${item.id}'),
            onTapEmpty: (slot) => taps.add('пусто ${slot.id}'),
          ),
        ),
      ),
    );

    Future<String> tapAt(double u, double v) async {
      taps.clear();
      await tester.tapAt(Offset(u, v) * scale);
      return taps.isEmpty ? 'мимо' : taps.single;
    }

    // Точки — в пикселях кадра.
    expect(await tapAt(230, 880), 'nursery.floor_left/armchair');
    expect(await tapAt(677, 760), 'nursery.floor_right/dresser');
    expect(await tapAt(480, 1330), 'nursery.rug/rug');
    // Пол справа у ног мишки — в тени кресла, но не кресло.
    expect(await tapAt(700, 1150), isNot(contains('armchair')));

    await tester.binding.setSurfaceSize(null);
    game.dispose();
    bear.dispose();
  });
}
