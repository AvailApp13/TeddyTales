import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Живые слои спальни: мишка сопит, моргает и засыпает под одеялом.
///
/// Заказчик 21.09: «во вкладке сон, где мишка в кровати лежит, сделать
/// анимацию дыхания и моргания глаз, будто он хочет спать». Дальше по
/// версиям 22.09: глаза открыты, а прикрытые — эпизоды; дышать должно
/// одеяло, а не голова; одеяло — «только в районе мишки… как будто укрылся
/// человек, и вот тут он дышит»; и засыпать быстро — «2–3 раза, чтобы он
/// моргнул медленно, и как бы засыпал».
///
/// По ТЗ аниматора это `act_sleep`: «укладывается, засыпает, сопит» — риг в
/// Rive. Позы «лёжа» в риге нет, и заказчик прислал спальню картинкой вместо
/// неё. Картинка разобрана на слои (`tool/cut_bedroom_layers.py`), и из них
/// здесь собрано то, что из `act_sleep` можно собрать без рига: сопение,
/// моргание, засыпание с покачиванием головы. Укладывание и потягивание при
/// пробуждении — уже только риг.
///
/// Слои снизу вверх: комната без мишки (фон комнаты, рисуется не здесь) →
/// уши → голова с лицом → лапы → передний край одеяла → свет ночника. Уши
/// за головой, чтобы дёргаться, не трогая капюшон. Лапы отдельно, чтобы
/// лежать на месте, пока голова клюёт носом. Одеяло поверх, чтобы низ
/// фигуры уходил под него — и чтобы дышать могло оно, а не мишка.
class BedroomScene extends StatefulWidget {
  const BedroomScene({super.key});

  /// Где лежит каждый слой — в долях кадра комнаты (941 × 1672).
  ///
  /// Числа печатает `tool/cut_bedroom_layers.py`: он же режет сами файлы,
  /// так что менять их вручную не надо — пересобрать и переписать.
  static const Rect bear = Rect.fromLTWH(0.381509, 0.412679, 0.238045, 0.157297);
  static const Rect earLeft = Rect.fromLTWH(0.385233, 0.464521, 0.049270, 0.030751);
  static const Rect earRight = Rect.fromLTWH(0.560544, 0.455505, 0.054713, 0.033327);
  static const Rect blanket = Rect.fromLTWH(0, 0.544258, 1, 0.310407);
  static const Rect glow = Rect.fromLTWH(0.420829, 0.199761, 0.579171, 0.459928);

  /// Корень уха — где оно уходит под капюшон, в долях своего слоя.
  /// Вокруг него ухо и дёргается; снято по основе, где ухо уходит под край
  /// капюшона.
  static const Alignment earLeftRoot = Alignment(0.83, 0.58);
  static const Alignment earRightRoot = Alignment(-0.84, 0.71);

  /// На сколько ухо вздрагивает — радианы. Вверх и чуть внутрь: так
  /// прядёт ухом зверь, которого что-то задело сквозь сон.
  static const double earTwitch = 0.10;

  /// Вдох-выдох. Четыре с небольшим секунды на цикл — темп спящего
  /// ребёнка; на взрослых трёх секундах мишка выглядит встревоженным.
  static const Duration breath = Duration(milliseconds: 4400);

  /// Где под одеялом грудь — в долях слоя одеяла — и насколько широко
  /// расходится вздох. Дышит только это место: остальное одеяло лежит.
  static const Offset chest = Offset(0.50, 0.10);
  static const Size chestSpread = Size(0.17, 0.24);

  /// На сколько поднимается одеяло над грудью — в долях высоты слоя.
  /// Заказчик: «прям немного это должно быть заметно».
  static const double chestRise = 0.013;

  /// Плечи под капюшоном чуть расширяются, макушка ходит на волосок.
  static const double shoulderSwell = 0.010;
  static const double shoulderSpread = 0.005;

  /// Засыпая, голова наклоняется и опускается. Радианы и доля высоты.
  static const double nodTilt = -0.026;
  static const double nodDrop = 0.016;

  /// Ночник дышит своим темпом: совпади он с мишкой, комната начала бы
  /// пульсировать целиком.
  static const Duration lampBreath = Duration(milliseconds: 5500);

  @override
  State<BedroomScene> createState() => _BedroomSceneState();
}

/// Какой вариант лица показан.
///
/// Взгляды в стороны и вниз — с основы 22.09 («гладкий капюшон»); зевка у
/// неё нет, да он и не читался: без движения головы открытый рот — просто
/// «непонятно, что там происходит» (заказчик 22.09).
enum _Face {
  open('assets/rooms/bedroom/bear_open.png'),
  half('assets/rooms/bedroom/bear_half.png'),
  closed('assets/rooms/bedroom/bear_closed.png'),
  left('assets/rooms/bedroom/bear_left.png'),
  right('assets/rooms/bedroom/bear_right.png'),
  down('assets/rooms/bedroom/bear_down.png');

  const _Face(this.asset);

  final String asset;
}

/// Один шаг сценария: показать лицо, перетекая к нему за [fade], держать
/// его [hold] и, если сказано, начать или прекратить клевать носом.
typedef _Step = ({_Face face, Duration fade, Duration hold, bool? nod});

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

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );

  /// Голова: 0 — прямо, 1 — свесилась. Вперёд медленно, а обратно
  /// вздрагивает: спохватился.
  late final AnimationController _nodDrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
    reverseDuration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _nod = CurvedAnimation(
    parent: _nodDrive,
    curve: Curves.easeInOutSine,
    reverseCurve: Curves.easeOutBack,
  );

  /// Уши: 0 — лежит, 1 — вздёрнуто. Вздрагивает резко, опускается мягко.
  late final AnimationController _earLeft = _earDrive();
  late final AnimationController _earRight = _earDrive();

  AnimationController _earDrive() => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 90),
        reverseDuration: const Duration(milliseconds: 260),
      );

  late final Animation<double> _earLeftFlick = _flickOf(_earLeft);
  late final Animation<double> _earRightFlick = _flickOf(_earRight);

  Animation<double> _flickOf(AnimationController ear) => CurvedAnimation(
        parent: ear,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInOutSine,
      );

  /// Вдох короче выдоха: так дышат во сне. Ровная синусоида читается как
  /// качание, а не как дыхание.
  late final Animation<double> _wave = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 58,
    ),
  ]).animate(_breath);

  /// Что показано сейчас и из чего перетекаем.
  _Face _face = _Face.open;
  _Face _under = _Face.open;

  final math.Random _dice = math.Random();
  final Queue<_Step> _plan = Queue();
  Timer? _next;
  Timer? _earNext;

  /// Картинка одеяла — нужна как `ui.Image`, потому что одеяло рисуется
  /// сеткой, а не целиком: дышит только его кусок над грудью.
  ui.Image? _blanket;
  ImageStream? _blanketStream;
  ImageStreamListener? _blanketListener;

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  bool get _still => _stillSetting ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBlanket();

    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда мишка просто лежит с открытыми глазами.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _next?.cancel();
      _earNext?.cancel();
      _plan.clear();
      _breath.stop();
      _lamp.stop();
      _nodDrive.stop();
      _earLeft.stop();
      _earRight.stop();
      _breath.value = 0;
      _lamp.value = 0;
      _nodDrive.value = 0;
      _earLeft.value = 0;
      _earRight.value = 0;
      _show(_Face.open, Duration.zero);
    } else {
      _breath.repeat();
      _lamp.repeat(reverse: true);
      _rest();
      _earRest();
    }
  }

  void _loadBlanket() {
    final stream = const AssetImage('assets/rooms/bedroom/blanket_front.png')
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _blanketStream?.key) return;
    _dropBlanket();
    _blanketStream = stream;
    _blanketListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _blanket = info.image);
    });
    stream.addListener(_blanketListener!);
  }

  void _dropBlanket() {
    if (_blanketListener != null) {
      _blanketStream?.removeListener(_blanketListener!);
    }
    _blanketStream = null;
    _blanketListener = null;
  }

  @override
  void dispose() {
    _next?.cancel();
    _earNext?.cancel();
    _dropBlanket();
    _breath.dispose();
    _lamp.dispose();
    _fade.dispose();
    _nodDrive.dispose();
    _earLeft.dispose();
    _earRight.dispose();
    super.dispose();
  }

  /// Уши живут своим расписанием, не в ногу с глазами: одно вздрогнет,
  /// иногда дважды, изредка оба. Не чаще, чем раз в несколько секунд —
  /// чаще уже читается как нервный тик.
  void _earRest() {
    _earNext?.cancel();
    _earNext = Timer(_ms(3500, 6000), _earTwitch);
  }

  Future<void> _earTwitch() async {
    if (!mounted || _still) return;
    final ear = _dice.nextBool() ? _earLeft : _earRight;
    final both = _dice.nextInt(5) == 0;
    final twice = _dice.nextBool();
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      await Future.wait([
        _flick(ear),
        if (both) _flick(ear == _earLeft ? _earRight : _earLeft),
      ]);
      if (!mounted || _still) return;
    }
    _earRest();
  }

  Future<void> _flick(AnimationController ear) async {
    await ear.forward(from: 0);
    if (!mounted || _still) return;
    await ear.reverse();
  }

  Duration _ms(int base, [int spread = 0]) =>
      Duration(milliseconds: base + (spread == 0 ? 0 : _dice.nextInt(spread)));

  /// Полежать с открытыми глазами, потом — что-нибудь сделать.
  ///
  /// Паузы нарочно неровные: ровный интервал глаз ловит сразу и читает как
  /// мигающую лампочку, а не как живое существо.
  void _rest() {
    _next?.cancel();
    _next = Timer(_ms(2200, 1800), _act);
  }

  /// Один круг: обычное моргание, потом два-три медленных — и заснул.
  ///
  /// Заказчик 22.09: «нужно 2–3 раза, чтобы он моргнул медленно, и как бы
  /// засыпал» — и чтобы ждать этого не приходилось. Круг целиком занимает
  /// около двадцати секунд.
  void _act() {
    if (!mounted || _still) return;

    // Обычное моргание в три фазы через полуприкрытые: щелчок без
    // промежуточного кадра выглядит как сбой картинки.
    _plan.addAll([
      (face: _Face.half, fade: _ms(55), hold: Duration.zero, nod: null),
      (face: _Face.closed, fade: _ms(55), hold: _ms(90, 60), nod: null),
      (face: _Face.half, fade: _ms(70), hold: Duration.zero, nod: null),
      (face: _Face.open, fade: _ms(110), hold: _ms(1600, 1400), nod: null),
    ]);

    // Посмотрел в сторону — что там? — и обратно. В какую, решает жребий:
    // одна и та же сторона каждый круг выдаёт запись.
    _plan.addAll([
      (
        face: _dice.nextBool() ? _Face.left : _Face.right,
        fade: _ms(170),
        hold: _ms(900, 700),
        nod: null,
      ),
      (face: _Face.open, fade: _ms(200), hold: _ms(600, 500), nod: null),
    ]);

    // Первое медленное: веки тяжёлые, но ещё открывает до конца.
    _plan.addAll([
      (face: _Face.half, fade: _ms(420), hold: Duration.zero, nod: null),
      (face: _Face.closed, fade: _ms(480), hold: _ms(320, 200), nod: null),
      (face: _Face.half, fade: _ms(520), hold: Duration.zero, nod: null),
      (face: _Face.open, fade: _ms(520), hold: _ms(1300, 900), nod: null),
    ]);

    // Глаза опустились — уже не смотрит, а дремлет. Отсюда и второе
    // медленное: ещё медленнее, голова пошла вниз, глаза поднимаются только
    // до полуприкрытых.
    _plan.addAll([
      (face: _Face.down, fade: _ms(380), hold: _ms(600, 400), nod: null),
      (face: _Face.half, fade: _ms(560), hold: Duration.zero, nod: true),
      (face: _Face.closed, fade: _ms(640), hold: _ms(520, 300), nod: null),
      (face: _Face.half, fade: _ms(700), hold: _ms(900, 500), nod: null),
    ]);

    // Иногда третье — открыл до конца, будто борется со сном.
    if (_dice.nextBool()) {
      _plan.addAll([
        (face: _Face.open, fade: _ms(600), hold: _ms(700, 500), nod: null),
        (face: _Face.half, fade: _ms(700), hold: _ms(400, 300), nod: null),
      ]);
    }

    // Заснул. Через несколько секунд спохватывается и открывает глаза.
    _plan.addAll([
      (face: _Face.closed, fade: _ms(900), hold: _ms(4500, 3000), nod: null),
      (face: _Face.open, fade: _ms(260), hold: Duration.zero, nod: false),
    ]);
    _step();
  }

  /// Выполнить следующий шаг сценария; когда он кончился — отдыхать.
  void _step() {
    if (!mounted || _still) return;
    if (_plan.isEmpty) {
      _rest();
      return;
    }
    final step = _plan.removeFirst();
    _show(step.face, step.fade);
    switch (step.nod) {
      case true:
        _nodDrive.forward();
      case false:
        _nodDrive.reverse();
      case null:
        break;
    }
    _next?.cancel();
    _next = Timer(step.fade + step.hold, _step);
  }

  /// Показать вариант лица, перетекая из текущего за [fade].
  void _show(_Face face, Duration fade) {
    if (face == _face) return;
    setState(() {
      _under = _face;
      _face = face;
    });
    if (fade == Duration.zero) {
      _fade.value = 1;
    } else {
      _fade.duration = fade;
      _fade.forward(from: 0);
    }
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

          return Stack(
            children: [
              _headLayer(w, h),
              _place(BedroomScene.bear, w, h,
                  Image.asset('assets/rooms/bedroom/bear_paws.png',
                      fit: BoxFit.fill)),
              _place(BedroomScene.blanket, w, h, _blanketLayer()),
              _place(BedroomScene.glow, w, h, _glowLayer()),
            ],
          );
        },
      ),
    );
  }

  /// Голова: плечи дышат, лицо меняется, уши вздрагивают, засыпая —
  /// клюёт носом. Уши внутри головы, чтобы ходить вместе с ней.
  Widget _headLayer(double w, double h) {
    final box = BedroomScene.bear;
    final width = box.width * w;
    final height = box.height * h;

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _fade, _nodDrive]),
      builder: (context, ears) {
        final wave = _wave.value;
        final nod = _nod.value;

        return Positioned(
          left: box.left * w,
          top: box.top * h + height * BedroomScene.nodDrop * nod,
          width: width,
          height: height,
          // Всё от нижнего края: он под одеялом, и ему двигаться нельзя.
          child: Transform.rotate(
            angle: BedroomScene.nodTilt * nod,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scaleX: 1 + BedroomScene.shoulderSpread * wave,
              scaleY: 1 + BedroomScene.shoulderSwell * wave,
              alignment: Alignment.bottomCenter,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ears!,
                  // Нижний слой держит кадр целиком, верхний проступает
                  // сквозь него: так между вариантами не мелькает фон.
                  Image.asset(_under.asset, fit: BoxFit.fill),
                  Opacity(
                    opacity: _fade.value,
                    child: Image.asset(_face.asset, fit: BoxFit.fill),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ear(
            width,
            height,
            BedroomScene.earLeft,
            BedroomScene.earLeftRoot,
            _earLeftFlick,
            'assets/rooms/bedroom/ear_left.png',
            // Кончик левого уха — выше и левее корня: по часовой он идёт
            // вверх и внутрь. Правое зеркально — против часовой.
            BedroomScene.earTwitch,
          ),
          _ear(
            width,
            height,
            BedroomScene.earRight,
            BedroomScene.earRightRoot,
            _earRightFlick,
            'assets/rooms/bedroom/ear_right.png',
            -BedroomScene.earTwitch,
          ),
        ],
      ),
    );
  }

  /// Ухо на своём месте внутри слоя головы, крутится вокруг корня.
  ///
  /// [place] — доли кадра комнаты, как и у остальных слоёв; здесь они
  /// переводятся в точки внутри слоя головы размером [w] × [h].
  Widget _ear(double w, double h, Rect place, Alignment root,
      Animation<double> flick, String asset, double twitch) {
    final bear = BedroomScene.bear;
    return Positioned(
      left: (place.left - bear.left) / bear.width * w,
      top: (place.top - bear.top) / bear.height * h,
      width: place.width / bear.width * w,
      height: place.height / bear.height * h,
      child: AnimatedBuilder(
        animation: flick,
        builder: (context, child) => Transform.rotate(
          angle: twitch * flick.value,
          alignment: root,
          child: child,
        ),
        child: Image.asset(asset, fit: BoxFit.fill),
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
      return Image.asset('assets/rooms/bedroom/blanket_front.png',
          fit: BoxFit.fill);
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
      child: Image.asset('assets/rooms/bedroom/lamp_glow.png',
          fit: BoxFit.fill),
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
        positions.add(Offset(u * size.width, v * size.height - rise * bump * size.height));
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
