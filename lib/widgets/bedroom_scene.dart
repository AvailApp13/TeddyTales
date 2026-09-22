import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Живые слои спальни: мишка дышит, моргает и зевает под одеялом.
///
/// Заказчик 21.09: «можем ли мы во вкладке сон, где мишка в кровати лежит,
/// сделать анимацию дыхания и моргания глаз, будто он хочет спать».
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

  /// Вдох-выдох. Четыре секунды на полный цикл — темп спящего ребёнка;
  /// на взрослых трёх секундах мишка выглядит встревоженным.
  static const Duration breath = Duration(milliseconds: 4200);

  /// Насколько мишка ходит вверх-вниз — в долях собственной высоты.
  /// Больше двух процентов уже читается как подпрыгивание.
  static const double breathLift = 0.022;

  /// Ночник дышит своим темпом: совпади он с мишкой, комната начала бы
  /// пульсировать целиком.
  static const Duration lampBreath = Duration(milliseconds: 5500);

  /// Переход между вариантами лица. Меньше ста миллисекунд — щелчок,
  /// больше двухсот — мишка «жмурится» вместо того, чтобы моргнуть.
  static const Duration faceFade = Duration(milliseconds: 140);

  @override
  State<BedroomScene> createState() => _BedroomSceneState();
}

/// Какой вариант лица показан сейчас.
enum _Face {
  half('assets/rooms/bedroom/bear_half.png'),
  closed('assets/rooms/bedroom/bear_closed.png'),
  yawn('assets/rooms/bedroom/bear_yawn.png');

  const _Face(this.asset);

  final String asset;
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

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: BedroomScene.faceFade,
    value: 1,
  );

  /// Спящий мишка большую часть времени с полуприкрытыми глазами: это и
  /// есть «хочет спать». Закрытые и зевок — короткие гости.
  _Face _face = _Face.half;
  _Face _under = _Face.half;

  final math.Random _dice = math.Random();
  Timer? _next;

  /// Сколько морганий прошло с прошлого зевка. Зевать каждые пять секунд
  /// мишка не должен — это читается как тик.
  int _blinks = 0;

  /// `null`, пока настройку ещё не читали: иначе первый заход совпал бы
  /// со значением по умолчанию и анимации не запустились бы вовсе.
  bool? _stillSetting;

  bool get _still => _stillSetting ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Системная настройка «убрать анимацию» — для тех, кому от движения
    // на экране плохо. Тогда мишка просто лежит с полуприкрытыми глазами.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _next?.cancel();
      _breath.stop();
      _lamp.stop();
      _breath.value = 0;
      _lamp.value = 0;
      _show(_Face.half);
    } else {
      _breath.repeat(reverse: true);
      _lamp.repeat(reverse: true);
      _schedule();
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

  /// Назначить следующее событие лица.
  ///
  /// Паузы нарочно неровные: ровный интервал глаз ловит сразу и читает как
  /// мигающую лампочку, а не как живое существо.
  void _schedule() {
    _next?.cancel();
    final pause = 2400 + _dice.nextInt(3000);
    _next = Timer(Duration(milliseconds: pause), _blinkOrYawn);
  }

  void _blinkOrYawn() {
    if (!mounted || _still) return;

    // Зевок — раз в пять-восемь морганий, то есть примерно раз в полминуты.
    final yawning = _blinks >= 5 && _dice.nextInt(3) == 0;
    _blinks = yawning ? 0 : _blinks + 1;

    _show(yawning ? _Face.yawn : _Face.closed);
    final hold = yawning ? 1400 : 260 + _dice.nextInt(200);
    _next = Timer(Duration(milliseconds: hold), () {
      if (!mounted || _still) return;
      _show(_Face.half);
      _schedule();
    });
  }

  /// Показать вариант лица, мягко перетекая из текущего.
  void _show(_Face face) {
    if (face == _face) return;
    setState(() {
      _under = _face;
      _face = face;
    });
    if (_still) {
      _fade.value = 1;
    } else {
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
        // Вдох — плавный подъём и еле заметное «раздувание» вверх от
        // одеяла. Низ остаётся на месте: он и так спрятан под одеялом.
        final wave = Curves.easeInOutSine.transform(_breath.value);
        final lift = -height * BedroomScene.breathLift * wave;

        return Positioned(
          left: box.left * w,
          top: box.top * h + lift,
          width: box.width * w,
          height: height,
          child: Transform.scale(
            scaleY: 1 + 0.006 * wave,
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
