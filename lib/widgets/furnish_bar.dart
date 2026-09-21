import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/room_kind.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'item_picture.dart';
import 'scene_label.dart';

/// Лента своих вещей внизу экрана: что можно поставить в эту комнату.
///
/// Заказчик 20.09 спросил, зачем магазин и комната продают одно и то же, и
/// согласился развести: магазин — единственная касса, комната — только про
/// «куда поставить». В играх с обстановкой так и сделано: расставляют прямо
/// на сцене, потому что расстановка — это примерка. Уйти на другой экран,
/// выбрать вещь вслепую и вернуться смотреть — уже не примерка.
///
/// Поэтому здесь нет ни цен, ни покупки: только то, что уже куплено. А если
/// нужного нет, последней в ленте стоит карточка «Купить ещё» — она и ведёт
/// в магазин, в тот самый раздел.
class FurnishBar extends StatelessWidget {
  const FurnishBar({
    super.key,
    required this.game,
    required this.room,
    required this.picked,
    required this.onPick,
    required this.onShop,
    required this.onDone,
  });

  final GameState game;
  final RoomKind room;

  /// Какую вещь держат в руках. `null` — ещё не выбрали.
  final ShopItem? picked;

  final ValueChanged<ShopItem> onPick;
  final VoidCallback onShop;
  final VoidCallback onDone;

  /// Купленные вещи, которым в этой комнате есть куда встать.
  ///
  /// Уже поставленных в ленте нет. Заказчик 21.09: «если расстановку сделали,
  /// например, двух картин — они из списка должны исчезнуть, а они остаются,
  /// будто одну и ту же вещь можно поставить дважды». Вещь одна, и она либо
  /// в комнате, либо в ленте. Забрать её обратно в ленту можно тапом по ней
  /// же в комнате.
  ///
  /// Вещей без картинки здесь тоже нет: рисовать их нечем, и в ленте они
  /// выглядели серыми коробками.
  List<ShopItem> get items {
    final here = [
      for (final slot in roomSlots)
        if (slot.room == room) slot,
    ];

    return [
      for (final item in ItemCatalog.all)
        if (game.isOwned(item.id) &&
            game.slotOf(item.id) == null &&
            here.any((slot) => slot.takes(item)))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mine = items;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    picked == null
                        ? l10n.furnishPickItem
                        : l10n.furnishPickSlot,
                    style: sceneText(size: 13, weight: 700),
                  ),
                ),
                TextButton(
                  onPressed: onDone,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.sageDark,
                  ),
                  child: Text(
                    l10n.furnishDone,
                    style: sceneText(
                      size: 14,
                      weight: 800,
                      color: AppColors.sageDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mine.length + 1,
                separatorBuilder: (context, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == mine.length) {
                    return _ShopCard(onTap: onShop);
                  }

                  final item = mine[index];

                  return _ItemCard(
                    item: item,
                    chosen: item.id == picked?.id,
                    onTap: () => onPick(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Своя вещь в ленте.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.chosen,
    required this.onTap,
  });

  final ShopItem item;

  /// Выбрана сейчас: подсвечена, и подходящие места ждут её.
  final bool chosen;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: chosen ? AppColors.sageSoft : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: chosen ? AppColors.sage : AppColors.outline,
            width: chosen ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(child: Center(child: ItemPicture(item: item))),
            const SizedBox(height: 2),
            Text(
              shopItemName(context.l10n, item.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: sceneText(
                size: 10,
                weight: chosen ? 800 : 600,
                color: chosen ? AppColors.sageDark : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Последняя карточка ленты: за новым — в магазин.
class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 92,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_rounded,
              size: 28,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.furnishBuyMore,
              textAlign: TextAlign.center,
              style: sceneText(
                size: 10,
                weight: 700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
