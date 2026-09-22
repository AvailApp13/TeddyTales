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
/// человек, и вот тут он дышит»; засыпать быстро — «2–3 раза, чтобы он
/// моргнул медленно, и как бы засыпал»; и веки — плавно, а не «покадрово».
///
/// По ТЗ аниматора это `act_sleep`: «укладывается, засыпает, сопит» — риг в
/// Rive. Позы «лёжа» в риге нет, и заказчик прислал спальню картинкой вместо
/// неё. Картинка разобрана на слои (`tool/cut_bedroom_layers.py`), и из них
/// здесь собрано то, что из `act_sleep` можно собрать без рига: сопение,
/// моргание, взгляд по сторонам, засыпание с покачиванием головы.
/// Укладывание и потягивание при пробуждении — уже только риг.
///
/// Слои снизу вверх: комната без мишки (фон комнаты, рисуется не здесь) →
/// уши → голова с лицом → лапы → передний край одеяла → свет ночника. Уши
/// за головой, чтобы дёргаться, не трогая капюшон. Лапы отдельно, чтобы
/// лежать на месте, пока голова клюёт носом. Одеяло поверх, чтобы низ
/// фигуры уходил под него — и чтобы дышать могло оно, а не мишка.
class BedroomScene extends StatefulWidget {
  const BedroomScene({super.key, this.asleep = false});

  /// Уложили спать: глаза закрыты и не открываются, круг засыпания не
  /// идёт. Дыхание и уши живут — спящий тоже дышит и прядёт ушами.
  /// Заказчик 22.09: «при нажатии её наш мишка должен закрыть глаза
  /// полностью».
  final bool asleep;

  /// Где лежит каждый слой — в долях кадра комнаты (941 × 1672).
  ///
  /// Числа печатает `tool/cut_bedroom_layers.py`: он же режет сами файлы,
  /// так что менять их вручную не надо — пересобрать и переписать.
  static const Rect bear = Rect.fromLTWH(0.381509, 0.412679, 0.238045, 0.157297);
  static const Rect earLeft = Rect.fromLTWH(0.385233, 0.464521, 0.057864, 0.036547);
  static const Rect earRight = Rect.fromLTWH(0.553382, 0.455505, 0.061874, 0.037835);
  static const Rect blanket = Rect.fromLTWH(0, 0.544258, 1, 0.310407);
  static const Rect glow = Rect.fromLTWH(0.420829, 0.199761, 0.579171, 0.459928);

  /// Зоны глаз — в долях слоя головы. По ним опускается веко.
  static const List<Rect> eyes = [
    Rect.fromLTWH(0.3225, 0.5834, 0.1324, 0.1024),
    Rect.fromLTWH(0.5764, 0.5589, 0.1324, 0.1024),
  ];

  /// Корень уха — где оно уходит под капюшон, в долях своего слоя.
  /// Вокруг него ухо и дёргается: у левого корень внизу справа, у правого
  /// внизу слева.
  static const Alignment earLeftRoot = Alignment(0.72, 0.74);
  static const Alignment earRightRoot = Alignment(-0.74, 0.78);

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

  /// Сколько мишка засыпает после «Уложить спать»: сумма шагов `_doze`.
  /// К этому моменту глаза закрыты — и можно показывать сон.
  static const Duration fallAsleep = Duration(milliseconds: 7500);

  /// Все картинки сцены.
  static const List<String> assets = [
    'assets/rooms/bedroom/bear_open.png',
    'assets/rooms/bedroom/bear_left.png',
    'assets/rooms/bedroom/bear_right.png',
    'assets/rooms/bedroom/bear_down.png',
    _closedAsset,
    'assets/rooms/bedroom/bear_paws.png',
    'assets/rooms/bedroom/ear_left.png',
    'assets/rooms/bedroom/ear_right.png',
    'assets/rooms/bedroom/blanket_front.png',
    'assets/rooms/bedroom/lamp_glow.png',
  ];

  /// Заранее раскодировать картинки — ещё до того, как открыли «Сон».
  ///
  /// Иначе при первом открытии голова появлялась на долю секунды позже
  /// ушей и лап: её картинки крупнее и декодируются дольше. А в версии 47
  /// от того же мишка «моргал» целиком: лицо переключалось на ещё не
  /// раскодированную картинку, и слой на миг пустел.
  static Future<void> warmUp(BuildContext context) => Future.wait([
        for (final asset in assets) precacheImage(AssetImage(asset), context),
      ]);

  @override
  State<BedroomScene> createState() => _BedroomSceneState();
}

/// Куда смотрит мишка. Картинки отличаются только глазами, и между ними
/// можно перетекать.
///
/// Веко — не вариант взгляда, а шторка: см. [_FacePainter]. Зевка в наборе
/// нет: без движения головы открытый рот не читался как зевок —
/// заказчик 22.09: «непонятно, что там происходит».
enum _Gaze {
  open('assets/rooms/bedroom/bear_open.png'),
  left('assets/rooms/bedroom/bear_left.png'),
  right('assets/rooms/bedroom/bear_right.png'),
  down('assets/rooms/bedroom/bear_down.png');

  const _Gaze(this.asset);

  final String asset;
}

/// Из этой картинки берётся веко — глаза здесь закрыты.
const String _closedAsset = 'assets/rooms/bedroom/bear_closed.png';

/// Один шаг сценария: за [move] перевести взгляд на [gaze] и/или веко в
/// положение [lid] (0 — открыто, 1 — закрыто), держать [hold] и, если
/// сказано, начать или прекратить клевать носом.
typedef _Step = ({
  _Gaze? gaze,
  double? lid,
  Curve curve,
  Duration move,
  Duration hold,
  bool? nod,
});

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

  /// Перетекание взгляда: 0 — ещё прежний, 1 — уже новый.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );

  /// Веко: 0 — глаза открыты, 1 — закрыты. Идёт непрерывно, потому и
  /// без кадров: заказчик 22.09 — «как будто покадрово, тык-тык-тык».
  late final AnimationController _lid = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
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

  /// Куда смотрит сейчас и откуда перетекаем.
  _Gaze _gaze = _Gaze.open;
  _Gaze _under = _Gaze.open;

  final math.Random _dice = math.Random();
  final Queue<_Step> _plan = Queue();
  Timer? _next;
  Timer? _earNext;

  /// Картинки лица и одеяла — как `ui.Image`: они рисуются не целиком.
  /// Лицо — со шторкой века по зонам глаз, одеяло — сеткой, чтобы дышал
  /// только его кусок над грудью.
  late final _Pictures _pictures = _Pictures(
    [
      for (final gaze in _Gaze.values) gaze.asset,
      _closedAsset,
      'assets/rooms/bedroom/blanket_front.png',
    ],
    onChange: () {
      if (mounted) setState(() {});
    },
  );

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  bool get _still => _stillSetting ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pictures.load(context);

    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда мишка просто лежит с открытыми глазами.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _next?.cancel();
      _earNext?.cancel();
      _plan.clear();
      for (final drive in [_breath, _lamp, _nodDrive, _earLeft, _earRight, _lid]) {
        drive.stop();
        drive.value = 0;
      }
      _lid.value = widget.asleep ? 1 : 0;
      _look(_Gaze.open, Duration.zero);
    } else {
      _breath.repeat();
      _lamp.repeat(reverse: true);
      if (widget.asleep) {
        _lid.value = 1;
      } else {
        _rest();
      }
      _earRest();
    }
  }

  @override
  void didUpdateWidget(BedroomScene old) {
    super.didUpdateWidget(old);
    if (old.asleep == widget.asleep) return;
    _next?.cancel();
    _plan.clear();
    if (_still) {
      _lid.value = widget.asleep ? 1 : 0;
      _look(_Gaze.open, Duration.zero);
      return;
    }
    if (widget.asleep) {
      _doze();
    } else {
      // Проснулся: глаза открыл быстро, голову поднял, дальше — как днём.
      _lid.animateTo(0,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      _nodDrive.reverse();
      _look(_Gaze.open, const Duration(milliseconds: 200));
      _rest();
    }
  }

  /// Уложили: засыпает по-настоящему — два медленных моргания, взгляд
  /// вниз, голова клюёт носом, и глаза закрываются насовсем.
  ///
  /// Времена здесь без разброса: ровно через [BedroomScene.fallAsleep]
  /// глаза закрыты, и облако мыслей над головой ждёт именно этого.
  void _doze() {
    _plan.addAll([
      _go(lid: 1, move: _ms(600), hold: _ms(350)),
      _go(lid: 0, move: _ms(640), hold: _ms(900)),
      _go(gaze: _Gaze.down, lid: 0.15, move: _ms(380), hold: _ms(500)),
      _go(lid: 1, move: _ms(900), hold: _ms(500), nod: true),
      _go(lid: 0.55, move: _ms(900), hold: _ms(700)),
      _go(lid: 1, move: _ms(1100)),
    ]);
    _step();
  }

  @override
  void dispose() {
    _next?.cancel();
    _earNext?.cancel();
    _pictures.dispose();
    _breath.dispose();
    _lamp.dispose();
    _fade.dispose();
    _lid.dispose();
    _nodDrive.dispose();
    _earLeft.dispose();
    _earRight.dispose();
    super.dispose();
  }

  Duration _ms(int base, [int spread = 0]) =>
      Duration(milliseconds: base + (spread == 0 ? 0 : _dice.nextInt(spread)));

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

  /// Полежать с открытыми глазами, потом — что-нибудь сделать.
  ///
  /// Паузы нарочно неровные: ровный интервал глаз ловит сразу и читает как
  /// мигающую лампочку, а не как живое существо.
  void _rest() {
    _next?.cancel();
    _next = Timer(_ms(2200, 1800), _act);
  }

  _Step _go({
    _Gaze? gaze,
    double? lid,
    Curve curve = Curves.easeInOutSine,
    required Duration move,
    Duration hold = Duration.zero,
    bool? nod,
  }) =>
      (gaze: gaze, lid: lid, curve: curve, move: move, hold: hold, nod: nod);

  /// Один круг бодрствования: моргнул, иногда дважды, иногда огляделся.
  ///
  /// Заказчик 22.09: пока не уложили, «просто открытые глаза, моргание,
  /// ушки и дыхание». Засыпание — только по кнопке, см. [_doze].
  void _act() {
    if (!mounted || _still || widget.asleep) return;

    // Обычное моргание: веко падает быстро, поднимается чуть медленнее.
    // Иногда двойное — так моргают живые, а не заведённые.
    final twice = _dice.nextInt(4) == 0;
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      _plan.addAll([
        _go(lid: 1, move: _ms(90), hold: _ms(50, 50), curve: Curves.easeIn),
        _go(
          lid: 0,
          move: _ms(170),
          hold: i == 0 && twice ? _ms(120, 80) : _ms(1600, 1400),
          curve: Curves.easeOut,
        ),
      ]);
    }

    // Посмотрел в сторону — что там? — и обратно. В какую, решает жребий:
    // одна и та же сторона каждый круг выдаёт запись. Не каждый круг:
    // постоянно бегающий взгляд читается как тревога.
    if (_dice.nextBool()) {
      _plan.addAll([
        _go(
          gaze: _dice.nextBool() ? _Gaze.left : _Gaze.right,
          move: _ms(170),
          hold: _ms(900, 700),
        ),
        _go(gaze: _Gaze.open, move: _ms(200), hold: _ms(600, 500)),
      ]);
    }
    _step();
  }

  /// Выполнить следующий шаг сценария; когда он кончился — отдыхать.
  /// Уснувшему отдыхать нечего: последний шаг [_doze] закрыл глаза.
  void _step() {
    if (!mounted || _still) return;
    if (_plan.isEmpty) {
      if (!widget.asleep) _rest();
      return;
    }
    final step = _plan.removeFirst();
    if (step.gaze != null) _look(step.gaze!, step.move);
    if (step.lid != null) {
      _lid.animateTo(step.lid!, duration: step.move, curve: step.curve);
    }
    switch (step.nod) {
      case true:
        _nodDrive.forward();
      case false:
        _nodDrive.reverse();
      case null:
        break;
    }
    _next?.cancel();
    _next = Timer(step.move + step.hold, _step);
  }

  /// Перевести взгляд, перетекая из текущего за [fade].
  void _look(_Gaze gaze, Duration fade) {
    if (gaze == _gaze) return;
    setState(() {
      _under = _gaze;
      _gaze = gaze;
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

  /// Голова: плечи дышат, взгляд и веки живут, уши вздрагивают, засыпая —
  /// клюёт носом. Уши внутри головы, чтобы ходить вместе с ней.
  Widget _headLayer(double w, double h) {
    final box = BedroomScene.bear;
    final width = box.width * w;
    final height = box.height * h;

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _fade, _lid, _nodDrive]),
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
                  _face(),
                ],
              ),
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Под каждым ухом — его же неподвижная копия. В голове на месте
          // уха дыра, и когда ухо вздрагивает, с одной стороны она
          // открывалась бы до комнаты. Копия закрывает её ворсом.
          _ear(width, height, BedroomScene.earLeft, 'assets/rooms/bedroom/ear_left.png'),
          _ear(width, height, BedroomScene.earRight, 'assets/rooms/bedroom/ear_right.png'),
          _ear(
            width,
            height,
            BedroomScene.earLeft,
            'assets/rooms/bedroom/ear_left.png',
            root: BedroomScene.earLeftRoot,
            flick: _earLeftFlick,
            // Кончик левого уха — выше и левее корня: по часовой он идёт
            // вверх и внутрь. Правое зеркально — против часовой.
            twitch: BedroomScene.earTwitch,
          ),
          _ear(
            width,
            height,
            BedroomScene.earRight,
            'assets/rooms/bedroom/ear_right.png',
            root: BedroomScene.earRightRoot,
            flick: _earRightFlick,
            twitch: -BedroomScene.earTwitch,
          ),
        ],
      ),
    );
  }

  /// Лицо: взгляд, перетекающий из прежнего, и веко-шторка поверх.
  ///
  /// Пока картинки не загрузились — просто открытые глаза: секунда без
  /// моргания незаметна, а пустое место на подушке — нет.
  Widget _face() {
    final under = _pictures[_under.asset];
    final face = _pictures[_gaze.asset];
    final closed = _pictures[_closedAsset];
    if (under == null || face == null || closed == null) {
      return Image.asset(_Gaze.open.asset, fit: BoxFit.fill);
    }
    return CustomPaint(
      painter: _FacePainter(
        under: under,
        face: face,
        blend: _fade.value,
        closed: closed,
        lid: _lid.value,
      ),
    );
  }

  /// Ухо на своём месте внутри слоя головы; с [flick] крутится вокруг
  /// корня [root], без него лежит.
  ///
  /// [place] — доли кадра комнаты, как и у остальных слоёв; здесь они
  /// переводятся в точки внутри слоя головы размером [w] × [h].
  Widget _ear(
    double w,
    double h,
    Rect place,
    String asset, {
    Alignment root = Alignment.center,
    Animation<double>? flick,
    double twitch = 0,
  }) {
    final bear = BedroomScene.bear;
    final image = Image.asset(asset, fit: BoxFit.fill);
    return Positioned(
      left: (place.left - bear.left) / bear.width * w,
      top: (place.top - bear.top) / bear.height * h,
      width: place.width / bear.width * w,
      height: place.height / bear.height * h,
      child: flick == null
          ? image
          : AnimatedBuilder(
              animation: flick,
              builder: (context, child) => Transform.rotate(
                angle: twitch * flick.value,
                alignment: root,
                child: child,
              ),
              child: image,
            ),
    );
  }

  /// Одеяло: приподнимается на вдохе — но только над грудью.
  ///
  /// Пока картинка не загрузилась, лежит как есть: секунда без дыхания
  /// незаметна, а пустое место на кровати — нет.
  Widget _blanketLayer() {
    final image = _pictures['assets/rooms/bedroom/blanket_front.png'];
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

/// Картинки из ассетов в виде `ui.Image` — для тех слоёв, что рисуются
/// не целиком. Грузятся раз, живут, пока жив экран.
class _Pictures {
  _Pictures(this.assets, {required this.onChange});

  final List<String> assets;
  final VoidCallback onChange;

  final Map<String, ui.Image> _images = {};
  final Map<String, (ImageStream, ImageStreamListener)> _streams = {};

  ui.Image? operator [](String asset) => _images[asset];

  void load(BuildContext context) {
    final configuration = createLocalImageConfiguration(context);
    for (final asset in assets) {
      final stream = AssetImage(asset).resolve(configuration);
      if (stream.key == _streams[asset]?.$1.key) continue;
      _drop(asset);
      final listener = ImageStreamListener((info, _) {
        _images[asset] = info.image;
        onChange();
      });
      stream.addListener(listener);
      _streams[asset] = (stream, listener);
    }
  }

  void _drop(String asset) {
    final entry = _streams.remove(asset);
    if (entry != null) entry.$1.removeListener(entry.$2);
  }

  void dispose() {
    for (final asset in assets) {
      _drop(asset);
    }
  }
}

/// Лицо мишки: взгляд и веко.
///
/// Взгляд — две картинки, отличающиеся только глазами: нижняя целиком,
/// верхняя проступает на [blend]. Веко — шторка: над каждым глазом зона из
/// картинки с закрытыми глазами, открытая сверху вниз на [lid] с мягким
/// краем. Так веко опускается непрерывно, а не тремя кадрами: заказчик
/// 22.09 — «не плавно они закрываются».
class _FacePainter extends CustomPainter {
  const _FacePainter({
    required this.under,
    required this.face,
    required this.blend,
    required this.closed,
    required this.lid,
  });

  final ui.Image under;
  final ui.Image face;
  final double blend;
  final ui.Image closed;
  final double lid;

  /// Где в зоне глаза веко начинает и заканчивает путь — в долях высоты
  /// зоны: сам глаз занимает её середину, а не всю.
  static const double lidFrom = 0.06;
  static const double lidTo = 0.96;

  /// Ширина мягкого края века — в долях высоты зоны.
  static const double lidFeather = 0.14;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;

    canvas.drawImageRect(under, _whole(under), dst, paint);
    if (blend > 0 && face != under) {
      canvas.drawImageRect(face, _whole(face), dst,
          paint..color = Color.fromRGBO(0, 0, 0, blend.clamp(0, 1)));
    }
    if (lid <= 0) return;

    for (final eye in BedroomScene.eyes) {
      final zone = Rect.fromLTWH(eye.left * size.width, eye.top * size.height,
          eye.width * size.width, eye.height * size.height);
      final source = Rect.fromLTWH(
          eye.left * closed.width,
          eye.top * closed.height,
          eye.width * closed.width,
          eye.height * closed.height);
      final edge = zone.top + zone.height * (lidFrom + (lidTo - lidFrom) * lid);
      final feather = zone.height * lidFeather;

      canvas.saveLayer(zone, Paint());
      canvas.drawImageRect(closed, source, zone,
          Paint()..filterQuality = FilterQuality.medium);
      canvas.drawRect(
        zone,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(zone.left, edge - feather),
            Offset(zone.left, edge + feather),
            const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ),
      );
      canvas.restore();
    }
  }

  Rect _whole(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.under != under ||
      old.face != face ||
      old.blend != blend ||
      old.closed != closed ||
      old.lid != lid;
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
