import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../game/room_kind.dart';
import '../theme/app_colors.dart';
import 'bedroom_scene.dart';

/// Облако мыслей над головой уснувшего мишки: слева над капюшоном.
///
/// Заказчик 22.09: «над головой слева должно открываться облачко…
/// поэтапно: раз, два — маленькое, и большое уже три». В большом — сон:
/// короткий видеоряд по кругу, «типа его снов».
///
/// Вырастает в три шага, как в комиксах: пузырёк у головы, пузырёк
/// побольше, потом само облако. Медленно и без пружины — это уже сон.
/// Внутри облака, обрезанный его контуром, крутится ролик; он появляется
/// вместе с облаком и растёт с ним.
class SleepThought extends StatefulWidget {
  const SleepThought({
    super.key,
    required this.shown,
    this.dream = 'assets/rooms/bedroom/dreams/dream1.mp4',
  });

  /// Показывать ли: облако появляется, когда мишку уложили, и уходит,
  /// когда он проснулся.
  final bool shown;

  /// Ролик сна. Требования к нему — `docs/living-scene.md`, раздел 6.
  final String dream;

  /// Сколько длится появление целиком, и когда стартует каждый шаг —
  /// в долях этого времени. Медленно: это уже сон, и заказчик 22.09
  /// просил «плавнее и мягче, а то оно прям выскакивает».
  static const Duration grow = Duration(milliseconds: 3800);
  static const List<double> starts = [0.0, 0.26, 0.50];

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

  /// Ролик готовится заранее: к моменту, когда облако выросло, он должен
  /// уже идти, а не догружаться в пустом облаке.
  late final VideoPlayerController _dream =
      VideoPlayerController.asset(widget.dream);
  bool _dreamReady = false;

  /// Облако ждёт, пока мишка уснёт: появиться раньше закрытых глаз —
  /// значит показать сон бодрствующему.
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.shown) _grow.value = 1;
    _grow.addStatusListener(_onGrow);
    _dream.setLooping(true);
    _dream.setVolume(0);
    _dream.initialize().then((_) {
      if (!mounted) return;
      setState(() => _dreamReady = true);
      if (_grow.value > 0) _dream.play();
    }).catchError((Object _) {
      // Без ролика облако остаётся пустым — как было до него.
    });
  }

  /// Ролик идёт, пока облако видно, и стоит, пока его нет.
  void _onGrow(AnimationStatus status) {
    if (!_dreamReady) return;
    if (status == AnimationStatus.dismissed) {
      _dream.pause();
    } else if (!_dream.value.isPlaying) {
      _dream.play();
    }
  }

  @override
  void didUpdateWidget(SleepThought old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) return;
    _wait?.cancel();
    if (widget.shown) {
      _wait = Timer(BedroomScene.fallAsleep, () {
        if (!mounted || !widget.shown) return;
        if (_dreamReady) _dream.play();
        _grow.forward();
      });
    } else {
      _grow.reverse();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _grow.removeStatusListener(_onGrow);
    _grow.dispose();
    _dream.dispose();
    super.dispose();
  }

  /// Насколько вырос шаг [index]: 0 — его ещё нет, 1 — на месте.
  /// Без перелёта: выплывает и садится, как выдох, а не как пружина.
  double _step(int index) {
    final start = SleepThought.starts[index];
    final span = index == 2 ? 0.50 : 0.36;
    final t = ((_grow.value - start) / span).clamp(0.0, 1.0);
    return Curves.easeInOutSine.transform(t);
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
              final steps = [_step(0), _step(1), _step(2)];
              return Stack(
                children: [
                  CustomPaint(
                    size: Size(w, h),
                    painter: _ThoughtPainter(
                      one: one,
                      oneRadius: 0.045 * bear.width * w,
                      two: two,
                      twoRadius: 0.075 * bear.width * w,
                      cloud: cloud,
                      steps: steps,
                    ),
                  ),
                  if (_dreamReady && steps[2] > 0)
                    _dreamLayer(Size(w, h), cloud, steps[2]),
                  if (steps[2] > 0)
                    CustomPaint(
                      size: Size(w, h),
                      painter: _RimPainter(cloud: cloud, grown: steps[2]),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Ролик заливает облако целиком, до самого контура. Растёт и проступает
  /// вместе с ним из того же угла, что и само облако.
  ///
  /// Заказчик 22.09: «чтобы не было вот этого квадрата в облаке… чтобы он
  /// полностью облако закрывал и не было ни одного белого пробела».
  ///
  /// Обрезать ролик по контуру напрямую нельзя: на вебе видео — отдельный
  /// слой браузера, и произвольный контур к нему не применяется. Поэтому
  /// окно ролика — прямоугольник по границам контура, а углы, торчащие за
  /// горбы, закрыты сверху куском стены комнаты, вырезанным по обратной
  /// маске. Стена та же картинка, что и фон, в тех же координатах, — шва
  /// не видно. Под облаком только стена: окно левее, мишка ниже.
  Widget _dreamLayer(Size frame, Rect cloud, double grown) {
    final size = _dream.value.size;
    final window = cloudPath(cloud).getBounds();
    final scale = 0.6 + 0.4 * grown;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: window,
            child: Transform.scale(
              scale: scale,
              // Облако растёт из своего нижнего правого угла; окно шире
              // рамки облака, поэтому якорь — в тех же координатах, но
              // относительно окна.
              alignment: Alignment(
                _anchor(cloud.right, window.left, window.width),
                _anchor(cloud.bottom, window.top, window.height),
              ),
              child: Opacity(
                opacity: grown.clamp(0.0, 1.0),
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: VideoPlayer(_dream),
                  ),
                ),
              ),
            ),
          ),
          ClipPath(
            clipper: _OutsideCloud(cloud: cloud, window: window, scale: scale),
            child: Image.asset(
              RoomKind.bedroom.asset,
              width: frame.width,
              height: frame.height,
              fit: BoxFit.fill,
            ),
          ),
        ],
      ),
    );
  }

  /// Точка [at] в координатах кадра — как выравнивание внутри отрезка
  /// от [start] длиной [length]: −1 в начале, +1 в конце.
  static double _anchor(double at, double start, double length) =>
      (at - start) / length * 2 - 1;
}

/// Матрица роста облака: масштаб [scale] вокруг его нижнего правого угла.
Matrix4 cloudGrowth(Rect cloud, double scale) => Matrix4.identity()
  ..translateByDouble(cloud.right, cloud.bottom, 0, 1)
  ..scaleByDouble(scale, scale, 1, 1)
  ..translateByDouble(-cloud.right, -cloud.bottom, 0, 1);

/// Всё, что внутри окна ролика, но снаружи контура облака: этим куском
/// стены накрываются углы прямоугольного видео.
class _OutsideCloud extends CustomClipper<Path> {
  const _OutsideCloud({
    required this.cloud,
    required this.window,
    required this.scale,
  });

  final Rect cloud;
  final Rect window;
  final double scale;

  @override
  Path getClip(Size size) {
    // Окно чуть шире контура: край видео с антиалиасингом не должен
    // просвечивать тонкой линией вдоль горбов.
    final growth = cloudGrowth(cloud, scale);
    return ring(
      MatrixUtils.transformRect(growth, window.inflate(2)),
      MatrixUtils.transformRect(growth, cloud),
    );
  }

  /// Кольцо: прямоугольник [outer] без облака в рамке [grown]. Через
  /// заливку «чёт-нечет», а не `Path.combine(difference)`: на вебе разность
  /// с трансформированным контуром давала пустой результат, и маска
  /// накрывала ролик целиком. Контур в масштабе строится заново от
  /// выросшей рамки — все его горбы заданы в её долях.
  static Path ring(Rect outer, Rect grown) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(outer)
    ..addPath(cloudPath(grown), Offset.zero);

  @override
  bool shouldReclip(_OutsideCloud old) =>
      old.cloud != cloud || old.window != window || old.scale != scale;
}

/// Контур облака — овал с горбами по верху и по низу. Горбы разного
/// размера: одинаковые читаются как шестерёнка.
Path cloudPath(Rect r) {
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
    // Каждый шаг не только растёт, но и проступает: так он выплывает из
    // ничего, а не появляется точкой и раздувается.
    void draw(Path path, double grown, double shadow) {
      final alpha = grown.clamp(0.0, 1.0);
      canvas.drawShadow(
          path, Color.fromRGBO(32, 48, 64, alpha), shadow * alpha, true);
      canvas.drawPath(
          path, Paint()..color = AppColors.surface.withValues(alpha: alpha));
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.outline.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Пузырьки чуть неровные — овал с наклоном: ровный кружок выглядит
    // кнопкой. Заказчик 22.09: «маленькая белая точечка неровная».
    void bubble(Offset center, double radius, double grown, double tilt) {
      if (grown <= 0) return;
      final path = Path()
        ..addOval(Rect.fromCenter(
          center: Offset.zero,
          width: 2 * radius * grown,
          height: 1.72 * radius * grown,
        ));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      draw(path, grown, 6);
      canvas.restore();
    }

    bubble(one, oneRadius, steps[0], -0.5);
    bubble(two, twoRadius, steps[1], 0.35);

    final grown = steps[2];
    if (grown <= 0) return;

    // Облако растёт из своего нижнего правого угла — оттуда, где пузырьки.
    // Только заливка: тень и кромку кладёт [_RimPainter] поверх ролика,
    // иначе их накрыла бы маска стены вокруг видео.
    canvas.save();
    canvas.transform(cloudGrowth(cloud, 0.6 + 0.4 * grown).storage);
    canvas.drawPath(
      cloudPath(cloud),
      Paint()..color = AppColors.surface.withValues(alpha: grown.clamp(0, 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThoughtPainter old) =>
      old.steps[0] != steps[0] ||
      old.steps[1] != steps[1] ||
      old.steps[2] != steps[2] ||
      old.cloud != cloud;
}

/// Тень и кромка облака поверх ролика: ролик обрезан по контуру, и без
/// кромки край выглядит резаным. Тень только снаружи контура: внутри —
/// ролик, и темнить его нечем.
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.cloud, required this.grown});

  final Rect cloud;
  final double grown;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = grown.clamp(0.0, 1.0);
    // Контур в текущем масштабе строится от выросшей рамки, без
    // трансформации пути: см. [_OutsideCloud.ring].
    final grownCloud = MatrixUtils.transformRect(
        cloudGrowth(cloud, 0.6 + 0.4 * grown), cloud);
    final path = cloudPath(grownCloud);
    canvas.save();
    canvas.clipPath(_OutsideCloud.ring(path.getBounds().inflate(40), grownCloud));
    canvas.drawShadow(path, Color.fromRGBO(32, 48, 64, alpha), 8 * alpha, true);
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.outline.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.grown != grown || old.cloud != cloud;
}
