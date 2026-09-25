import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'bedroom_scene.dart';
import 'scene_label.dart';

/// Обратный отсчёт засыпания (заказчик 25.09): после «Уложить спать» на
/// одеяле — кружок в стиле колец ухода наверху, в нём секунды до того, как
/// мишка закроет глаза и появятся «zzz» и облако сна. Иначе кажется, что
/// ничего не происходит, и «Уложить спать» жмут ещё раз.
///
/// Уложили уже спящего (зашли, а мишка спит с прошлого раза) — отсчёта нет.
class SleepCountdown extends StatefulWidget {
  const SleepCountdown({super.key, required this.shown});

  /// Мишку уложили. Стало `true` — отсчёт с начала.
  final bool shown;

  /// Где кружок в кадре спальни: на одеяле под мишкой, на складке пледа.
  static const Offset spot = Offset(0.5, 0.63);

  static const double size = 58;

  @override
  State<SleepCountdown> createState() => _SleepCountdownState();
}

class _SleepCountdownState extends State<SleepCountdown>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: BedroomScene.fallAsleep,
  )..addStatusListener(_onStatus);

  /// Появление и уход кружка.
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(SleepCountdown old) {
    super.didUpdateWidget(old);
    if (widget.shown == old.shown) return;
    if (widget.shown) {
      _count.forward(from: 0);
      _show.forward(from: 0);
    } else {
      _count.stop();
      _show.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    // Мишка уснул: кружок уступает место «zzz» и облаку.
    if (status == AnimationStatus.completed) _show.reverse();
  }

  @override
  void dispose() {
    _count.dispose();
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return AnimatedBuilder(
            animation: Listenable.merge([_count, _show]),
            builder: (context, _) {
              final show = _show.value;
              if (show <= 0) return const SizedBox.shrink();
              final total = BedroomScene.fallAsleep.inMilliseconds / 1000;
              final left = (1 - _count.value) * total;
              final seconds = math.max(1, left.ceil());
              // Каждая новая секунда чуть «вздрагивает».
              final tick = left - left.floor();
              final pulse = _count.isAnimating
                  ? 1 + 0.12 * Curves.easeOut.transform(tick)
                  : 1.0;
              return Stack(
                children: [
                  Positioned(
                    left:
                        size.width * SleepCountdown.spot.dx -
                        SleepCountdown.size,
                    top:
                        size.height * SleepCountdown.spot.dy -
                        SleepCountdown.size / 2,
                    width: SleepCountdown.size * 2,
                    child: Opacity(
                      opacity: show,
                      child: Transform.scale(
                        scale: 0.7 + 0.3 * Curves.easeOutBack.transform(show),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              key: const ValueKey('sleep-countdown'),
                              width: SleepCountdown.size,
                              height: SleepCountdown.size,
                              child: CustomPaint(
                                painter: _CountdownRing(1 - _count.value),
                                child: Center(
                                  child: Container(
                                    width: SleepCountdown.size - 13,
                                    height: SleepCountdown.size - 13,
                                    decoration: const BoxDecoration(
                                      color: AppColors.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Transform.scale(
                                      scale: pulse,
                                      child: Text(
                                        '$seconds',
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SceneLabel(
                              text: context.l10n.sleepCountdownLabel,
                              size: 12,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Цифра — тем же лиловым, что кольцо сна, только гуще.
const _ink = Color(0xFF7D76B4);

/// Кольцо как у показателей ухода, цвет сна; убывает к нулю.
class _CountdownRing extends CustomPainter {
  _CountdownRing(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.11;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.surface.withValues(alpha: 0.85),
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = AppColors.statSleep,
    );
  }

  @override
  bool shouldRepaint(_CountdownRing old) => old.value != value;
}
