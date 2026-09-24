import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
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
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => _PurchaseDialog(
      picture: picture,
      name: name,
      price: price,
      coins: coins,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(curve),
          child: child,
        ),
      );
    },
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, AppColors.surface],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.28),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
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
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(26),
                    ),
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
                      color: enough
                          ? AppColors.textSecondary
                          : AppColors.blushStrong,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (enough)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: const StadiumBorder(),
                              side: const BorderSide(color: AppColors.outline),
                              foregroundColor: AppColors.textSecondary,
                            ),
                            child: Text(
                              l10n.buyConfirmCancel,
                              style: sceneText(
                                size: 15,
                                weight: 800,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: const StadiumBorder(),
                              backgroundColor: AppColors.sageDark,
                              elevation: 3,
                              shadowColor: AppColors.sageDark.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            child: Text(
                              l10n.buyConfirmAction,
                              style: sceneText(
                                size: 15,
                                weight: 800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: const StadiumBorder(),
                          backgroundColor: AppColors.sageDark,
                        ),
                        child: Text(
                          l10n.buyNotEnoughOk,
                          style: sceneText(
                            size: 15,
                            weight: 800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
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
