/// Места в комнате: куда игрок может поставить вещь.
///
/// ## Почему слоты, а не координаты у предметов
///
/// До 18.09 у каждого из тридцати предметов была своя жёсткая координата.
/// Из этого следовало две беды. Первая: комната у всех игроков собиралась
/// одинаково — кроватка всегда там, шкаф всегда тут, и редактор комнаты
/// (КП 10.7) существовал только на бумаге. Вторая: размер вещи задавала сама
/// вещь, поэтому кроватка в 1.7 роста занимала полкадра и накрывала мишку.
///
/// Решение заказчика (18.09): комната размечается местами, а размеры вещей
/// подгоняются под место. Слот принимает **любой предмет своей категории** —
/// в место у левой стены встанет кроватка, или кресло, или комод, что игрок
/// туда поставит. Комнаты у разных людей получаются разные, а художник
/// рисует каждую вещь под известный максимальный габарит.
///
/// Плата за это — размерный ряд перестаёт быть правдивым: шкаф не будет
/// вдвое выше мишки, его подгонит слот. Размен осознанный: в кадре важнее
/// композиция, чем сантиметры. Настоящие пропорции каталога остались в
/// `docs/interior-size-guide.md` для дизайнера.
///
/// ## Координаты
///
/// Всё в долях кадра сцены. `x` — центр места по горизонтали, `y` — линия,
/// на которой вещь стоит (для настенных — центр по вертикали). `maxW` и
/// `maxH` — наибольший габарит: вещь вписывается в него по своим пропорциям
/// и никогда не выходит за края.
///
/// Разметка сделана по сгенерированным фонам, а не по расчёту: угол стен,
/// линия плинтуса и окно на каждой картинке свои, и места привязаны к тому,
/// что реально нарисовано.
library;

import 'room_kind.dart';
import 'shop_items.dart';

/// Одно место в комнате.
class RoomSlot {
  const RoomSlot({
    required this.id,
    required this.room,
    required this.x,
    required this.y,
    required this.maxW,
    required this.maxH,
    required this.accepts,
    this.onWall = false,
    this.depth = 1,
  });

  /// Устойчивый ключ места: под ним хранится, что игрок сюда поставил.
  final String id;

  final RoomKind room;

  /// Центр по горизонтали и линия пола (или центр по вертикали для стен).
  final double x;
  final double y;

  /// Наибольший габарит вещи в долях кадра.
  final double maxW;
  final double maxH;

  /// Какие категории каталога сюда становятся.
  final Set<ItemKind> accepts;

  final bool onWall;

  /// Порядок отрисовки: больше — ближе к зрителю. Мишка стоит между 5 и 6,
  /// поэтому игрушки на переднем плане (depth 6+) рисуются перед ним.
  final int depth;

  bool takes(ShopItem item) => accepts.contains(item.kind);
}

/// Все места всех комнат.
///
/// В детской двенадцать мест: этого хватает, чтобы комната выглядела
/// обжитой, и мало настолько, чтобы каждая купленная вещь была заметна.
/// Тридцать мест дали бы витрину склада, а не комнату.
const List<RoomSlot> roomSlots = [
  // --- Детская ------------------------------------------------------------
  //
  // Перемерено 20.09 по пустой комнате, которую прислал заказчик. Прежняя
  // разметка обходила нарисованную мебель — кресло, комод, ковёр были частью
  // фона, и места лепились по остаткам. Теперь комната пустая, и места
  // расставлены как в настоящей детской: крупная мебель вдоль задней стены,
  // мягкое — по углам, ковёр под ногами, картины на стене.
  //
  // Стык стены с полом на 0.525, у левой стены он уходит вниз до 0.60.
  // Мишка стоит по центру на 0.80 и занимает примерно от 0.33 до 0.67
  // ширины — центральные напольные места этой полосы избегают, иначе рамка
  // перечёркивает ему лицо.

  // Задняя стена, левее центра: кроватка, комод, стеллаж.
  RoomSlot(
    id: 'nursery.back_left',
    room: RoomKind.nursery,
    x: 0.29,
    y: 0.585,
    maxW: 0.27,
    maxH: 0.24,
    accepts: {ItemKind.furniture},
    depth: 2,
  ),
  // Задняя стена, правее центра.
  RoomSlot(
    id: 'nursery.back_right',
    room: RoomKind.nursery,
    x: 0.71,
    y: 0.585,
    maxW: 0.27,
    maxH: 0.24,
    accepts: {ItemKind.furniture},
    depth: 2,
  ),
  // У окна слева. Высота ограничена подоконником: высокая вещь здесь лезет
  // на окно — заказчик поймал это первым ещё на старом фоне.
  RoomSlot(
    id: 'nursery.floor_left',
    room: RoomKind.nursery,
    x: 0.13,
    y: 0.70,
    maxW: 0.25,
    maxH: 0.22,
    accepts: {ItemKind.furniture, ItemKind.decor},
    depth: 4,
  ),
  // Правый угол: кресло, качели, растение.
  RoomSlot(
    id: 'nursery.corner_right',
    room: RoomKind.nursery,
    x: 0.87,
    y: 0.72,
    maxW: 0.26,
    maxH: 0.26,
    accepts: {ItemKind.furniture, ItemKind.decor},
    depth: 3,
  ),
  // Ковёр под ногами мишки — единственное место, где вещь лежит, а не стоит.
  RoomSlot(
    id: 'nursery.rug',
    room: RoomKind.nursery,
    x: 0.50,
    y: 0.92,
    maxW: 0.54,
    maxH: 0.15,
    accepts: {ItemKind.furniture},
    depth: 1,
  ),
  // Три места под игрушки: по бокам от мишки и ближе к зрителю.
  RoomSlot(
    id: 'nursery.toy_left',
    room: RoomKind.nursery,
    x: 0.15,
    y: 0.88,
    maxW: 0.17,
    maxH: 0.15,
    accepts: {ItemKind.toy},
    depth: 6,
  ),
  RoomSlot(
    id: 'nursery.toy_right',
    room: RoomKind.nursery,
    x: 0.85,
    y: 0.88,
    maxW: 0.17,
    maxH: 0.15,
    accepts: {ItemKind.toy},
    depth: 6,
  ),
  RoomSlot(
    id: 'nursery.toy_front',
    room: RoomKind.nursery,
    x: 0.63,
    y: 0.99,
    maxW: 0.19,
    maxH: 0.16,
    accepts: {ItemKind.toy},
    depth: 7,
  ),
  // Стены. Задняя — два места под картины и полки, левая у окна — одно.
  RoomSlot(
    id: 'nursery.wall_back_left',
    room: RoomKind.nursery,
    x: 0.36,
    y: 0.31,
    maxW: 0.20,
    maxH: 0.17,
    accepts: {ItemKind.decor},
    onWall: true,
  ),
  RoomSlot(
    id: 'nursery.wall_back_right',
    room: RoomKind.nursery,
    x: 0.68,
    y: 0.31,
    maxW: 0.20,
    maxH: 0.17,
    accepts: {ItemKind.decor},
    onWall: true,
  ),
  RoomSlot(
    id: 'nursery.wall_left',
    room: RoomKind.nursery,
    x: 0.14,
    y: 0.25,
    maxW: 0.15,
    maxH: 0.15,
    accepts: {ItemKind.decor},
    onWall: true,
  ),
  // --- Кухня ---------------------------------------------------------------
  // Мест меньше: кухня не обставляется игроком, она пока смена обстановки.
  // Четыре места — чтобы было куда поставить купленное, если человек
  // захочет обжить и её.
  RoomSlot(
    id: 'kitchen.floor_left',
    room: RoomKind.kitchen,
    x: 0.22,
    y: 0.78,
    maxW: 0.34,
    maxH: 0.24,
    accepts: {ItemKind.furniture},
    depth: 4,
  ),
  RoomSlot(
    id: 'kitchen.back_right',
    room: RoomKind.kitchen,
    x: 0.72,
    y: 0.66,
    maxW: 0.28,
    maxH: 0.26,
    accepts: {ItemKind.furniture},
    depth: 2,
  ),
  RoomSlot(
    id: 'kitchen.toy_front',
    room: RoomKind.kitchen,
    x: 0.80,
    y: 0.94,
    maxW: 0.16,
    maxH: 0.14,
    accepts: {ItemKind.toy},
    depth: 7,
  ),
  RoomSlot(
    id: 'kitchen.wall_back',
    room: RoomKind.kitchen,
    x: 0.66,
    y: 0.26,
    maxW: 0.16,
    maxH: 0.18,
    accepts: {ItemKind.decor},
    onWall: true,
  ),

  // --- Ванная --------------------------------------------------------------
  RoomSlot(
    id: 'bath.floor_left',
    room: RoomKind.bath,
    x: 0.24,
    y: 0.80,
    maxW: 0.32,
    maxH: 0.22,
    accepts: {ItemKind.furniture},
    depth: 4,
  ),
  RoomSlot(
    id: 'bath.corner_right',
    room: RoomKind.bath,
    x: 0.88,
    y: 0.74,
    maxW: 0.20,
    maxH: 0.22,
    accepts: {ItemKind.furniture, ItemKind.decor},
    depth: 3,
  ),
  RoomSlot(
    id: 'bath.toy_front',
    room: RoomKind.bath,
    x: 0.70,
    y: 0.95,
    maxW: 0.16,
    maxH: 0.14,
    accepts: {ItemKind.toy},
    depth: 7,
  ),
  RoomSlot(
    id: 'bath.wall_back',
    room: RoomKind.bath,
    x: 0.60,
    y: 0.28,
    maxW: 0.16,
    maxH: 0.18,
    accepts: {ItemKind.decor},
    onWall: true,
  ),
];

/// Места выбранной комнаты, в порядке отрисовки.
List<RoomSlot> slotsOf(RoomKind room) =>
    [
      for (final slot in roomSlots)
        if (slot.room == room) slot,
    ]..sort((a, b) {
      // Настенное всегда позади напольного: оно висит на стене.
      if (a.onWall != b.onWall) return a.onWall ? -1 : 1;
      return a.depth.compareTo(b.depth);
    });

RoomSlot? slotById(String id) {
  for (final slot in roomSlots) {
    if (slot.id == id) return slot;
  }
  return null;
}

/// Во сколько раз уменьшить вещь, чтобы она влезла в место.
///
/// Вписывание по меньшей стороне, а не растяжение: пропорции вещи — это её
/// узнаваемость. Кроватка, растянутая под квадратное место, перестаёт быть
/// кроваткой.
({double w, double h}) fitIntoSlot(RoomSlot slot, ShopItem item) {
  final placement = _aspect(item.id);
  final byWidth = slot.maxW / placement.w;
  final byHeight = slot.maxH / placement.h;
  final k = byWidth < byHeight ? byWidth : byHeight;
  return (w: placement.w * k, h: placement.h * k);
}

/// Пропорции вещи берём из размерной сетки: там честные габариты каталога.
/// Слот решает, насколько крупно вещь показать, сетка — какой она формы.
({double w, double h}) _aspect(String itemId) {
  for (final p in _proportions) {
    if (p.$1 == itemId) return (w: p.$2, h: p.$3);
  }
  return (w: 1, h: 1);
}

const List<(String, double, double)> _proportions = [
  ('wardrobe', 1.15, 1.9),
  ('shelf', 0.95, 1.75),
  ('bed', 1.7, 1.0),
  ('dresser', 1.0, 1.05),
  ('table', 1.1, 0.85),
  ('chair', 0.6, 0.95),
  ('armchair', 1.05, 1.05),
  ('lamp', 0.5, 1.5),
  ('basket', 0.65, 0.55),
  ('rug', 2.4, 0.45),
  ('pic_bear', 0.55, 0.55),
  ('pic_forest', 0.55, 0.55),
  ('pic_moon', 0.5, 0.5),
  ('clock', 0.42, 0.42),
  ('poster', 0.52, 0.72),
  ('garland', 2.2, 0.22),
  ('plant', 0.55, 0.85),
  ('cactus', 0.35, 0.5),
  ('pillow_heart', 0.45, 0.35),
  ('pillow_star', 0.45, 0.35),
  ('teddy', 0.42, 0.5),
  ('ball', 0.35, 0.35),
  ('cubes', 0.5, 0.36),
  ('duck', 0.3, 0.3),
  ('drum', 0.45, 0.36),
  ('car', 0.5, 0.3),
  ('train', 0.7, 0.32),
  ('puzzle', 0.5, 0.14),
  ('rocket', 0.38, 0.6),
  ('kite', 0.6, 0.7),
];
