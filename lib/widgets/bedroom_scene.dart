import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Живые слои спальни: мишка дышит, моргает и засыпает под одеялом.
///
/// Заказчик 21.09: «во вкладке сон, где мишка в кровати лежит, сделать
/// анимацию дыхания и моргания глаз, будто он хочет спать». И 22.09, после
/// первой версии: «у него должно быть открыто, и он должен моргать. Это
/// эффект, когда человек как будто бы засыпает» — то есть основное
/// состояние с открытыми глазами, а прикрытые и закрытые — эпизоды.
///
/// Раньше это было нечем сделать: спальню прислали одной плоской картинкой,
/// мишка был впечатан в фон вместе с подушками. Теперь картинка разобрана на
/// слои (`tool/cut_bedroom_layers.py`), и мишка — отдельный файл, который
/// можно двигать и подменять.
///
/// Слои складываются снизу вверх: комната без мишки (это фон комнаты,
/// рисуется не здесь) → мишка → передний край одеяла → свет ночника. Одеяло
/// поверх мишки нужно именно для дыхания: его низ уходит под одеяло, а не
/// болтается над ним.
///
/// Живой риг (`BearView`) сюда не ставится: поза «лёжа под одеялом» в риге
/// не собрана, и заказчик прислал спальню как раз вместо неё.
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

  /// Насколько мишка ходит вверх-вниз — в долях собственной высоты, и
  /// насколько раздувается грудью. Заказчик 22.09 попросил заметнее: «чтобы
  /// видно было, что он дышит грудью». Больше этого уже читается как
  /// подпрыгивание.
  static const double breathLift = 0.032;
  static const double breathSwell = 0.022;

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

/// Один шаг сценария: показать лицо, перетекая к нему за [fade], и держать
/// его [hold], прежде чем идти дальше.
typedef _Step = ({_Face face, Duration fade, Duration hold});

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
      _breath.value = 0;
      _lamp.value = 0;
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
      // Моргание: быстро закрыть, чуть медленнее открыть.
      _plan.addAll([
        (face: _Face.closed, fade: _ms(80), hold: _ms(110, 60)),
        (face: _Face.open, fade: _ms(120), hold: Duration.zero),
      ]);
    } else {
      _blinks = 0;
      // Засыпание: веки тяжелеют, глаза закрываются, и через несколько
      // секунд он спохватывается и открывает их снова. Перед этим —
      // иногда зевок.
      if (_dice.nextBool()) {
        _plan.add((face: _Face.yawn, fade: _ms(220), hold: _ms(1300, 300)));
      }
      _plan.addAll([
        (face: _Face.half, fade: _ms(700), hold: _ms(1400, 1200)),
        (face: _Face.closed, fade: _ms(900), hold: _ms(2600, 2400)),
        (face: _Face.open, fade: _ms(260), hold: Duration.zero),
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
              _bearLayer(w, h),
              _place(BedroomScene.blanket, w, h,
                  Image.asset('assets/rooms/bedroom/blanket_front.png',
                      fit: BoxFit.fill)),
              _place(BedroomScene.glow, w, h, _glowLayer()),
            ],
          );
        },
      ),
    );
  }

  /// Мишка: дышит и меняет лицо.
  Widget _bearLayer(double w, double h) {
    final box = BedroomScene.bear;
    final height = box.height * h;

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _fade]),
      builder: (context, _) {
        // Вдох — подъём и раздувание груди вверх и в стороны от одеяла.
        // Низ остаётся на месте: он и так спрятан под одеялом.
        final wave = _wave.value;
        final lift = -height * BedroomScene.breathLift * wave;
        final swell = BedroomScene.breathSwell * wave;

        return Positioned(
          left: box.left * w,
          top: box.top * h + lift,
          width: box.width * w,
          height: height,
          child: Transform.scale(
            scaleX: 1 + swell * 0.45,
            scaleY: 1 + swell,
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
        );
      },
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
