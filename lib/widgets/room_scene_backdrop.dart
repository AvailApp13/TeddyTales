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

import '../game/room_camera.dart';
import '../game/room_kind.dart';
import '../game/room_layout.dart';

/// Где на экране лежит кадр комнаты и всё, что к нему привязано.
///
/// Появился, когда комната поехала на весь экран телефона (задача заказчика
/// 20.09). До этого сцена была карточкой примерно той же формы, что и кадр
/// фона, и доли кадра совпадали с долями сцены. На телефоне они не совпадают,
/// и все числа — линия пола, точка схода, рост мишки — остались долями
/// **кадра**, а не экрана. Иначе мишка менял бы размер от модели телефона.
///
/// Как кадр ложится на экран, зависит от того, нарисован ли на нём потолок
/// ([RoomCamera.hasCeiling]).
class RoomFrame {
  const RoomFrame._(this.scene, this.rect, this.camera);

  /// Вся сцена — весь экран.
  final Size scene;

  /// Кадр комнаты внутри неё.
  final Rect rect;

  /// Чем снята эта комната.
  final RoomCamera camera;

  factory RoomFrame.of(Size scene, RoomKind room) {
    final camera = cameraOf(room);

    if (camera.hasCeiling) {
      // Потолок нарисован — кадр закрывает экран целиком, лишнее уходит за
      // края. Прижат к низу: срезать можно потолок, но не пол, иначе мишка
      // встанет ниже края экрана.
      final scale = math.max(
        scene.width / camera.artWidth,
        scene.height / camera.artHeight,
      );
      final size = Size(camera.artWidth * scale, camera.artHeight * scale);
      return RoomFrame._(
        scene,
        Rect.fromLTWH(
          (scene.width - size.width) / 2,
          scene.height - size.height,
          size.width,
          size.height,
        ),
        camera,
      );
    }

    // Потолка на картинке нет: кадр вписывается по ширине и прижимается к
    // низу, а полосу сверху занимает нарисованный потолок.
    final height = scene.width * camera.artHeight / camera.artWidth;
    return RoomFrame._(
      scene,
      Rect.fromLTWH(0, scene.height - height, scene.width, height),
      camera,
    );
  }

  /// Полоса под нарисованный потолок. Ноль, если он есть на самой картинке.
  double get ceilingHeight => math.max(0, rect.top);

  /// Точка схода в координатах сцены: по ней сходятся и линии пола на
  /// картинке, и стыки нарисованного потолка.
  double get vanishingY => rect.top + camera.eyeLine * rect.height;

  /// Линия пола, на которой стоит мишка.
  double get standY => rect.top + camera.standLine * rect.height;

  /// Рост мишки в пикселях.
  ///
  /// Считается от высоты **экрана**, а не кадра: кадры у комнат разной
  /// формы, и одна и та же доля кадра давала на экране разный размер —
  /// заказчик замечал это при каждом переключении.
  double get bearHeight => scene.height * bearScreenHeight;

  /// Какую долю кадра он при этом занимает. Нужно, чтобы посчитать, каким
  /// ростом он читается в метрах.
  double get bearFrameFraction => bearHeight / rect.height;

  /// Верх мишки.
  double get bearTop => standY - bearHeight;

  /// Полосы, в которых мишку видно, сверху вниз.
  ///
  /// Обычно одна — он весь на виду. В комнате с мебелью переднего плана их
  /// две: над мебелью и в просвете под ней. Мебель нарисована на самом
  /// фоне, то есть лежит под мишкой, и без этих полос его ноги оказались
  /// бы поверх столешницы, а сам он выглядел бы приклеенным к столу.
  List<({double top, double bottom})> get bearSlices {
    // Мишка нарисован на самой картинке — живого поверх неё не надо.
    if (camera.bearInArt) return const [];

    final front = camera.frontLine;
    if (front == null) return [(top: bearTop, bottom: standY)];

    final frontTop = rect.top + front * rect.height;
    final slices = <({double top, double bottom})>[];

    if (frontTop > bearTop) {
      slices.add((top: bearTop, bottom: math.min(frontTop, standY)));
    }

    final bottom = camera.frontBottom;
    if (bottom != null) {
      final frontBottom = rect.top + bottom * rect.height;
      if (standY > frontBottom) {
        slices.add((top: math.max(frontBottom, bearTop), bottom: standY));
      }
    }
    return slices;
  }

  /// Куда смотрит камера по горизонтали.
  double get centerX => rect.center.dx;

  /// Вертикаль, на которой стоит мишка.
  ///
  /// Не по центру: заказчик просил сдвинуть примерно на 10% правее, со
  /// стороны зрителя.
  double get bearCenterX => rect.left + rect.width * (0.5 + camera.bearOffsetX);

  /// Сдвиг мишки вправо от центра, в долях ширины.
  static const double bearOffsetX = 0.10;
}

class RoomSceneBackdrop extends StatelessWidget {
  const RoomSceneBackdrop({super.key, this.room = RoomKind.nursery});

  /// Какая комната показана.
  final RoomKind room;

  /// Рост мишки в долях высоты сцены — модуль, в котором меряются места.
  static const double defaultBearModule = 0.45;

  /// Вертикаль угла между левой и задней стеной, доля ширины.
  ///
  /// Нужна только запасному рисованному фону: у настоящих картинок угол свой.
  static const double cornerX = 0.27;

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
/// Стык стены с полом у запасного рисованного фона.
const double _fallbackHorizon = 0.564;

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

    final horizon = _fallbackHorizon * size.height;
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
