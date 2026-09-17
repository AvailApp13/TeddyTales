import 'package:flutter/material.dart';

import '../game/room_layout.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import 'room_scene_backdrop.dart';

/// Делает поставленные вещи нажимаемыми.
///
/// Сама сцена (`RoomSceneBackdrop`) их только рисует — она фон и ничего не
/// знает про инвентарь. Этот слой кладёт поверх каждой стоящей вещи
/// прозрачную область: тап по кроватке открывает лист «убрать или
/// заменить».
///
/// Области считаются по той же размерной сетке, что и сама отрисовка, —
/// иначе нажималось бы не там, где нарисовано.
class RoomItemsLayer extends StatelessWidget {
  const RoomItemsLayer({
    super.key,
    required this.placed,
    required this.onTap,
    this.bearModule = RoomSceneBackdrop.defaultBearModule,
  });

  final Set<String> placed;
  final ValueChanged<String> onTap;
  final double bearModule;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final module = height * bearModule;

        final items = [
          for (final p in roomLayout)
            // Обои и пол покрывают комнату целиком: у них нет «места», по
            // которому можно тапнуть, и менять их надо в разделе комнаты,
            // где видно все шесть вариантов сразу.
            if (placed.contains(p.id) && !_isSurface(p.id)) p,
        ];

        return Stack(
          children: [
            for (final p in items)
              Positioned(
                left: (p.fx * width - p.w * module / 2).clamp(
                  0.0,
                  (width - p.w * module).clamp(0.0, double.infinity),
                ),
                top: p.onWall
                    ? p.wallFy! * height - p.h * module / 2
                    : RoomSceneBackdrop.floorLine * height - p.h * module,
                width: p.w * module,
                height: p.h * module,
                child: Semantics(
                  button: true,
                  label: shopItemName(context.l10n, p.id),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(p.id),
                    // Без своей краски: вещь уже нарисована фоном, а подсветка
                    // поверх неё читалась бы как «здесь чего-то не хватает» —
                    // ровно наоборот тому, что значит стоящий предмет.
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static bool _isSurface(String id) {
    final kind = ItemCatalog.byId(id).kind;
    return kind == ItemKind.wallpaper || kind == ItemKind.floor;
  }
}
