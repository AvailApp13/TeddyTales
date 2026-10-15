import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';

/// Стены и пол игровой из 3D (заказчик 09.10, `docs/room-structure-plan.md`).
///
/// Комната собрана слоями (`tool/nursery3d/compose.py`), снизу вверх:
/// стена (цвет или обои, со светом комнаты) → пол → отделка (потолок,
/// карниз, плинтусы, рама, вид за окном) → тюль. Отделка и тюль одни на все
/// варианты и всегда белые; меняются только стена и пол.
///
/// Под слоями лежит картинка по умолчанию (`nursery3d.jpg` — пудровые стены
/// и светлое дерево), поэтому пока слои грузятся, комната уже на месте.
///
/// [preview] — вариант, который сейчас примеряют, ещё не купив: пока
/// открыто окно покупки, комната уже в нём.
class RoomSurfaces extends StatelessWidget {
  const RoomSurfaces({super.key, required this.game, this.preview});

  final GameState game;
  final ShopItem? preview;

  static const String _trim = 'assets/rooms/nursery/trim.webp';
  static const String _curtains = 'assets/rooms/nursery/curtains.webp';

  ShopItem _current(ItemKind kind, String fallback) {
    final p = preview;
    if (p != null && p.kind == kind) return p;
    for (final id in game.placed) {
      final item = ItemCatalog.byIdOrNull(id);
      if (item != null && item.kind == kind) return item;
    }
    return ItemCatalog.byId(fallback);
  }

  @override
  Widget build(BuildContext context) {
    if (!kRoomSurfacesShown) return const SizedBox.shrink();
    final wall = _current(ItemKind.wallpaper, 'wall_rose');
    final floor = _current(ItemKind.floor, 'floor_wood');
    // По умолчанию картинка под слоями — ровно это, рисовать нечего.
    if (wall.id == 'wall_rose' && floor.id == 'floor_wood') {
      return const SizedBox.shrink();
    }
    final layers = [wall.surfaceLayer!, floor.surfaceLayer!, _trim, _curtains];

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final path in layers)
            Image.asset(
              path,
              key: ValueKey(path),
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
