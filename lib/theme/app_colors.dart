import 'package:flutter/material.dart';

/// Палитра из макета.
///
/// 24.08.2026 — сверка попиксельно с присланным макетом (замечание владельца
/// продукта о расхождении гаммы): фоны потеплели (сливочные, а не сероватые),
/// шалфей и румяна стали насыщеннее — выбранные состояния макета #8FBF91,
/// розовая CTA #E79C94. Замеры делались доминирующим цветом по участкам
/// макета, а не пипеткой по одному пикселю джипега.
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
  static const Color sageSoft = Color(0xFFDCEBD4);

  /// Свотч 2 — пудрово-розовый. Акценты, сердца, кнопка заказа.
  static const Color blush = Color(0xFFF0B7AA);

  /// Свотч 3 — кремовый. Поверхности карточек, фон экрана.
  static const Color cream = Color(0xFFF6E8D3);

  /// Свотч 4 — тёплый бежево-коричневый. Вторичный текст, обводки, дерево.
  static const Color tan = Color(0xFFC1A07D);

  // --- Снято с экранов ----------------------------------------------------

  /// Основной зелёный: активные вкладки, нижняя навигация, главные кнопки.
  static const Color sage = Color(0xFF90BF90);

  /// Нажатый / более тёмный зелёный.
  static const Color sageDark = Color(0xFF6FA173);

  /// Розовый на кнопке «Заказать моего мишку».
  static const Color blushStrong = Color(0xFFE79C94);

  /// Фон экрана.
  static const Color background = Color(0xFFFAF3E6);

  /// Карточки и панели поверх фона.
  static const Color surface = Color(0xFFFFFBF2);

  /// Приподнятая поверхность: неактивные чипы, плитки показателей.
  static const Color surfaceMuted = Color(0xFFF5E9D6);

  /// Обводка карточек и разделители.
  static const Color outline = Color(0xFFEBDCC4);

  /// Основной текст — тёмно-коричневый, не чёрный.
  static const Color textPrimary = Color(0xFF4A3B2A);

  /// Подписи, единицы, второстепенное.
  static const Color textSecondary = Color(0xFF8C7A66);

  /// Монеты.
  static const Color coin = Color(0xFFEFC15E);

  /// Иконка «сердца» в шапке.
  static const Color heart = Color(0xFFE6938C);

  /// Цвета показателей ухода на главном экране.
  ///
  /// В макете плитки одинаково-кремовые, различает их только иконка. Эти
  /// значения — для колец и полосок прогресса, если они появятся.
  static const Color statFood = Color(0xFFE79C94);
  static const Color statHygiene = Color(0xFF90BF90);
  static const Color statSleep = Color(0xFFB7B2D8);
  static const Color statPlay = Color(0xFFEFC15E);
  static const Color statLove = Color(0xFFE6938C);
}
