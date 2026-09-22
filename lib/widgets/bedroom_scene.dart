import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Живые слои спальни: мишка сопит, моргает и засыпает под одеялом.
///
/// Заказчик 21.09: «во вкладке сон, где мишка в кровати лежит, сделать
/// анимацию дыхания и моргания глаз, будто он хочет спать». 22.09, после
/// первой версии: «у него должно быть открыто, и он должен моргать. Это
/// эффект, когда человек как будто бы засыпает». И после второй: «дыхание
/// очень сильное, как будто подпрыгивает его тело» — то есть дышать должно
/// одеяло и плечи, а не голова.
///
/// По ТЗ аниматора это `act_sleep`: «укладывается, засыпает, сопит» — риг в
/// Rive. Позы «лёжа» в риге нет, и заказчик прислал спальню картинкой вместо
/// неё. Картинка разобрана на слои (`tool/cut_bedroom_layers.py`), и из них
/// здесь собрано то, что из `act_sleep` можно собрать без рига: сопение,
/// моргание, засыпание с покачиванием головы. Укладывание и потягивание при
/// пробуждении — уже только риг.
///
/// Слои снизу вверх: комната без мишки (фон комнаты, рисуется не здесь) →
/// голова с лицом → лапы → передний край одеяла → свет ночника. Лапы отдельно,
/// чтобы лежать на месте, пока голова клюёт носом. Одеяло поверх, чтобы низ
/// фигуры уходил под него.
class BedroomScene extends StatefulWidget {
  const BedroomScene({super.key});

  /// Где лежит каждый слой — в долях кадра комнаты (941 × 1672).
  ///
  /// Числа печатает `tool/cut_bedroom_layers.py`: он же режет сами файлы,
  /// так что менять их вручную не надо — пересобрать и переписать.
  static const Rect bear = Rect.fromLTWH(0.376196, 0.412679, 0.248672, 0.157297);
  static const Rect blanket = Rect.fromLTWH(0, 0.544258, 1, 0.310407);
  static const Rect glow = Rect.fromLTWH(0.420829, 0.199761, 0.579171, 0.459928);

  /// Вдох-выдох. Четыре с небольшим секунды на цикл — темп спящего
  /// ребёнка; на взрослых трёх секундах мишка выглядит встревоженным.
  static const Duration breath = Duration(milliseconds: 4400);

  /// Дыхание — это одеяло и плечи, не голова. Одеяло приподнимается от
  /// нижнего края, плечи чуть расширяются, макушка ходит на волосок.
  /// Заказчик 22.09: при подъёме всей фигуры «как будто подпрыгивает».
  static const double blanketRise = 0.010;
  static const double shoulderSwell = 0.014;
  static const double shoulderSpread = 0.006;

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
enum _Face {
  open('assets/rooms/bedroom/bear_open.png'),
  half('assets/rooms/bedroom/bear_half.png'),
  closed('assets/rooms/bedroom/bear_closed.png'),
  yawn('assets/rooms/bedroom/bear_yawn.png');

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
    duration: const Duration(milliseconds: 3600),
    reverseDuration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _nod = CurvedAnimation(
    parent: _nodDrive,
    curve: Curves.easeInOutSine,
    reverseCurve: Curves.easeOutBack,
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

  /// Сколько морганий прошло с последнего засыпания: задремать он должен
  /// после нескольких, а не с первого.
  int _blinks = 0;

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  bool get _still => _stillSetting ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда мишка просто лежит с открытыми глазами.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _next?.cancel();
      _plan.clear();
      _breath.stop();
      _lamp.stop();
      _nodDrive.stop();
      _breath.value = 0;
      _lamp.value = 0;
      _nodDrive.value = 0;
      _show(_Face.open, Duration.zero);
    } else {
      _breath.repeat();
      _lamp.repeat(reverse: true);
      _rest();
    }
  }

  @override
  void dispose() {
    _next?.cancel();
    _breath.dispose();
    _lamp.dispose();
    _fade.dispose();
    _nodDrive.dispose();
    super.dispose();
  }

  Duration _ms(int base, [int spread = 0]) =>
      Duration(milliseconds: base + (spread == 0 ? 0 : _dice.nextInt(spread)));

  /// Полежать с открытыми глазами, потом — что-нибудь сделать.
  ///
  /// Паузы нарочно неровные: ровный интервал глаз ловит сразу и читает как
  /// мигающую лампочку, а не как живое существо.
  void _rest() {
    _next?.cancel();
    _next = Timer(_ms(2000, 2600), _act);
  }

  /// Моргнуть — или, если моргал уже достаточно, начать засыпать.
  void _act() {
    if (!mounted || _still) return;

    final drowsy = _blinks >= 3 && _dice.nextInt(3) == 0;
    if (!drowsy) {
      _blinks++;
      // Моргание в три фазы через полуприкрытые: щелчок «открыто-закрыто»
      // без промежуточного кадра выглядит как сбой картинки.
      _plan.addAll([
        (face: _Face.half, fade: _ms(55), hold: Duration.zero, nod: null),
        (face: _Face.closed, fade: _ms(55), hold: _ms(90, 60), nod: null),
        (face: _Face.half, fade: _ms(70), hold: Duration.zero, nod: null),
        (face: _Face.open, fade: _ms(110), hold: Duration.zero, nod: null),
      ]);
    } else {
      _blinks = 0;
      // Засыпание: веки тяжелеют, голова клюёт носом, глаза закрываются —
      // и через несколько секунд он спохватывается. Перед этим иногда
      // зевок.
      if (_dice.nextBool()) {
        _plan.add((face: _Face.yawn, fade: _ms(220), hold: _ms(1300, 300), nod: null));
      }
      _plan.addAll([
        (face: _Face.half, fade: _ms(700), hold: _ms(1400, 1200), nod: true),
        (face: _Face.closed, fade: _ms(900), hold: _ms(2600, 2400), nod: null),
        (face: _Face.open, fade: _ms(260), hold: Duration.zero, nod: false),
      ]);
    }
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

  /// Голова: плечи дышат, лицо меняется, засыпая — клюёт носом.
  Widget _headLayer(double w, double h) {
    final box = BedroomScene.bear;
    final height = box.height * h;

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _fade, _nodDrive]),
      builder: (context, _) {
        final wave = _wave.value;
        final nod = _nod.value;

        return Positioned(
          left: box.left * w,
          top: box.top * h + height * BedroomScene.nodDrop * nod,
          width: box.width * w,
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
    );
  }

  /// Одеяло приподнимается на вдохе — это и есть то, что видно у спящего.
  Widget _blanketLayer() {
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, child) => Transform.scale(
        scaleY: 1 + BedroomScene.blanketRise * _wave.value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Image.asset('assets/rooms/bedroom/blanket_front.png',
          fit: BoxFit.fill),
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
