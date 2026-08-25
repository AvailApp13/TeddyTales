/// Фон комнаты: стены, пол, окно и расставленные предметы каталога.
///
/// Это габаритная сборка («блокаут») для утверждения размерного ряда:
/// каждый размещённый предмет рисуется эмодзи-заглушкой ровно того размера,
/// который задан в `room_layout.dart`, в модулях роста мишки. Дизайнер
/// интерьера смотрит на эту сцену и на `docs/interior-size-guide.md` и
/// отрисовывает предметы в тех же габаритах — тогда готовый арт встанет
/// на место заглушек без переразметки.
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

  /// Рост мишки в долях высоты сцены. Модуль всей размерной сетки.
  /// Персонаж на главном экране вписывается в этот же модуль — сцена
  /// показывает честный размерный ряд каталога относительно героя.
  final double bearModule;

  static const double defaultBearModule = 0.22;

  /// Линия пола: доля высоты сцены, на которой стоят мишка и мебель.
  static const double floorLine = 0.82;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final module = height * bearModule;

        final items = [
          for (final p in roomLayout)
            if (placed.contains(p.id)) p,
        ]..sort((a, b) => a.z.compareTo(b.z));

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _RoomPainter(placed)),
              ),
              for (final p in items)
                Positioned(
                  left: p.fx * width - p.w * module / 2,
                  top: p.onWall
                      ? p.wallFy! * height - p.h * module / 2
                      : floorLine * height - p.h * module,
                  width: p.w * module,
                  height: p.h * module,
                  child: _ItemGhost(
                    id: p.id,
                    heightPx: p.h * module,
                    // Напольные предметы прижаты к низу габарита, настенные —
                    // по центру: так торшер не «плавает» в середине своей рамки.
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

/// Стены, пол, плинтус, окно с небом и занавеской.
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
    final floorTop = RoomSceneBackdrop.floorLine * size.height;

    // Стена и пол.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, floorTop),
      Paint()..color = Color(wall.$1),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, floorTop, size.width, size.height - floorTop),
      Paint()..color = Color(floor.$1),
    );
    // Плинтус и доски.
    canvas.drawRect(
      Rect.fromLTWH(0, floorTop, size.width, 3),
      Paint()..color = Color(floor.$2),
    );
    final boards = Paint()
      ..color = Color(floor.$2).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = floorTop + (size.height - floorTop) * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), boards);
    }

    // Окно слева: рама, небо, переплёт, подоконник. Габариты — в модулях
    // размерной сетки, подоконник примерно на уровне плеч героя.
    final module = size.height * RoomSceneBackdrop.defaultBearModule;
    final window = Rect.fromLTWH(
      size.width * 0.06,
      floorTop - module * 2.6,
      size.width * 0.26,
      module * 1.9,
    );
    final frame = RRect.fromRectAndRadius(
      window.inflate(size.width * 0.012),
      const Radius.circular(10),
    );
    canvas.drawRRect(frame, Paint()..color = Color(wall.$2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, const Radius.circular(6)),
      Paint()..color = const Color(0xFFCFE6EF),
    );
    // Облако-намёк.
    canvas.drawOval(
      Rect.fromCenter(
        center: window.center.translate(-window.width * 0.15, -window.height * 0.2),
        width: window.width * 0.5,
        height: window.height * 0.16,
      ),
      Paint()..color = const Color(0xFFF3FAFD),
    );
    final mullion = Paint()
      ..color = Color(wall.$2)
      ..strokeWidth = 3;
    canvas.drawLine(window.topCenter, window.bottomCenter, mullion);
    canvas.drawLine(window.centerLeft, window.centerRight, mullion);
    canvas.drawRect(
      Rect.fromLTWH(
        window.left - size.width * 0.02,
        window.bottom + size.width * 0.012,
        window.width + size.width * 0.04,
        6,
      ),
      Paint()..color = Color(wall.$2),
    );

    // Занавеска: привязана к окну, свисает от верха рамы чуть ниже подоконника.
    final cTop = window.top - size.width * 0.03;
    final cBottom = window.bottom + size.width * 0.04;
    final curtain = Path()
      ..moveTo(window.right - size.width * 0.005, cTop)
      ..quadraticBezierTo(
        window.right + size.width * 0.05,
        (cTop + cBottom) / 2,
        window.right + size.width * 0.015,
        cBottom,
      )
      ..lineTo(window.right + size.width * 0.075, cBottom)
      ..quadraticBezierTo(
        window.right + size.width * 0.075,
        (cTop + cBottom) / 2.2,
        window.right + size.width * 0.055,
        cTop,
      )
      ..close();
    canvas.drawPath(curtain, Paint()..color = const Color(0xFFF2CFC4));
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.placed != placed;
}
