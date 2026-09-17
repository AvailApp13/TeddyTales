import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Что делать с вещью, которая уже стоит в комнате.
///
/// Замечание заказчика (17.09): поставленную кроватку нельзя было тронуть
/// прямо со сцены — ни убрать, ни поменять. Единственный путь вёл в раздел
/// «Комната», и человек, который тапнул по кроватке, не получал в ответ
/// ничего.
///
/// Лист показывает ровно два действия: убрать и заменить. Замена — это и
/// есть витрина: рядом со своими вещами лежат покупные того же вида, с
/// ценой. Человек пришёл поменять кроватку — и видит, на какую может
/// поменять. Более честного места для продажи в игре нет.
Future<void> showRoomItemSheet({
  required BuildContext context,
  required GameState game,
  required String itemId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _RoomItemSheet(game: game, itemId: itemId),
  );
}

class _RoomItemSheet extends StatelessWidget {
  const _RoomItemSheet({required this.game, required this.itemId});

  final GameState game;
  final String itemId;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _remove(BuildContext context) {
    final name = shopItemName(context.l10n, itemId);
    game.togglePlaced(itemId);
    Navigator.of(context).pop();
    _toast(context, context.l10n.roomItemRemoved(name));
  }

  void _replace(BuildContext context, ShopItem next) {
    final l10n = context.l10n;
    final name = shopItemName(l10n, next.id);
    final wasOwned = game.isOwned(next.id);

    if (!game.replacePlaced(itemId, next.id)) {
      // Единственная причина отказа — не хватило монет на покупку. Старая
      // вещь при этом осталась на месте, и говорить об этом не нужно:
      // человек видит, что комната не изменилась.
      _toast(context, l10n.roomNotEnoughCoins);
      return;
    }

    Navigator.of(context).pop();
    _toast(
      context,
      wasOwned ? l10n.roomItemPlaced(name) : l10n.roomItemBought(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = ItemCatalog.byId(itemId);
    final theme = Theme.of(context);

    // Меняем на вещь того же вида: кроватку на кроватку, картину на картину.
    // Предлагать вместо кроватки барабан значило бы не «заменить», а
    // «переставить комнату», и место под кроватку осталось бы пустым.
    final stage = game.bear.state.stage;
    final others =
        [
          for (final other in ItemCatalog.ofKind(item.kind))
            if (other.id != itemId && !game.isPlaced(other.id)) other,
        ]..sort((a, b) {
          // Своё вперёд покупного: поставить то, что уже есть, — бесплатно.
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
                Text(item.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shopItemName(l10n, itemId),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Purse(coins: game.coins),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _remove(context),
                icon: const Icon(Icons.delete_outline, size: 19),
                label: Text(l10n.roomSheetRemove),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.outline),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                l10n.roomSheetReplace.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              // Высота ограничена: видов, где вещей много (декор, одежда),
              // хватает, чтобы лист занял весь экран и перестал быть листом.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: others.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final other = others[index];
                    return _OptionTile(
                      item: other,
                      owned: game.isOwned(other.id),
                      affordable: game.coins >= other.price,
                      onTap: () => _replace(context, other),
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

/// Строка варианта замены: своё — с пометкой, покупное — с ценой.
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
                Text(item.emoji, style: const TextStyle(fontSize: 22)),
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
