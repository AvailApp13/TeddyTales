import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';
import 'item_picture.dart';
import 'scene_label.dart';

/// Окно подтверждения покупки.
///
/// Заказчик 24.09: «корзину убираем вообще; покупка каждого блюда или каждой
/// вещи — отдельно: нажимаешь „купить“, вылезает красивое окошко, ты
/// подтверждаешь или отклоняешь; на трёх языках».
///
/// Одно окно на все покупки: магазин, просмотр товара, место в комнате,
/// блюдо на кухне. Показывает вещь, цену, сколько на счету и сколько
/// останется. Монет не хватает — «Купить» не предлагает, а говорит, сколько
/// не хватает.
///
/// Возвращает `true`, только если человек нажал «Купить».
Future<bool> confirmPurchase({
  required BuildContext context,
  required Widget picture,
  required String name,
  required int price,
  required int coins,
}) async {
  // Заказчик 26.09: окно из матового стекла посреди комнаты, кнопки —
  // как на главном экране.
  final result = await showGlassPanel<bool>(
    context: context,
    center: const Offset(0.5, 0.5),
    width: 320,
    builder: (context) => _PurchaseDialog(
      picture: picture,
      name: name,
      price: price,
      coins: coins,
    ),
  );
  return result ?? false;
}

/// Купить вещь магазина с подтверждением. `true` — куплено.
///
/// Общая дорожка для витрины, просмотра и комнаты: окно → покупка →
/// подсказка внизу «Куплено». Сервер проводит покупку следом по своей цене
/// (КП 11.1), отказ откатывает её в [GameState.buy].
Future<bool> buyItemConfirmed({
  required BuildContext context,
  required GameState game,
  required ShopItem item,
  bool showToast = true,
}) async {
  if (game.isOwned(item.id)) return true;
  final l10n = context.l10n;
  final name = shopItemName(l10n, item.id);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final ok = await confirmPurchase(
    context: context,
    picture: ItemPicture(item: item),
    name: name,
    price: item.price,
    coins: game.coins,
  );
  if (!ok || !game.buy(item.id)) return false;

  if (showToast) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.roomItemBought(name)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
  return true;
}

class _PurchaseDialog extends StatelessWidget {
  const _PurchaseDialog({
    required this.picture,
    required this.name,
    required this.price,
    required this.coins,
  });

  final Widget picture;
  final String name;
  final int price;
  final int coins;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enough = coins >= price;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          enough ? l10n.buyConfirmTitle : l10n.buyNotEnoughTitle,
          style: sceneText(
            size: 13,
            weight: 800,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        // Вещь на мягкой подложке — как на полке витрины.
        Container(
          width: 132,
          height: 132,
          padding: const EdgeInsets.all(12),
          decoration: glassTile(radius: 26),
          child: Center(child: picture),
        ),
        const SizedBox(height: 14),
        Text(
          name,
          textAlign: TextAlign.center,
          style: sceneText(size: 19, weight: 800),
        ),
        const SizedBox(height: 10),
        _PriceChip(price: price),
        const SizedBox(height: 12),
        Text(
          enough
              ? l10n.buyConfirmBalance(coins, coins - price)
              : l10n.buyNotEnough(price - coins),
          key: const ValueKey('purchase-balance'),
          textAlign: TextAlign.center,
          style: sceneText(
            size: 13,
            weight: 700,
            color: enough ? AppColors.textSecondary : AppColors.blushStrong,
          ),
        ),
        const SizedBox(height: 18),
        if (enough)
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: l10n.buyConfirmCancel,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  key: const ValueKey('purchase-buy'),
                  primary: true,
                  icon: Icons.shopping_bag_rounded,
                  label: l10n.buyConfirmAction,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          )
        else
          GlassButton(
            primary: true,
            label: l10n.buyNotEnoughOk,
            onPressed: () => Navigator.of(context).pop(false),
          ),
      ],
    );
  }
}

/// Цена: монета и число в тёплой капсуле — как на карточке витрины.
class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: glassTile(radius: 999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('$price', style: sceneText(size: 17, weight: 800)),
        ],
      ),
    );
  }
}
