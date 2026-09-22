import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
  static const Rect footLeft = Rect.fromLTWH(0.361111, 0.751953, 0.115741, 0.050781);
  static const Rect footRight = Rect.fromLTWH(0.503472, 0.751953, 0.116898, 0.052083);
  static const Rect earLeft = Rect.fromLTWH(0.348380, 0.444010, 0.079861, 0.065104);
  static const Rect earRight = Rect.fromLTWH(0.567130, 0.445312, 0.079861, 0.063802);
  static const Rect pawLeft = Rect.fromLTWH(0.335648, 0.579427, 0.092593, 0.037760);
  static const Rect pawRight = Rect.fromLTWH(0.562500, 0.579427, 0.086806, 0.037760);
  static const Rect sleeveLeft = Rect.fromLTWH(0.340278, 0.554688, 0.096065, 0.052734);
  static const Rect sleeveRight = Rect.fromLTWH(0.554398, 0.554688, 0.091435, 0.050130);
  static const Rect torso = Rect.fromLTWH(0.406250, 0.541016, 0.178241, 0.067057);
  static const Rect head = Rect.fromLTWH(0.357639, 0.382161, 0.275463, 0.185547);
  static const Rect eyes = Rect.fromLTWH(0.430556, 0.505208, 0.129630, 0.033854);
  static const Rect mouth = Rect.fromLTWH(0.458333, 0.536458, 0.071759, 0.023438);

  /// Край стола со скатертью: кусок фона, положенный поверх ножек, чтобы
  /// их припуск уходил под стол. От кромки стола до низа скатерти.
  static const Rect tableFront = Rect.fromLTWH(0, 0.6065, 1, 0.1483);

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
  static const double earTwitch = 0.28;

  /// Дыхание — тот же темп, что в спальне: заказчик просил один ритм.
  static const Duration breath = Duration(milliseconds: 4400);
  static const double chestSwell = 0.012;

  /// Наклон головы вперёд, к столу: в плоской картинке это в основном
  /// опускание (доля высоты головы) и лёгкое сжатие, чуть-чуть поворота.
  /// Вбок — радианы.
  static const double bowTilt = 0.04;
  static const double bowDrop = 0.16;
  static const double sideTilt = 0.05;

  /// Взмах руки от плечевого сустава — наружу и вверх (радость) — и
  /// доворот лапы в запястье. Радианы. Ко рту плюшевая рука не достаёт:
  /// ест он, наклоняясь к столу, как из миски (ТЗ: `act_eat` из миски).
  static const double armLift = 0.6;
  static const double wristBend = 0.22;

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
      tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutSine)),
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

  /// Картинки ушей как `ui.Image`: они рисуются сеткой, а не целиком.
  late final _Pictures _pictures = _Pictures(
    [KitchenScene.assets[2], KitchenScene.assets[3]],
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
    _hearts.dispose();
    super.dispose();
  }

  List<AnimationController> get _drives => [
        _bow, _side, _armLeft, _armRight, _pawLeft, _pawRight,
        _earLeft, _earRight, _footLeft, _footRight, _lookX, _lookY,
      ];

  /// Всё в исходную позу: сидит прямо, смотрит перед собой.
  void _reset() {
    for (final d in [_bow, _armLeft, _armRight, _pawLeft, _pawRight]) {
      d.value = 0;
    }
    for (final d in [_side, _earLeft, _earRight, _footLeft, _footRight, _lookX, _lookY]) {
      d.value = 0.5;
    }
    _hearts.value = 0;
    setState(() {
      _eyes = _Eyes.open;
      _mouth = _Mouth.neutral;
    });
  }

  // --- Мелочи сценариев ---------------------------------------------------

  bool _alive(int run) => mounted && !_still && run == _run;

  Future<void> _wait(int run, int ms, [int spread = 0]) async {
    await Future<void>.delayed(
        Duration(milliseconds: ms + (spread == 0 ? 0 : _dice.nextInt(spread))));
    if (!_alive(run)) throw _Stopped();
  }

  /// Перевести [drive] в [to] за [ms]. Не ждёт конца: параллельные
  /// движения складываются из нескольких таких вызовов.
  void _to(AnimationController drive, double to, int ms,
      [Curve curve = Curves.easeInOutSine]) {
    drive.animateTo(to, duration: Duration(milliseconds: ms), curve: curve);
  }

  void _face({_Eyes? eyes, _Mouth? mouth}) {
    if (!mounted) return;
    if ((eyes ?? _eyes) == _eyes && (mouth ?? _mouth) == _mouth) return;
    setState(() {
      if (eyes != null) _eyes = eyes;
      if (mouth != null) _mouth = mouth;
    });
  }

  Future<void> _blink(int run, {bool twice = false}) async {
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      _face(eyes: _Eyes.closed);
      await _wait(run, 110, 50);
      _face(eyes: _Eyes.open);
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
          final x = _dice.nextBool() ? 0.0 : 1.0;
          _to(_lookX, x, 170);
          await _wait(run, 900, 700);
          _to(_lookX, 0.5, 200);
          await _wait(run, 600, 500);
        }

        if (_dice.nextInt(3) == 0) {
          // Наклонил голову набок — прислушался — и обратно.
          _to(_side, _dice.nextBool() ? 0.0 : 1.0, 900);
          await _wait(run, 1400, 900);
          _to(_side, 0.5, 700);
          await _wait(run, 700);
        }

        if (widget.hungry && _dice.nextInt(3) == 0) {
          // Голоден: посмотрел вниз, на пустой стол, и погрустнел.
          _to(_lookY, 1, 250);
          _to(_bow, 0.5, 700);
          await _wait(run, 400);
          _face(eyes: _Eyes.sad, mouth: _Mouth.sad);
          _to(_earLeft, 0.15, 500);
          _to(_earRight, 0.15, 500);
          await _wait(run, 1600, 600);
          _face(eyes: _Eyes.open, mouth: _Mouth.neutral);
          _to(_lookY, 0.5, 250);
          _to(_bow, 0, 600);
          _to(_earLeft, 0.5, 400);
          _to(_earRight, 0.5, 400);
          await _wait(run, 800);
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
        Duration(milliseconds: 3500 + _dice.nextInt(6000)), _earTwitch);
  }

  Future<void> _earTwitch() async {
    if (!mounted || _still) return;
    final ear = _dice.nextBool() ? _earLeft : _earRight;
    final both = _dice.nextInt(5) == 0;
    final twice = _dice.nextBool();
    for (var i = 0; i < (twice ? 2 : 1); i++) {
      for (final e in [ear, if (both) ear == _earLeft ? _earRight : _earLeft]) {
        _to(e, 1, 90, Curves.easeOutCubic);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || _still) return;
      for (final e in [ear, if (both) ear == _earLeft ? _earRight : _earLeft]) {
        _to(e, 0.5, 260);
      }
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || _still) return;
    }
    _earRest();
  }

  // --- Еда ---------------------------------------------------------------

  /// `act_eat`: увидел еду, наклонился к столу и ест, как из миски —
  /// два захода с жеванием, между ними поднял голову. Лапы на столе чуть
  /// подбираются, будто держат миску. Потом эмоция по настроению и снова
  /// покой.
  Future<void> _eat(int run, KitchenMood mood) async {
    try {
      _face(eyes: _Eyes.open, mouth: _Mouth.neutral);
      _to(_side, 0.5, 300);
      _to(_earLeft, 0.5, 300);
      _to(_earRight, 0.5, 300);

      // Увидел еду: глаза вниз, лапы подобрал.
      _to(_lookY, 1, 220);
      _to(_pawLeft, 1, 400);
      _to(_pawRight, 1, 400);
      await _wait(run, 350);

      for (var bite = 0; bite < 2; bite++) {
        // К столу: голова опускается, рот открывается по пути.
        _to(_bow, 1, 620, Curves.easeInOutCubic);
        await _wait(run, 380);
        _face(mouth: _Mouth.open);
        await _wait(run, 380);
        // Откусил: рот закрылся, жуёт, голова чуть покачивается.
        _face(mouth: _Mouth.chew);
        _to(_bow, 0.55, 300);
        _to(_lookY, 0.5, 300);
        await _wait(run, 300);
        for (var chew = 0; chew < 3; chew++) {
          _to(_bow, 0.45, 150);
          _face(mouth: chew == 1 ? _Mouth.neutral : _Mouth.chew);
          await _wait(run, 150);
          _to(_bow, 0.6, 150);
          _face(mouth: _Mouth.chew);
          await _wait(run, 150);
        }
        _face(mouth: _Mouth.neutral);
        if (bite == 0) {
          _to(_lookY, 1, 200);
          await _wait(run, 250);
        }
      }

      // Наелся: выпрямился, лапы легли.
      _to(_bow, 0, 500);
      _to(_lookY, 0.5, 300);
      _to(_pawLeft, 0, 400);
      _to(_pawRight, 0, 400);
      await _wait(run, 450);

      switch (mood) {
        case KitchenMood.happy:
          await _happy(run);
        case KitchenMood.love:
          await _love(run);
        case KitchenMood.surprise:
          await _surprise(run);
          await _happy(run);
      }
      _reset();
      await _idle(run);
    } on _Stopped {
      // Сценарий сменили.
    }
  }

  /// `emo_happy_burst`: зажмурился, заулыбался, подпрыгнул головой, лапы
  /// вверх, ножки заболтались.
  Future<void> _happy(int run) async {
    _face(eyes: _Eyes.happy, mouth: _Mouth.smile);
    _to(_earLeft, 1, 200, Curves.easeOutCubic);
    _to(_earRight, 1, 200, Curves.easeOutCubic);
    _to(_armLeft, 1, 300, Curves.easeOutBack);
    _to(_armRight, 1, 300, Curves.easeOutBack);
    for (var i = 0; i < 3; i++) {
      _to(_bow, -0.35, 220, Curves.easeOut);
      _to(_footLeft, i.isEven ? 1 : 0, 220);
      _to(_footRight, i.isEven ? 0 : 1, 220);
      await _wait(run, 220);
      _to(_bow, 0, 260, Curves.easeIn);
      await _wait(run, 260);
    }
    _to(_footLeft, 0.5, 400);
    _to(_footRight, 0.5, 400);
    _to(_armLeft, 0, 400);
    _to(_armRight, 0, 400);
    _to(_earLeft, 0.5, 400);
    _to(_earRight, 0.5, 400);
    await _wait(run, 900);
    _face(eyes: _Eyes.open, mouth: _Mouth.neutral);
  }

  /// `emo_love`: прикрыл глаза, тихо улыбнулся, склонил голову набок,
  /// над головой сердечки.
  Future<void> _love(int run) async {
    _face(eyes: _Eyes.happy, mouth: _Mouth.neutral);
    _to(_side, 1, 900);
    _to(_earLeft, 0.25, 700);
    _to(_earRight, 0.25, 700);
    _hearts.forward(from: 0);
    await _wait(run, 2300);
    _to(_side, 0.5, 700);
    _to(_earLeft, 0.5, 500);
    _to(_earRight, 0.5, 500);
    await _wait(run, 700);
    _face(eyes: _Eyes.open, mouth: _Mouth.neutral);
  }

  /// `emo_surprise`: глаза во всю бусину, рот кружком, голова назад, уши
  /// торчком.
  Future<void> _surprise(int run) async {
    _face(eyes: _Eyes.wide, mouth: _Mouth.o);
    _to(_bow, -0.5, 180, Curves.easeOut);
    _to(_earLeft, 1, 120, Curves.easeOutCubic);
    _to(_earRight, 1, 120, Curves.easeOutCubic);
    await _wait(run, 1000);
    _to(_bow, 0, 300);
    await _wait(run, 300);
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
            animation: Listenable.merge([_breath, ..._drives, _hearts]),
            builder: (context, _) => Stack(
              children: [
                _foot(w, h, KitchenScene.footLeft, 'foot_left', _footLeft, 1),
                _foot(w, h, KitchenScene.footRight, 'foot_right', _footRight, -1),
                _tableFront(w, h),
                // Плечевые доборы: внутренняя половина рукава, неподвижная,
                // под туловищем. Когда рука взмахивает, у плеча иначе
                // просвечивал бы стул. Заказчик 22.09: «каждое движение
                // нужно делать доборы». Наружную половину не дублируем —
                // она читалась бы второй рукой.
                _shoulder(w, h, KitchenScene.sleeveLeft, 'sleeve_left', keepRight: true),
                _shoulder(w, h, KitchenScene.sleeveRight, 'sleeve_right', keepRight: false),
                // Рука висит от сустава у туловища вниз и наружу: взмах —
                // левая по часовой (наружу и вверх), правая против.
                _arm(w, h, KitchenScene.pawLeft, 'paw_left',
                    KitchenScene.shoulderLeft, _armLeft, KitchenScene.wristLeft, _pawLeft, 1),
                _arm(w, h, KitchenScene.pawRight, 'paw_right',
                    KitchenScene.shoulderRight, _armRight, KitchenScene.wristRight, _pawRight, -1),
                _arm(w, h, KitchenScene.sleeveLeft, 'sleeve_left',
                    KitchenScene.shoulderLeft, _armLeft, null, null, 1),
                _arm(w, h, KitchenScene.sleeveRight, 'sleeve_right',
                    KitchenScene.shoulderRight, _armRight, null, null, -1),
                _torso(w, h),
                _head(w, h),
                if (_hearts.isAnimating || _hearts.value > 0) _heartsLayer(w, h),
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

  Positioned _place(Rect box, double w, double h, Widget child) =>
      Positioned(
        left: box.left * w,
        top: box.top * h,
        width: box.width * w,
        height: box.height * h,
        child: child,
      );

  /// Ножка: качается от колена под кромкой стола.
  Widget _foot(double w, double h, Rect box, String name,
      AnimationController swing, double sign) {
    return _place(
      box,
      w,
      h,
      Transform.rotate(
        angle: sign * KitchenScene.footSwing * (swing.value - 0.5) * 2,
        alignment: Alignment.topCenter,
        child: _image(name),
      ),
    );
  }

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
            child: Image.asset(RoomKind.kitchen.asset,
                width: w, height: h, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }

  /// Туловище: дышит от нижнего края, он на кромке стола и стоит.
  /// Наклоняясь к столу, чуть подаётся вперёд вместе с головой.
  Widget _torso(double w, double h) {
    final wave = _wave.value;
    final bow = _bow.value;
    return _place(
      KitchenScene.torso,
      w,
      h,
      Transform.scale(
        scaleY: 1 + KitchenScene.chestSwell * wave - 0.02 * bow,
        scaleX: 1 + KitchenScene.chestSwell * 0.4 * wave,
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
    final bow = _bow.value;
    final side = (_side.value - 0.5) * 2;
    final width = box.width * w;
    final height = box.height * h;
    final neck = _pivot(KitchenScene.neck, box);

    return Positioned(
      left: box.left * w,
      top: box.top * h -
          KitchenScene.chestSwell * 0.5 * wave * height +
          KitchenScene.bowDrop * bow * height,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: KitchenScene.bowTilt * bow * 0.3 + KitchenScene.sideTilt * side,
        alignment: neck,
        child: Transform.scale(
          scaleY: 1 - 0.02 * bow,
          alignment: Alignment.bottomCenter,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Уши внутри головы: наклонилась голова — уехали и уши.
              // Под каждым — неподвижная копия (добор): когда ухо гнётся,
              // на его месте открывалась бы стена. Заказчик 22.09: «при
              // движении ушей видны пробелы, нужно делать доборы».
              _inHead(width, height, KitchenScene.earLeft, _image('ear_left')),
              _inHead(width, height, KitchenScene.earRight, _image('ear_right')),
              _inHead(width, height, KitchenScene.earLeft,
                  _ear(KitchenScene.earLeft, KitchenScene.assets[2],
                      KitchenScene.earLeftRoot, KitchenScene.earLeftTip, _earLeft, 1)),
              _inHead(width, height, KitchenScene.earRight,
                  _ear(KitchenScene.earRight, KitchenScene.assets[3],
                      KitchenScene.earRightRoot, KitchenScene.earRightTip, _earRight, -1)),
              _image('head'),
              _sprite(width, height, KitchenScene.eyes, _eyes.asset,
                  shift: Offset(
                    (_lookX.value - 0.5) * 0.06,
                    (_lookY.value - 0.5) * 0.08,
                  )),
              _sprite(width, height, KitchenScene.mouth, _mouth.asset),
            ],
          ),
        ),
      ),
    );
  }

  /// Спрайт на своём месте внутри головы; подменяется с коротким
  /// перетеканием, чтобы моргание не щёлкало. [shift] — в долях рамки
  /// спрайта: взгляд в сторону.
  Widget _sprite(double w, double h, Rect place, String asset,
      {Offset shift = Offset.zero}) {
    final head = KitchenScene.head;
    final width = place.width / head.width * w;
    final height = place.height / head.height * h;
    return Positioned(
      left: (place.left - head.left) / head.width * w + shift.dx * width,
      top: (place.top - head.top) / head.height * h + shift.dy * height,
      width: width,
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 70),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: Image.asset(asset, key: ValueKey(asset), fit: BoxFit.fill),
      ),
    );
  }

  /// Рукав или лапа: крутится в плече на [lift]; лапа ещё и в запястье.
  Widget _arm(double w, double h, Rect box, String name, Offset shoulder,
      AnimationController lift, Offset? wrist, AnimationController? bend,
      double sign) {
    Widget child = _image(name);
    if (wrist != null && bend != null) {
      child = Transform.rotate(
        angle: sign * KitchenScene.wristBend * bend.value,
        alignment: _pivot(wrist, box),
        child: child,
      );
    }
    return _place(
      box,
      w,
      h,
      Transform.rotate(
        angle: sign * KitchenScene.armLift * lift.value,
        alignment: _pivot(shoulder, box),
        child: child,
      ),
    );
  }

  /// Ухо: гнётся вдоль своей оси сеткой, как стебель. Ставится в рамку
  /// [box] снаружи — см. [_inHead].
  Widget _ear(Rect box, String asset, Offset root, Offset tip,
      AnimationController bend, double sign) {
    final image = _pictures[asset];
    if (image == null) return Image.asset(asset, fit: BoxFit.fill);
    return CustomPaint(
      painter: _EarBend(
        image: image,
        root: Offset((root.dx - box.left) / box.width, (root.dy - box.top) / box.height),
        tip: Offset((tip.dx - box.left) / box.width, (tip.dy - box.top) / box.height),
        angle: sign * KitchenScene.earTwitch * (bend.value - 0.5) * 2,
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
  Widget _shoulder(double w, double h, Rect box, String name,
      {required bool keepRight}) {
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

/// Оставляет [fraction] ширины с правого или левого края.
class _HalfClipper extends CustomClipper<Rect> {
  const _HalfClipper({required this.keepRight, required this.fraction});

  final bool keepRight;
  final double fraction;

  @override
  Rect getClip(Size size) => keepRight
      ? Rect.fromLTWH(size.width * (1 - fraction), 0, size.width * fraction, size.height)
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
        positions.add(Offset(
          r.dx + d.dx * cosA - d.dy * sinA,
          r.dy + d.dx * sinA + d.dy * cosA,
        ));
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
  bool shouldRepaint(_EarBend old) =>
      old.angle != angle || old.image != image;
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
    p.cubicTo(c.dx - s * 0.9, c.dy - s * 0.2, c.dx - s * 0.45, c.dy - s * 0.75, c.dx, c.dy - s * 0.3);
    p.cubicTo(c.dx + s * 0.45, c.dy - s * 0.75, c.dx + s * 0.9, c.dy - s * 0.2, c.dx, c.dy + s * 0.45);
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
