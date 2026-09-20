import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'item_picture.dart';
import 'scene_label.dart';

/// Товар во весь экран: картинка крупно, название, цена и покупка.
///
/// Заказчик 20.09: «на каждом товаре должна быть кнопка увеличить, и она
/// должна раскрывать товар». В карточке витрины вещь видна стороной в
/// полтораста точек — разглядеть вышивку на кроватке или книги на полке там
/// нельзя, а картинки присланы подробные, и это их главное достоинство.
///
/// Раскрывается именно карточка, а не открывается «ещё один экран»: вещь
/// вырастает со своего места (`Hero` по id товара) на размытую комнату и
/// тем же движением уходит обратно. Так человек не теряет место в витрине,
/// где листал.
Future<void> showItemPreview({
  required BuildContext context,
  required ShopItem item,
  required GameState game,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: _ItemPreview(item: item, game: game),
      ),
    ),
  );
}

class _ItemPreview extends StatelessWidget {
  const _ItemPreview({required this.item, required this.game});

  final ShopItem item;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: game,
      builder: (context, _) {
        final owned = game.isOwned(item.id);
        final inCart = game.isInCart(item.id);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Витрина остаётся на месте — просто уходит из фокуса. Это и
              // есть «раскрыть товар»: не уйти с экрана, а приблизить вещь.
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: ColoredBox(
                      color: AppColors.textPrimary.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: _CloseButton(
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Hero(
                            tag: 'shop.item.${item.id}',
                            child: ItemPicture(item: item),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SceneLabel(
                        text: shopItemName(l10n, item.id),
                        size: 17,
                        weight: 800,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PreviewAction(
                        item: item,
                        owned: owned,
                        inCart: inCart,
                        onTap: () {
                          game.toggleCart(item.id);
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Кнопка под картинкой: положить в корзину, вынуть обратно или напомнить,
/// что вещь уже куплена.
class _PreviewAction extends StatelessWidget {
  const _PreviewAction({
    required this.item,
    required this.owned,
    required this.inCart,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final bool inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (owned) {
      return SceneLabel(
        text: l10n.shopOwnedLabel,
        size: 14,
        weight: 800,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: inCart ? AppColors.surface : AppColors.sage,
          foregroundColor: inCart ? AppColors.textPrimary : Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          elevation: 5,
          shadowColor: AppColors.textPrimary.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              inCart ? Icons.remove_rounded : Icons.add_rounded,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              inCart ? l10n.shopRemoveFromCart : l10n.shopAddToCart,
              style: sceneText(
                size: 15,
                weight: 800,
                color: inCart ? AppColors.textPrimary : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            _PriceChip(price: item.price, onDark: !inCart),
          ],
        ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.price, required this.onDark});

  final int price;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.24)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$price',
            style: sceneText(
              size: 13,
              weight: 800,
              color: onDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 22,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
