import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/room_kind.dart';

/// Потолок над комнатой.
///
/// Кадр фона нарисован 4:5, экран телефона примерно вдвое выше своей ширины.
/// Если вписывать комнату по ширине — а иначе не сохранить соотношение мишки
/// к комнате, — сверху остаётся полоса почти в половину экрана. Её и занимает
/// потолок.
///
/// Рисуется кодом намеренно. Заказчик просил потолок раньше, чем появится
/// арт, и код даёт то, чего не даст картинка: потолок сходится ровно в ту же
/// точку схода, что и пол на фотографии комнаты, при любой высоте экрана.
/// Когда потолки нарисуют, этот слой заменится картинкой — разметка мест и
/// мишка не сдвинутся, они привязаны к кадру комнаты, а не к потолку.
class RoomCeiling extends StatelessWidget {
  const RoomCeiling({
    super.key,
    required this.room,
    required this.vanishingY,
    required this.centerX,
  });

  final RoomKind room;

  /// Где лежит точка схода, в пикселях от верха этого слоя. Значение
  /// отрицательным не бывает: точка схода всегда ниже потолка.
  final double vanishingY;

  /// Горизонталь точки схода, в пикселях.
  final double centerX;

  /// Цвет, которым фон комнаты обрывается по верхнему краю.
  ///
  /// Снято с самих картинок (усреднение по верхним шести строкам): потолок
  /// должен встретиться с ними без шва, иначе на стыке появится ступенька.
  static const Map<RoomKind, Color> _edge = {
    RoomKind.nursery: Color(0xFFE9CCBA),
    RoomKind.kitchen: Color(0xFFE5DABD),
    RoomKind.bath: Color(0xFFC1D2D9),
  };

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CeilingPainter(
        edge: _edge[room]!,
        vanishingY: vanishingY,
        centerX: centerX,
      ),
      size: Size.infinite,
    );
  }
}

class _CeilingPainter extends CustomPainter {
  _CeilingPainter({
    required this.edge,
    required this.vanishingY,
    required this.centerX,
  });

  final Color edge;
  final double vanishingY;
  final double centerX;

  /// Насколько потолок светлее стыка у дальней стены.
  ///
  /// Светлее именно вверху: верх кадра — это потолок над головой зрителя,
  /// он ближе к окну и к лампе. Ровная заливка читалась бы как лист бумаги.
  static Color _lighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFDF8), t)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(edge, 0.55), _lighten(edge, 0.22), edge],
          stops: const [0, 0.62, 1],
        ).createShader(rect),
    );

    // Стыки плит сходятся в ту же точку, что и доски пола на фоне. Именно
    // это и создаёт ощущение, что потолок принадлежит той же комнате, а не
    // подложен сверху.
    final vanishing = Offset(centerX, vanishingY);
    final lines = Paint()
      ..color = edge.withValues(alpha: 0.45)
      ..strokeWidth = 1
      ..isAntiAlias = true;

    for (var i = 0; i <= 7; i++) {
      final x = size.width * i / 7;
      canvas.drawLine(Offset(x, 0), vanishing, lines);
    }

    _paintLamp(canvas, size);
  }

  /// Лампа под потолком.
  ///
  /// Висит не по центру кадра, а по центру комнаты — то есть на той же
  /// вертикали, что и точка схода. Иначе шнур уходил бы в потолок под углом
  /// к его собственным стыкам.
  void _paintLamp(Canvas canvas, Size size) {
    final cordEnd = size.height * 0.62;
    if (cordEnd <= 0) return;

    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, cordEnd),
      Paint()
        ..color = edge.withValues(alpha: 0.75)
        ..strokeWidth = 1.6,
    );

    final shadeWidth = math.min(size.width * 0.22, 108.0);
    final shade = Rect.fromCenter(
      center: Offset(centerX, cordEnd + shadeWidth * 0.22),
      width: shadeWidth,
      height: shadeWidth * 0.52,
    );

    // Свет от лампы — мягкое пятно вокруг плафона. Рисуется до самого
    // плафона, иначе перекроет его.
    canvas.drawCircle(
      shade.center,
      shadeWidth * 0.95,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF0CC).withValues(alpha: 0.55),
            const Color(0xFFFFF0CC).withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: shade.center, radius: shadeWidth * 0.95),
        ),
    );

    canvas.drawPath(
      Path()
        ..moveTo(shade.left, shade.center.dy)
        ..quadraticBezierTo(
          shade.left + shade.width * 0.08,
          shade.top,
          shade.center.dx,
          shade.top,
        )
        ..quadraticBezierTo(
          shade.right - shade.width * 0.08,
          shade.top,
          shade.right,
          shade.center.dy,
        )
        ..quadraticBezierTo(
          shade.right,
          shade.bottom,
          shade.center.dx,
          shade.bottom,
        )
        ..quadraticBezierTo(
          shade.left,
          shade.bottom,
          shade.left,
          shade.center.dy,
        )
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(edge, 0.92), _lighten(edge, 0.45)],
        ).createShader(shade),
    );
  }

  @override
  bool shouldRepaint(_CeilingPainter old) =>
      old.edge != edge ||
      old.vanishingY != vanishingY ||
      old.centerX != centerX;
}
