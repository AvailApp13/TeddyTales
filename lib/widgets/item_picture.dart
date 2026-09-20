import 'package:flutter/material.dart';

import '../game/shop_items.dart';
import '../theme/app_colors.dart';

/// Картинка вещи — в магазине, в комнате и в списке купленного.
///
/// До 20.09 вещи рисовались эмодзи: 🛏 вместо кроватки, 🚪 вместо шкафа. Это
/// была заглушка из прототипа, и рядом с фотографическими комнатами она
/// читалась как чужая игра — заказчик: «все эмодзи, которые остались,
/// удали их».
///
/// Теперь у вещи либо своя картинка, либо её нет вовсе — и тогда рисуется
/// спокойная плашка с коробкой. Показывать такую вещь в витрине всё равно
/// не станут: магазин отбирает только то, у чего картинка есть.
class ItemPicture extends StatelessWidget {
  const ItemPicture({super.key, required this.item, this.size});

  final ShopItem item;

  /// Сторона картинки. `null` — занять всё доступное место.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final image = item.image;

    if (image == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            Icons.inventory_2_outlined,
            size: (size ?? 48) * 0.5,
            color: AppColors.textSecondary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return Image.asset(
      image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
