import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'item_picture.dart';
import 'purchase_confirm.dart';
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
  required List<ShopItem> items,
  required int index,
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
        child: _ItemPreview(items: items, index: index, game: game),
      ),
    ),
  );
}

class _ItemPreview extends StatefulWidget {
  const _ItemPreview({
    required this.items,
    required this.index,
    required this.game,
  });

  /// Весь раздел витрины в том же порядке, что на её экране: из просмотра
  /// листают дальше, а не возвращаются за каждой вещью в список.
  final List<ShopItem> items;
  final int index;
  final GameState game;

  @override
  State<_ItemPreview> createState() => _ItemPreviewState();
}

class _ItemPreviewState extends State<_ItemPreview> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _current = widget.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = _current + delta;
    if (next < 0 || next >= widget.items.length) return;

    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: widget.game,
      builder: (context, _) {
        final item = widget.items[_current];
        final owned = widget.game.isOwned(item.id);

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
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PageView.builder(
                              controller: _pages,
                              itemCount: widget.items.length,
                              onPageChanged: (page) =>
                                  setState(() => _current = page),
                              itemBuilder: (context, page) {
                                final shown = widget.items[page];

                                return Hero(
                                  tag: 'shop.item.${shown.id}',
                                  child: ItemPicture(item: shown),
                                );
                              },
                            ),
                            // Стрелки — для тех, кто не догадается смахнуть,
                            // и для крайних вещей: по ним сразу видно, что
                            // раздел кончился.
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _ArrowButton(
                                icon: Icons.chevron_left_rounded,
                                enabled: _current > 0,
                                onTap: () => _step(-1),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _ArrowButton(
                                icon: Icons.chevron_right_rounded,
                                enabled: _current < widget.items.length - 1,
                                onTap: () => _step(1),
                              ),
                            ),
                          ],
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
                      // Кнопка остаётся на месте, меняются только картинка,
                      // название и цена. Покупка — с подтверждением, по
                      // одной вещи (корзины нет, заказчик 24.09).
                      _PreviewAction(
                        item: item,
                        owned: owned,
                        onTap: () => buyItemConfirmed(
                          context: context,
                          game: widget.game,
                          item: item,
                        ),
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

/// Стрелка листания. На краю раздела гаснет, а не исчезает: пропадающая
/// кнопка дёргает раскладку и заставляет искать её заново.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.25,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 26, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Кнопка под картинкой: купить или напомнить, что вещь уже куплена.
class _PreviewAction extends StatelessWidget {
  const _PreviewAction({
    required this.item,
    required this.owned,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Высота одна и та же с кнопкой: при листании низ экрана не должен
    // прыгать оттого, что одна вещь куплена, а соседняя нет.
    if (owned) {
      return SizedBox(
        height: 56,
        child: Center(
          child: SceneLabel(
            text: l10n.shopOwnedLabel,
            size: 14,
            weight: 800,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sage,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          elevation: 5,
          shadowColor: AppColors.textPrimary.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.buyConfirmAction,
              style: sceneText(size: 15, weight: 800, color: Colors.white),
            ),
            const SizedBox(width: 12),
            _PriceChip(price: item.price, onDark: true),
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
