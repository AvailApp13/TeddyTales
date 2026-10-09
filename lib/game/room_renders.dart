// Сгенерировано tool/nursery3d/items.py — не править руками.
//
// Вещи игровой, посчитанные в 3D на своих местах: слой вещи вместе с
// тенью и где он лежит в кадре комнаты (доли ширины и высоты кадра).
// Пара «место/вещь», которой здесь нет, рисуется картинкой магазина.

import 'room_render.dart';

const Map<String, RoomRender> roomRenders = {
  'nursery.floor_left/armchair': RoomRender(0.00106, 0.33852, 0.88948, 0.26854),
  'nursery.rug/rug': RoomRender(0.12859, 0.71591, 0.75877, 0.14713),
  'nursery.wall_pic_left/pic_bear': RoomRender(
    0.40170,
    0.20036,
    0.13815,
    0.09569,
  ),
  'nursery.wall_pic_left/pic_heart': RoomRender(
    0.39639,
    0.19617,
    0.14453,
    0.10347,
  ),
  'nursery.wall_pic_right/pic_bear': RoomRender(
    0.57598,
    0.20036,
    0.14453,
    0.09569,
  ),
  'nursery.wall_pic_right/pic_heart': RoomRender(
    0.57705,
    0.19557,
    0.14453,
    0.10467,
  ),
  'nursery.wall_shelf/pic_bear': RoomRender(0.74070, 0.24880, 0.14346, 0.09629),
  'nursery.wall_shelf/pic_heart': RoomRender(
    0.73964,
    0.24402,
    0.14559,
    0.10467,
  ),
  'nursery.wall_shelf/shelf': RoomRender(0.70670, 0.24701, 0.22742, 0.09270),
};
