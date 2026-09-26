import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Ночное окно спальни: луна и звёзды мерцают, по небу пролетают звёзды.
///
/// Заказчик 22.09: «луна и звёзды — чтобы свет чуть ярче, чуть тусклее;
/// и раз в две секунды пролетала звезда именно в этом окне». Частота —
/// его решение: человек в спальне недолго, и звезду он должен застать.
///
/// Всё рисуется кодом поверх картинки комнаты, без новых файлов: ореол
/// луны и точки звёзд — мягкие пятна, чья прозрачность ходит по синусу;
/// падающая звезда — штрих со шлейфом. Небо обрезано рамкой створки,
/// чтобы ничего не вылетало на стену. На кадр это одна-две операции
/// рисования: дешевле дыхания одеяла.
class NightWindow extends StatefulWidget {
  const NightWindow({super.key});

  /// Верхняя створка окна — небо. В долях кадра комнаты 941 × 1672,
  /// снято по картинке.
  static const Rect sky = Rect.fromLTWH(0.0234, 0.2004, 0.0829, 0.1226);

  /// Где луна и её видимый радиус — в долях ширины кадра.
  static const Offset moon = Offset(0.0638, 0.2721);
  static const double moonRadius = 0.032;

  /// Звёзды, нарисованные на картинке: их и подсвечиваем.
  static const List<Offset> stars = [
    Offset(0.0372, 0.2273),
    Offset(0.0871, 0.2363),
    Offset(0.0319, 0.3050),
    Offset(0.0903, 0.3110),
    Offset(0.0372, 0.3499),
    Offset(0.0659, 0.3529),
  ];

  /// Пауза между пролётами: от [shotEvery] до него же плюс [shotSpread].
  static const double shotEvery = 1.4;
  static const double shotSpread = 1.2;

  /// Сколько летит одна звезда.
  static const double shotFlight = 0.65;

  @override
  State<NightWindow> createState() => _NightWindowState();
}

/// Одна падающая звезда: откуда, куда и когда родилась. Всё в долях
/// створки, чтобы не зависеть от размера экрана.
class _Shot {
  const _Shot({required this.from, required this.dir, required this.born});

  final Offset from;
  final Offset dir;
  final double born;
}

class _NightWindowState extends State<NightWindow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Секунды с запуска — единственные часы всего окна.
  final ValueNotifier<double> _time = ValueNotifier(0);
  final List<_Shot> _shots = [];
  final math.Random _dice = math.Random();
  double _nextShot = 1.2;
  bool? _stillSetting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _ticker.stop();
      _shots.clear();
      _time.value = 0;
    } else {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t >= _nextShot) {
      _spawn(t);
      // Иногда две подряд: вторая чуть позже и из другого места.
      if (_dice.nextInt(3) == 0) _spawn(t + 0.22 + _dice.nextDouble() * 0.2);
      _nextShot =
          t +
          NightWindow.shotEvery +
          _dice.nextDouble() * NightWindow.shotSpread;
    }
    _shots.removeWhere((s) => t - s.born > NightWindow.shotFlight);
    _time.value = t;
  }

  void _spawn(double born) {
    // Старт в верхней части неба, полёт вниз и вбок; чаще направо —
    // так летят «настоящие», но не все, иначе это конвейер.
    final right = _dice.nextInt(4) != 0;
    _shots.add(
      _Shot(
        from: Offset(
          right
              ? 0.05 + _dice.nextDouble() * 0.45
              : 0.5 + _dice.nextDouble() * 0.45,
          0.04 + _dice.nextDouble() * 0.5,
        ),
        dir: Offset(right ? 1 : -1, 0.45 + _dice.nextDouble() * 0.3),
        born: born,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _NightPainter(time: _time, shots: _shots),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NightPainter extends CustomPainter {
  _NightPainter({required this.time, required this.shots})
    : super(repaint: time);

  final ValueNotifier<double> time;
  final List<_Shot> shots;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width;
    final h = size.height;
    final sky = Rect.fromLTWH(
      NightWindow.sky.left * w,
      NightWindow.sky.top * h,
      NightWindow.sky.width * w,
      NightWindow.sky.height * h,
    );

    canvas.save();
    canvas.clipRect(sky);

    // Луна: ореол дышит медленно, как ночник, но в своём темпе.
    final moonWave = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 4.6);
    _glow(
      canvas,
      Offset(NightWindow.moon.dx * w, NightWindow.moon.dy * h),
      NightWindow.moonRadius * w * 1.9,
      0.10 + 0.16 * moonWave,
    );

    // Звёзды: у каждой свой период и фаза, чтобы не мигали хором.
    for (var i = 0; i < NightWindow.stars.length; i++) {
      final star = NightWindow.stars[i];
      final period = 1.7 + 0.5 * i;
      final wave = 0.5 + 0.5 * math.sin(t * 2 * math.pi / period + i * 1.9);
      _glow(
        canvas,
        Offset(star.dx * w, star.dy * h),
        0.011 * w,
        0.15 + 0.55 * wave,
      );
    }

    // Падающие звёзды: штрих со шлейфом, ярче всего на середине пути.
    for (final shot in shots) {
      final p = ((t - shot.born) / NightWindow.shotFlight).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final travel = sky.width * 0.62;
      final dir = shot.dir / shot.dir.distance;
      final head =
          Offset(
            sky.left + shot.from.dx * sky.width,
            sky.top + shot.from.dy * sky.height,
          ) +
          dir * (travel * Curves.easeOut.transform(p));
      final bright = math.sin(p * math.pi);
      final tail = head - dir * (travel * 0.30 * bright);
      final paint = Paint()
        ..strokeWidth = 0.0032 * w
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.95 * bright),
          ],
        ).createShader(Rect.fromPoints(tail, head));
      canvas.drawLine(tail, head, paint);
      canvas.drawCircle(
        head,
        0.0038 * w,
        Paint()..color = Colors.white.withValues(alpha: bright),
      );
    }

    canvas.restore();
  }

  /// Мягкое пятно света: белое в центре, ничего по краю.
  void _glow(Canvas canvas, Offset center, double radius, double alpha) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_NightPainter old) => true;
}
