import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../bear/bear_rig_spec.dart';
import '../bear/rive_bear_trial.dart';

/// Живая спальня: мишка в кровати под одеялом, ночник.
///
/// Заказчик 21.09–22.09: дышать должно одеяло, а не голова, и только «в
/// районе мишки… как будто укрылся человек»; засыпать быстро — два-три
/// медленных моргания; веки — плавно, а не «покадрово».
///
/// С 10.10 в кровати тот же Rive-мишка, что в игровой и на кухне (заказчик:
/// «во сне поменять мишку на того, что в главной комнате»). Лежит там же,
/// где лежал нарисованный: глаза — на месте его глаз, тело под одеялом.
/// Лапы — как у прежнего (заказчик 11.10: «лежит, как будто сидит», «лапки
/// на одеяле, как в предыдущей версии»): у подбородка, держат край одеяла и
/// выглядывают из-под него. Руки за кистями по одеялу больше не тянутся —
/// так мишка казался сидящим в кровати. Засыпает и спит сам мишка
/// ([RiveBearTrial.asleep]):
/// сонные веки и медленное моргание, потом петля сна (ТЗ `idle_asleep`) —
/// голова склонилась, глаза закрыты, как в моргании покоя, дышит медленно,
/// изредка дёргает ухом.
///
/// Дышит одеяло вместе с мишкой (заказчик 11.10: «подъём одеяла… сейчас
/// не совпадает», «часто дышит»): горб над грудью поднимается от вдоха
/// самого рига ([RiveBearTrial.breath]) — и в темпе спокойного покоя
/// (6 с), и во сне (6,4 с), и на вздохах эмоций. Лапы держат край одеяла и
/// поднимаются с ним.
///
/// Тело рига в кровати спрятано (11.10, как на кухне): под подбородком —
/// ровный край капюшона прежнего мишка ([_collarAsset]), без заломов
/// воротника рига и без его плеча у левой лапы.
///
/// Слои снизу вверх: комната (рисуется не здесь) → воротник прежнего
/// мишка → голова мишка → лапы прежнего мишка у подбородка → передний
/// край одеяла (дышит над грудью, закрывает запястья) → свет ночника.
class BedroomScene extends StatefulWidget {
  const BedroomScene({
    super.key,
    this.asleep = false,
    required this.cue,
    this.mood = BearMood.normal,
    this.trait = BearTrait.active,
    this.skin = BearSkin.boy,
  });

  /// Герой (КП 2.4). Девочка лежит, как мальчик (заказчик 14.10: «делай
  /// лапки девочки… у одеяла»): тело рига спрятано, под подбородком — ворот
  /// её кофточки, у подбородка — лапы в её мех (`tool/rive/girl_bed.py`).
  final BearSkin skin;

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

  /// Коробка Rive-мишки (артборд 1024 × 1024) в долях кадра: размер —
  /// по глазам нарисованного (между глазами 57 px кадра против 110 px
  /// артборда → масштаб 0,52).
  ///
  /// Поднят на [bearRaise] над глазами прежнего (заказчик 11.10: «одеяло
  /// прикрывает его бороду… чуть-чуть повыше»): у нашего от глаз до низа
  /// подбородка 68 px кадра, у прежнего 53, и с глазами на прежнем месте
  /// (854) подбородок уходил под край одеяла (913) на 8 px. Теперь глаза —
  /// 834, подбородок — 901, под ним виден край капюшона, как у прежнего
  /// (у того подбородок 906).
  static const double bearLeft = 208.4 / 941;
  static const double bearRaise = 20 / 1672;
  static const double bearTop = 638.0 / 1672 - bearRaise;
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

  /// Горб одеяла над грудью: центр и разброс — в долях слоя одеяла.
  static const Offset chest = Offset(0.50, 0.10);
  static const Size chestSpread = Size(0.17, 0.24);

  /// На сколько поднимается грудь на вдохе — в долях высоты слоя одеяла.
  static const double chestRise = 0.013;

  /// Сколько горба одеяла приходится на точку (доли кадра): 1 — над
  /// грудью, к краям сходит на нет.
  static double blanketBump(Offset at) {
    final u = (at.dx - blanket.left) / blanket.width;
    final v = (at.dy - blanket.top) / blanket.height;
    final dx = (u - chest.dx) / chestSpread.width;
    final dy = (v - chest.dy) / chestSpread.height;
    return math.exp(-(dx * dx + dy * dy));
  }

  /// Ночник: медленное мерцание.
  static const Duration lampBreath = Duration(milliseconds: 5500);

  /// Сколько мишка засыпает: через это время глаза закрыты насовсем, и
  /// облако мыслей с буквами z ждут именно этого.
  static const Duration fallAsleep = Duration(milliseconds: 4000);

  static const String _blanketAsset = 'assets/rooms/bedroom/blanket_front.png';

  /// Лапы прежнего мишка — слой той же коробки [bear]: у подбородка, под
  /// краем одеяла. Картинка одна на обе лапы: левая — столбцы до
  /// [pawSplit], правая — после.
  static const String _pawsAsset = 'assets/rooms/bedroom/bear_paws.png';
  static const double pawSplit = 0.5;

  /// Правая лапа (справа для зрителя) отодвинута от лица — доля ширины
  /// кадра. Заказчик 11.10: «правая лапка чересчур закрывает лицо». У
  /// прежнего мишка лапы стояли несимметрично: правая на 75 px кадра от
  /// середины мордочки, левая на 87; наша мордочка шире — правая теперь
  /// там же, где левая, на 89 px.
  static const double pawRightShift = 14 / 941;

  /// Лапы чуть выше прежнего места — вслед за поднятым мишкой (доля
  /// высоты кадра): держат край одеяла по бокам подбородка.
  static const double pawRaise = 6 / 1672;

  /// Середины лап (доли кадра) — по ним лапы поднимаются с одеялом.
  static const Offset pawLeftAt = Offset(387 / 941, 915 / 1672);
  static const Offset pawRightAt = Offset((548 + 14) / 941, 915 / 1672);

  /// Лапы нарисованы под свет спальни и светлее нашего мишка под
  /// [night]: замер 11.10 — лапы (238, 213, 197), щека (218, 197, 178).
  static const ColorFilter pawTone = ColorFilter.matrix(<double>[
    0.92, 0, 0, 0, 0, //
    0, 0.925, 0, 0, 0, //
    0, 0, 0.90, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Ровный край капюшона прежнего мишка под подбородком — в той же
  /// рамке [bear] (`tool/cut_bedroom_collar.py`). Тело рига в кровати
  /// спрятано ([RiveBearTrial.headOnly]): заказчик 11.10 — «около лапки
  /// появилась часть его кофты», «под подбородком складки ужасно выглядят…
  /// как на кухне, сделай так же и в спальне».
  static const String _collarAsset = 'assets/rooms/bedroom/bear_collar.png';

  /// Середина воротника (доли кадра) — по ней он поднимается с одеялом.
  static const Offset collarAt = Offset(474 / 941, 913 / 1672);

  /// Девочка: ворот её кофточки между лапами и круглые лапы в её мех — в
  /// той же рамке [bear], на тех же местах, что у мальчика. Цвет — как у
  /// слоёв рига, свет спальни — [night].
  static const String _girlCollarAsset = 'assets/rooms/bedroom/girl_collar.png';
  static const String _girlPawsAsset = 'assets/rooms/bedroom/girl_paws.png';

  static const List<String> assets = [
    _blanketAsset,
    _pawsAsset,
    _collarAsset,
    _girlPawsAsset,
    _girlCollarAsset,
    'assets/rooms/bedroom/lamp_glow.png',
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
  /// Вдох мишка — пишет сам риг каждый кадр ([RiveBearTrial.breath]).
  final ValueNotifier<double> _breath = ValueNotifier(0);

  late final AnimationController _lamp = AnimationController(
    vsync: this,
    duration: BedroomScene.lampBreath,
  );

  /// Насколько поднята грудь: 0 — выдох, 1 — вдох. Вдох рига от −1 до +1
  /// (в кровати размах 0,6, во сне свой), вздох эмоции — выше 1.
  double get _rise {
    if (_stillSetting ?? false) return 0;
    return ((_breath.value + 1) / 2).clamp(0.0, 1.5);
  }

  ui.Image? _blanket;
  ui.Image? _paws;
  ui.Image? _girlPaws;
  final List<(ImageStream, ImageStreamListener)> _streams = [];

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_streams.isEmpty) {
      _load(BedroomScene._blanketAsset, (i) => _blanket = i);
      _load(BedroomScene._pawsAsset, (i) => _paws = i);
      _load(BedroomScene._girlPawsAsset, (i) => _girlPaws = i);
    }
    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда одеяло и ночник стоят.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _lamp
        ..stop()
        ..value = 0;
    } else {
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

          final girl = widget.cue.heroOr(widget.skin) == BearSkin.girl;
          return Stack(
            children: [
              // Воротник под головой: капюшон (у девочки — подбородок)
              // ложится на него сверху.
              _place(BedroomScene.bear, w, h, _collarLayer(h, girl: girl)),
              Positioned.fromRect(
                rect: box,
                child: ColorFiltered(
                  colorFilter: BedroomScene.night,
                  child: RiveBearTrial(
                    cue: widget.cue,
                    trait: widget.trait,
                    mood: widget.mood,
                    skin: widget.skin,
                    seated: true,
                    headOnly: true,
                    asleep: widget.asleep,
                    breath: _breath,
                  ),
                ),
              ),
              // Лапы держат край одеяла у подбородка: под одеялом, как у
              // прежнего мишки, — край одеяла закрывает запястья.
              _place(BedroomScene.bear, w, h, _pawsLayer(h, girl: girl)),
              _place(BedroomScene.blanket, w, h, _blanketLayer()),
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
          rise: BedroomScene.chestRise * _rise,
        ),
      ),
    );
  }

  /// Воротник поднимается с грудью — на столько же, на сколько одеяло у
  /// подбородка. Цвет мальчика уже подогнан под ночник — без фильтра; ворот
  /// девочки — под [BedroomScene.night], как её голова.
  Widget _collarLayer(double h, {bool girl = false}) {
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -BedroomScene.chestRise *
              _rise *
              BedroomScene.blanket.height *
              h *
              BedroomScene.blanketBump(BedroomScene.collarAt),
        ),
        child: child,
      ),
      child: girl
          ? ColorFiltered(
              colorFilter: BedroomScene.night,
              child: Image.asset(
                BedroomScene._girlCollarAsset,
                fit: BoxFit.fill,
              ),
            )
          : Image.asset(BedroomScene._collarAsset, fit: BoxFit.fill),
    );
  }

  /// Лапы прежнего мишка: правая отодвинута от лица, обе поднимаются с
  /// краем одеяла — ровно на столько, на сколько горб одеяла у них. У
  /// девочки — те же лапы в её мех, под свет спальни, как её голова.
  Widget _pawsLayer(double h, {bool girl = false}) {
    final image = girl ? _girlPaws : _paws;
    if (image == null) return const SizedBox.shrink();
    return ColorFiltered(
      colorFilter: girl ? BedroomScene.night : BedroomScene.pawTone,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, _) {
          final lift =
              BedroomScene.chestRise * _rise * BedroomScene.blanket.height * h;
          final raise = BedroomScene.pawRaise * h;
          return CustomPaint(
            painter: _BedPaws(
              image: image,
              liftLeft:
                  raise +
                  lift * BedroomScene.blanketBump(BedroomScene.pawLeftAt),
              liftRight:
                  raise +
                  lift * BedroomScene.blanketBump(BedroomScene.pawRightAt),
              shiftRight: BedroomScene.pawRightShift / BedroomScene.bear.width,
            ),
          );
        },
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

/// Лапы у подбородка — две половины одной картинки: левая на месте,
/// правая сдвинута на [shiftRight] (доля ширины слоя); каждая поднята на
/// свой подъём края одеяла, px.
class _BedPaws extends CustomPainter {
  const _BedPaws({
    required this.image,
    required this.liftLeft,
    required this.liftRight,
    required this.shiftRight,
  });

  final ui.Image image;
  final double liftLeft;
  final double liftRight;
  final double shiftRight;

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    const split = BedroomScene.pawSplit;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw * split, ih),
      Rect.fromLTWH(0, -liftLeft, size.width * split, size.height),
      paint,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(iw * split, 0, iw * (1 - split), ih),
      Rect.fromLTWH(
        size.width * (split + shiftRight),
        -liftRight,
        size.width * (1 - split),
        size.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BedPaws old) =>
      old.image != image ||
      old.liftLeft != liftLeft ||
      old.liftRight != liftRight ||
      old.shiftRight != shiftRight;
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
