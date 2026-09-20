/// Камера комнаты: как снят её фон и где в этом кадре стоит мишка.
///
/// До 20.09 камера была одна на все комнаты — фоны генерировались серией, в
/// одном кадре 4:5 и с одинаковой высотой горизонта. Заказчик прислал новую
/// детскую, нарисованную сразу с потолком и в кадре 9:16, и снятую с другой
/// высоты: камера там стоит вдвое выше прежней. Общие константы после этого
/// врали бы либо детской, либо кухне с ванной.
///
/// Все доли меряются от **кадра фона**, а не от экрана: экран у каждого свой,
/// а кадр один и тот же на любом телефоне. Значения сняты с самих картинок —
/// по стыку потолка со стеной, стыку стены с полом и по тому, где сходятся
/// линии пола.
library;

import 'room_kind.dart';

class RoomCamera {
  const RoomCamera({
    required this.artWidth,
    required this.artHeight,
    required this.wallTop,
    required this.eyeLine,
    required this.floorLine,
    required this.standLine,
    required this.bearHeight,
    required this.hasCeiling,
  });

  /// Размер картинки в пикселях — по нему вписывается кадр.
  final double artWidth;
  final double artHeight;

  /// Верх стены: там, где она встречается с потолком.
  final double wallTop;

  /// Точка схода — высота глаза камеры в кадре. Главное число: по нему
  /// считается, каким ростом читается мишка.
  final double eyeLine;

  /// Стык стены с полом.
  final double floorLine;

  /// Линия пола, на которой стоит мишка.
  final double standLine;

  /// Рост мишки в долях высоты кадра.
  final double bearHeight;

  /// Нарисован ли потолок на самой картинке. Если нет — его дорисовывает
  /// [RoomCeiling] поверх пустой полосы над кадром.
  final bool hasCeiling;

  /// Высота камеры над полом в долях высоты стены.
  ///
  /// Отсюда и берётся рост: на полу с перспективой предмет читается не своей
  /// величиной в кадре, а отношением этой величины к расстоянию от его ног
  /// до точки схода.
  double get cameraOverWall => (floorLine - eyeLine) / (floorLine - wallTop);

  /// Рост мишки в метрах при заданной высоте потолка.
  ///
  /// Не для показа — для проверки. Этим числом сверяются комнаты между
  /// собой: мишка должен быть одного роста и в детской, и на кухне, иначе
  /// переход между ними будет выглядеть как смена масштаба мира.
  double bearMetres({double ceilingMetres = 2.5}) =>
      bearHeight / (standLine - eyeLine) * cameraOverWall * ceilingMetres;
}

/// Камера каждой комнаты.
const Map<RoomKind, RoomCamera> roomCameras = {
  // Присланная заказчиком 20.09 детская: кадр 9:16, потолок уже нарисован.
  // Померено по картинке: стык потолка со стеной 0.452, стык стены с полом
  // 0.748, линии стен сходятся на 0.598 — камера на половине высоты стены,
  // то есть примерно 1.25 м при потолке 2.5 м.
  RoomKind.nursery: RoomCamera(
    artWidth: 864,
    artHeight: 1536,
    wallTop: 0.452,
    eyeLine: 0.598,
    floorLine: 0.748,
    standLine: 0.95,
    // 0.30 кадра при этой камере даёт те же 1.07 м, что и 0.52 на прежнем
    // фоне. Заказчику обещано, что мишка останется «влитым», — это и
    // значит: меняется кадр, а рост в метрах нет.
    bearHeight: 0.30,
    hasCeiling: true,
  ),
  // Черновики от 17.09: кадр 4:5, потолка нет, камера низкая — 0.24 высоты
  // стены, около 60 см. Разбор в docs/room-design-v1.md, раздел 14.
  RoomKind.kitchen: _draft,
  RoomKind.bath: _draft,
};

const RoomCamera _draft = RoomCamera(
  artWidth: 896,
  artHeight: 1120,
  wallTop: 0.079,
  eyeLine: 0.447,
  floorLine: 0.564,
  standLine: 0.74,
  bearHeight: 0.52,
  hasCeiling: false,
);

RoomCamera cameraOf(RoomKind room) => roomCameras[room]!;
