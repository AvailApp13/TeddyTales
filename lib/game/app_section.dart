import 'package:flutter/material.dart';

import '../bear/bear_rig_spec.dart';

/// Разделы нижней навигации (КП 3.5).
///
/// КП говорит «шесть разделов», но не перечисляет их. На макете вкладок пять:
/// Главная · Комната · Магазин · Достижения · Профиль, причём «Достижения» —
/// механика сверх КП, отложенная во вторую версию. Оставшиеся четыре дополнены
/// двумя разделами, которым в КП нужен вход: обучение (раздел 9) и каталог
/// физических мишек (раздел 12).
///
/// **ДОПУЩЕНИЕ:** состав шестёрки выведен, а не задан. Уточнить.
enum AppSection {
  home('Главная', Icons.home_rounded, BearStage.newborn),
  room('Комната', Icons.chair_rounded, BearStage.firstSteps),
  shop('Магазин', Icons.storefront_rounded, BearStage.crawling),
  learning('Обучение', Icons.school_rounded, BearStage.growing),
  catalog('Мишки', Icons.card_giftcard_rounded, BearStage.newborn),
  profile('Профиль', Icons.person_rounded, BearStage.newborn);

  const AppSection(this.title, this.icon, this.minStage);

  final String title;
  final IconData icon;

  /// С какой стадии раздел открыт. До неё показывается замок с пояснением
  /// (КП 3.5).
  ///
  /// Каталог открыт с первого дня — так требует КП 12.1.
  final BearStage minStage;

  bool isUnlockedAt(BearStage stage) =>
      stage.riveValue >= minStage.riveValue;

  /// Пояснение к замку.
  String lockReason() => 'Откроется на стадии «${minStage.title}»';
}
