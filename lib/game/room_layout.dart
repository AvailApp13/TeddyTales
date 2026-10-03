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
/// напольные предметы стоят на линии пола своего плана, настенные висят на
/// высоте [RoomPlacement.wallFy] (доля высоты сцены до ЦЕНТРА предмета).
///
/// ## Три плана глубины
///
/// Раскладка переписана 18.09 по `docs/room-design-v1.md`. До этого все
/// предметы стояли в одной плоскости, и это не работало арифметически: при
/// герое в 45 % высоты кадра вся ширина комнаты — 1.95 роста мишки, а одна
/// только напольная мебель каталога занимает 14.6. Кроватка съедала 87 %
/// ширины, ковёр не помещался вовсе, рядом не вставало ничего.
///
/// Теперь у комнаты три плана со своим масштабом и своей линией пола —
/// дальний, средний и передний. Это не украшение, а единственный способ
/// вместить в кадр собственный каталог.
library;

/// План глубины: насколько предмет уменьшен и на какой линии стоит.
///
/// Масштабы подобраны под самый высокий предмет каталога: шкаф в 1.9 роста
/// на дальнем плане становится 1.18 — заметно выше мишки, но не упирается в
/// потолок.
enum RoomPlane {
  /// Задняя стена: шкаф, книжная полка, комод. Ширина плана — 3.15 роста.
  far(0.62, 0.58),

  /// Основная мебель: кроватка, стол, стул, кресло. Ширина — 2.44 роста.
  mid(0.80, 0.70),

  /// Ковёр, игрушки и сам мишка. Ширина — 1.95 роста.
  near(1.0, 0.86);

  const RoomPlane(this.scale, this.floorLine);

  /// Во сколько раз предметы этого плана мельче своего размера в модулях.
  final double scale;

  /// Линия пола плана — доля высоты сцены, на которой стоят его предметы.
  final double floorLine;
}

/// Один предмет в комнате.
class RoomPlacement {
  const RoomPlacement(
    this.id,
    this.fx, {
    required this.w,
    required this.h,
    required this.plane,
    this.wallFy,
    this.z = 0,
  });

  final String id;

  /// Центр по горизонтали, доля ширины сцены.
  final double fx;

  /// Габариты в модулях (1.0 — рост мишки).
  final double w;
  final double h;

  /// На каком плане глубины стоит предмет.
  final RoomPlane plane;

  /// Для настенных предметов — высота центра, доля высоты сцены.
  /// `null` — предмет стоит на полу.
  final double? wallFy;

  /// Порядок отрисовки: больше — ближе к зрителю. Мишка рисуется поверх
  /// всего заднего плана, перед ним — только z >= 10.
  final int z;

  bool get onWall => wallFy != null;

  /// Множитель размера с учётом плана.
  double get scale => plane.scale;
}

/// Раскладка всех предметов каталога, которые могут стоять в комнате.
///
/// Координаты — из раздела 6 `docs/room-design-v1.md`, где они разложены по
/// трём зонам КП 10.1: сон слева, еда справа, игра в центре и на переднем
/// плане. Габариты подобраны под макет и утверждаются дизайнером; правится
/// ровно этот список, сцена и гайд пересобираются сами.
const List<RoomPlacement> roomLayout = [
  // --- Дальний план: задняя стена -----------------------------------------
  RoomPlacement('wardrobe', 0.20, w: 1.15, h: 1.9, plane: RoomPlane.far),
  RoomPlacement('shelf', 0.36, w: 0.95, h: 1.75, plane: RoomPlane.far),
  RoomPlacement('dresser', 0.72, w: 1.0, h: 1.05, plane: RoomPlane.far),

  // --- Средний план --------------------------------------------------------
  // Зона сна: кроватка вдоль левой стены, торшер у изголовья.
  RoomPlacement('bed', 0.22, w: 1.7, h: 1.0, plane: RoomPlane.mid),
  RoomPlacement('lamp', 0.06, w: 0.5, h: 1.5, plane: RoomPlane.mid),
  // Зона еды: стол со стулом у задней стены справа.
  RoomPlacement('table', 0.62, w: 1.1, h: 0.85, plane: RoomPlane.mid),
  RoomPlacement('chair', 0.76, w: 0.6, h: 0.95, plane: RoomPlane.mid),
  RoomPlacement('armchair', 0.88, w: 1.05, h: 1.05, plane: RoomPlane.mid, z: 1),
  // Зелень разделяет зоны.
  RoomPlacement('plant', 0.50, w: 0.55, h: 0.85, plane: RoomPlane.mid, z: 1),
  RoomPlacement('cactus', 0.68, w: 0.35, h: 0.5, plane: RoomPlane.mid, z: 1),

  // --- Передний план: зона игры -------------------------------------------
  // Ковёр лежит под мишкой — рисуется первым.
  RoomPlacement('rug', 0.50, w: 2.4, h: 0.45, plane: RoomPlane.near, z: -1),
  RoomPlacement('basket', 0.90, w: 0.65, h: 0.55, plane: RoomPlane.near, z: 1),
  RoomPlacement(
    'pillow_heart',
    0.12,
    w: 0.45,
    h: 0.35,
    plane: RoomPlane.near,
    z: 2,
  ),
  RoomPlacement(
    'pillow_star',
    0.80,
    w: 0.45,
    h: 0.35,
    plane: RoomPlane.near,
    z: 2,
  ),
  RoomPlacement('teddy', 0.06, w: 0.42, h: 0.5, plane: RoomPlane.near, z: 10),
  RoomPlacement('rocket', 0.16, w: 0.38, h: 0.6, plane: RoomPlane.near, z: 10),
  RoomPlacement('ball', 0.24, w: 0.35, h: 0.35, plane: RoomPlane.near, z: 10),
  RoomPlacement('cubes', 0.34, w: 0.5, h: 0.36, plane: RoomPlane.near, z: 10),
  RoomPlacement('duck', 0.42, w: 0.3, h: 0.3, plane: RoomPlane.near, z: 10),
  RoomPlacement('drum', 0.60, w: 0.45, h: 0.36, plane: RoomPlane.near, z: 10),
  RoomPlacement('car', 0.70, w: 0.5, h: 0.3, plane: RoomPlane.near, z: 10),
  RoomPlacement('train', 0.82, w: 0.7, h: 0.32, plane: RoomPlane.near, z: 10),
  RoomPlacement('puzzle', 0.92, w: 0.5, h: 0.14, plane: RoomPlane.near, z: 10),

  // --- Стены ---------------------------------------------------------------
  // Настенное живёт на дальнем плане: оно висит за всей мебелью.
  RoomPlacement(
    'garland',
    0.60,
    w: 2.2,
    h: 0.22,
    plane: RoomPlane.far,
    wallFy: 0.10,
  ),
  RoomPlacement(
    'kite',
    0.92,
    w: 0.6,
    h: 0.7,
    plane: RoomPlane.far,
    wallFy: 0.16,
  ),
  RoomPlacement(
    'clock',
    0.66,
    w: 0.42,
    h: 0.42,
    plane: RoomPlane.far,
    wallFy: 0.26,
  ),
  RoomPlacement(
    'pic_forest',
    0.44,
    w: 0.55,
    h: 0.55,
    plane: RoomPlane.far,
    wallFy: 0.28,
  ),
  RoomPlacement(
    'pic_bear',
    0.80,
    w: 0.55,
    h: 0.55,
    plane: RoomPlane.far,
    wallFy: 0.30,
  ),
  // Левая стена: над кроваткой и у самого угла.
  RoomPlacement(
    'pic_moon',
    0.10,
    w: 0.5,
    h: 0.5,
    plane: RoomPlane.far,
    wallFy: 0.30,
  ),
  RoomPlacement(
    'poster',
    0.03,
    w: 0.52,
    h: 0.72,
    plane: RoomPlane.far,
    wallFy: 0.42,
  ),
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
