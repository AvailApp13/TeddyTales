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

import 'package:flutter/material.dart';

import '../game/room_layout.dart';
import '../game/shop_items.dart';

class RoomSceneBackdrop extends StatelessWidget {
  const RoomSceneBackdrop({
    super.key,
    required this.placed,
    this.bearModule = defaultBearModule,
  });

  /// Какие предметы размещены (ids из каталога, включая обои и пол).
  final Set<String> placed;

  /// Рост мишки в долях высоты сцены. Модуль всей размерной сетки: предмет
  /// в 1.0 модуля равен герою, стоящему на переднем плане.
  final double bearModule;

  static const double defaultBearModule = 0.45;

  /// Линия горизонта: где задняя стена встречается с полом.
  static const double horizon = 0.58;

  /// Вертикаль угла между левой и задней стеной, доля ширины.
  static const double cornerX = 0.26;

  /// Линия пола переднего плана — на ней стоит герой.
  static double get floorLine => RoomPlane.near.floorLine;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // Дальний план рисуется первым, передний последним: иначе шкаф у
        // стены закрыл бы мячик, лежащий у ног зрителя.
        final items =
            [
              for (final p in roomLayout)
                if (placed.contains(p.id)) p,
            ]..sort((a, b) {
              final byPlane = a.plane.index.compareTo(b.plane.index);
              return byPlane != 0 ? byPlane : a.z.compareTo(b.z);
            });

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _RoomPainter(placed)),
              ),
              for (final p in items)
                Positioned(
                  left: p.fx * width - p.w * bearModule * p.scale * height / 2,
                  top: p.onWall
                      ? p.wallFy! * height -
                            p.h * bearModule * p.scale * height / 2
                      : p.plane.floorLine * height -
                            p.h * bearModule * p.scale * height,
                  width: p.w * bearModule * p.scale * height,
                  height: p.h * bearModule * p.scale * height,
                  child: _ItemGhost(
                    id: p.id,
                    heightPx: p.h * bearModule * p.scale * height,
                    // Напольные предметы прижаты к низу габарита, настенные —
                    // по центру: так торшер не «плавает» в середине рамки.
                    alignment: p.onWall
                        ? Alignment.center
                        : Alignment.bottomCenter,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Эмодзи-заглушка предмета, растянутая до габарита из размерной сетки.
class _ItemGhost extends StatelessWidget {
  const _ItemGhost({
    required this.id,
    required this.heightPx,
    required this.alignment,
  });

  final String id;
  final double heightPx;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // Ковёр — не эмодзи, а мягкий эллипс: он лежит под мишкой и должен
    // читаться пятном, как в макете.
    if (id == 'rug') {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEFC9BC),
          borderRadius: BorderRadius.all(
            Radius.elliptical(heightPx * 4, heightPx),
          ),
        ),
      );
    }

    // Эмодзи — из каталога: у предмета один источник картинки-заглушки.
    return FittedBox(
      fit: BoxFit.contain,
      alignment: alignment,
      child: Text(
        ItemCatalog.byId(id).emoji,
        style: const TextStyle(fontSize: 100),
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
