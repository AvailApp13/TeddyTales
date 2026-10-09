/// Вещь игровой, посчитанная в 3D на своём месте (`tool/nursery3d/items.py`).
///
/// Заказчик 09.10: картинки вещей, наклеенные на 3D-комнату, не встают — у
/// каждой картинки свой ракурс и свой свет, теней нет, кроватка висит на
/// стене, ковёр стоит плакатом. Вещь, посчитанная в той же сцене, что и
/// комната, — той же камерой и тем же светом, — лежит готовым слоем: вещь
/// вместе со своей тенью на стене и полу. Слой кладётся поверх любых стен и
/// пола (`docs/room-furniture-plan.md`).
///
/// Пара «место/вещь», которой ещё нет в [roomRenders], рисуется картинкой
/// магазина, как раньше.
library;

import 'room_kind.dart';
import 'room_renders.dart';

/// Где слой вещи лежит в кадре комнаты — доли ширины и высоты кадра.
class RoomRender {
  const RoomRender(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Готовый слой вещи [itemId] в месте [slotId] или `null`.
RoomRender? roomRenderOf(String slotId, String itemId) =>
    kNursery3d ? roomRenders['$slotId/$itemId'] : null;

/// Файл слоя: `assets/rooms/nursery/items/<место>__<вещь>.webp`.
String roomRenderAsset(String slotId, String itemId) =>
    'assets/rooms/nursery/items/${slotId.split('.').last}__$itemId.webp';
