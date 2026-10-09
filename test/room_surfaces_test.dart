import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/widgets/furnish_bar.dart';

/// Стены и пол игровой — по 10, 4 бесплатно (заказчик 09.10,
/// docs/room-surfaces-answers.md).
void main() {
  for (final kind in [ItemKind.wallpaper, ItemKind.floor]) {
    group(kind.name, () {
      final all = ItemCatalog.ofKind(kind);

      test('10 вариантов, 4 бесплатно, 6 за монеты', () {
        expect(all, hasLength(10));
        expect(all.where((i) => i.price == 0), hasLength(4));
        expect(all.where((i) => i.price > 0), hasLength(6));
      });

      test('у показанных есть образец и слой', () {
        for (final item in FurnishBar.surfaces(kind)) {
          expect(File(item.image!).existsSync(), isTrue, reason: item.id);
          final layer = item.surfaceLayer;
          if (layer != null) {
            expect(File(layer).existsSync(), isTrue, reason: item.id);
          }
        }
      });
    });
  }

  test('нынешние стена и пол — сама картинка комнаты, без слоя', () {
    expect(ItemCatalog.byId('wall_rose').surfaceLayer, isNull);
    expect(ItemCatalog.byId('floor_wood').surfaceLayer, isNull);
    expect(ItemCatalog.byId('wall_mint').surfaceLayer, isNotNull);
  });

  test('снятый с продажи id в сохранении не роняет каталог', () {
    expect(ItemCatalog.byIdOrNull('wall_sage'), isNull);
  });

  test('бесплатная стена берётся без монет и встаёт вместо прежней', () {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(
        name: PetProfile.defaultName,
        birthAt: DateTime(2026, 9, 26),
        skin: BearSkin.girl,
        zodiac: BearZodiac.libra,
        birthHeightCm: 16.6,
        birthWeightG: 186,
      ),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    final coins = game.coins;
    expect(game.buy('wall_mint'), isTrue);
    expect(game.coins, coins);
    game.togglePlaced('wall_mint');
    expect(game.isPlaced('wall_mint'), isTrue);
    expect(game.isPlaced('wall_rose'), isFalse);
  });
}
