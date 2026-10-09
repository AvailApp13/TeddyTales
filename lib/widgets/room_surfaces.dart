import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';

/// Стены и пол игровой поверх картинки комнаты (заказчик 09.10).
///
/// Картинка `nursery.jpg` — это и есть нынешние стены (пудровые) и пол
/// (светлое дерево). Остальные варианты — прозрачные слои того же размера
/// (`tool/room_surfaces.py`): перекрашенная стена или узор в перспективе,
/// со светом из окна. Окно, шторы, карниз и плинтус остаются с картинки.
///
/// [preview] — вариант, который сейчас примеряют, ещё не купив: пока
/// открыто окно покупки, комната уже в нём.
class RoomSurfaces extends StatelessWidget {
  const RoomSurfaces({super.key, required this.game, this.preview});

  final GameState game;
  final ShopItem? preview;

  ShopItem? _current(ItemKind kind) {
    final p = preview;
    if (p != null && p.kind == kind) return p;
    for (final id in game.placed) {
      final item = ItemCatalog.byIdOrNull(id);
      if (item != null && item.kind == kind) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final layers = [
      for (final kind in const [ItemKind.wallpaper, ItemKind.floor])
        if (_current(kind)?.surfaceLayer case final path?) path,
    ];
    if (layers.isEmpty) return const SizedBox.shrink();

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
              // Слоя нет (не собран) — остаётся картинка комнаты.
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
