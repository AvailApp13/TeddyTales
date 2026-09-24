import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Пузырь сытости: съеденное блюдо превращается в пузырик с «+N», тот
/// змейкой летит вверх, бьётся о кружок «Еда» и лопается — кружок
/// подпрыгивает, проценты бегут вверх, а монеты делают «у-у»: кнопка
/// раздувается, число скатывается на цену (или прибавляет награду за
/// готовку), под ней мелькает «−7» или «+9».
///
/// Заказчик 24.09: «когда еда исчезает, появляется пузырь… в нём плюс 7,
/// плюс 13… летит вверх, как змейка, бьётся о кружочек еды и лопается, и
/// туда плюс 7… и процент увеличивается»; монеты — вместе с пузырём.
/// Строку «Пирог · еда +40, −15 монет» внизу экрана это заменяет.
///
/// Показатель и кошелёк меняются в игре сразу при покупке, а на экране —
/// в момент удара: до него [FeedFx] держит прежние числа ([hold]).
class FeedFx extends ChangeNotifier {
  /// Кружок «Еда»: куда летит пузырь. Ставится на само кольцо.
  final GlobalKey foodRing = GlobalKey(debugLabel: 'feed-fx-food-ring');

  double? _heldFood;
  int? _heldCoins;

  // Подсчёт после удара: от чего к чему бегут числа. `null` в цели — к
  // живому значению игры.
  double? _fromFood;
  double? _toFood;
  int? _fromCoins;
  int? _toCoins;
  double _count = 0;

  int _inFlight = 0;
  final List<FeedLaunch> _queue = [];

  /// Удар о кружок: 0…1 от удара до покоя, `null` — покой.
  double? get foodBump => _foodBump;
  double? _foodBump;

  /// «У-у» монет: 0…1, `null` — покой.
  double? get coinBump => _coinBump;
  double? _coinBump;

  /// Плашка «−7» / «+9» под монетами: сколько и где она в своём пути 0…1.
  int get coinDelta => _coinDelta;
  int _coinDelta = 0;
  double? get coinChip => _coinChip;
  double? _coinChip;

  /// Бегут ли сейчас проценты — подпись «Еда» светится золотым.
  bool get counting => _fromFood != null;

  /// Запомнить, что было на экране до еды: до удара пузыря показываются
  /// эти числа. Если пузырь уже летит — остаются числа до первого.
  void hold({required double food, required int coins}) {
    _heldFood ??= food;
    _heldCoins ??= coins;
    notifyListeners();
  }

  /// Выпустить пузырь.
  void launch(FeedLaunch launch) {
    _inFlight++;
    _queue.add(launch);
    notifyListeners();
  }

  /// Пузыря не будет (готовку бросили после того, как блюдо уже засчитано):
  /// числа просто добегают до настоящих.
  void settle() {
    if (_heldFood == null && _heldCoins == null) return;
    _queue.add(const FeedLaunch._settle());
    notifyListeners();
  }

  /// Сколько «Еды» показывать при настоящем значении [live].
  double food(double live) {
    final from = _fromFood;
    if (from != null) {
      final to = _toFood ?? live;
      return from + (to - from) * _count;
    }
    return _heldFood ?? live;
  }

  /// Сколько монет показывать при настоящем балансе [live].
  int coins(int live) {
    final from = _fromCoins;
    if (from != null) {
      final to = _toCoins ?? live;
      return (from + (to - from) * _count).round();
    }
    return _heldCoins ?? live;
  }

  List<FeedLaunch> _take() {
    final out = List.of(_queue);
    _queue.clear();
    return out;
  }

  void _impact(FeedLaunch l, double liveFood, int liveCoins) {
    if (!l.isSettle) _inFlight = math.max(0, _inFlight - 1);
    final shownFood = food(liveFood);
    final shownCoins = coins(liveCoins);
    final last = _inFlight == 0;
    _fromFood = shownFood;
    _toFood = last ? null : math.min(liveFood, shownFood + l.gain);
    _fromCoins = shownCoins;
    _toCoins = last ? null : shownCoins + l.coins;
    _count = 0;
    if (!l.isSettle) {
      _foodBump = 0;
      if (l.coins != 0) {
        _coinBump = 0;
        _coinDelta = l.coins;
        _coinChip = 0;
      }
    }
    notifyListeners();
  }

  void _countDone() {
    if (_inFlight == 0) {
      _heldFood = null;
      _heldCoins = null;
    } else {
      _heldFood = _toFood;
      _heldCoins = _toCoins;
    }
    _fromFood = null;
    _toFood = null;
    _fromCoins = null;
    _toCoins = null;
    _count = 0;
  }

  void _frame({
    required double? count,
    required double? foodBump,
    required double? coinBump,
    required double? coinChip,
  }) {
    if (count != null) {
      _count = count;
      if (count >= 1) _countDone();
    }
    _foodBump = foodBump;
    _coinBump = coinBump;
    _coinChip = coinChip;
    notifyListeners();
  }

  /// Движение удара: резкий подскок и затухающее покачивание. Общее для
  /// кружка и монет — они отзываются одним почерком.
  static double bounce(double t) {
    if (t <= 0 || t >= 1) return 0;
    const up = 0.12;
    if (t < up) return Curves.easeOutCubic.transform(t / up);
    final u = t - up;
    return math.exp(-6 * u) * math.cos(11 * u);
  }
}

/// Один пузырь: откуда вылетает, что написано и на сколько меняются монеты
/// (минус — потрачено, плюс — награда).
class FeedLaunch {
  const FeedLaunch({
    required this.origin,
    required this.gain,
    required this.coins,
  }) : isSettle = false;

  const FeedLaunch._settle()
    : origin = null,
      gain = 0,
      coins = 0,
      isSettle = true;

  /// Где родится пузырь — по размеру слоя (там же, где тарелка).
  final Offset Function(Size layer)? origin;

  /// Прибавка «Еды» — число в пузыре.
  final int gain;
  final int coins;
  final bool isSettle;
}

/// Слой поверх всего экрана, где летят пузыри. Касаний не ловит.
class FeedBurstLayer extends StatefulWidget {
  const FeedBurstLayer({
    super.key,
    required this.fx,
    required this.liveFood,
    required this.liveCoins,
  });

  final FeedFx fx;

  /// Настоящие значения игры: к ним бегут числа после удара.
  final double Function() liveFood;
  final int Function() liveCoins;

  /// Рождение: пузырик выдувается из тарелки.
  static const double birth = 0.42;

  /// Полёт змейкой до кружка.
  static const double flight = 1.25;

  /// Сплющился о кружок.
  static const double squash = 0.13;

  /// От запуска до удара.
  static const double impactAt = birth + flight + squash;

  /// Числа бегут, кружок подпрыгивает, монеты «у-у», плашка тает.
  static const double count = 0.9;
  static const double bump = 0.85;
  static const double chip = 1.3;

  /// Размер пузыря.
  static const double radius = 21;

  @override
  State<FeedBurstLayer> createState() => _FeedBurstLayerState();
}

class _Burst {
  _Burst(this.launch, this.start);

  final FeedLaunch launch;
  final double start;
  Offset? origin;
  bool impacted = false;
  bool born = false;
  double lastSpark = 0;
}

class _Particle {
  _Particle({
    required this.pos,
    required this.vel,
    required this.born,
    required this.life,
    required this.size,
    required this.kind,
    this.gravity = 0,
    this.spin = 0,
  });

  Offset pos;
  final Offset vel;
  final double born;
  final double life;
  final double size;
  final _Kind kind;
  final double gravity;
  final double spin;
}

enum _Kind { dot, star, drop }

/// Вспышка лопнувшего пузыря: кольцо-волна, осколки оболочки и число,
/// влетающее в кружок.
class _Pop {
  _Pop(this.at, this.center, this.target, this.text, this.born);

  final Offset at;
  final Offset center;
  final Offset target;
  final String text;
  final double born;
}

class _FeedBurstLayerState extends State<FeedBurstLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Время слоя, секунды. Идёт только пока тикер работает; каждый новый
  /// запуск тикера продолжает с того же места.
  double _clock = 0;
  double _base = 0;
  final List<_Burst> _bursts = [];
  final List<_Particle> _particles = [];
  final List<_Pop> _pops = [];
  final math.Random _dice = math.Random();

  double? _countFrom;
  double? _bumpFrom;
  double? _coinFrom;
  double? _chipFrom;

  FeedFx get _fx => widget.fx;

  @override
  void initState() {
    super.initState();
    _fx.addListener(_onFx);
  }

  @override
  void didUpdateWidget(FeedBurstLayer old) {
    super.didUpdateWidget(old);
    if (old.fx != widget.fx) {
      old.fx.removeListener(_onFx);
      widget.fx.addListener(_onFx);
    }
  }

  @override
  void dispose() {
    _fx.removeListener(_onFx);
    _ticker.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _onFx() {
    final launches = _fx._take();
    if (launches.isEmpty) return;
    for (final l in launches) {
      if (l.isSettle || l.origin == null || _still) {
        _impact(l);
      } else {
        _bursts.add(_Burst(l, _clock));
      }
    }
    _run();
    setState(() {});
  }

  void _run() {
    if (_ticker.isActive || _still) return;
    _base = _clock;
    _ticker.start();
  }

  void _impact(FeedLaunch l) {
    _fx._impact(l, widget.liveFood(), widget.liveCoins());
    final t = _clock;
    _countFrom = t;
    if (!l.isSettle) {
      _bumpFrom = t;
      if (l.coins != 0) {
        _coinFrom = t;
        _chipFrom = t;
      }
    }
    if (_still) {
      // Без анимаций — сразу к итогу.
      _fx._frame(count: 1, foodBump: null, coinBump: null, coinChip: null);
      _countFrom = _bumpFrom = _coinFrom = _chipFrom = null;
    } else {
      _run();
    }
  }

  Offset _target(Size size) {
    final ring = _fx.foodRing.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (ring is RenderBox && me is RenderBox && ring.attached) {
      final c = ring.localToGlobal(ring.size.center(Offset.zero));
      return me.globalToLocal(c);
    }
    // Ряд колец спрятан — пузырь уходит к его кнопке справа вверху.
    return Offset(size.width * 0.3, 110);
  }

  static double _ease(double t) => Curves.easeInOutSine.transform(t);

  /// Где пузырь в момент [t] от запуска.
  ({Offset c, double sx, double sy, double rot, double scale, double alpha})
  _where(_Burst b, Size size, double t) {
    final origin = b.origin ??= b.launch.origin!(size);
    final ring = _target(size);
    const r = FeedBurstLayer.radius;
    // Удар — снизу о кольцо: центр пузыря чуть ниже края кружка.
    final hit = ring + const Offset(0, 29 + r * 0.72);
    final lift = origin - const Offset(0, 38);
    if (t < FeedBurstLayer.birth) {
      final u = t / FeedBurstLayer.birth;
      final grow = Curves.easeOutBack.transform(u);
      return (
        c: Offset.lerp(origin, lift, Curves.easeOutCubic.transform(u))!,
        sx: 1 + 0.12 * (1 - u) * math.sin(u * math.pi * 3),
        sy: 1 - 0.12 * (1 - u) * math.sin(u * math.pi * 3),
        rot: 0,
        scale: grow,
        alpha: math.min(1, u * 2.5),
      );
    }
    final ft = t - FeedBurstLayer.birth;
    if (ft < FeedBurstLayer.flight) {
      final u = ft / FeedBurstLayer.flight;
      final e = _ease(u);
      final base = Offset.lerp(lift, hit, e)!;
      final d = hit - lift;
      final len = d.distance == 0 ? 1.0 : d.distance;
      final perp = Offset(-d.dy / len, d.dx / len);
      // Змейка: две с половиной волны, затихают у цели.
      final wave = 34 * math.sin(u * math.pi * 2.5) * math.pow(1 - u, 0.8);
      final c = base + perp * wave.toDouble();
      // Желе: чуть тянется по ходу, чуть качается.
      final jelly = 0.06 * math.sin(ft * 14);
      final slope = 34 * math.pi * 2.5 * math.cos(u * math.pi * 2.5) / len;
      return (
        c: c,
        sx: 1 + jelly,
        sy: 1 - jelly,
        rot: 0.35 * math.atan(slope) * (1 - u),
        scale: 1,
        alpha: 1,
      );
    }
    // Сплющился о кружок.
    final u = ((ft - FeedBurstLayer.flight) / FeedBurstLayer.squash).clamp(
      0.0,
      1.0,
    );
    final s = Curves.easeOut.transform(u);
    return (
      c: hit - Offset(0, 4 * s),
      sx: 1 + 0.26 * s,
      sy: 1 - 0.24 * s,
      rot: 0,
      scale: 1,
      alpha: 1,
    );
  }

  void _tick(Duration elapsed) {
    final t = _base + elapsed.inMicroseconds / 1e6;
    final dt = (t - _clock).clamp(0.0, 0.05);
    _clock = t;
    final size = (context.findRenderObject() as RenderBox?)?.size;
    if (size == null) return;

    // Пузыри: след, удар, хлопок.
    for (final b in _bursts.toList()) {
      final bt = t - b.start;
      if (bt < 0) continue;
      final w = _where(b, size, bt);
      if (!b.born) {
        b.born = true;
        _birthSparkles(b.origin!, t);
      }
      final flying =
          bt > FeedBurstLayer.birth &&
          bt < FeedBurstLayer.birth + FeedBurstLayer.flight;
      if (flying) {
        _particles.add(
          _Particle(
            pos: w.c + _jitter(5),
            vel: Offset(_dice.nextDouble() * 16 - 8, 18),
            born: t,
            life: 0.5,
            size: 5.5 + _dice.nextDouble() * 2,
            kind: _Kind.dot,
          ),
        );
        if (t - b.lastSpark > 0.07) {
          b.lastSpark = t;
          _particles.add(
            _Particle(
              pos: w.c + _jitter(14),
              vel: Offset(_dice.nextDouble() * 30 - 15, 26),
              born: t,
              life: 0.6,
              size: 4 + _dice.nextDouble() * 3,
              kind: _Kind.star,
              spin: _dice.nextDouble() * 4 - 2,
            ),
          );
        }
      }
      if (!b.impacted && bt >= FeedBurstLayer.impactAt) {
        b.impacted = true;
        _burst(w.c, t);
        _pops.add(_Pop(w.c, w.c, _target(size), '+${b.launch.gain}', t));
        _bursts.remove(b);
        _impact(b.launch);
      }
    }

    // Частицы живут своё и гаснут.
    for (final p in _particles.toList()) {
      final age = t - p.born;
      if (age > p.life) {
        _particles.remove(p);
        continue;
      }
      p.pos += p.vel * dt + Offset(0, p.gravity * age * dt);
    }
    _pops.removeWhere((p) => t - p.born > 0.45);

    // Кружок, монеты и числа.
    double? progress(double? from, double length) {
      if (from == null) return null;
      return ((t - from) / length).clamp(0.0, 1.0);
    }

    final count = progress(_countFrom, FeedBurstLayer.count);
    final bump = progress(_bumpFrom, FeedBurstLayer.bump);
    final coin = progress(_coinFrom, FeedBurstLayer.bump);
    final chip = progress(_chipFrom, FeedBurstLayer.chip);
    _fx._frame(
      count: count == null ? null : Curves.easeOutCubic.transform(count),
      foodBump: bump == null || bump >= 1 ? null : bump,
      coinBump: coin == null || coin >= 1 ? null : coin,
      coinChip: chip == null || chip >= 1 ? null : chip,
    );
    if (count != null && count >= 1) _countFrom = null;
    if (bump != null && bump >= 1) _bumpFrom = null;
    if (coin != null && coin >= 1) _coinFrom = null;
    if (chip != null && chip >= 1) _chipFrom = null;

    final idle =
        _bursts.isEmpty &&
        _particles.isEmpty &&
        _pops.isEmpty &&
        _countFrom == null &&
        _bumpFrom == null &&
        _coinFrom == null &&
        _chipFrom == null;
    if (idle) _ticker.stop();
    setState(() {});
  }

  Offset _jitter(double r) =>
      Offset(_dice.nextDouble() * 2 - 1, _dice.nextDouble() * 2 - 1) * r;

  void _birthSparkles(Offset at, double t) {
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.2;
      _particles.add(
        _Particle(
          pos: at + Offset(math.cos(a) * 18, math.sin(a) * 10),
          vel: Offset(math.cos(a) * 70, math.sin(a) * 45 - 20),
          born: t,
          life: 0.65,
          size: i.isOdd ? 6 : 4.5,
          kind: _Kind.star,
          spin: i.isOdd ? 2 : -2,
        ),
      );
    }
  }

  void _burst(Offset at, double t) {
    for (var i = 0; i < 12; i++) {
      final a = i * 2 * math.pi / 12 + _dice.nextDouble() * 0.3;
      final speed = 130 + _dice.nextDouble() * 110;
      _particles.add(
        _Particle(
          pos: at,
          vel: Offset(math.cos(a), math.sin(a) * 0.85) * speed,
          born: t,
          life: 0.55 + _dice.nextDouble() * 0.15,
          size: 3 + _dice.nextDouble() * 2.5,
          kind: _Kind.drop,
          gravity: 420,
        ),
      );
    }
    for (var i = 0; i < 9; i++) {
      final a = i * 2 * math.pi / 9 + 0.3;
      final speed = 90 + _dice.nextDouble() * 80;
      _particles.add(
        _Particle(
          pos: at,
          vel: Offset(math.cos(a), math.sin(a)) * speed,
          born: t,
          life: 0.6,
          size: 5 + _dice.nextDouble() * 3,
          kind: _Kind.star,
          spin: _dice.nextDouble() * 6 - 3,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bursts.isEmpty && _particles.isEmpty && _pops.isEmpty) {
      return const SizedBox.expand();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return CustomPaint(
          size: size,
          painter: _BurstPainter(
            bubbles: [
              for (final b in _bursts)
                if (_clock - b.start >= 0)
                  (
                    where: _where(b, size, _clock - b.start),
                    text: '+${b.launch.gain}',
                  ),
            ],
            particles: _particles,
            pops: _pops,
            now: _clock,
          ),
        );
      },
    );
  }
}

typedef _Bubble = ({
  ({Offset c, double sx, double sy, double rot, double scale, double alpha})
  where,
  String text,
});

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.bubbles,
    required this.particles,
    required this.pops,
    required this.now,
  });

  final List<_Bubble> bubbles;
  final List<_Particle> particles;
  final List<_Pop> pops;
  final double now;

  static const Color _warm = Color(0xFFFFC478);
  static const Color _gold = Color(0xFFFFE6A8);
  static const Color _drop = Color(0xFFFFB985);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final k = ((now - p.born) / p.life).clamp(0.0, 1.0);
      final fade = 1 - k;
      switch (p.kind) {
        case _Kind.dot:
          canvas.drawCircle(
            p.pos,
            p.size * (1 - 0.6 * k),
            Paint()
              ..color = _warm.withValues(alpha: 0.55 * fade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        case _Kind.star:
          _star(
            canvas,
            p.pos,
            p.size * (1 - 0.5 * k),
            p.spin * (now - p.born),
            (k < 0.5 ? Colors.white : _gold).withValues(alpha: fade),
          );
        case _Kind.drop:
          canvas.drawCircle(
            p.pos,
            p.size * (1 - 0.4 * k),
            Paint()..color = _drop.withValues(alpha: 0.95 * fade),
          );
          canvas.drawCircle(
            p.pos - Offset(p.size * 0.3, p.size * 0.3),
            p.size * 0.35,
            Paint()..color = Colors.white.withValues(alpha: 0.7 * fade),
          );
      }
    }

    for (final p in pops) {
      final k = ((now - p.born) / 0.45).clamp(0.0, 1.0);
      const r = FeedBurstLayer.radius;
      // Волна от хлопка.
      canvas.drawCircle(
        p.center,
        r * (1 + 1.6 * Curves.easeOut.transform(k)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - k)
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - k)),
      );
      // Осколки оболочки разлетаются дугами.
      final rr = r * (1 + 0.9 * Curves.easeOut.transform(k));
      for (var i = 0; i < 5; i++) {
        final a0 = i * 2 * math.pi / 5 + 0.3;
        canvas.drawArc(
          Rect.fromCircle(center: p.center, radius: rr),
          a0,
          0.45,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.5 * (1 - k)
            ..color = const Color(0xFFFFF1DC).withValues(alpha: 1 - k),
        );
      }
      // «+25» влетает в кружок, уменьшаясь.
      final m = Curves.easeInCubic.transform(k);
      final at = Offset.lerp(p.center, p.target, m)!;
      _text(canvas, at, p.text, r * 0.8 * (1.15 - 0.55 * m), 1 - m * m);
    }

    for (final b in bubbles) {
      _bubble(canvas, b.where, b.text);
    }
  }

  void _bubble(
    Canvas canvas,
    ({Offset c, double sx, double sy, double rot, double scale, double alpha})
    w,
    String text,
  ) {
    const r = FeedBurstLayer.radius;
    final a = w.alpha;
    if (w.scale <= 0.01 || a <= 0) return;
    canvas.save();
    canvas.translate(w.c.dx, w.c.dy);
    canvas.rotate(w.rot);
    canvas.scale(w.sx * w.scale, w.sy * w.scale);

    // Тёплое свечение вокруг.
    canvas.drawCircle(
      Offset.zero,
      r * 1.55,
      Paint()
        ..color = _warm.withValues(alpha: 0.38 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Тело: медовое, светлее к бликовой стороне.
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            const Color(0xFFFFF7E8).withValues(alpha: 0.97 * a),
            const Color(0xFFFFD49A).withValues(alpha: 0.95 * a),
            const Color(0xFFF6A36E).withValues(alpha: 0.95 * a),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    // Светлый ободок.
    canvas.drawCircle(
      Offset.zero,
      r - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.6 * a),
    );
    // Отсвет снизу — полумесяц.
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.76),
      0.35,
      2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withValues(alpha: 0.28 * a),
    );
    // Блик.
    canvas.save();
    canvas.translate(-r * 0.36, -r * 0.46);
    canvas.rotate(-0.55);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 0.66, height: r * 0.34),
      Paint()..color = Colors.white.withValues(alpha: 0.82 * a),
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(r * 0.02, -r * 0.66),
      r * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.8 * a),
    );
    _text(canvas, const Offset(0, 1), text, r * 0.78, a);
    canvas.restore();
  }

  void _text(Canvas canvas, Offset at, String text, double size, double a) {
    if (a <= 0) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: size,
          height: 1,
          fontVariations: const [FontVariation('wght', 900)],
          color: Colors.white.withValues(alpha: a),
          shadows: [
            Shadow(
              color: const Color(0xFF9A4A1E).withValues(alpha: 0.65 * a),
              blurRadius: 2.5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  void _star(Canvas canvas, Offset c, double r, double turn, Color color) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn);
    final w = r * 0.3;
    final path = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(w, -w, r, 0)
      ..quadraticBezierTo(w, w, 0, r)
      ..quadraticBezierTo(-w, w, -r, 0)
      ..quadraticBezierTo(-w, -w, 0, -r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}
