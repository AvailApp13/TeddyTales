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
import 'top_toast.dart';

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
class FurnishBar extends StatefulWidget {
  const FurnishBar({
    super.key,
    required this.game,
    required this.room,
    required this.picked,
    required this.onPick,
    required this.onShop,
    required this.onDone,
    this.onSurface,
    this.onSurfaceTab,
  });

  final GameState game;
  final RoomKind room;

  /// Какую вещь держат в руках. `null` — ещё не выбрали.
  final ShopItem? picked;

  final ValueChanged<ShopItem> onPick;
  final VoidCallback onShop;
  final VoidCallback onDone;

  /// Выбрали стены или пол (вкладки «Стены» и «Пол», только в игровой).
  /// `null` — вкладок нет.
  final ValueChanged<ShopItem>? onSurface;

  /// Открыта вкладка «Стены» или «Пол» (`true`) или «Интерьер» (`false`).
  /// Заказчик 09.10: крестики мест — только когда ставят вещи.
  final ValueChanged<bool>? onSurfaceTab;

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

  /// Все варианты стен или пола — и свои, и в продаже (заказчик 09.10:
  /// 10 стен и 10 полов). Стены и пол не вещь в слоте, а вся комната:
  /// выбрать их вслепую в магазине нельзя, поэтому здесь видны все, с ценой,
  /// и платный вариант сначала примеряется на комнате.
  static List<ShopItem> surfaces(ItemKind kind) => [
    for (final item in ItemCatalog.ofKind(kind))
      if (item.photo) item,
  ];

  @override
  State<FurnishBar> createState() => _FurnishBarState();
}

enum _Tab { items, walls, floor }

class _FurnishBarState extends State<FurnishBar> {
  _Tab _tab = _Tab.items;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final game = widget.game;
    final picked = widget.picked;
    final mine = widget.items;
    final tabs =
        kRoomSurfacesShown &&
        widget.onSurface != null &&
        widget.room == RoomKind.nursery;
    final tab = tabs ? _tab : _Tab.items;
    final surfaceKind = switch (tab) {
      _Tab.walls => ItemKind.wallpaper,
      _Tab.floor => ItemKind.floor,
      _Tab.items => null,
    };
    final surfaces = surfaceKind == null
        ? const <ShopItem>[]
        : FurnishBar.surfaces(surfaceKind);

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
                  child: Text(switch (tab) {
                    _Tab.walls => l10n.furnishPickWall,
                    _Tab.floor => l10n.furnishPickFloor,
                    _Tab.items =>
                      picked == null
                          ? l10n.furnishPickItem
                          : l10n.furnishPickSlot,
                  }, style: sceneText(size: 13, weight: 700)),
                ),
                TextButton(
                  onPressed: widget.onDone,
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
            if (tabs) ...[
              const SizedBox(height: 4),
              // Сверху над «скоро» нужен запас под пометку; на узком экране
              // ряд листается вбок.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    for (final t in _Tab.values) ...[
                      if (t != _Tab.items) const SizedBox(width: 8),
                      _TabChip(
                        label: switch (t) {
                          _Tab.items => l10n.furnishTabItems,
                          _Tab.walls => l10n.furnishTabWalls,
                          _Tab.floor => l10n.furnishTabFloor,
                        },
                        chosen: t == tab,
                        onTap: () {
                          setState(() => _tab = t);
                          widget.onSurfaceTab?.call(t != _Tab.items);
                        },
                      ),
                    ],
                    // ⚠ ждёт согласования с Ириной: выбор тюля и потолка —
                    // сверх ТЗ (docs/irina-wishes.md, строка 3). Заказчик
                    // 09.10: кнопки показать сейчас с пометкой «скоро», чтобы
                    // предложить Ирине доделать в следующем обновлении.
                    for (final soon in [
                      l10n.furnishTabCurtains,
                      l10n.furnishTabCeiling,
                    ]) ...[
                      const SizedBox(width: 8),
                      _SoonChip(
                        label: soon,
                        onTap: () =>
                            showTopToast(context, l10n.furnishSoonToast(soon)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 104,
              child: surfaceKind != null
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: surfaces.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = surfaces[index];
                        return _SurfaceCard(
                          item: item,
                          current: game.isPlaced(item.id),
                          owned: game.isOwned(item.id),
                          onTap: () => widget.onSurface?.call(item),
                        );
                      },
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: mine.length + 1,
                      separatorBuilder: (context, _) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index == mine.length) {
                          return _ShopCard(onTap: widget.onShop);
                        }

                        final item = mine[index];

                        return _ItemCard(
                          item: item,
                          chosen: item.id == picked?.id,
                          onTap: () => widget.onPick(item),
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

/// Вкладка ленты: «Интерьер», «Стены», «Пол» (заказчик 09.10: не «Вещи»).
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: chosen ? AppColors.sageSoft : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: chosen ? AppColors.sage : AppColors.outline,
            width: chosen ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: sceneText(
            size: 12,
            weight: chosen ? 800 : 600,
            color: chosen ? AppColors.sageDark : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Кнопка того, что появится позже: приглушённая, с пометкой «скоро» сверху.
class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              label,
              style: sceneText(
                size: 12,
                weight: 600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Positioned(
            top: -9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.blushStrong,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                context.l10n.furnishSoon,
                style: sceneText(size: 9, weight: 800, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Вариант стен или пола: образец, название, цена или «Сейчас».
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.item,
    required this.current,
    required this.owned,
    required this.onTap,
  });

  final ShopItem item;

  /// Стоит в комнате сейчас.
  final bool current;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final Widget badge;
    if (current) {
      badge = Text(
        l10n.furnishCurrent,
        style: sceneText(size: 10, weight: 800, color: AppColors.sageDark),
      );
    } else if (owned) {
      badge = const Icon(
        Icons.check_rounded,
        size: 14,
        color: AppColors.textSecondary,
      );
    } else if (item.price == 0) {
      badge = Text(
        l10n.furnishFree,
        style: sceneText(size: 10, weight: 700, color: AppColors.sageDark),
      );
    } else {
      badge = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${item.price}', style: sceneText(size: 11, weight: 800)),
          const SizedBox(width: 3),
          Container(
            width: 11,
            height: 11,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: current ? AppColors.sageSoft : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: current ? AppColors.sage : AppColors.outline,
            width: current ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ItemPicture(item: item),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              shopItemName(l10n, item.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: sceneText(
                size: 10,
                weight: current ? 800 : 600,
                color: current ? AppColors.sageDark : AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 14, child: Center(child: badge)),
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
            Expanded(
              child: Center(child: ItemPicture(item: item)),
            ),
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
