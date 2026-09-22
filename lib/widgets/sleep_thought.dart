import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bedroom_scene.dart';

/// Облако мыслей над головой уснувшего мишки: слева над капюшоном.
///
/// Заказчик 22.09: «над головой слева должно открываться облачко…
/// поэтапно: раз, два — маленькое, и большое уже три». Что будет внутри
/// большого — отдельное решение заказчика; пока облако пустое.
///
/// Вырастает в три шага, как в комиксах: пузырёк у головы, пузырёк
/// побольше, потом само облако. Каждый шаг чуть перелетает размер и
/// садится назад — так оно «всплывает», а не включается.
class SleepThought extends StatefulWidget {
  const SleepThought({super.key, required this.shown});

  /// Показывать ли: облако появляется, когда мишку уложили, и уходит,
  /// когда он проснулся.
  final bool shown;

  /// Сколько длится появление целиком, и когда стартует каждый шаг —
  /// в долях этого времени.
  static const Duration grow = Duration(milliseconds: 1500);
  static const List<double> starts = [0.0, 0.28, 0.52];

  @override
  State<SleepThought> createState() => _SleepThoughtState();
}

class _SleepThoughtState extends State<SleepThought>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: SleepThought.grow,
    reverseDuration: const Duration(milliseconds: 450),
  );

  @override
  void initState() {
    super.initState();
    if (widget.shown) _grow.value = 1;
  }

  /// Облако ждёт, пока мишка уснёт: появиться раньше закрытых глаз —
  /// значит показать сон бодрствующему.
  Timer? _wait;

  @override
  void didUpdateWidget(SleepThought old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) return;
    _wait?.cancel();
    if (widget.shown) {
      _wait = Timer(BedroomScene.fallAsleep, () {
        if (mounted && widget.shown) _grow.forward();
      });
    } else {
      _grow.reverse();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _grow.dispose();
    super.dispose();
  }

  /// Насколько вырос шаг [index]: 0 — его ещё нет, 1 — на месте.
  /// С перелётом: `easeOutBack` уходит выше единицы и возвращается.
  double _step(int index) {
    final start = SleepThought.starts[index];
    final span = index == 2 ? 0.48 : 0.30;
    final t = ((_grow.value - start) / span).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final bear = BedroomScene.bear;

          // Всё привязано к рамке мишки, а не к кадру: сдвинется мишка —
          // облако уйдёт за ним.
          final one = Offset(
            (bear.left + 0.30 * bear.width) * w,
            (bear.top + 0.06 * bear.height) * h,
          );
          final two = Offset(
            (bear.left + 0.13 * bear.width) * w,
            (bear.top - 0.17 * bear.height) * h,
          );
          final cloud = Rect.fromLTWH(
            (bear.left - 0.86 * bear.width) * w,
            (bear.top - 0.95 * bear.height) * h,
            0.96 * bear.width * w,
            0.64 * bear.height * h,
          );

          return AnimatedBuilder(
            animation: _grow,
            builder: (context, _) {
              if (_grow.value == 0) return const SizedBox.shrink();
              return CustomPaint(
                size: Size(w, h),
                painter: _ThoughtPainter(
                  one: one,
                  oneRadius: 0.045 * bear.width * w,
                  two: two,
                  twoRadius: 0.075 * bear.width * w,
                  cloud: cloud,
                  steps: [_step(0), _step(1), _step(2)],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Два пузырька и облако — одним цветом с капсулами приложения, с тенью
/// на стену, чтобы не висеть плоской наклейкой.
class _ThoughtPainter extends CustomPainter {
  const _ThoughtPainter({
    required this.one,
    required this.oneRadius,
    required this.two,
    required this.twoRadius,
    required this.cloud,
    required this.steps,
  });

  final Offset one;
  final double oneRadius;
  final Offset two;
  final double twoRadius;
  final Rect cloud;
  final List<double> steps;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = AppColors.surface;
    final rim = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    void bubble(Offset center, double radius, double grown) {
      if (grown <= 0) return;
      final path = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius * grown));
      canvas.drawShadow(path, const Color(0xFF203040), 6, true);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, rim);
    }

    bubble(one, oneRadius, steps[0]);
    bubble(two, twoRadius, steps[1]);

    final grown = steps[2];
    if (grown <= 0) return;

    // Облако растёт из своего нижнего правого угла — оттуда, где пузырьки.
    final anchor = cloud.bottomRight;
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(grown);
    canvas.translate(-anchor.dx, -anchor.dy);

    final path = _cloudPath(cloud);
    canvas.drawShadow(path, const Color(0xFF203040), 8, true);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, rim);
    canvas.restore();
  }

  /// Облако — овал с горбами по верху и по низу. Горбы разного размера:
  /// одинаковые читаются как шестерёнка.
  static Path _cloudPath(Rect r) {
    var path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + r.width * 0.06, r.top + r.height * 0.28,
            r.width * 0.88, r.height * 0.52),
        Radius.circular(r.height * 0.26),
      ));
    const bumps = [
      // Центр (в долях облака) и радиус (в долях высоты).
      (0.22, 0.30, 0.30),
      (0.45, 0.20, 0.36),
      (0.70, 0.27, 0.32),
      (0.88, 0.45, 0.24),
      (0.12, 0.55, 0.26),
      (0.30, 0.76, 0.24),
      (0.58, 0.80, 0.26),
      (0.82, 0.72, 0.22),
    ];
    for (final (cx, cy, radius) in bumps) {
      final bump = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(r.left + r.width * cx, r.top + r.height * cy),
          radius: r.height * radius,
        ));
      path = Path.combine(PathOperation.union, path, bump);
    }
    return path;
  }

  @override
  bool shouldRepaint(_ThoughtPainter old) =>
      old.steps[0] != steps[0] ||
      old.steps[1] != steps[1] ||
      old.steps[2] != steps[2] ||
      old.cloud != cloud;
}
