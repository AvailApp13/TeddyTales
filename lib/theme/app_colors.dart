import 'package:flutter/material.dart';

/// Палитра из макета.
///
/// Четыре значения [sageSoft], [blush], [cream], [tan] — это официальные
/// свотчи, вынесенные в макете отдельной строкой под баннером. Остальные сняты
/// пипеткой с самих экранов.
///
/// **Требует сверки с брендбуком.** Раздел 3 ТЗ аниматора говорит, что у бренда
/// есть брендбук с палитрой; его нам не передавали. Значения ниже сняты с
/// растрового макета, то есть уже прошли через сжатие JPEG — на глаз совпадают,
/// но точными считать их нельзя. Когда придёт брендбук, правится только этот
/// файл.
abstract final class AppColors {
  // --- Официальные свотчи макета -----------------------------------------

  /// Свотч 1 — светлый шалфейный. Фоны, заливка прогресса.
  static const Color sageSoft = Color(0xFFD8DDC9);

  /// Свотч 2 — пудрово-розовый. Акценты, сердца, кнопка заказа.
  static const Color blush = Color(0xFFECBAAF);

  /// Свотч 3 — кремовый. Поверхности карточек, фон экрана.
  static const Color cream = Color(0xFFF3E6D5);

  /// Свотч 4 — тёплый бежево-коричневый. Вторичный текст, обводки, дерево.
  static const Color tan = Color(0xFFC1A07D);

  // --- Снято с экранов ----------------------------------------------------

  /// Основной зелёный: активные вкладки, нижняя навигация, главные кнопки.
  static const Color sage = Color(0xFF9CC49A);

  /// Нажатый / более тёмный зелёный.
  static const Color sageDark = Color(0xFF7FA97C);

  /// Розовый на кнопке «Заказать моего мишку».
  static const Color blushStrong = Color(0xFFE9A79E);

  /// Фон экрана.
  static const Color background = Color(0xFFF6F1EB);

  /// Карточки и панели поверх фона.
  static const Color surface = Color(0xFFFFFDFA);

  /// Приподнятая поверхность: неактивные чипы, плитки показателей.
  static const Color surfaceMuted = Color(0xFFF1E9DF);

  /// Обводка карточек и разделители.
  static const Color outline = Color(0xFFE3D8C9);

  /// Основной текст — тёмно-коричневый, не чёрный.
  static const Color textPrimary = Color(0xFF4A3B2A);

  /// Подписи, единицы, второстепенное.
  static const Color textSecondary = Color(0xFF8C7A66);

  /// Монеты.
  static const Color coin = Color(0xFFEFC15E);

  /// Иконка «сердца» в шапке.
  static const Color heart = Color(0xFFE58C86);

  /// Цвета показателей ухода на главном экране.
  ///
  /// В макете плитки одинаково-кремовые, различает их только иконка. Эти
  /// значения — для колец и полосок прогресса, если они появятся.
  static const Color statFood = Color(0xFFE9A79E);
  static const Color statHygiene = Color(0xFF9CC49A);
  static const Color statSleep = Color(0xFFB7B2D8);
  static const Color statPlay = Color(0xFFEFC15E);
  static const Color statLove = Color(0xFFE58C86);
}
