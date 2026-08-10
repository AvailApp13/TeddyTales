import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Размеры и радиусы, снятые с макета.
abstract final class AppDimens {
  /// Карточки товаров, панели, плитки показателей.
  static const double radiusCard = 20;

  /// Чипы категорий и мелкие кнопки.
  static const double radiusChip = 14;

  /// Крупные кнопки во всю ширину и пузырь реплики.
  static const double radiusPill = 28;

  static const double gap = 12;
  static const double pagePadding = 16;
}

/// Тема приложения по макету.
///
/// Тема светлая и единственная: тёмной версии в макете нет. Если её попросят,
/// это отдельная работа — вся палитра построена на тёплых кремовых
/// поверхностях, механическая инверсия даст грязь.
abstract final class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.sage,
      onPrimary: Colors.white,
      primaryContainer: AppColors.sageSoft,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.blush,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.blush,
      onSecondaryContainer: AppColors.textPrimary,
      tertiary: AppColors.tan,
      onTertiary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.outline,
      outlineVariant: AppColors.outline,
    );

    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      // fontFamilyFallback нужен явно: движок ищет недостающие глифы в сети,
      // и без запасного семейства эмодзи офлайн превращаются в квадраты.
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
            fontFamily: 'Roboto',
          )
          .apply(fontFamilyFallback: const ['NotoColorEmoji']),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.sage,
        side: BorderSide.none,
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusChip),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sage,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.sage,
        inactiveTrackColor: AppColors.sageSoft,
        thumbColor: AppColors.sage,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.sage
              : AppColors.surfaceMuted,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.sage,
        linearTrackColor: AppColors.sageSoft,
      ),
    );
  }
}
