/// Размерная сетка комнаты: где стоит каждый предмет и какого он размера.
///
/// Зачем. Дизайнеру интерьера нужен размерный ряд всего каталога: насколько
/// шкаф выше мишки, какого диаметра ковёр, где висят картины. Этот файл —
/// единственный источник правды по габаритам: из него рисуется сцена комнаты
/// в приложении (габаритная сборка-«блокаут») и генерируется гайд
/// `docs/interior-size-guide.md` для дизайнера.
///
/// Система измерений. Базовый модуль — РОСТ МИШКИ, стоящего в комнате.
/// У реального героя каталога это 15 см, поэтому перевод в сантиметры для
/// дизайнера: 1.0 модуля = 15 см. Все ширины и высоты ниже — в модулях.
///
/// Координаты — доли сцены: fx — центр предмета по горизонтали (0..1),
/// напольные предметы стоят на линии пола, настенные висят на высоте
/// [RoomPlacement.wallFy] (доля высоты сцены до ЦЕНТРА предмета).
library;

/// Один предмет в комнате.
class RoomPlacement {
  const RoomPlacement(
    this.id,
    this.fx, {
    required this.w,
    required this.h,
    this.wallFy,
    this.z = 0,
  });

  final String id;

  /// Центр по горизонтали, доля ширины сцены.
  final double fx;

  /// Габариты в модулях (1.0 — рост мишки).
  final double w;
  final double h;

  /// Для настенных предметов — высота центра, доля высоты сцены.
  /// `null` — предмет стоит на полу.
  final double? wallFy;

  /// Порядок отрисовки: больше — ближе к зрителю. Мишка рисуется поверх
  /// всего заднего плана, перед ним — только z >= 10.
  final int z;

  bool get onWall => wallFy != null;
}

/// Раскладка всех предметов каталога, которые могут стоять в комнате.
///
/// Габариты подобраны под макет (кроватка чуть длиннее мишки, шкаф почти
/// в два роста) и здравый смысл кукольной комнаты; утверждаются дизайнером —
/// правится ровно этот список, сцена и гайд пересобираются сами.
const List<RoomPlacement> roomLayout = [
  // --- Мебель, задний план ---
  RoomPlacement('wardrobe', 0.08, w: 1.15, h: 1.9),
  RoomPlacement('shelf', 0.20, w: 0.95, h: 1.75),
  RoomPlacement('bed', 0.13, w: 1.7, h: 1.0),
  RoomPlacement('dresser', 0.66, w: 1.0, h: 1.05),
  RoomPlacement('table', 0.33, w: 1.1, h: 0.85),
  RoomPlacement('chair', 0.44, w: 0.6, h: 0.95),
  RoomPlacement('armchair', 0.13, w: 1.05, h: 1.05, z: 1),
  RoomPlacement('lamp', 0.93, w: 0.5, h: 1.5),
  RoomPlacement('basket', 0.68, w: 0.65, h: 0.55, z: 1),
  // Ковёр лежит под мишкой — рисуется первым.
  RoomPlacement('rug', 0.5, w: 2.4, h: 0.45, z: -1),

  // --- Декор: стены ---
  RoomPlacement('pic_bear', 0.83, w: 0.55, h: 0.55, wallFy: 0.26),
  RoomPlacement('pic_forest', 0.63, w: 0.55, h: 0.55, wallFy: 0.22),
  RoomPlacement('pic_moon', 0.72, w: 0.5, h: 0.5, wallFy: 0.33),
  RoomPlacement('clock', 0.5, w: 0.42, h: 0.42, wallFy: 0.16),
  RoomPlacement('poster', 0.06, w: 0.52, h: 0.72, wallFy: 0.27),
  RoomPlacement('garland', 0.5, w: 2.2, h: 0.22, wallFy: 0.07),

  // --- Декор: пол и поверхности ---
  RoomPlacement('plant', 0.80, w: 0.55, h: 0.85, z: 1),
  RoomPlacement('cactus', 0.70, w: 0.35, h: 0.5, z: 1),
  RoomPlacement('pillow_heart', 0.10, w: 0.45, h: 0.35, z: 2),
  RoomPlacement('pillow_star', 0.92, w: 0.45, h: 0.35, z: 2),

  // --- Игрушки: передний план, мельче мишки ---
  RoomPlacement('teddy', 0.075, w: 0.42, h: 0.5, z: 10),
  RoomPlacement('ball', 0.20, w: 0.35, h: 0.35, z: 10),
  RoomPlacement('cubes', 0.29, w: 0.5, h: 0.36, z: 10),
  RoomPlacement('duck', 0.375, w: 0.3, h: 0.3, z: 10),
  RoomPlacement('drum', 0.63, w: 0.45, h: 0.36, z: 10),
  RoomPlacement('car', 0.72, w: 0.5, h: 0.3, z: 10),
  RoomPlacement('train', 0.84, w: 0.7, h: 0.32, z: 10),
  RoomPlacement('puzzle', 0.94, w: 0.5, h: 0.14, z: 10),
  RoomPlacement('rocket', 0.55, w: 0.38, h: 0.6, z: 10),
  RoomPlacement('kite', 0.93, w: 0.6, h: 0.7, wallFy: 0.12),
];

RoomPlacement? placementOf(String id) {
  for (final p in roomLayout) {
    if (p.id == id) return p;
  }
  return null;
}

/// Цвета сменных поверхностей. Ключи — id обоев и полов из каталога.
/// Значения — пары «основной/дополнительный» в ARGB, чтобы слой сцены не
/// зависел от Flutter-типов (файл без импортов, тестируется как чистый Dart).
const Map<String, (int, int)> roomSurfaces = {
  'wall_rose': (0xFFF6E3DC, 0xFFF0D5CC),
  'wall_sage': (0xFFE4EDDC, 0xFFD6E4CC),
  'wall_sky': (0xFFE0EAF2, 0xFFD0DEEA),
  'floor_wood': (0xFFE8CBA8, 0xFFDDBC94),
  'floor_light': (0xFFF1E3CD, 0xFFE8D7BC),
  'floor_carpet': (0xFFEBD8D2, 0xFFE0C8C0),
};
