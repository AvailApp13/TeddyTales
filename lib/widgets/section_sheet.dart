import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Раздел открывается листом поверх комнаты, а не отдельным экраном.
///
/// Решение заказчика 20.09: «с выпадающими окнами на самом экране». Разница
/// не косметическая. Полноэкранный переход уводит от питомца — человек
/// перестаёт его видеть, и возвращение читается как «выйти обратно». Лист
/// оставляет комнату на месте: магазин выезжает снизу, мишка виден над ним,
/// и покупка происходит при нём, а не вместо него.
///
/// Высота — доля экрана, а не содержимого: полоска комнаты сверху должна
/// оставаться всегда, иначе лист ничем не отличается от экрана.
Future<T?> showSectionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double heightFactor = 0.88,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.32),
    builder: (context) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: Column(
            children: [
              // Полоска-ручка: знак, что лист тянется вниз и закрывается
              // жестом, а не только кнопкой.
              Container(
                width: 46,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(child: Builder(builder: builder)),
            ],
          ),
        ),
      ),
    ),
  );
}
