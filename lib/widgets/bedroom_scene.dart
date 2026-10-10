import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../bear/bear_rig_spec.dart';
import '../bear/rive_bear_trial.dart';
import 'kitchen_bear.dart' show TablePawsPainter;

/// Живая спальня: мишка в кровати под одеялом, ночник.
///
/// Заказчик 21.09–22.09: дышать должно одеяло, а не голова, и только «в
/// районе мишки… как будто укрылся человек»; засыпать быстро — два-три
/// медленных моргания; веки — плавно, а не «покадрово».
///
/// С 10.10 в кровати тот же Rive-мишка, что в игровой и на кухне (заказчик:
/// «во сне поменять мишку на того, что в главной комнате»). Лежит там же,
/// где лежал нарисованный: глаза — на месте его глаз, тело под одеялом, лапы
/// поверх одеяла. Засыпает и спит сам мишка ([RiveBearTrial.asleep]):
/// сонные веки и медленное моргание, потом петля сна (ТЗ `idle_asleep`) —
/// голова склонилась, глаза закрыты, как в моргании покоя, дышит медленно,
/// изредка дёргает ухом.
///
/// Слои снизу вверх: комната (рисуется не здесь) → мишка → передний край
/// одеяла (дышит над грудью) → лапы на одеяле → свет ночника.
class BedroomScene extends StatefulWidget {
  const BedroomScene({
    super.key,
    this.asleep = false,
    required this.cue,
    this.mood = BearMood.normal,
    this.trait = BearTrait.active,
  });

  /// Уложили спать: мишка засыпает и спит, глаза закрыты. Заказчик 22.09:
  /// «при нажатии её наш мишка должен закрыть глаза полностью».
  final bool asleep;

  final BearFaceCue cue;
  final BearMood mood;
  final BearTrait trait;

  /// Где лежала голова нарисованного мишки — в долях кадра комнаты
  /// (941 × 1672). По ней встаёт облако мыслей; голова нынешнего мишки на
  /// том же месте.
  static const Rect bear = Rect.fromLTWH(
    0.381509,
    0.412679,
    0.238045,
    0.157297,
  );

  /// Коробка Rive-мишки (артборд 1024 × 1024) в долях кадра: глаза — на
  /// месте глаз нарисованного (между глазами 57 px кадра против 110 px
  /// артборда → масштаб 0,52; середина глаз — (474, 854) кадра).
  static const double bearLeft = 208.4 / 941;
  static const double bearTop = 638.0 / 1672;
  static const double bearSide = 532.1 / 941;

  static const Rect blanket = Rect.fromLTWH(0, 0.544258, 1, 0.310407);
  static const Rect glow = Rect.fromLTWH(
    0.420829,
    0.199761,
    0.579171,
    0.459928,
  );

  /// Свет спальни на мишке: ночник тёплый, комната тёмная — мишка чуть
  /// темнее и теплее, чем днём в игровой (как на кухне под её светом).
  static const ColorFilter night = ColorFilter.matrix(<double>[
    0.95, 0, 0, 0, 0, //
    0, 0.91, 0, 0, 0, //
    0, 0, 0.88, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Дыхание: вдох короче выдоха. 4,4 с — как петля сна мишка.
  static const Duration breath = Duration(milliseconds: 4400);

  /// Горб одеяла над грудью: центр и разброс — в долях слоя одеяла.
  static const Offset chest = Offset(0.50, 0.10);
  static const Size chestSpread = Size(0.17, 0.24);

  /// На сколько поднимается грудь на вдохе — в долях высоты слоя одеяла.
  static const double chestRise = 0.013;

  /// Ночник: медленное мерцание.
  static const Duration lampBreath = Duration(milliseconds: 5500);

  /// Сколько мишка засыпает: через это время глаза закрыты насовсем, и
  /// облако мыслей с буквами z ждут именно этого.
  static const Duration fallAsleep = Duration(milliseconds: 4000);

  static const String _blanketAsset = 'assets/rooms/bedroom/blanket_front.png';

  static const List<String> assets = [
    _blanketAsset,
    'assets/rooms/bedroom/lamp_glow.png',
    'assets/rooms/kitchen/table_paw_left.png',
    'assets/rooms/kitchen/table_paw_right.png',
  ];

  /// Заранее раскодировать картинки — ещё до того, как открыли «Сон»:
  /// иначе одеяло и лапы появлялись бы на долю секунды позже мишка.
  static Future<void> warmUp(BuildContext context) => Future.wait([
    for (final asset in assets) precacheImage(AssetImage(asset), context),
  ]);

  @override
  State<BedroomScene> createState() => _BedroomSceneState();
}

class _BedroomSceneState extends State<BedroomScene>
    with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: BedroomScene.breath,
  );

  late final AnimationController _lamp = AnimationController(
    vsync: this,
    duration: BedroomScene.lampBreath,
  );

  /// Вдох короче выдоха: так дышат во сне. Ровная синусоида читается как
  /// качание, а не как дыхание.
  late final Animation<double> _wave = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 58,
    ),
  ]).animate(_breath);

  /// Где кисти мишка — сюда их пишет сам мишка каждый кадр, лапы рисуются
  /// по ним поверх одеяла.
  final TablePaws _paws = TablePaws();

  ui.Image? _blanket;
  ui.Image? _pawLeft;
  ui.Image? _pawRight;
  final List<(ImageStream, ImageStreamListener)> _streams = [];

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_streams.isEmpty) {
      _load(BedroomScene._blanketAsset, (i) => _blanket = i);
      _load('assets/rooms/kitchen/table_paw_left.png', (i) => _pawLeft = i);
      _load('assets/rooms/kitchen/table_paw_right.png', (i) => _pawRight = i);
    }
    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда одеяло и ночник стоят.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _breath
        ..stop()
        ..value = 0;
      _lamp
        ..stop()
        ..value = 0;
    } else {
      _breath.repeat();
      _lamp.repeat(reverse: true);
    }
  }

  void _load(String asset, void Function(ui.Image) done) {
    final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => done(info.image));
    });
    stream.addListener(listener);
    _streams.add((stream, listener));
  }

  @override
  void dispose() {
    for (final (stream, listener) in _streams) {
      stream.removeListener(listener);
    }
    _paws.dispose();
    _breath.dispose();
    _lamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Слой ничего не ловит: погладить мишку ловит слой под всей сценой,
    // иначе кровать перехватывала бы касания по комнате.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final box = Rect.fromLTWH(
            BedroomScene.bearLeft * w,
            BedroomScene.bearTop * h,
            BedroomScene.bearSide * w,
            BedroomScene.bearSide * w,
          );
          final pawLeft = _pawLeft;
          final pawRight = _pawRight;

          return Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                child: ColorFiltered(
                  colorFilter: BedroomScene.night,
                  child: RiveBearTrial(
                    cue: widget.cue,
                    trait: widget.trait,
                    mood: widget.mood,
                    seated: true,
                    asleep: widget.asleep,
                    paws: _paws,
                  ),
                ),
              ),
              _place(BedroomScene.blanket, w, h, _blanketLayer()),
              // Лапы — поверх одеяла, в той же коробке, что мишка.
              if (pawLeft != null && pawRight != null)
                Positioned.fromRect(
                  rect: box,
                  child: ColorFiltered(
                    colorFilter: BedroomScene.night,
                    child: CustomPaint(
                      painter: TablePawsPainter(
                        paws: _paws,
                        pat: kAlwaysDismissedAnimation,
                        left: pawLeft,
                        right: pawRight,
                      ),
                    ),
                  ),
                ),
              _place(BedroomScene.glow, w, h, _glowLayer()),
            ],
          );
        },
      ),
    );
  }

  /// Одеяло: приподнимается на вдохе — но только над грудью.
  ///
  /// Пока картинка не загрузилась, лежит как есть: секунда без дыхания
  /// незаметна, а пустое место на кровати — нет.
  Widget _blanketLayer() {
    final image = _blanket;
    if (image == null) {
      return Image.asset(BedroomScene._blanketAsset, fit: BoxFit.fill);
    }
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) => CustomPaint(
        painter: _BreathingBlanket(
          image: image,
          rise: BedroomScene.chestRise * _wave.value,
        ),
      ),
    );
  }

  /// Свет ночника: еле заметно колышется, как живой огонёк.
  Widget _glowLayer() {
    return AnimatedBuilder(
      animation: _lamp,
      builder: (context, child) {
        final wave = Curves.easeInOutSine.transform(_lamp.value);
        return Opacity(opacity: 0.84 + 0.16 * wave, child: child);
      },
      child: Image.asset(
        'assets/rooms/bedroom/lamp_glow.png',
        fit: BoxFit.fill,
      ),
    );
  }

  Widget _place(Rect box, double w, double h, Widget child) {
    return Positioned(
      left: box.left * w,
      top: box.top * h,
      width: box.width * w,
      height: box.height * h,
      child: child,
    );
  }
}

/// Одеяло, натянутое на сетку: узлы над грудью приподняты, остальные лежат.
///
/// Вздох спящего под одеялом — это горб над грудью, который сходит на нет
/// к краям. Двигать слой целиком нельзя: заказчик 22.09 — «одеяло начинает
/// двигаться полностью всё, нужно только в районе мишки».
class _BreathingBlanket extends CustomPainter {
  const _BreathingBlanket({required this.image, required this.rise});

  final ui.Image image;

  /// На сколько сейчас поднята грудь — в долях высоты слоя.
  final double rise;

  /// Частота сетки. Горб плавный, и двадцати ячеек хватает, чтобы на нём
  /// не было видно изломов.
  static const int cols = 24;
  static const int rows = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = <Offset>[];
    final texture = <Offset>[];
    final chest = BedroomScene.chest;
    final spread = BedroomScene.chestSpread;

    for (var r = 0; r <= rows; r++) {
      final v = r / rows;
      for (var c = 0; c <= cols; c++) {
        final u = c / cols;
        // Горб — гауссов колокол над грудью. У нижнего и боковых краёв
        // он уже нулевой сам по себе, и слой сидит на фоне без шва.
        final dx = (u - chest.dx) / spread.width;
        final dy = (v - chest.dy) / spread.height;
        final bump = math.exp(-(dx * dx + dy * dy));
        positions.add(
          Offset(u * size.width, v * size.height - rise * bump * size.height),
        );
        texture.add(Offset(u * image.width, v * image.height));
      }
    }

    final indices = <int>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final a = r * (cols + 1) + c;
        final b = a + 1;
        final d = a + cols + 1;
        final e = d + 1;
        indices.addAll([a, b, d, b, e, d]);
      }
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: Uint16List.fromList(indices),
    );
    final paint = Paint()
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Matrix4.identity().storage,
      )
      ..filterQuality = FilterQuality.medium;
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
  }

  @override
  bool shouldRepaint(_BreathingBlanket old) =>
      old.rise != rise || old.image != image;
}
