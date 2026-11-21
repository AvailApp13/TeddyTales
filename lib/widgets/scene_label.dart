import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Надпись поверх комнаты: тёмная капсула, белые буквы, округлый шрифт.
///
/// До 20.09 такие надписи — имя питомца, возраст, подписи колец — рисовались
/// текстом со светлой обводкой по букве. Заказчик: «что это за белая
/// обводка… смотрится как-то некрасиво, по-деревенски». Обводка и правда
/// приём дешёвый: на светлом потолке она сливается с фоном, на тёмном даёт
/// грязный ореол, а буквы от неё толстеют.
///
/// Капсула решает ту же задачу честно: подложка отделяет текст от комнаты,
/// какой бы та ни была, — от розовой детской до ночной спальни. Тот же приём
/// уже стоял на лепестках лапы, и заказчик показал на них как на образец;
/// теперь он один на весь экран.
class SceneLabel extends StatelessWidget {
  const SceneLabel({
    super.key,
    required this.text,
    this.trailing,
    this.size = 11,
    this.weight = 700,
    this.trailingColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
  });

  /// Основной текст.
  final String text;

  /// Приписка через пробел — например, процент показателя. Ставится тем же
  /// кеглем, но другим цветом, чтобы название и число не сливались.
  final String? trailing;

  final double size;

  /// Вес по оси `wght`: шрифт вариативный, и обычный `fontWeight` его не
  /// двигает.
  final double weight;

  final Color? trailingColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Nunito',
      fontSize: size,
      height: 1.25,
      fontVariations: [FontVariation('wght', weight)],
      color: Colors.white,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (trailing != null)
              TextSpan(
                text: '  $trailing',
                style: base.copyWith(
                  color: trailingColor ?? Colors.white.withValues(alpha: 0.75),
                  fontVariations: [FontVariation('wght', weight - 100)],
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: base,
      ),
    );
  }
}

/// Тот же округлый шрифт для надписей, которым капсула не нужна, — внутри
/// светлых плашек и кнопок.
TextStyle sceneText({
  double size = 13,
  double weight = 700,
  Color color = AppColors.textPrimary,
  double height = 1.2,
}) => TextStyle(
  fontFamily: 'Nunito',
  fontSize: size,
  height: height,
  color: color,
  fontVariations: [FontVariation('wght', weight)],
);
