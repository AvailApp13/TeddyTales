import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sounds.dart';
import '../l10n/l10n.dart';

/// Что оказалось в подарке дня: монеты (заказчик 25.09 — только монеты,
/// никаких вещей и мишек).
class GiftOutcome {
  const GiftOutcome({this.coins = 0});

  final int coins;
}

/// Открытие подарка дня (заказчик 25.09: «конверты мы делаем»).
///
/// Дни 1–6 — красный конверт с золотой печатью: покачивается, по касанию
/// дрожит, клапан откидывается, выезжает карточка с монетами, монеты летят
/// к кошельку, сыплется конфетти. День 7 — большая коробка с бантом на
/// фоне лучей: крышка слетает, из коробки поднимаются монеты.
///
/// Готовой анимации конверта, доступной для скачивания, не нашлось (сайты
/// LottieFiles и Rive закрыты для среды сборки), поэтому всё нарисовано
/// здесь — как пузырь сытости: без картинок и лицензий.
///
/// [claim] забирает подарок на сервере; `null` — не вышло (окно
/// закрывается, экран подарка покажет ошибку).
Future<GiftOutcome?> showGiftReveal(
  BuildContext context, {
  required bool box,
  required Future<GiftOutcome?> Function() claim,
}) => showGeneralDialog<GiftOutcome>(
  context: context,
  barrierDismissible: false,
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 250),
  pageBuilder: (_, _, _) => GiftReveal(box: box, claim: claim),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

class GiftReveal extends StatefulWidget {
  const GiftReveal({super.key, required this.box, required this.claim});

  final bool box;
  final Future<GiftOutcome?> Function() claim;

  /// Длина раскрытия — от касания до карточки с наградой.
  static const Duration open = Duration(milliseconds: 2600);

  @override
  State<GiftReveal> createState() => _GiftRevealState();
}

enum _Phase { waiting, claiming, opening, done }

class _GiftRevealState extends State<GiftReveal> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: GiftReveal.open,
  );
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  _Phase _phase = _Phase.waiting;
  GiftOutcome? _outcome;
  final List<_Confetto> _confetti = [];
  final math.Random _dice = math.Random();

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void dispose() {
    _idle.dispose();
    _open.dispose();
    _rays.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_phase != _Phase.waiting) return;
    setState(() => _phase = _Phase.claiming);
    HapticFeedback.lightImpact();
    final outcome = await widget.claim();
    if (!mounted) return;
    if (outcome == null) {
      Navigator.of(context).pop();
      return;
    }
    _outcome = outcome;
    _confetti
      ..clear()
      ..addAll(List.generate(70, (_) => _Confetto.random(_dice)));
    setState(() => _phase = _Phase.opening);
    HapticFeedback.mediumImpact();
    Sounds.play(Sfx.bubblePop);
    if (_still) {
      _open.value = 1;
    } else {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Sounds.play(widget.box ? Sfx.fill : Sfx.coinsEarn);
      });
      await _open.forward();
    }
    if (mounted) setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    // Кошелёк — слева в шапке: туда летят монеты.
    final wallet = Offset(52, topPad + 30);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _phase == _Phase.done
            ? () => Navigator.of(context).pop(_outcome)
            : _tap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _open, _rays]),
          builder: (context, _) {
            final t = _open.value;
            final center = Offset(size.width / 2, size.height * 0.46);
            return Stack(
              children: [
                // Затемнение.
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xFF1E0F12).withValues(alpha: 0.72),
                  ),
                ),
                // Лучи за подарком — у коробки всегда, у конверта при
                // раскрытии.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RaysPainter(
                      center: center,
                      turn: _rays.value,
                      strength: widget.box
                          ? 0.55 + 0.45 * t
                          : Curves.easeOut.transform(t),
                    ),
                  ),
                ),
                Positioned(
                  left: center.dx - 120,
                  top: center.dy - 160,
                  width: 240,
                  height: 320,
                  child: widget.box
                      ? _Box(
                          idle: _idle.value,
                          claiming: _phase == _Phase.claiming,
                          t: t,
                          coins: _outcome?.coins ?? 0,
                        )
                      : _Envelope(
                          idle: _idle.value,
                          claiming: _phase == _Phase.claiming,
                          t: t,
                          coins: _outcome?.coins ?? 0,
                        ),
                ),
                // Монеты к кошельку и конфетти.
                if (_phase == _Phase.opening || _phase == _Phase.done)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _BurstPainter(
                          t: t,
                          from: center + const Offset(0, -40),
                          wallet: wallet,
                          coins: widget.box || (_outcome?.coins ?? 0) == 0
                              ? 0
                              : 14,
                          confetti: _confetti,
                          size: size,
                        ),
                      ),
                    ),
                  ),
                // Подсказки.
                Positioned(
                  left: 24,
                  right: 24,
                  top: center.dy + 185,
                  child: Text(
                    switch (_phase) {
                      _Phase.waiting || _Phase.claiming =>
                        widget.box ? l10n.giftBoxTap : l10n.giftEnvelopeTap,
                      _Phase.opening || _Phase.done => _caption(l10n),
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE9B0),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                if (_phase == _Phase.done)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.paddingOf(context).bottom + 36,
                    child: Center(
                      child: FilledButton(
                        key: const ValueKey('gift-collect'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE0A93B),
                          foregroundColor: const Color(0xFF4A1A10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 36,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(_outcome),
                        child: Text(
                          l10n.giftCollect,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _caption(AppLocalizations l10n) {
    final outcome = _outcome;
    if (outcome == null) return '';
    return l10n.giftCoinsCaption(outcome.coins);
  }
}

// --- Конверт -----------------------------------------------------------------

const _red = Color(0xFFD42A33);
const _redDark = Color(0xFFA3161E);
const _gold = Color(0xFFF2C14E);
const _goldDark = Color(0xFFC7922B);
const _cream = Color(0xFFFFF6E3);

class _Envelope extends StatelessWidget {
  const _Envelope({
    required this.idle,
    required this.claiming,
    required this.t,
    required this.coins,
  });

  final double idle;
  final bool claiming;
  final double t;
  final int coins;

  @override
  Widget build(BuildContext context) {
    // Покачивание в ожидании; частая дрожь, пока сервер отвечает, и в
    // начале раскрытия.
    final shakeAmp = claiming ? 0.07 : (t > 0 && t < 0.18 ? 0.09 : 0.0);
    final wobble = t == 0
        ? math.sin(idle * math.pi * 2) * 0.035 +
              (idle > 0.8 ? math.sin(idle * math.pi * 30) * 0.03 : 0)
        : 0.0;
    final shake = math.sin((claiming ? idle : t) * math.pi * 60) * shakeAmp;
    final bob = t == 0 ? math.sin(idle * math.pi * 2) * 6 : 0.0;
    // Раскрытие: клапан 0.15–0.4, карточка 0.3–0.6.
    final flap = Curves.easeInOut.transform(_seg(t, 0.15, 0.4));
    final card = Curves.easeOutBack.transform(_seg(t, 0.3, 0.62));
    final pop = t > 0 ? 1 + 0.08 * math.sin(_seg(t, 0, 0.2) * math.pi) : 1.0;

    return Transform.translate(
      offset: Offset(0, bob),
      child: Transform.rotate(
        angle: wobble + shake,
        child: Transform.scale(
          scale: pop,
          child: Center(
            child: SizedBox(
              width: 190,
              height: 250,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Задняя стенка.
                  Positioned.fill(
                    child: CustomPaint(painter: _EnvelopeBackPainter()),
                  ),
                  // Клапан, откинутый назад, — за карточкой.
                  if (flap > 0.5) _flapWidget(flap),
                  // Карточка с наградой.
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 40 - 150 * card,
                    height: 150,
                    child: _Card(coins: coins, shown: card),
                  ),
                  // Передний карман.
                  Positioned.fill(
                    child: CustomPaint(painter: _EnvelopeFrontPainter()),
                  ),
                  // Клапан закрыт или только начал подниматься — спереди.
                  if (flap <= 0.5) _flapWidget(flap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flapWidget(double flap) => Positioned(
    left: 0,
    right: 0,
    top: 0,
    height: 125,
    child: Transform(
      alignment: Alignment.topCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0025)
        ..rotateX(-math.pi * flap),
      child: CustomPaint(painter: _FlapPainter(back: flap > 0.5)),
    ),
  );
}

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

class _EnvelopeBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.drawRRect(r, Paint()..color = _redDark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EnvelopeFrontPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Карман — нижние две трети с мягким «V» сверху.
    final top = size.height * 0.36;
    final path = Path()
      ..moveTo(0, top)
      ..quadraticBezierTo(size.width / 2, top + 46, size.width, top)
      ..lineTo(size.width, size.height - 16)
      ..quadraticBezierTo(size.width, size.height, size.width - 16, size.height)
      ..lineTo(16, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 16)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_red, _redDark],
        ).createShader(Offset.zero & size),
    );
    // Золотая кайма и узор.
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, top + 30, size.width - 20, size.height - top - 40),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..color = _gold.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Золотые «облачка» по углам — как на праздничных конвертах.
    final cloud = Paint()
      ..color = _gold.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (final c in [
      Offset(28, size.height - 30),
      Offset(size.width - 28, size.height - 30),
    ]) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 9),
        math.pi,
        math.pi,
        false,
        cloud,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c + const Offset(9, 3), radius: 6),
        math.pi,
        math.pi,
        false,
        cloud,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlapPainter extends CustomPainter {
  _FlapPainter({required this.back});

  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 16)
      ..quadraticBezierTo(0, 0, 16, 0)
      ..lineTo(size.width - 16, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 16)
      ..lineTo(size.width / 2 + 16, size.height - 12)
      ..quadraticBezierTo(
        size.width / 2,
        size.height,
        size.width / 2 - 16,
        size.height - 12,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: back ? [_redDark, _redDark] : [const Color(0xFFE23A41), _red],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _gold.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    if (back) return;
    // Золотая печать с лапкой на кончике клапана.
    final seal = Offset(size.width / 2, size.height - 14);
    canvas.drawCircle(
      seal,
      27,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFE08A), _gold, _goldDark],
        ).createShader(Rect.fromCircle(center: seal, radius: 27)),
    );
    canvas.drawCircle(
      seal,
      22,
      Paint()
        ..color = _redDark.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.pets.codePoint),
        style: TextStyle(
          fontFamily: Icons.pets.fontFamily,
          package: Icons.pets.fontPackage,
          fontSize: 24,
          color: _redDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, seal - Offset(icon.width / 2, icon.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FlapPainter oldDelegate) =>
      oldDelegate.back != back;
}

/// Карточка внутри конверта: «+20» и монетка.
class _Card extends StatelessWidget {
  const _Card({required this.coins, required this.shown});

  final int coins;
  final double shown;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold, width: 2),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.6 * shown),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Opacity(
          opacity: shown.clamp(0.0, 1.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CoinIcon(size: 40),
              const SizedBox(height: 6),
              Text(
                '+$coins',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: _redDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinIcon extends StatelessWidget {
  const _CoinIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      _drawCoin(canvas, size.center(Offset.zero), size.width / 2, 1);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _drawCoin(Canvas canvas, Offset c, double r, double squeeze) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.scale(squeeze.clamp(0.15, 1.0), 1);
  final rect = Rect.fromCircle(center: Offset.zero, radius: r);
  canvas.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [Color(0xFFFFE9A3), _gold, _goldDark],
      ).createShader(rect),
  );
  canvas.drawCircle(
    Offset.zero,
    r * 0.72,
    Paint()
      ..color = _goldDark.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.1,
  );
  canvas.restore();
}

// --- Коробка -----------------------------------------------------------------

class _Box extends StatelessWidget {
  const _Box({
    required this.idle,
    required this.claiming,
    required this.t,
    required this.coins,
  });

  final double idle;
  final bool claiming;
  final double t;
  final int coins;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Коробка подпрыгивает в ожидании, трясётся перед раскрытием.
    final hop = t == 0
        ? -math.max(0.0, math.sin(idle * math.pi * 2)) * 10
        : 0.0;
    final shake = claiming || (t > 0 && t < 0.2)
        ? math.sin((claiming ? idle : t) * math.pi * 50) * 0.05
        : 0.0;
    final squash = t > 0 && t < 0.22
        ? math.sin(_seg(t, 0, 0.22) * math.pi)
        : 0.0;
    // Крышка: 0.2–0.5 взлетает и уходит вправо-вверх, вращаясь.
    final lid = Curves.easeOutCubic.transform(_seg(t, 0.2, 0.55));
    // Монеты: 0.35–0.75 поднимаются и растут.
    final rise = Curves.easeOutBack.transform(_seg(t, 0.35, 0.75));

    return Transform.translate(
      offset: Offset(0, hop),
      child: Transform.rotate(
        angle: shake,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Монеты поднимаются из коробки.
            Positioned(
              bottom: 110 + 120 * rise,
              child: Opacity(
                opacity: _seg(t, 0.35, 0.5),
                child: Transform.scale(
                  scale: 0.3 + 0.9 * rise,
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _CoinIcon(size: 56),
                          Text(
                            '+$coins',
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Коробка.
            Positioned(
              bottom: 0,
              child: Transform.scale(
                scaleX: 1 + 0.08 * squash,
                scaleY: 1 - 0.1 * squash,
                alignment: Alignment.bottomCenter,
                child: const SizedBox(
                  width: 200,
                  height: 140,
                  child: CustomPaint(painter: _BoxPainter()),
                ),
              ),
            ),
            // Крышка с бантом.
            Positioned(
              bottom: 128 + 160 * lid,
              left: 12 + 150 * lid,
              child: Opacity(
                opacity: 1 - _seg(t, 0.45, 0.6),
                child: Transform.rotate(
                  angle: 0.9 * lid,
                  child: const SizedBox(
                    width: 216,
                    height: 90,
                    child: CustomPaint(painter: _LidPainter()),
                  ),
                ),
              ),
            ),
            // Надпись над крышкой — под коробкой место подсказки.
            if (t == 0)
              Positioned(
                bottom: 236,
                child: Text(
                  l10n.giftBoxDay7,
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_red, _redDark],
        ).createShader(Offset.zero & size),
    );
    // Лента по центру.
    canvas.drawRect(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 30,
        height: size.height,
      ),
      Paint()
        ..shader = const LinearGradient(colors: [_goldDark, _gold, _goldDark])
            .createShader(
              Rect.fromCenter(
                center: size.center(Offset.zero),
                width: 30,
                height: size.height,
              ),
            ),
    );
    // Тень от крышки.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 10),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LidPainter extends CustomPainter {
  const _LidPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height - 40, size.width, 40),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE5424A), _red],
        ).createShader(lid.outerRect),
    );
    final cx = size.width / 2;
    canvas.drawRect(
      Rect.fromLTWH(cx - 15, size.height - 40, 30, 40),
      Paint()..color = _gold,
    );
    // Бант: две петли и узелок.
    final bow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFE08A), _gold, _goldDark],
      ).createShader(Rect.fromLTWH(cx - 60, 0, 120, size.height - 30));
    final knotY = size.height - 44;
    for (final side in [-1.0, 1.0]) {
      final loop = Path()
        ..moveTo(cx, knotY)
        ..cubicTo(
          cx + side * 20,
          knotY - 50,
          cx + side * 70,
          knotY - 40,
          cx + side * 52,
          knotY - 6,
        )
        ..cubicTo(
          cx + side * 40,
          knotY + 10,
          cx + side * 14,
          knotY + 4,
          cx,
          knotY,
        )
        ..close();
      canvas.drawPath(loop, bow);
      canvas.drawPath(
        loop,
        Paint()
          ..color = _goldDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    canvas.drawCircle(Offset(cx, knotY), 11, Paint()..color = _goldDark);
    canvas.drawCircle(Offset(cx, knotY), 8, Paint()..color = _gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Лучи, монеты, конфетти --------------------------------------------------

class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.center,
    required this.turn,
    required this.strength,
  });

  final Offset center;
  final double turn;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    canvas.drawCircle(
      center,
      190,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: 0.45 * strength),
            _gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 190)),
    );
    final paint = Paint()..color = _gold.withValues(alpha: 0.12 * strength);
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final a = turn * math.pi * 2 + i * math.pi * 2 / rays;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(a - 0.08) * 420,
          center.dy + math.sin(a - 0.08) * 420,
        )
        ..lineTo(
          center.dx + math.cos(a + 0.08) * 420,
          center.dy + math.sin(a + 0.08) * 420,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) =>
      old.turn != turn || old.strength != strength;
}

class _Confetto {
  _Confetto(
    this.x,
    this.vx,
    this.vy,
    this.spin,
    this.color,
    this.w,
    this.delay,
  );

  factory _Confetto.random(math.Random d) => _Confetto(
    d.nextDouble() * 2 - 1,
    d.nextDouble() * 160 - 80,
    -260 - d.nextDouble() * 260,
    d.nextDouble() * 14 - 7,
    const [_red, _gold, _cream, Color(0xFFE5424A), Color(0xFFFFE08A)][d.nextInt(
      5,
    )],
    5 + d.nextDouble() * 6,
    d.nextDouble() * 0.12,
  );

  final double x;
  final double vx;
  final double vy;
  final double spin;
  final Color color;
  final double w;
  final double delay;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.from,
    required this.wallet,
    required this.coins,
    required this.confetti,
    required this.size,
  });

  final double t;
  final Offset from;
  final Offset wallet;
  final int coins;
  final List<_Confetto> confetti;
  final Size size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // Конфетти: вылетает с раскрытием (0.3) и оседает до конца.
    final ct = _seg(t, 0.3, 1.0) * GiftReveal.open.inMilliseconds / 1000;
    for (final c in confetti) {
      final s = (ct - c.delay).clamp(0.0, 10.0);
      if (s <= 0) continue;
      final p =
          from + Offset(c.x * 30 + c.vx * s, c.vy * s + 0.5 * 520 * s * s);
      if (p.dy > size.height + 20) continue;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(c.spin * s);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: c.w, height: c.w * 0.55),
        Paint()
          ..color = c.color.withValues(
            alpha: (1 - _seg(t, 0.85, 1)).clamp(0.0, 1.0),
          ),
      );
      canvas.restore();
    }
    // Монеты: по дуге к кошельку, одна за другой (0.45–0.95).
    for (var i = 0; i < coins; i++) {
      final start = 0.45 + i * 0.025;
      final u = _seg(t, start, start + 0.3);
      if (u <= 0 || u >= 1) continue;
      final e = Curves.easeInCubic.transform(u);
      final mid = Offset(
        (from.dx + wallet.dx) / 2 + (i.isEven ? 60 : -40),
        math.min(from.dy, wallet.dy) - 60,
      );
      final a = Offset.lerp(from, mid, e)!;
      final b = Offset.lerp(mid, wallet, e)!;
      final p = Offset.lerp(a, b, e)!;
      _drawCoin(canvas, p, 12 - 5 * e, math.cos(u * math.pi * 4).abs());
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
