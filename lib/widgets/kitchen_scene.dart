import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

import '../game/room_kind.dart';
import '../theme/app_colors.dart';

/// Что мишка только что съел — и как ему это.
///
/// Реакция по ТЗ (раздел 7.4): характер задаёт предпочтения в еде, и
/// эмоция после еды — из четырёх `emo_*` стадий 4–5. Пока правило простое:
/// любимое блюдо — нежность, приготовленное своими лапами — удивление и
/// радость, остальное — радость.
enum KitchenMood { happy, love, surprise }

/// Одна еда. [id] растёт с каждым кормлением: по нему сцена понимает, что
/// пришла новая, даже если настроение то же.
class KitchenMeal {
  const KitchenMeal({required this.id, required this.mood});

  final int id;
  final KitchenMood mood;
}

/// Живая кухня: мишка за столом дышит, моргает, оглядывается, прядёт
/// ушами, а когда его покормили — ест и радуется.
///
/// Собрана по памятке спальни (`docs/living-scene.md`), но не из целой
/// картинки, а из частей: заказчик 22.09 — «разбил по частям, чтобы
/// анимировать разные части, как ноги, верхние лапы». Части вырезал GPT из
/// исходной кухни по `docs/kitchen-brief.pdf`, ассеты режет
/// `tool/cut_kitchen_parts.py`, он же печатает доли кадра ниже.
///
/// Слои снизу вверх: комната без мишки (фон, рисуется не здесь) → ножки
/// под столом → край стола и скатерть (кусок фона поверх ножек) →
/// неподвижные копии ушей (доборы) → уши → лапы → рукава → туловище →
/// голова → глаза и рот спрайтами. Глаза и рот
/// не нарисованы на голове, а кладутся сверху: так любая пара глаз
/// сочетается с любым ртом — ТЗ аниматора, раздел 5.9.
class KitchenScene extends StatefulWidget {
  const KitchenScene({super.key, this.meal, this.hungry = false});

  /// Последнее кормление. Новое — мишка ест и показывает эмоцию.
  final KitchenMeal? meal;

  /// Показатель «Еда» низкий: покой `idle_hungry` — иногда грустит.
  final bool hungry;

  // --- Где лежит каждая часть — в долях кадра комнаты 941 × 1672. -------
  // Числа печатает tool/cut_kitchen_parts.py: он же режет файлы.
  // Ножки подняты на 0.012 против нарезки: круглая подушка заходит под
  // скатерть (низ скатерти 0.760) на 10 px кадра, иначе висят, «как
  // будто ни к чему не привязаны», а при качании у скатерти проблески
  // (заказчик 23.09). Припуск сверху уходит под слой стола.
  static const Rect footLeft = Rect.fromLTWH(
    0.361111,
    0.739953,
    0.115741,
    0.050781,
  );
  static const Rect footRight = Rect.fromLTWH(
    0.503472,
    0.739953,
    0.116898,
    0.052083,
  );
  static const Rect earLeft = Rect.fromLTWH(
    0.348380,
    0.444010,
    0.079861,
    0.065104,
  );
  static const Rect earRight = Rect.fromLTWH(
    0.567130,
    0.445312,
    0.079861,
    0.063802,
  );
  static const Rect pawLeft = Rect.fromLTWH(
    0.335648,
    0.579427,
    0.092593,
    0.037760,
  );
  static const Rect pawRight = Rect.fromLTWH(
    0.562500,
    0.579427,
    0.086806,
    0.037760,
  );
  static const Rect sleeveLeft = Rect.fromLTWH(
    0.340278,
    0.554688,
    0.096065,
    0.052734,
  );
  static const Rect sleeveRight = Rect.fromLTWH(
    0.554398,
    0.554688,
    0.091435,
    0.050130,
  );
  static const Rect torso = Rect.fromLTWH(
    0.406250,
    0.541016,
    0.178241,
    0.067057,
  );
  static const Rect head = Rect.fromLTWH(
    0.357639,
    0.382161,
    0.275463,
    0.185547,
  );
  static const Rect eyes = Rect.fromLTWH(
    0.430556,
    0.505208,
    0.129630,
    0.033854,
  );
  static const Rect mouth = Rect.fromLTWH(
    0.458333,
    0.536458,
    0.071759,
    0.023438,
  );

  /// Край стола со скатертью: кусок фона, положенный поверх ножек, чтобы
  /// их припуск уходил под стол. От кромки стола до низа скатерти
  /// (скатерть на фоне кончается на 0.760; слой чуть ниже, иначе шов
  /// припуска ножек торчал под скатертью — заказчик 23.09).
  static const Rect tableFront = Rect.fromLTWH(0, 0.6065, 1, 0.1565);

  // --- Оси, вокруг которых части крутятся — в долях кадра. ---------------
  static const Offset neck = Offset(0.50053, 0.56220);

  /// Плечевой сустав — у края туловища, под рукавом, а не на внешнем краю
  /// плеча: рука висит на теле, и крутиться должна оттуда, где к нему
  /// пришита. Иначе рукав отрывается от туловища и торчит лопастью.
  static const Offset shoulderLeft = Offset(0.4150, 0.5760);
  static const Offset shoulderRight = Offset(0.5860, 0.5760);
  static const Offset wristLeft = Offset(0.3850, 0.5930);
  static const Offset wristRight = Offset(0.6200, 0.5930);

  /// Ось сгиба уха: от корня под капюшоном к вершине у края капюшона.
  /// Заказчик 22.09 нарисовал её сам: ухо гнётся вдоль неё, как стебель.
  static const Offset earLeftRoot = Offset(0.36238, 0.50658);
  static const Offset earLeftTip = Offset(0.41764, 0.44737);
  static const Offset earRightRoot = Offset(0.63868, 0.50658);
  static const Offset earRightTip = Offset(0.58342, 0.44737);

  /// На сколько ухо гнётся при вздрагивании — радианы у вершины.
  static const double earTwitch = 0.18;

  /// Дыхание — тот же темп, что в спальне: заказчик просил один ритм.
  static const Duration breath = Duration(milliseconds: 4400);
  static const double chestSwell = 0.012;

  /// Наклон головы вперёд, к столу: в плоской картинке это в основном
  /// опускание (доля высоты головы) и лёгкое сжатие, чуть-чуть поворота.
  /// Вбок — радианы.
  static const double bowTilt = 0.04;

  /// Кивок к столу — наклон, а не сползание: макушка идёт вниз и вперёд
  /// (голова сжимается по высоте от шеи на [bowSquash]), сама голова
  /// опускается лишь на [bowDrop], а мордочка — глаза, нос, рот — съезжает
  /// вниз по голове на [bowFace], как у настоящего кивка. Туловище чуть
  /// подаётся вперёд на [bowLean]. Заказчик 22.09: «будто часть головы
  /// просто шатается».
  static const double bowDrop = 0.05;
  static const double bowSquash = 0.11;
  static const double bowFace = 0.04;
  static const double bowLean = 0.03;
  static const double sideTilt = 0.05;

  /// Руки остаются на столе (заказчик 22.09): рукав чуть приподнимается
  /// в плече, лапа похлопывает от запястья. Радианы. Ест он, наклоняясь
  /// к столу, как из миски (ТЗ: `act_eat` из миски).
  static const double armLift = 0.16;
  static const double wristBend = 0.16;

  /// Голова еле заметно ходит с дыханием — радианы. Без этого мишка
  /// между морганиями стоит как фотография.
  static const double breathSway = 0.006;

  /// Ножки под столом качаются от колена под кромкой стола.
  static const double footSwing = 0.16;

  static const String _dir = 'assets/rooms/kitchen';

  /// Все картинки сцены.
  static final List<String> assets = [
    '$_dir/foot_left.png',
    '$_dir/foot_right.png',
    '$_dir/ear_left.png',
    '$_dir/ear_right.png',
    '$_dir/paw_left.png',
    '$_dir/paw_right.png',
    '$_dir/sleeve_left.png',
    '$_dir/sleeve_right.png',
    '$_dir/torso.png',
    '$_dir/head.png',
    for (final e in _Eyes.values) e.asset,
    for (final m in _Mouth.values) m.asset,
  ];

  /// Заранее раскодировать картинки — ещё до того, как открыли кухню:
  /// иначе мишка появляется по частям.
  static Future<void> warmUp(BuildContext context) => Future.wait([
    for (final asset in assets) precacheImage(AssetImage(asset), context),
  ]);

  @override
  State<KitchenScene> createState() => _KitchenSceneState();
}

/// Пары глаз-бусин: спрайты на одном месте, подменяются целиком.
enum _Eyes {
  open('${KitchenScene._dir}/eyes_open.png'),
  closed('${KitchenScene._dir}/eyes_closed.png'),
  happy('${KitchenScene._dir}/eyes_happy.png'),
  sad('${KitchenScene._dir}/eyes_sad.png'),
  wide('${KitchenScene._dir}/eyes_wide.png');

  const _Eyes(this.asset);

  final String asset;
}

/// Вышитые рты — так же.
enum _Mouth {
  neutral('${KitchenScene._dir}/mouth_neutral.png'),
  open('${KitchenScene._dir}/mouth_open.png'),
  chew('${KitchenScene._dir}/mouth_chew.png'),
  smile('${KitchenScene._dir}/mouth_smile.png'),
  sad('${KitchenScene._dir}/mouth_sad.png'),
  o('${KitchenScene._dir}/mouth_o.png');

  const _Mouth(this.asset);

  final String asset;
}

class _KitchenSceneState extends State<KitchenScene>
    with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: KitchenScene.breath,
  );

  /// Вдох короче выдоха — как в спальне.
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

  /// Голова: наклон вперёд 0…1, наклон вбок −1…1 (через 0.5 = прямо).
  late final AnimationController _bow = _drive(lowerBound: -1);
  late final AnimationController _side = _drive(value: 0.5);

  /// Руки: подъём рукава 0…1 и доворот лапы 0…1; по одной на сторону.
  late final AnimationController _armLeft = _drive();
  late final AnimationController _armRight = _drive();
  late final AnimationController _pawLeft = _drive();
  late final AnimationController _pawRight = _drive();

  /// Уши: сгиб −1…1 через 0.5 = прямо. Плюс — к макушке, минус — вниз.
  late final AnimationController _earLeft = _drive(value: 0.5);
  late final AnimationController _earRight = _drive(value: 0.5);

  /// Ножки: качание −1…1 через 0.5.
  late final AnimationController _footLeft = _drive(value: 0.5);
  late final AnimationController _footRight = _drive(value: 0.5);

  /// Взгляд: сдвиг бусин по горизонтали и вертикали, −1…1 через 0.5.
  late final AnimationController _lookX = _drive(value: 0.5);
  late final AnimationController _lookY = _drive(value: 0.5);

  /// Действие целиком — одна непрерывная кривая времени: еда или эмоция.
  /// Все её движения (наклон, челюсть, жевание, взгляд, лапы) считаются
  /// из одного времени гладкими функциями, а не цепочкой отдельных
  /// движений со своими стартами и остановками — иначе на стыках рывки.
  /// Заказчик 22.09: «наклон к еде смотрится рывками… рот как у робота».
  late final AnimationController _act = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  _Motion Function(double t)? _motionOf;
  double _actSeconds = 1;

  /// Откуда переходить, если новое действие перебило старое на полпути:
  /// старая поза за [_blendSeconds] перетекает в новую кривую, а не
  /// прыгает в её начало.
  _Motion? _blendFrom;
  static const double _blendSeconds = 0.45;

  /// Текущее движение действия; вне действия — покой.
  _Motion get _m {
    final motion = _motionOf;
    if (motion == null) return const _Motion();
    final t = _act.value * _actSeconds;
    final now = motion(t);
    final from = _blendFrom;
    if (from == null) return now;
    return _Motion.lerp(from, now, _ramp(t, 0, _blendSeconds));
  }

  /// Веко: 0 — глаза открыты, 1 — закрыты. Шторка, как в спальне: моргание
  /// идёт непрерывно, а не щелчком двух картинок.
  late final AnimationController _lid = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  /// Сердечки над головой: 0 — нет, 1 — улетели.
  late final AnimationController _hearts = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  AnimationController _drive({double value = 0, double lowerBound = 0}) =>
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
        lowerBound: lowerBound,
        value: value,
      );

  _Eyes _eyes = _Eyes.open;
  _Mouth _mouth = _Mouth.neutral;

  /// Картинки ушей и глаз как `ui.Image`: уши рисуются сеткой, глаза —
  /// со шторкой века.
  late final _Pictures _pictures = _Pictures(
    [
      KitchenScene.assets[2],
      KitchenScene.assets[3],
      '${KitchenScene._dir}/head.png',
      for (final e in _Eyes.values) e.asset,
      for (final m in _Mouth.values) m.asset,
    ],
    onChange: () {
      if (mounted) setState(() {});
    },
  );

  final math.Random _dice = math.Random();

  /// Кто сейчас ведёт сцену. Каждый сценарий получает свой номер и
  /// прекращается, как только номер сменился: так еда прерывает покой,
  /// а следующая еда — предыдущую.
  int _run = 0;
  Timer? _earNext;

  bool? _stillSetting;
  bool get _still => _stillSetting ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pictures.load(context);
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _stillSetting) return;
    _stillSetting = still;
    if (still) {
      _run++;
      _earNext?.cancel();
      _breath.stop();
      _breath.value = 0;
      _lid.value = 0;
      _act.stop();
      _motionOf = null;
      _reset();
    } else {
      _breath.repeat();
      _idle(++_run);
      _earRest();
    }
  }

  @override
  void didUpdateWidget(KitchenScene old) {
    super.didUpdateWidget(old);
    final meal = widget.meal;
    if (meal != null && meal.id != old.meal?.id && !_still) {
      _eat(++_run, meal.mood);
    }
  }

  @override
  void dispose() {
    _run++;
    _earNext?.cancel();
    _pictures.dispose();
    for (final d in _drives) {
      d.dispose();
    }
    _breath.dispose();
    _lid.dispose();
    _act.dispose();
    _hearts.dispose();
    super.dispose();
  }

  List<AnimationController> get _drives => [
    _bow,
    _side,
    _armLeft,
    _armRight,
    _pawLeft,
    _pawRight,
    _earLeft,
    _earRight,
    _footLeft,
    _footRight,
    _lookX,
    _lookY,
  ];

  /// Всё в исходную позу разом: сидит прямо, смотрит перед собой. Только
  /// для режима без анимации — живому мишке нужен [_settle].
  void _reset() {
    for (final d in [_bow, _armLeft, _armRight, _pawLeft, _pawRight]) {
      d.value = 0;
    }
    for (final d in [
      _side,
      _earLeft,
      _earRight,
      _footLeft,
      _footRight,
      _lookX,
      _lookY,
    ]) {
      d.value = 0.5;
    }
    _hearts.value = 0;
    setState(() {
      _eyes = _Eyes.open;
      _mouth = _Mouth.neutral;
    });
  }

  /// Мягко вернуться в покой за [ms]: после эмоции ничего не должно
  /// прыгать на место.
  void _settle([int ms = 450]) {
    for (final d in [_bow, _armLeft, _armRight, _pawLeft, _pawRight]) {
      _to(d, 0, ms);
    }
    for (final d in [
      _side,
      _earLeft,
      _earRight,
      _footLeft,
      _footRight,
      _lookX,
      _lookY,
    ]) {
      _to(d, 0.5, ms);
    }
    _face(mouth: _Mouth.neutral);
    if (_eyes != _Eyes.open) {
      _eyesTo(_run, _Eyes.open).catchError((Object _) {});
    }
  }

  // --- Мелочи сценариев ---------------------------------------------------

  bool _alive(int run) => mounted && !_still && run == _run;

  /// Пауза сценария. Уважает [timeDilation]: при замедленной съёмке
  /// паузы растягиваются вместе с анимациями, иначе сценарий убегал бы
  /// вперёд движений.
  Future<void> _wait(int run, int ms, [int spread = 0]) async {
    await _delay(ms + (spread == 0 ? 0 : _dice.nextInt(spread)));
    if (!_alive(run)) throw _Stopped();
  }

  static Future<void> _delay(int ms) =>
      Future<void>.delayed(Duration(milliseconds: (ms * timeDilation).round()));

  /// Перевести [drive] в [to] за [ms]. Не ждёт конца: параллельные
  /// движения складываются из нескольких таких вызовов.
  void _to(
    AnimationController drive,
    double to,
    int ms, [
    Curve curve = Curves.easeInOutSine,
  ]) {
    drive.animateTo(
      to,
      duration: Duration(milliseconds: ms),
      curve: curve,
    );
  }

  void _face({_Eyes? eyes, _Mouth? mouth}) {
    if (!mounted) return;
    if ((eyes ?? _eyes) == _eyes && (mouth ?? _mouth) == _mouth) return;
    setState(() {
      if (eyes != null) _eyes = eyes;
      if (mouth != null) _mouth = mouth;
    });
  }

  /// Сменить выражение глаз под веком: закрыл, поменял, открыл. Живые так
  /// и делают — новый взгляд появляется из-под века, а не проступает
  /// сквозь старый. [mouth] меняется в тот же момент, пока глаза закрыты.
  Future<void> _eyesTo(int run, _Eyes eyes, {_Mouth? mouth}) async {
    if (eyes == _eyes && _lid.value == 0 && !_lid.isAnimating) {
      _face(mouth: mouth);
      return;
    }
    _to(_lid, 1, 90, Curves.easeIn);
    await _wait(run, 110);
    _face(eyes: eyes, mouth: mouth);
    _to(_lid, 0, 170, Curves.easeOut);
    await _wait(run, 170);
  }

  /// Моргание: веко падает быстро, поднимается чуть медленнее — те же
  /// 90/170 мс, что в спальне. Иногда двойное.
  Future<void> _blink(int run, {bool twice = false}) async {
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      _to(_lid, 1, 90, Curves.easeIn);
      await _wait(run, 90 + 50, 50);
      _to(_lid, 0, 170, Curves.easeOut);
      await _wait(run, 170);
      if (twice && i == 0) await _wait(run, 120, 80);
    }
  }

  // --- Покой -------------------------------------------------------------

  /// Круг бодрствования, как в спальне: отдых с разбросом → моргание,
  /// иногда двойное → в половине случаев взгляд в сторону → изредка
  /// покачать головой. Голодный иногда грустит.
  Future<void> _idle(int run) async {
    try {
      while (_alive(run)) {
        await _wait(run, 2200, 1800);
        await _blink(run, twice: _dice.nextInt(4) == 0);

        if (_dice.nextBool()) {
          // Взгляд в сторону: 220 мс туда, 260 обратно, синус — без
          // старта рывком. Заказчик 23.09: «более плавные взгляды».
          // В сторону, а в трети случаев — вверх искоса (23.09: «или
          // чуть-чуть вверх искоса»).
          final x = _dice.nextBool() ? 0.0 : 1.0;
          final up = _dice.nextInt(3) == 0;
          _to(_lookX, x, 220);
          if (up) _to(_lookY, 0.2, 220);
          await _wait(run, 900, 700);
          _to(_lookX, 0.5, 260);
          if (up) _to(_lookY, 0.5, 260);
          await _wait(run, 600, 500);
        }

        if (_dice.nextInt(3) == 0) {
          // Наклонил голову набок — прислушался — и обратно. Медленно:
          // быстрый наклон читается как вздрагивание.
          _to(_side, _dice.nextBool() ? 0.1 : 0.9, 1100);
          await _wait(run, 1600, 900);
          _to(_side, 0.5, 900);
          await _wait(run, 900);
        }

        if (widget.hungry && _dice.nextInt(3) == 0) {
          // Голоден: посмотрел вниз, на пустой стол, и погрустнел.
          _at(run, 450, () => _eyesTo(run, _Eyes.sad, mouth: _Mouth.sad));
          _at(run, 2350, () => _eyesTo(run, _Eyes.open, mouth: _Mouth.neutral));
          await _play(run, 3.4, _hungryMotion);
          await _wait(run, 600);
        }
      }
    } on _Stopped {
      // Сценарий сменили.
    }
  }

  /// Уши живут своим расписанием, не в ногу с глазами.
  void _earRest() {
    _earNext?.cancel();
    _earNext = Timer(
      Duration(
        milliseconds: ((3500 + _dice.nextInt(6000)) * timeDilation).round(),
      ),
      _earTwitch,
    );
  }

  Future<void> _earTwitch() async {
    if (!mounted || _still) return;
    final ear = _dice.nextBool() ? _earLeft : _earRight;
    final both = _dice.nextInt(5) == 0;
    final twice = _dice.nextBool();
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      // Вверх 180 мс, вниз 420: заказчик 23.09 — «более плавные движения
      // ушами». Кривая вверх — синус, а не кубик: без щелчка на старте.
      for (final e in [ear, if (both) ear == _earLeft ? _earRight : _earLeft]) {
        _to(e, 1, 180, Curves.easeOutSine);
      }
      await _delay(190);
      if (!mounted || _still) return;
      for (final e in [ear, if (both) ear == _earLeft ? _earRight : _earLeft]) {
        _to(e, 0.5, 420);
      }
      await _delay(470);
      if (!mounted || _still) return;
    }
    _earRest();
  }

  // --- Еда и эмоции: непрерывные кривые ------------------------------------

  /// Прогресс 0…1 между моментами [a] и [b] секунд по кривой [curve].
  static double _ramp(
    double t,
    double a,
    double b, [
    Curve curve = Curves.easeInOutSine,
  ]) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return curve.transform((t - a) / (b - a));
  }

  /// Проиграть кривую [motion] длиной [seconds]. Функция должна
  /// возвращать покой в начале и в конце, тогда стыков нет.
  Future<void> _play(
    int run,
    double seconds,
    _Motion Function(double) motion,
  ) async {
    final was = _m;
    setState(() {
      _blendFrom = was.isRest ? null : was;
      _motionOf = motion;
      _actSeconds = seconds;
    });
    _act.duration = Duration(milliseconds: (seconds * 1000).round());
    _act.forward(from: 0);
    try {
      await _wait(run, (seconds * 1000).round());
    } finally {
      if (mounted && run == _run) {
        setState(() {
          _motionOf = null;
          _blendFrom = null;
        });
      }
    }
  }

  /// Сделать что-то в нужный момент кривой, не останавливая её.
  void _at(int run, int ms, Future<void> Function() what) {
    Future<void>(() async {
      await _wait(run, ms);
      await what();
    }).catchError((Object _) {});
  }

  /// `act_eat`: увидел еду → взгляд вниз → откусил (рот мягко открылся и
  /// закрылся) → довольно жуёт закрытым ртом, покачивая головой, → ещё
  /// раз. Без наклона головы к столу — заказчик 23.09: «даже у Тома нет
  /// наклона головы к еде, там видно как он жуёт… красивое плавное
  /// жевание с улыбкой глаз». Глаза-улыбка включаются в [_eat] под веком.
  /// Руки на столе (заказчик 22.09).
  static _Motion _eatMotion(double t) {
    var jaw = 0.0, chew = 0.0, munch = 0.0, grind = 0.0;
    var bow = 0.0, side = 0.0, lookY = 0.0;
    // Увидел: взгляд вниз; в конце обратно.
    lookY += _ramp(t, 0, 0.5);
    // Лапы лежат на столе всю еду (заказчик 22.09: «не обязательно руки
    // подносить ко рту, могут оставаться на столе»; 23.09: «лапки
    // закрывают скатерть»).
    const paws = 0.0;
    for (final s in [0.6, 3.5]) {
      // Откусил: рот раскрывается и закрывается по синусу — без резкого
      // старта и стопа, иначе «рот как у робота».
      jaw += 0.8 * (_ramp(t, s, s + 0.4) - _ramp(t, s + 0.4, s + 0.8));
      lookY -= 0.7 * _ramp(t, s + 0.6, s + 1.0);
      // Жуёт закрытым ртом: губы сжимаются и отпускают, челюсть чуть ходит
      // вниз, голова в такт покачивается и слегка водит из стороны в
      // сторону, как от удовольствия.
      final c0 = s + 0.8, c1 = s + 2.55;
      if (t >= c0 && t <= c1) {
        final u = t - c0;
        final env = _ramp(u, 0, 0.3) * (1 - _ramp(u, c1 - c0 - 0.4, c1 - c0));
        final phase = 2 * math.pi * 1.8 * u;
        chew += env;
        // Челюсть ходит по кругу: вниз (munch) и в сторону (grind), как
        // настоящее перетирание. Голова чуть кивает и водит в такт.
        munch += (0.5 - 0.5 * math.cos(phase)) * env;
        grind += math.sin(phase) * env;
        bow += 0.04 * math.sin(phase) * env;
        side += 0.12 * math.sin(phase / 2 + math.pi / 2) * env;
      }
      // Перед вторым кусочком снова посмотрел на еду.
      if (s < 1) lookY += 0.7 * _ramp(t, 3.15, 3.5);
    }
    lookY -= 0.3 * _ramp(t, 6.0, 6.5);
    return _Motion(
      jaw: jaw.clamp(0.0, 1.0),
      chew: chew.clamp(0.0, 1.0),
      munch: munch.clamp(0.0, 1.0),
      grind: grind.clamp(-1.0, 1.0),
      bow: bow,
      side: side,
      lookY: lookY.clamp(0.0, 1.0),
      paws: paws.clamp(0.0, 1.0),
    );
  }

  /// `emo_happy_burst`: три подскока головы с затуханием, лапы попеременно
  /// похлопывают по столу, ножки болтаются, уши вверх.
  static _Motion _happyMotion(double t) {
    // Разгон: лапы и ножки не дёргаются с первого кадра, а раскачиваются.
    final env =
        math.exp(-0.75 * t) * (1 - _ramp(t, 2.3, 2.9)) * _ramp(t, 0, 0.3);
    final w = 2 * math.pi * 1.6 * t;
    final hop = math.sin(w / 2);
    return _Motion(
      bow: -0.32 * hop * hop * env,
      pat: math.sin(w) * env,
      feet: math.sin(w + math.pi / 2) * env,
      ears: _ramp(t, 0, 0.35) - _ramp(t, 2.6, 3.3),
    );
  }

  /// Голодный покой: посмотрел вниз, на пустой стол, ссутулился, уши
  /// повисли — и отпустило. Одной кривой, глаза меняются под веком.
  static _Motion _hungryMotion(double t) => _Motion(
    bow: 0.4 * (_ramp(t, 0, 0.9) - _ramp(t, 2.5, 3.4)),
    lookY: _ramp(t, 0, 0.5) - _ramp(t, 2.5, 3.1),
    ears: -0.7 * (_ramp(t, 0.3, 1.0) - _ramp(t, 2.5, 3.3)),
  );

  /// `emo_love`: голова медленно клонится набок, уши мягко опускаются.
  static _Motion _loveMotion(double t) => _Motion(
    side: _ramp(t, 0, 1.3) - _ramp(t, 2.7, 3.7),
    ears: -0.6 * (_ramp(t, 0.1, 1.2) - _ramp(t, 2.7, 3.6)),
  );

  /// `emo_surprise`: голова отшатнулась, уши торчком, потом отпустило.
  static _Motion _surpriseMotion(double t) => _Motion(
    bow: -0.5 * (_ramp(t, 0, 0.28, Curves.easeOutBack) - _ramp(t, 1.05, 1.6)),
    ears: _ramp(t, 0, 0.2, Curves.easeOutCubic) - _ramp(t, 1.1, 1.6),
  );

  Future<void> _eat(int run, KitchenMood mood) async {
    try {
      // Покой мог быть прерван на полпути: взгляд в сторону, наклон
      // набок, уши — всё мягко возвращается, пока он замечает еду.
      _to(_lookX, 0.5, 300);
      _to(_side, 0.5, 300);
      _to(_earLeft, 0.5, 300);
      _to(_earRight, 0.5, 300);
      await _eyesTo(run, _Eyes.open, mouth: _Mouth.neutral);
      // Довольное лицо с первым кусочком: глаза-улыбка под веком, пока
      // жуёт, и до конца еды.
      _at(run, 1150, () => _eyesTo(run, _Eyes.happy));
      await _play(run, 6.7, _eatMotion);
      switch (mood) {
        case KitchenMood.happy:
          await _happy(run);
        case KitchenMood.love:
          await _love(run);
        case KitchenMood.surprise:
          await _surprise(run);
          await _happy(run);
      }
      _settle();
      await _wait(run, 500);
      await _idle(run);
    } on _Stopped {
      // Сценарий сменили.
    }
  }

  Future<void> _happy(int run) async {
    await _eyesTo(run, _Eyes.happy, mouth: _Mouth.smile);
    _at(run, 2500, () => _eyesTo(run, _Eyes.open, mouth: _Mouth.neutral));
    await _play(run, 3.4, _happyMotion);
  }

  Future<void> _love(int run) async {
    await _eyesTo(run, _Eyes.happy, mouth: _Mouth.neutral);
    _at(run, 200, () async => _hearts.forward(from: 0));
    _at(run, 3000, () => _eyesTo(run, _Eyes.open, mouth: _Mouth.neutral));
    await _play(run, 3.8, _loveMotion);
  }

  Future<void> _surprise(int run) async {
    // Удивление — единственное, что бьёт без моргания: глаза распахиваются.
    _face(eyes: _Eyes.wide, mouth: _Mouth.o);
    await _play(run, 1.7, _surpriseMotion);
  }

  // --- Отрисовка ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return AnimatedBuilder(
            animation: Listenable.merge([
              _breath,
              ..._drives,
              _lid,
              _act,
              _hearts,
            ]),
            builder: (context, _) => Stack(
              children: [
                // Под качающейся ножкой — её же неподвижный верх: при
                // качании у скатерти открывались бы углы (заказчик 23.09:
                // «подложки под те части, где видны пробелы»).
                _footBack(w, h, KitchenScene.footLeft, 'foot_left'),
                _footBack(w, h, KitchenScene.footRight, 'foot_right'),
                _foot(w, h, KitchenScene.footLeft, 'foot_left', _footLeft, 1),
                _foot(
                  w,
                  h,
                  KitchenScene.footRight,
                  'foot_right',
                  _footRight,
                  -1,
                ),
                _tableFront(w, h),
                // Плечевые доборы: внутренняя половина рукава, неподвижная,
                // под туловищем. Когда рука взмахивает, у плеча иначе
                // просвечивал бы стул. Заказчик 22.09: «каждое движение
                // нужно делать доборы». Наружную половину не дублируем —
                // она читалась бы второй рукой.
                // Туловище, руки и доборы дышат вместе, от кромки стола:
                // иначе плечи поднимаются, а рукава отстают, и по шву
                // видна щель.
                _breathing(
                  w,
                  h,
                  Stack(
                    children: [
                      _shoulder(
                        w,
                        h,
                        KitchenScene.sleeveLeft,
                        'sleeve_left',
                        keepRight: true,
                      ),
                      _shoulder(
                        w,
                        h,
                        KitchenScene.sleeveRight,
                        'sleeve_right',
                        keepRight: false,
                      ),
                      // Рука висит от сустава у туловища вниз и наружу:
                      // левая крутится по часовой, правая против.
                      _arm(
                        w,
                        h,
                        KitchenScene.pawLeft,
                        'paw_left',
                        KitchenScene.shoulderLeft,
                        _armLeft,
                        KitchenScene.wristLeft,
                        _pawLeft,
                        1,
                      ),
                      _arm(
                        w,
                        h,
                        KitchenScene.pawRight,
                        'paw_right',
                        KitchenScene.shoulderRight,
                        _armRight,
                        KitchenScene.wristRight,
                        _pawRight,
                        -1,
                      ),
                      _arm(
                        w,
                        h,
                        KitchenScene.sleeveLeft,
                        'sleeve_left',
                        KitchenScene.shoulderLeft,
                        _armLeft,
                        null,
                        null,
                        1,
                      ),
                      _arm(
                        w,
                        h,
                        KitchenScene.sleeveRight,
                        'sleeve_right',
                        KitchenScene.shoulderRight,
                        _armRight,
                        null,
                        null,
                        -1,
                      ),
                      _torso(w, h),
                    ],
                  ),
                ),
                _head(w, h),
                if (_hearts.isAnimating || _hearts.value > 0)
                  _heartsLayer(w, h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _image(String name) =>
      Image.asset('${KitchenScene._dir}/$name.png', fit: BoxFit.fill);

  /// Точка кадра как выравнивание внутри рамки [box]: −1 у левого/верхнего
  /// края, +1 у правого/нижнего. Может выходить за рамку — это нормально.
  Alignment _pivot(Offset point, Rect box) => Alignment(
    (point.dx - box.left) / box.width * 2 - 1,
    (point.dy - box.top) / box.height * 2 - 1,
  );

  Positioned _place(Rect box, double w, double h, Widget child) => Positioned(
    left: box.left * w,
    top: box.top * h,
    width: box.width * w,
    height: box.height * h,
    child: child,
  );

  /// Ножка: качается от колена под кромкой стола.
  Widget _foot(
    double w,
    double h,
    Rect box,
    String name,
    AnimationController swing,
    double sign,
  ) {
    return _place(
      box,
      w,
      h,
      Transform.rotate(
        angle:
            sign * KitchenScene.footSwing * ((swing.value - 0.5) * 2 + _m.feet),
        alignment: Alignment.topCenter,
        child: _image(name),
      ),
    );
  }

  /// Подложка ножки: верхние 45 % спрайта, неподвижно.
  Widget _footBack(double w, double h, Rect box, String name) => _place(
    box,
    w,
    h,
    ClipRect(clipper: const _TopClipper(fraction: 0.45), child: _image(name)),
  );

  /// Край стола и скатерть: кусок фона комнаты поверх ножек.
  Widget _tableFront(double w, double h) {
    final box = KitchenScene.tableFront;
    return _place(
      box,
      w,
      h,
      ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: Transform.translate(
            offset: Offset(0, -box.top * h),
            child: Image.asset(
              RoomKind.kitchen.asset,
              width: w,
              height: h,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );
  }

  /// Вдох: группа слоёв растёт от кромки стола — она под столом и стоит.
  Widget _breathing(double w, double h, Widget child) {
    final wave = _wave.value;
    final bottom = KitchenScene.torso.bottom;
    return Positioned.fill(
      child: Transform.scale(
        scaleY: 1 + KitchenScene.chestSwell * wave,
        scaleX: 1 + KitchenScene.chestSwell * 0.3 * wave,
        alignment: Alignment(0, bottom * 2 - 1),
        child: child,
      ),
    );
  }

  /// Туловище: наклоняясь к столу, чуть подаётся вперёд вместе с головой.
  Widget _torso(double w, double h) {
    final bow = _bow.value + _m.bow;
    return _place(
      KitchenScene.torso,
      w,
      h,
      Transform.scale(
        scaleY: 1 - KitchenScene.bowLean * bow,
        alignment: Alignment.bottomCenter,
        child: _image('torso'),
      ),
    );
  }

  /// Голова с глазами и ртом: дышит вместе с плечами, кивает вокруг шеи,
  /// клонится набок.
  Widget _head(double w, double h) {
    final box = KitchenScene.head;
    final wave = _wave.value;
    final bow = _bow.value + _m.bow;
    final side = (_side.value - 0.5) * 2 + _m.side;
    final width = box.width * w;
    final height = box.height * h;
    final neck = _pivot(KitchenScene.neck, box);

    return Positioned(
      left: box.left * w,
      top:
          box.top * h -
          KitchenScene.chestSwell * 0.5 * wave * height +
          KitchenScene.bowDrop * bow * height,
      width: width,
      height: height,
      child: Transform.rotate(
        angle:
            KitchenScene.bowTilt * bow * 0.3 +
            KitchenScene.sideTilt * side +
            KitchenScene.breathSway * (wave - 0.5) * 2,
        alignment: neck,
        child: Transform.scale(
          scaleY: 1 - KitchenScene.bowSquash * bow,
          alignment: Alignment.bottomCenter,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Уши внутри головы: наклонилась голова — уехали и уши.
              // Лежат под головой, сзади — стена. Спрайт уха вырезан из
              // цельного мишки GPT вместе с куском капюшона
              // (tool/cut_kitchen_backings.py): капюшон в нём накрыт
              // капюшоном головы, а шва между ухом и капюшоном нет, как
              // в исходнике. Копии и подложки не нужны: с прямым срезом
              // они выглядывали при сгибе (заказчик 23.09).
              _inHead(
                width,
                height,
                KitchenScene.earLeft,
                _ear(
                  KitchenScene.earLeft,
                  KitchenScene.assets[2],
                  KitchenScene.earLeftRoot,
                  KitchenScene.earLeftTip,
                  _earLeft,
                  1,
                ),
              ),
              _inHead(
                width,
                height,
                KitchenScene.earRight,
                _ear(
                  KitchenScene.earRight,
                  KitchenScene.assets[3],
                  KitchenScene.earRightRoot,
                  KitchenScene.earRightTip,
                  _earRight,
                  -1,
                ),
              ),
              _image('head'),
              _muzzleLayer(width, height),
              _eyesLayer(width, height, bow),
              _mouthLayer(width, height, bow),
            ],
          ),
        ),
      ),
    );
  }

  /// Глаза: текущее выражение под веком-шторкой, сдвинутые по взгляду.
  /// Пока картинки не раскодированы — просто спрайт, без века.
  Widget _eyesLayer(double w, double h, double bow) {
    final head = KitchenScene.head;
    final place = KitchenScene.eyes;
    final width = place.width / head.width * w;
    final height = place.height / head.height * h;
    final base = _pictures[_eyes.asset];
    final closed = _pictures[_Eyes.closed.asset];
    // Бусины стоят на месте, взгляд показывает блик: он уезжает по
    // бусине в сторону взгляда, а нарисованный на спрайте гаснет.
    // Заказчик 23.09: «бусинки уходят влево-вправо, а нужно, чтобы стояли
    // на месте, но появлялся блик».
    final look = Offset(
      (_lookX.value - 0.5) * 2,
      ((_lookY.value - 0.5) * 2 + _m.lookY).clamp(-1.0, 1.0),
    );
    return Positioned(
      left: (place.left - head.left) / head.width * w,
      top:
          (place.top - head.top) / head.height * h +
          KitchenScene.bowFace * bow * h,
      width: width,
      height: height,
      child: base == null || closed == null
          ? Image.asset(_eyes.asset, fit: BoxFit.fill)
          : CustomPaint(
              painter: _LidPainter(
                base: base,
                closed: closed,
                lid: _lid.value,
                look: _eyes == _Eyes.open ? look : Offset.zero,
              ),
            ),
    );
  }

  /// Рот: базовое выражение (меняется под веком вместе с глазами) плюс
  /// челюсть — открытый рот раскрывается от верхней губы на [_Motion.jaw],
  /// и жевание — сжатые губы на [_Motion.chew].
  /// Челюсть сейчас: на сколько нижняя часть мордочки опущена и сдвинута
  /// в сторону, в долях головы; надуты ли щёки. Из этого рисуется и
  /// мордочка ([_MuzzlePainter]), и сдвиг губ.
  _Jaw get _jaw => _Jaw(
    drop:
        _Jaw.biteDrop * Curves.easeInOutSine.transform(_m.jaw) +
        _Jaw.chewDrop * _m.munch * _m.chew,
    shift: _Jaw.chewShift * _m.grind * _m.chew,
    cheeks: _m.munch * _m.chew,
  );

  /// Мордочка: нижняя часть морды на сетке, ходит как челюсть — вниз при
  /// укусе и по кругу при жевании, щёки надуваются. Нос стоит. Заказчик
  /// 23.09: «жевательный визуал не очень… может, щёки задействовать,
  /// чтобы смотрелось живым».
  Widget _muzzleLayer(double w, double h) {
    final image = _pictures['${KitchenScene._dir}/head.png'];
    final jaw = _jaw;
    if (image == null || jaw.isRest) return const SizedBox.shrink();
    return Positioned.fill(
      child: CustomPaint(
        painter: _MuzzlePainter(image: image, jaw: jaw),
      ),
    );
  }

  Widget _mouthLayer(double w, double h, double bow) {
    final head = KitchenScene.head;
    final place = KitchenScene.mouth;
    final base = _pictures[_mouth.asset];
    final open = _pictures[_Mouth.open.asset];
    final chew = _pictures[_Mouth.chew.asset];
    // Губы едут вместе с челюстью: сдвиг мордочки в середине зоны рта.
    final jaw = _jaw;
    final mouthY = (place.top + place.height / 2 - head.top) / head.height;
    final ride = jaw.at(mouthY, 0.5);
    return Positioned(
      left: (place.left - head.left) / head.width * w + ride.dx * w,
      top:
          (place.top - head.top) / head.height * h +
          KitchenScene.bowFace * bow * h +
          ride.dy * h,
      width: place.width / head.width * w,
      height: place.height / head.height * h,
      child: base == null || open == null || chew == null
          ? Image.asset(_mouth.asset, fit: BoxFit.fill)
          : CustomPaint(
              painter: _MouthPainter(
                base: base,
                open: open,
                chew: chew,
                jaw: _m.jaw,
                chewing: _m.chew,
                munch: _m.munch,
              ),
            ),
    );
  }

  /// Рукав или лапа: крутится в плече на [lift]; лапа ещё и в запястье.
  Widget _arm(
    double w,
    double h,
    Rect box,
    String name,
    Offset shoulder,
    AnimationController lift,
    Offset? wrist,
    AnimationController? bend,
    double sign,
  ) {
    // Похлопывание: плюс — левая лапа, минус — правая.
    final pat = (sign > 0 ? _m.pat : -_m.pat).clamp(0.0, 1.0);
    Widget child = _image(name);
    if (wrist != null && bend != null) {
      child = Transform.rotate(
        angle: sign * KitchenScene.wristBend * (bend.value + _m.paws + pat),
        alignment: _pivot(wrist, box),
        child: child,
      );
    }
    return _place(
      box,
      w,
      h,
      Transform.rotate(
        angle: sign * KitchenScene.armLift * (lift.value + pat),
        alignment: _pivot(shoulder, box),
        child: child,
      ),
    );
  }

  /// Ухо: гнётся вдоль своей оси сеткой, как стебель. Ставится в рамку
  /// [box] снаружи — см. [_inHead].
  Widget _ear(
    Rect box,
    String asset,
    Offset root,
    Offset tip,
    AnimationController bend,
    double sign,
  ) {
    final image = _pictures[asset];
    if (image == null) return Image.asset(asset, fit: BoxFit.fill);
    return CustomPaint(
      painter: _EarBend(
        image: image,
        root: Offset(
          (root.dx - box.left) / box.width,
          (root.dy - box.top) / box.height,
        ),
        tip: Offset(
          (tip.dx - box.left) / box.width,
          (tip.dy - box.top) / box.height,
        ),
        angle:
            sign * KitchenScene.earTwitch * ((bend.value - 0.5) * 2 + _m.ears),
      ),
    );
  }

  /// Рамка кадра [place] внутри слоя головы размером [w] × [h].
  Widget _inHead(double w, double h, Rect place, Widget child) {
    final head = KitchenScene.head;
    return Positioned(
      left: (place.left - head.left) / head.width * w,
      top: (place.top - head.top) / head.height * h,
      width: place.width / head.width * w,
      height: place.height / head.height * h,
      child: child,
    );
  }

  /// Плечевой добор: половина рукава со стороны туловища, неподвижная.
  Widget _shoulder(
    double w,
    double h,
    Rect box,
    String name, {
    required bool keepRight,
  }) {
    return _place(
      box,
      w,
      h,
      ClipRect(
        clipper: _HalfClipper(keepRight: keepRight, fraction: 0.55),
        child: _image(name),
      ),
    );
  }

  /// Сердечки над макушкой: всплывают и тают.
  Widget _heartsLayer(double w, double h) {
    final box = KitchenScene.head;
    return Positioned(
      left: box.left * w,
      top: (box.top - 0.12) * h,
      width: box.width * w,
      height: 0.2 * h,
      child: CustomPaint(painter: _HeartsPainter(progress: _hearts.value)),
    );
  }
}

/// Сценарий прерван: сцену повёл другой.
class _Stopped implements Exception {
  const _Stopped();
}

/// Движение действия в один момент времени — добавки к покою.
class _Motion {
  const _Motion({
    this.bow = 0,
    this.jaw = 0,
    this.chew = 0,
    this.lookY = 0,
    this.paws = 0,
    this.pat = 0,
    this.side = 0,
    this.ears = 0,
    this.feet = 0,
    this.munch = 0,
    this.grind = 0,
  });

  /// Жевательный такт 0…1 внутри [chew]: губы сжаты и челюсть внизу на 1.
  final double munch;

  /// Челюсть в сторону −1…1 при жевании (перетирание).
  final double grind;

  bool get isRest =>
      bow == 0 &&
      jaw == 0 &&
      chew == 0 &&
      lookY == 0 &&
      paws == 0 &&
      pat == 0 &&
      side == 0 &&
      ears == 0 &&
      feet == 0 &&
      munch == 0 &&
      grind == 0;

  static _Motion lerp(_Motion a, _Motion b, double k) => _Motion(
    bow: a.bow + (b.bow - a.bow) * k,
    jaw: a.jaw + (b.jaw - a.jaw) * k,
    chew: a.chew + (b.chew - a.chew) * k,
    lookY: a.lookY + (b.lookY - a.lookY) * k,
    paws: a.paws + (b.paws - a.paws) * k,
    pat: a.pat + (b.pat - a.pat) * k,
    side: a.side + (b.side - a.side) * k,
    ears: a.ears + (b.ears - a.ears) * k,
    feet: a.feet + (b.feet - a.feet) * k,
    munch: a.munch + (b.munch - a.munch) * k,
    grind: a.grind + (b.grind - a.grind) * k,
  );

  /// Наклон головы к столу: 0 прямо, 1 у стола, минус — назад.
  final double bow;

  /// Челюсть: 0 закрыт, 1 открыт. Жевание: 0 нет, 1 губы сжаты.
  final double jaw;
  final double chew;

  /// Взгляд вниз 0…1; лапы подобраны 0…1; похлопывание −1 (правая) … 1 (левая).
  final double lookY;
  final double paws;
  final double pat;

  /// Наклон набок −1…1, уши −1 (вниз) … 1 (вверх), ножки −1…1.
  final double side;
  final double ears;
  final double feet;
}

/// Рот: базовое выражение, поверх — сжатые губы на [chewing] и открытый
/// рот на [jaw]. Открытый рот раскрывается от верхней губы: растёт по
/// высоте вместе с прозрачностью, а не появляется готовым.
class _MouthPainter extends CustomPainter {
  const _MouthPainter({
    required this.base,
    required this.open,
    required this.chew,
    required this.jaw,
    required this.chewing,
    this.munch = 0,
  });

  final ui.Image base;
  final ui.Image open;
  final ui.Image chew;
  final double jaw;
  final double chewing;

  /// Такт жевания: на 1 губы сжаты сильнее всего и челюсть внизу.
  final double munch;

  @override
  void paint(Canvas canvas, Size size) {
    // Жуёт: губы чуть ходят вниз-вверх вместе с челюстью. Нос в базовом
    // спрайте стоит на месте.
    final still = Offset.zero & size;
    final zone = still;
    final openness = Curves.easeInOutSine.transform(jaw.clamp(0.0, 1.0));
    final pressed =
        chewing.clamp(0.0, 1.0) *
        (0.35 + 0.65 * munch.clamp(0.0, 1.0)) *
        (1 - openness);
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // Базовая вышивка тает, когда рот открывается или губы сжимаются.
    canvas.drawImageRect(
      base,
      _whole(base),
      still,
      paint
        ..color = Color.fromRGBO(
          0,
          0,
          0,
          (1 - math.max<double>(openness, pressed)).clamp(0.0, 1.0),
        ),
    );
    if (pressed > 0) {
      canvas.drawImageRect(
        chew,
        _whole(chew),
        zone,
        paint..color = Color.fromRGBO(0, 0, 0, pressed),
      );
    }
    if (openness > 0) {
      // Верхняя губа на месте, нижняя опускается: масштаб по высоте от верха.
      final height = size.height * (0.3 + 0.7 * openness);
      final top = zone.top + size.height * 0.12;
      canvas.drawImageRect(
        open,
        _whole(open),
        Rect.fromLTWH(0, top, size.width, height),
        paint..color = Color.fromRGBO(0, 0, 0, openness),
      );
    }
  }

  Rect _whole(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  @override
  bool shouldRepaint(_MouthPainter old) =>
      old.jaw != jaw ||
      old.chewing != chewing ||
      old.munch != munch ||
      old.base != base;
}

/// Веко-шторка. Голова под глазами — сплошной ворс, а спрайты глаз — одни
/// бусины и дуги. Поэтому веко не «накрывает» глаза, а стирает открытые
/// сверху вниз до ворса и в стёртой части рисует дуги закрытых. Край
/// мягкий, положение непрерывное — как в спальне: заказчик 22.09 — «не
/// плавно они закрываются… как будто покадрово».
class _LidPainter extends CustomPainter {
  const _LidPainter({
    required this.base,
    required this.closed,
    required this.lid,
    this.look = Offset.zero,
  });

  /// Текущее выражение и закрытые глаза.
  final ui.Image base;
  final ui.Image closed;

  /// 0 — открыто, 1 — закрыто.
  final double lid;

  /// Взгляд −1…1 по осям: блик на бусине уезжает в эту сторону.
  final Offset look;

  /// Бусины и блик в пикселях спрайта 112 × 52 (обмер `eyes_open.png`):
  /// центры бусин, где сидит нарисованный блик и его слабый сосед
  /// справа, на сколько блик может уехать.
  static const List<Offset> beads = [Offset(23.8, 25.1), Offset(88.1, 25.3)];
  static const Offset glintAt = Offset(-3.4, -2.7);
  static const Offset glintTwin = Offset(2.6, -2.6);
  static const Offset glintTravel = Offset(3.6, 2.4);
  static const Size sprite = Size(112, 52);

  /// Путь века в долях высоты спрайта и ширина мягкого края.
  /// Мягкий край уже, чем в спальне (там 0.14 зоны глаза): здесь зона —
  /// спрайт 112 × 52, и бусина радиусом 8 px целиком помещалась в край
  /// шириной 7 px — на середине моргания читалась серой полупрозрачной
  /// (проверка по кадрам 23.09). Край 3 px: веко режет бусину, как в
  /// спальне, а не растворяет её.
  static const double lidFrom = 0.06;
  static const double lidTo = 0.96;
  static const double feather = 0.06;

  @override
  void paint(Canvas canvas, Size size) {
    final zone = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (lid <= 0) {
      canvas.drawImageRect(base, _whole(base), zone, paint);
      _glint(canvas, size);
      return;
    }
    final edge = size.height * (lidFrom + (lidTo - lidFrom) * lid);
    final soft = size.height * feather;
    // Открытые глаза — только ниже края века.
    canvas.saveLayer(zone, Paint());
    canvas.drawImageRect(base, _whole(base), zone, paint);
    _glint(canvas, size);
    canvas.drawRect(zone, _mask(edge, soft, below: true));
    canvas.restore();
    // Закрытые — только выше края: дуга проступает, когда веко до неё
    // доходит, ровно как в спальне (там та же шторка над зоной глаза).
    canvas.saveLayer(zone, Paint());
    canvas.drawImageRect(
      closed,
      _whole(closed),
      zone,
      paint..color = const Color(0xFF000000),
    );
    canvas.drawRect(zone, _mask(edge, soft, below: false));
    canvas.restore();
  }

  /// Блик взгляда: нарисованный блик гаснет под тёмным пятном цвета
  /// бусины, а такой же блик рисуется сдвинутым в сторону взгляда. Сила
  /// — по длине взгляда, так что в покое не рисуется ничего.
  void _glint(Canvas canvas, Size size) {
    final k = Curves.easeInOutSine.transform(look.distance.clamp(0.0, 1.0));
    if (k <= 0) return;
    final sx = size.width / sprite.width;
    final sy = size.height / sprite.height;
    Offset at(Offset bead, Offset d) =>
        Offset((bead.dx + d.dx) * sx, (bead.dy + d.dy) * sy);
    final shift = Offset(look.dx * glintTravel.dx, look.dy * glintTravel.dy);
    final cover = Paint()
      ..color = Color.fromRGBO(22, 16, 14, k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.6 * sx);
    // Размер и яркость — как у нарисованной пары: иначе читается не
    // «блик уехал», а «блик уменьшился».
    final bright = Paint()
      ..color = Color.fromRGBO(255, 252, 248, k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.45 * sx);
    final faint = Paint()
      ..color = Color.fromRGBO(255, 252, 248, 0.85 * k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.45 * sx);
    for (final bead in beads) {
      canvas.drawOval(
        Rect.fromCenter(
          center: at(bead, const Offset(-0.4, -2.6)),
          width: 11 * sx,
          height: 6 * sy,
        ),
        cover,
      );
      canvas.drawCircle(at(bead, glintAt + shift), 2.1 * sx, bright);
      canvas.drawCircle(at(bead, glintTwin + shift), 1.7 * sx, faint);
    }
  }

  Paint _mask(double edge, double soft, {required bool below}) => Paint()
    ..blendMode = BlendMode.dstIn
    ..shader = ui.Gradient.linear(
      Offset(0, edge - soft),
      Offset(0, edge + soft),
      below
          ? const [Color(0x00FFFFFF), Color(0xFFFFFFFF)]
          : const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    );

  Rect _whole(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  @override
  bool shouldRepaint(_LidPainter old) =>
      old.lid != lid ||
      old.base != base ||
      old.closed != closed ||
      old.look != look;
}

/// Положение челюсти в долях головы.
class _Jaw {
  const _Jaw({required this.drop, required this.shift, required this.cheeks});

  /// Опускание при укусе и при жевании, сдвиг вбок при жевании, надув
  /// щёк — в долях высоты/ширины головы.
  static const double biteDrop = 0.035;
  static const double chewDrop = 0.022;
  static const double chewShift = 0.012;
  static const double cheekBulge = 0.02;

  /// Где челюсть начинает двигаться и где движется целиком — доли высоты
  /// головы: нос (0.79–0.85) стоит, ниже него мордочка ходит.
  static const double hinge = 0.85;
  static const double chin = 0.96;

  final double drop;
  final double shift;
  final double cheeks;

  bool get isRest => drop == 0 && shift == 0 && cheeks == 0;

  /// Вес челюсти в точке: 0 у носа и выше, 1 у подбородка.
  static double weight(double y) => Curves.easeInOutSine.transform(
    ((y - hinge) / (chin - hinge)).clamp(0.0, 1.0),
  );

  /// Сдвиг точки мордочки ([x], [y] — доли головы) в долях головы.
  Offset at(double y, double x) {
    final wy = weight(y);
    return Offset(shift * wy, drop * wy);
  }
}

/// Нижняя часть мордочки на сетке поверх головы: узлы ниже носа
/// опускаются и сдвигаются по [_Jaw], щёки надуваются в стороны. Край
/// заплатки мягкий сверху и с боков, где она совпадает с головой; снизу —
/// подбородок, он и должен опускаться.
class _MuzzlePainter extends CustomPainter {
  const _MuzzlePainter({required this.image, required this.jaw});

  final ui.Image image;
  final _Jaw jaw;

  /// Заплатка — доли головы.
  static const Rect patch = Rect.fromLTRB(0.10, 0.68, 0.90, 1.0);
  static const int cols = 16;
  static const int rows = 12;

  /// Щёки: центры и разброс (доли головы).
  static const double cheekY = 0.84;
  static const double cheekX = 0.24;
  static const double cheekSpread = 0.09;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = <Offset>[];
    final texture = <Offset>[];
    for (var row = 0; row <= rows; row++) {
      final y = patch.top + patch.height * row / rows;
      for (var col = 0; col <= cols; col++) {
        final x = patch.left + patch.width * col / cols;
        final d = jaw.at(y, x);
        // Щёки: выпуклость наружу колоколом вокруг центра щеки; та, куда
        // ушла челюсть, надута сильнее.
        final side = x < 0.5 ? -1.0 : 1.0;
        final cx = x < 0.5 ? cheekX : 1 - cheekX;
        final bell = math.exp(
          -(((x - cx) * (x - cx)) + ((y - cheekY) * (y - cheekY))) /
              (2 * cheekSpread * cheekSpread),
        );
        final favour = (jaw.shift * side > 0 ? 1.0 : 0.5);
        final bulge = _Jaw.cheekBulge * jaw.cheeks * favour * bell;
        positions.add(
          Offset(
            (x + d.dx + side * bulge) * size.width,
            (y + d.dy) * size.height,
          ),
        );
        texture.add(Offset(x * image.width, y * image.height));
      }
    }
    final indices = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final a = row * (cols + 1) + col;
        final b = a + 1;
        final c = a + cols + 1;
        final d = c + 1;
        indices.addAll([a, b, c, b, d, c]);
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: Uint16List.fromList(indices),
    );
    final zone = Rect.fromLTRB(
      patch.left * size.width,
      patch.top * size.height,
      patch.right * size.width,
      (patch.bottom + 0.06) * size.height,
    );
    canvas.saveLayer(zone, Paint());
    canvas.drawVertices(
      vertices,
      ui.BlendMode.srcOver,
      Paint()
        ..shader = ui.ImageShader(
          image,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          Matrix4.identity().storage,
        )
        ..filterQuality = FilterQuality.medium,
    );
    // Мягкий край: сверху и с боков заплатка растворяется в голове.
    canvas.drawRect(
      zone,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset(0, zone.top),
          Offset(0, zone.top + 0.12 * size.height),
          const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        ),
    );
    canvas.drawRect(
      zone,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset(zone.left, 0),
          Offset(zone.right, 0),
          const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          const [0.0, 0.12, 0.88, 1.0],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MuzzlePainter old) =>
      old.image != image ||
      old.jaw.drop != jaw.drop ||
      old.jaw.shift != jaw.shift ||
      old.jaw.cheeks != jaw.cheeks;
}

/// Оставляет [fraction] высоты сверху.
class _TopClipper extends CustomClipper<Rect> {
  const _TopClipper({required this.fraction});

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * fraction);

  @override
  bool shouldReclip(_TopClipper old) => old.fraction != fraction;
}

/// Оставляет [fraction] ширины с правого или левого края.
class _HalfClipper extends CustomClipper<Rect> {
  const _HalfClipper({required this.keepRight, required this.fraction});

  final bool keepRight;
  final double fraction;

  @override
  Rect getClip(Size size) => keepRight
      ? Rect.fromLTWH(
          size.width * (1 - fraction),
          0,
          size.width * fraction,
          size.height,
        )
      : Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_HalfClipper old) =>
      old.keepRight != keepRight || old.fraction != fraction;
}

/// Ухо, натянутое на сетку: узлы поворачиваются вокруг корня тем сильнее,
/// чем дальше они по оси к вершине. Корень стоит, вершина гнётся —
/// ухо изгибается дугой, а не ломается и не крутится целиком.
class _EarBend extends CustomPainter {
  const _EarBend({
    required this.image,
    required this.root,
    required this.tip,
    required this.angle,
  });

  final ui.Image image;

  /// Корень и вершина оси — в долях рамки уха.
  final Offset root;
  final Offset tip;

  /// Угол у вершины, радианы; вдоль оси нарастает от нуля.
  final double angle;

  static const int cols = 8;
  static const int rows = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset(root.dx * size.width, root.dy * size.height);
    final t = Offset(tip.dx * size.width, tip.dy * size.height);
    final axis = t - r;
    final length = axis.distance;
    final dir = axis / length;

    final positions = <Offset>[];
    final texture = <Offset>[];
    for (var row = 0; row <= rows; row++) {
      final v = row / rows;
      for (var col = 0; col <= cols; col++) {
        final u = col / cols;
        final p = Offset(u * size.width, v * size.height);
        // Сколько пройдено по оси от корня к вершине: 0 у корня, 1 у вершины.
        final along = (((p - r).dx * dir.dx + (p - r).dy * dir.dy) / length)
            .clamp(0.0, 1.0);
        final a = angle * along * along;
        final d = p - r;
        final cosA = math.cos(a);
        final sinA = math.sin(a);
        positions.add(
          Offset(
            r.dx + d.dx * cosA - d.dy * sinA,
            r.dy + d.dx * sinA + d.dy * cosA,
          ),
        );
        texture.add(Offset(u * image.width, v * image.height));
      }
    }
    final indices = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final a = row * (cols + 1) + col;
        final b = a + 1;
        final c = a + cols + 1;
        final d = c + 1;
        indices.addAll([a, b, c, b, d, c]);
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
  bool shouldRepaint(_EarBend old) => old.angle != angle || old.image != image;
}

/// Три сердечка разного размера всплывают над головой и тают.
class _HeartsPainter extends CustomPainter {
  const _HeartsPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    const hearts = [(0.35, 0.0, 0.16), (0.62, 0.18, 0.12), (0.48, 0.36, 0.10)];
    for (final (x, delay, scale) in hearts) {
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final alpha = t < 0.2 ? t / 0.2 : (1 - (t - 0.2) / 0.8);
      final s = size.width * scale * (0.6 + 0.4 * Curves.easeOut.transform(t));
      final c = Offset(
        x * size.width + math.sin(t * math.pi * 2) * size.width * 0.03,
        size.height * (1 - 0.9 * Curves.easeOut.transform(t)),
      );
      canvas.drawPath(
        _heart(c, s),
        Paint()..color = AppColors.blush.withValues(alpha: alpha.clamp(0, 1)),
      );
    }
  }

  Path _heart(Offset c, double s) {
    final p = Path()..moveTo(c.dx, c.dy + s * 0.45);
    p.cubicTo(
      c.dx - s * 0.9,
      c.dy - s * 0.2,
      c.dx - s * 0.45,
      c.dy - s * 0.75,
      c.dx,
      c.dy - s * 0.3,
    );
    p.cubicTo(
      c.dx + s * 0.45,
      c.dy - s * 0.75,
      c.dx + s * 0.9,
      c.dy - s * 0.2,
      c.dx,
      c.dy + s * 0.45,
    );
    return p..close();
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => old.progress != progress;
}

/// Картинки из ассетов как `ui.Image` — для слоёв, что рисуются сеткой.
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
