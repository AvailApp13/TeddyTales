/// Фон комнаты: две стены углом, пол с глубиной, окно и расставленные вещи.
///
/// Это габаритная сборка («блокаут») для утверждения размерного ряда:
/// каждый размещённый предмет рисуется эмодзи-заглушкой ровно того размера,
/// который задан в `room_layout.dart`, с поправкой на план глубины. Дизайнер
/// интерьера смотрит на эту сцену и на `docs/room-design-v1.md` и отрисовывает
/// предметы в тех же габаритах — тогда готовый арт встанет на место заглушек
/// без переразметки.
///
/// Комната показана углом со смещением влево: левая стена уходит под углом,
/// задняя ровная, пол уходит вглубь. Так устроен кадр в `room-design-v1.md`,
/// и так он держит три плана глубины — без них комната не вмещает каталог.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/room_kind.dart';
import '../game/room_layout.dart';

/// Где на экране лежит кадр комнаты и всё, что к нему привязано.
///
/// Появился, когда комната поехала на весь экран телефона (задача заказчика
/// 20.09). До этого сцена была карточкой примерно той же формы, что и кадр
/// фона, и доли кадра совпадали с долями сцены. На экране 9:19.5 они больше
/// не совпадают: кадр 4:5, вписанный по ширине, закрывает только низ.
///
/// Вписывание именно по ширине — не вкусовое решение. Заказчик просил, чтобы
/// мишка остался «влитым», то есть сохранил своё соотношение к комнате. Оно
/// держится, только если комната масштабируется целиком, одним числом; а
/// какое это число — задаёт ширина экрана, потому что по высоте кадр короче.
/// Остаток сверху занимает потолок.
class RoomFrame {
  const RoomFrame._(this.scene, this.rect);

  /// Вся сцена — весь экран.
  final Size scene;

  /// Кадр комнаты внутри неё.
  final Rect rect;

  /// Высота кадра фона к его ширине (896 × 1120).
  static const double aspect = 1120 / 896;

  factory RoomFrame.of(Size scene) {
    final height = scene.width * aspect;
    // Прижат к низу: пол должен доходить до края экрана, иначе мишка будет
    // стоять на полоске, под которой видно фон приложения.
    return RoomFrame._(
      scene,
      Rect.fromLTWH(0, scene.height - height, scene.width, height),
    );
  }

  /// Полоса под потолок. Ноль, если экран ниже кадра — тогда у картинки
  /// срезается верх, но пропорции и низ остаются на месте.
  double get ceilingHeight => math.max(0, rect.top);

  /// Точка схода в координатах сцены: по ней сходятся и доски пола на
  /// картинке, и стыки нарисованного потолка.
  double get vanishingY => rect.top + RoomSceneBackdrop.eyeLine * rect.height;

  /// Линия пола, на которой стоит мишка.
  double get standY => rect.top + RoomSceneBackdrop.standLine * rect.height;

  /// Рост мишки в пикселях — доля кадра комнаты, а не экрана.
  double get bearHeight => RoomSceneBackdrop.heroHeight * rect.height;

  /// Куда смотрит камера по горизонтали.
  double get centerX => rect.center.dx;

  /// Вертикаль, на которой стоит мишка.
  ///
  /// Не по центру: заказчик просил сдвинуть примерно на 10% правее, со
  /// стороны зрителя.
  double get bearCenterX => rect.left + rect.width * (0.5 + bearOffsetX);

  /// Сдвиг мишки вправо от центра, в долях ширины.
  static const double bearOffsetX = 0.10;
}

class RoomSceneBackdrop extends StatelessWidget {
  const RoomSceneBackdrop({super.key, this.room = RoomKind.nursery});

  /// Какая комната показана.
  final RoomKind room;

  /// Рост мишки в долях высоты сцены — модуль, в котором меряются места.
  static const double defaultBearModule = 0.45;

  /// Рост мишки в долях **кадра комнаты**.
  ///
  /// 45% было решением заказчика 17.09 взамен прежнего «во весь экран»,
  /// 18.09 он попросил прибавить примерно 15% — вышло 52%. С 20.09 это доля
  /// кадра комнаты, а не экрана: комната поехала на весь телефон, и считать
  /// рост от высоты экрана значило бы менять размер мишки от модели
  /// телефона.
  static const double heroHeight = 0.52;

  /// Линия горизонта: где задняя стена встречается с полом.
  static const double horizon = 0.564;

  /// Вертикаль угла между левой и задней стеной, доля ширины.
  static const double cornerX = 0.27;

  /// Точка схода: высота глаза камеры в кадре.
  ///
  /// Не на глаз — померено по швам досок пола в `assets/rooms/nursery.png`
  /// (896×1120). Три шва сходятся в точке (617, 501), то есть на 0.447
  /// высоты кадра. Верх стены на 0.079, стык с полом на 0.564, значит
  /// камера стоит на 0.24 высоты стены: при потолке 2.5 м — 60 см над
  /// полом. Низкая камера, вровень с ребёнком.
  static const double eyeLine = 0.447;

  /// Где мишка стоит на полу, доля высоты кадра.
  ///
  /// Это и есть «правильные пропорции»: на полу с перспективой рост
  /// предмета читается не его величиной в кадре, а отношением этой величины
  /// к расстоянию от его ног до точки схода. Мишка ростом 0.52 кадра,
  /// стоящий у самого нижнего края (0.92), давал
  /// 0.52 / (0.92 − 0.447) = 1.10 высоты камеры — 66 см против стены в
  /// 2.5 м. Отсюда и ощущение гигантской комнаты: не стена велика, а мишка
  /// стоял вплотную к зрителю, где всё кажется мельче своего масштаба.
  ///
  /// На 0.74 то же тело даёт 0.52 / (0.74 − 0.447) = 1.78 высоты камеры,
  /// то есть 1.07 м: ростом с трёхлетку, как кот Томми в своей комнате.
  /// Сам мишка при этом не изменился — заказчик утвердил 52% 18.09, и
  /// трогать их не нужно: он просто отошёл от зрителя вглубь комнаты, на
  /// треть её глубины.
  static const double standLine = 0.74;

  @override
  Widget build(BuildContext context) {
    // Фон — картинка; нарисованные стены остались запасным вариантом на
    // случай, если ассет не загрузится.
    //
    // BoxFit.fill здесь ничего не растягивает: с 20.09 виджету отдают
    // прямоугольник ровно тех же пропорций, что и у картинки
    // ([RoomFrame]). Раньше кадр 4:5 растягивался под форму карточки, и
    // линия горизонта — та, по которой размечены все места, — зависела от
    // высоты экрана.
    return ClipRect(
      child: Image.asset(
        room.asset,
        fit: BoxFit.fill,
        errorBuilder: (context, _, _) =>
            CustomPaint(painter: _RoomPainter(const {})),
      ),
    );
  }
}

/// Угол комнаты: две стены, пол с глубиной, плинтус и окно на левой стене.
class _RoomPainter extends CustomPainter {
  _RoomPainter(this.placed);

  final Set<String> placed;

  (int, int) _surface(String prefix, String fallback) {
    for (final id in placed) {
      if (id.startsWith(prefix)) {
        final colors = roomSurfaces[id];
        if (colors != null) return colors;
      }
    }
    return roomSurfaces[fallback]!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wall = _surface('wall_', 'wall_rose');
    final floor = _surface('floor_', 'floor_wood');

    final horizon = RoomSceneBackdrop.horizon * size.height;
    final corner = RoomSceneBackdrop.cornerX * size.width;

    // Задняя стена — от угла вправо. Левая стена уходит к зрителю, поэтому
    // её нижняя граница опускается: пол у левого края ближе, чем у угла.
    final leftFloorY = size.height * 0.74;

    canvas.drawRect(
      Rect.fromLTWH(corner, 0, size.width - corner, horizon),
      Paint()..color = Color(wall.$1),
    );

    // Левая стена — трапеция: вверху уходит за кадр, внизу спускается к
    // переднему краю пола. Тон чуть темнее задней: свет падает из окна,
    // которое на ней же и прорезано, поэтому сама стена в полутени.
    final leftWall = Path()
      ..moveTo(0, 0)
      ..lineTo(corner, 0)
      ..lineTo(corner, horizon)
      ..lineTo(0, leftFloorY)
      ..close();
    canvas.drawPath(leftWall, Paint()..color = Color(wall.$2));

    // Пол: от линии горизонта вниз, с уходящим влево краем.
    final floorPath = Path()
      ..moveTo(0, leftFloorY)
      ..lineTo(corner, horizon)
      ..lineTo(size.width, horizon)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(floorPath, Paint()..color = Color(floor.$1));

    // Плинтус вдоль обеих стен — одна ломаная линия.
    final skirting = Paint()
      ..color = Color(floor.$2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawPath(
      Path()
        ..moveTo(0, leftFloorY)
        ..lineTo(corner, horizon)
        ..lineTo(size.width, horizon),
      skirting,
    );

    // Доски пола сходятся к точке схода — это и создаёт глубину. Точка
    // схода лежит за углом комнаты, на линии горизонта.
    final vanishing = Offset(corner + (size.width - corner) * 0.42, horizon);
    final boards = Paint()
      ..color = Color(floor.$2).withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    for (var i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, size.height), vanishing, boards);
    }
    // Поперечные линии: ближе к зрителю реже, у горизонта чаще.
    for (var i = 1; i <= 4; i++) {
      final t = i / 5;
      final y = horizon + (size.height - horizon) * t * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), boards);
    }

    _paintWindow(canvas, size, wall, horizon, corner, leftFloorY);
  }

  /// Окно на левой стене: рама, небо, переплёт, подоконник, занавеска.
  ///
  /// Окно именно слева и именно на боковой стене — так вся задняя стена
  /// остаётся свободной под картины, часы и полки, то есть под то, что
  /// продаётся (КП 10.3).
  void _paintWindow(
    Canvas canvas,
    Size size,
    (int, int) wall,
    double horizon,
    double corner,
    double leftFloorY,
  ) {
    // Окно вписано в трапецию левой стены: у угла оно выше, у края ниже —
    // ровный прямоугольник на наклонной стене читался бы как наклейка.
    final top = size.height * 0.16;
    final bottom = size.height * 0.50;
    final near = corner * 0.10;
    final far = corner * 0.86;

    double slope(double x, double y) =>
        y + (leftFloorY - horizon) * (1 - x / corner) * 0.30;

    final glass = Path()
      ..moveTo(near, slope(near, top))
      ..lineTo(far, slope(far, top))
      ..lineTo(far, slope(far, bottom))
      ..lineTo(near, slope(near, bottom))
      ..close();

    canvas.drawPath(
      glass,
      Paint()
        ..color = Color(wall.$1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03,
    );
    canvas.drawPath(glass, Paint()..color = const Color(0xFFCFE6EF));

    // Облако-намёк.
    canvas.save();
    canvas.clipPath(glass);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset((near + far) / 2, slope((near + far) / 2, top) + 40),
        width: (far - near) * 0.6,
        height: (bottom - top) * 0.18,
      ),
      Paint()..color = const Color(0xFFF3FAFD),
    );
    canvas.restore();

    // Переплёт: одна вертикаль и одна горизонталь, тоже по наклону стены.
    final mullion = Paint()
      ..color = Color(wall.$1)
      ..strokeWidth = 3;
    final midX = (near + far) / 2;
    canvas.drawLine(
      Offset(midX, slope(midX, top)),
      Offset(midX, slope(midX, bottom)),
      mullion,
    );
    final midY = (top + bottom) / 2;
    canvas.drawLine(
      Offset(near, slope(near, midY)),
      Offset(far, slope(far, midY)),
      mullion,
    );

    // Занавеска у дальнего края окна — она же прикрывает стык со стеной.
    final curtain = Path()
      ..moveTo(far, slope(far, top) - size.height * 0.02)
      ..quadraticBezierTo(
        far + size.width * 0.04,
        slope(far, (top + bottom) / 2),
        far + size.width * 0.01,
        slope(far, bottom) + size.height * 0.03,
      )
      ..lineTo(far + size.width * 0.06, slope(far, bottom) + size.height * 0.03)
      ..quadraticBezierTo(
        far + size.width * 0.06,
        slope(far, (top + bottom) / 2.2),
        far + size.width * 0.045,
        slope(far, top) - size.height * 0.02,
      )
      ..close();
    canvas.drawPath(curtain, Paint()..color = const Color(0xFFF2CFC4));
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.placed != placed;
}
