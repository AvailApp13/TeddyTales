import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'item_picture.dart';
import 'purchase_confirm.dart';
import '../theme/app_theme.dart';

/// Что можно сделать с местом в комнате.
///
/// Один лист на два случая — место занято и место свободно, — потому что
/// действие по сути одно: решить, что здесь стоит. Свободное место
/// предлагает поставить, занятое добавляет сверху «убрать».
///
/// Список — это и есть витрина: рядом со своими вещами лежат покупные, с
/// ценой. Человек пришёл обставить угол и видит, чем может его обставить.
/// Более честного места для продажи в игре нет.
Future<void> showSlotSheet({
  required BuildContext context,
  required GameState game,
  required RoomSlot slot,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _SlotSheet(game: game, slot: slot),
  );
}

class _SlotSheet extends StatelessWidget {
  const _SlotSheet({required this.game, required this.slot});

  final GameState game;
  final RoomSlot slot;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _clear(BuildContext context, String itemId) {
    final name = shopItemName(context.l10n, itemId);
    game.clearSlot(slot.id);
    Navigator.of(context).pop();
    _toast(context, context.l10n.roomItemRemoved(name));
  }

  Future<void> _put(BuildContext context, ShopItem item) async {
    final l10n = context.l10n;
    final name = shopItemName(l10n, item.id);
    final wasOwned = game.isOwned(item.id);

    // Не куплено — сначала окно «Купить?» (заказчик 24.09: каждая покупка
    // с подтверждением). Отказался или не хватило монет — место остаётся
    // как было: окно само сказало, сколько не хватает.
    if (!wasOwned) {
      final bought = await buyItemConfirmed(
        context: context,
        game: game,
        item: item,
        showToast: false,
      );
      if (!bought || !context.mounted) return;
    }

    game.placeInSlot(slot.id, item.id);
    Navigator.of(context).pop();
    _toast(
      context,
      wasOwned ? l10n.roomItemPlaced(name) : l10n.roomItemBought(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final standing = game.itemInSlot(slot.id);
    final stage = game.bear.state.stage;

    // Что сюда становится: вещи подходящих категорий, кроме той, что уже
    // стоит здесь, и кроме тех, что заняты другими местами. Вещь не может
    // стоять в двух местах сразу, и предлагать её второй раз — обман.
    final options =
        [
          for (final item in ItemCatalog.all)
            if (slot.takes(item) &&
                item.id != standing &&
                (game.slotOf(item.id) == null))
              item,
        ]..sort((a, b) {
          // Своё вперёд покупного: поставить то, что уже есть, бесплатно.
          final ownedA = game.isOwned(a.id);
          final ownedB = game.isOwned(b.id);
          if (ownedA != ownedB) return ownedA ? -1 : 1;
          // Дальше — подходящее возрасту, потом по цене.
          final suitsA = a.suitsAt(stage);
          final suitsB = b.suitsAt(stage);
          if (suitsA != suitsB) return suitsA ? -1 : 1;
          return a.price.compareTo(b.price);
        });

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          0,
          AppDimens.pagePadding,
          AppDimens.pagePadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    standing == null
                        ? l10n.roomSlotEmpty
                        : shopItemName(l10n, standing),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Purse(coins: game.coins),
              ],
            ),
            if (standing != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _clear(context, standing),
                  icon: const Icon(Icons.delete_outline, size: 19),
                  label: Text(l10n.roomSheetRemove),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.outline),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
            if (options.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                (standing == null ? l10n.roomSlotPut : l10n.roomSheetReplace)
                    .toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              // Высота ограничена: в мебели и декоре вещей столько, что лист
              // занял бы весь экран и перестал быть листом.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = options[index];
                    return _OptionTile(
                      item: item,
                      owned: game.isOwned(item.id),
                      affordable: game.coins >= item.price,
                      onTap: () => _put(context, item),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка варианта: своё — с пометкой, покупное — с ценой.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.item,
    required this.owned,
    required this.affordable,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Денег не хватает — строка гаснет, но остаётся видимой: это витрина,
    // и недоступное сейчас должно быть видно, иначе незачем копить.
    final enabled = owned || affordable;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                ItemPicture(item: item, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shopItemName(l10n, item.id),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (owned)
                  Text(
                    l10n.roomSheetOwned,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.sageDark,
                    ),
                  )
                else
                  _Price(price: item.price),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Цена в монетах.
class _Price extends StatelessWidget {
  const _Price({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$price',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        const _Coin(),
      ],
    );
  }
}

/// Кошелёк в шапке листа: видно, на что хватает, не выходя из комнаты.
class _Purse extends StatelessWidget {
  const _Purse({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Coin(),
          const SizedBox(width: 5),
          Text(
            '$coins',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Coin extends StatelessWidget {
  const _Coin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: AppColors.coin,
        shape: BoxShape.circle,
      ),
    );
  }
}
