import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/food.dart';
import '../l10n/food_l10n.dart';
import '../l10n/l10n.dart';
import 'dish_carousel.dart';
import 'scene_label.dart';

/// Готовка прямо на кухне, без шторки (вариант A, утверждён заказчиком
/// 24.09).
///
/// Рецепт выбран на столе ([DishCarousel] с рецептами). Дальше:
/// - стол пустой — заказчик: «стол должен быть пустой, а когда
///   ингредиенты правильно собраны — оно появляется красиво на столе у
///   мишки в том же размере, как готовые блюда»;
/// - на скатерти то же табло, что у готовых блюд: название рецепта,
///   кружки шагов и награда; под ним крестик — бросить готовку;
/// - продукты стоят в ряд на полу под столом, у каждого подпись в стиле
///   подписей комнат ([SceneLabel]);
/// - нужный продукт подпрыгивает и растворяется с искорками, на табло
///   закрашивается кружок;
/// - не тот — подпрыгивает и возвращается на место, мишка мотает головой
///   ([onWrong]), а нужный продукт начинает покачиваться — подсказка.
///   Так же он покачивается, если долго ничего не выбирают. Порядок шагов
///   важен (КП 8.4), без подсказки ребёнку его не угадать;
/// - всё собрано — блюдо вырастает на столе перед мишкой с искорками, в
///   размере и на месте готового блюда ([DishArcGeometry.plate]); мишка
///   его ест, потом тарелка уходит.
///
/// Лежит поверх всей комнаты: ряд продуктов раскладывается по ширине
/// экрана (кадр кухни шире телефона, и его края срезаны), а стол, табло и
/// блюдо — в долях кадра [frame].
class KitchenCooking extends StatefulWidget {
  const KitchenCooking({
    super.key,
    required this.frame,
    required this.recipe,
    required this.onClose,
    this.onWrong,
    this.onCooked,
    this.onServe,
    this.onFinished,
    this.random,
  });

  /// Кадр кухни в координатах этого слоя.
  final Rect frame;
  final Recipe recipe;

  /// Крестик под табло — бросить готовку.
  final VoidCallback onClose;

  /// Выбрали не тот продукт: мишка мотает головой.
  final VoidCallback? onWrong;

  /// Всё собрано, блюдо появилось на столе: награда и еда.
  final ValueChanged<Recipe>? onCooked;

  /// Блюдо встало на стол — мишка начинает есть.
  final ValueChanged<Recipe>? onServe;

  /// Мишка доел, тарелка ушла — готовку можно убирать.
  final VoidCallback? onFinished;

  /// Порядок продуктов в ряду. Для тестов — с зерном.
  final math.Random? random;

  /// Прыжок продукта: нужный растворяется, не тот возвращается.
  static const Duration hop = Duration(milliseconds: 650);

  /// Блюдо вырастает на столе.
  static const Duration pop = Duration(milliseconds: 750);

  /// После последнего продукта — до появления блюда.
  static const Duration popDelay = Duration(milliseconds: 420);

  /// Блюдо появилось — через сколько мишка начинает есть.
  static const Duration serveDelay = Duration(milliseconds: 900);

  /// Сколько блюдо стоит перед мишкой, пока он ест (еда в сцене кухни —
  /// 6.7 с), и за сколько тарелка уходит.
  static const Duration eatHold = Duration(milliseconds: 6400);
  static const Duration leave = Duration(milliseconds: 600);

  /// Сколько ждать выбора, прежде чем подсказать нужный продукт.
  static const Duration idleHint = Duration(seconds: 6);

  @override
  State<KitchenCooking> createState() => _KitchenCookingState();
}

class _KitchenCookingState extends State<KitchenCooking>
    with TickerProviderStateMixin {
  /// Порядок продуктов в ряду: индексы в [Recipe.allChoices], перемешаны.
  late final List<int> _order;

  /// Сколько шагов уже собрано.
  int _step = 0;

  /// Положенные продукты: их в ряду больше нет.
  final Set<int> _used = {};

  /// Закрашенные кружки на табло — плавно, кружок за кружком.
  late final AnimationController _fill = AnimationController.unbounded(
    vsync: this,
  );

  /// Прыжок продукта [_hopIndex]: нужного ([_hopRight]) или нет.
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: KitchenCooking.hop,
  );
  int? _hopIndex;
  bool _hopRight = false;

  /// Покачивание подсказки.
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _hinting = false;

  /// Блюдо на столе: вырастает, потом уходит.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: KitchenCooking.pop,
  );
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: KitchenCooking.leave,
  );

  final List<Timer> _timers = [];
  Timer? _idle;

  Recipe get _recipe => widget.recipe;
  List<Ingredient> get _choices => _recipe.allChoices;
  bool get _serving => _step >= _recipe.steps.length;

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(_choices.length, (i) => i)
      ..shuffle(widget.random ?? math.Random());
    _waitForHint();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _fill.dispose();
    _hop.dispose();
    _hint.dispose();
    _pop.dispose();
    _leave.dispose();
    super.dispose();
  }

  void _later(Duration after, VoidCallback then) {
    _timers.add(
      Timer(after, () {
        if (mounted) then();
      }),
    );
  }

  /// Долго не выбирают — подсказать нужный продукт.
  void _waitForHint() {
    _idle?.cancel();
    _idle = Timer(KitchenCooking.idleHint, () {
      if (mounted && !_serving) _startHint();
    });
  }

  void _startHint() {
    if (_hinting) return;
    setState(() => _hinting = true);
    _hint.repeat();
  }

  void _stopHint() {
    if (!_hinting) return;
    _hint.stop();
    _hint.value = 0;
    _hinting = false;
  }

  void _tap(int index) {
    if (_serving || _used.contains(index)) return;
    final right = index == _step;
    setState(() {
      _hopIndex = index;
      _hopRight = right;
      if (right) {
        _used.add(index);
        _step++;
        _stopHint();
      }
    });
    _hop.forward(from: 0);
    if (right) {
      _fill.animateTo(
        _step.toDouble(),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      if (_serving) {
        _idle?.cancel();
        _later(KitchenCooking.popDelay, _serve);
      } else {
        _waitForHint();
      }
    } else {
      widget.onWrong?.call();
      _startHint();
      _waitForHint();
    }
  }

  /// Всё собрано: блюдо вырастает на столе, мишка ест, тарелка уходит.
  void _serve() {
    _pop.forward(from: 0);
    widget.onCooked?.call(_recipe);
    _later(KitchenCooking.serveDelay, () => widget.onServe?.call(_recipe));
    _later(KitchenCooking.serveDelay + KitchenCooking.eatHold, () {
      _leave.forward(from: 0).whenComplete(() {
        if (mounted) widget.onFinished?.call();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return AnimatedBuilder(
          animation: Listenable.merge([_fill, _hop, _hint, _pop, _leave]),
          builder: (context, _) {
            final frame = widget.frame;
            final scale = frame.height / 844;
            final popT = _pop.value;
            // Табло, крестик и ряд гаснут, пока вырастает блюдо.
            final chrome = (1 - popT * 1.6).clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (_pop.value > 0) ..._dish(frame, scale),
                if (chrome > 0) ...[
                  ..._row(context, screen, frame, scale, chrome),
                  _board(context, frame, scale, chrome),
                  if (!_serving)
                    TableBoard.closeButton(
                      key: const ValueKey('cook-close'),
                      size: frame.size,
                      origin: frame.topLeft,
                      label: context.l10n.cookClose,
                      onClose: widget.onClose,
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // --- Табло ---------------------------------------------------------------

  Widget _board(BuildContext context, Rect frame, double scale, double alpha) {
    final line = TableBoardLine(
      text: BoardText(
        name: recipeName(context.l10n, _recipe.id),
        value: '+${_recipe.reward}',
        steps: _recipe.steps.length,
        done: _fill.value,
      ),
      scale: scale,
    );
    final height = TableBoard.height(scale);
    final width = line.width + 20 * scale;
    final cx = frame.left + frame.width * TableBoard.center.dx;
    final cy = frame.top + frame.height * TableBoard.center.dy;
    return Positioned(
      key: const ValueKey('cook-board'),
      left: cx - width / 2,
      top: cy - height / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Opacity(
          opacity: alpha,
          child: DecoratedBox(
            decoration: TableBoard.decoration(scale),
            child: OverflowBox(
              maxWidth: double.infinity,
              child: Center(child: line),
            ),
          ),
        ),
      ),
    );
  }

  // --- Ряд продуктов под столом -------------------------------------------

  /// Где стоят продукты: донышки на полу под столом, подписи под ними.
  /// Доли кадра — по согласованному макету A.
  static const double _floor = 0.842;
  static const double _labelY = 0.856;

  /// Больше семи продуктов в ряд не помещаются с подписями: тогда подписи
  /// через одну опускаются на строчку ниже.
  static const int _oneLine = 7;

  List<Widget> _row(
    BuildContext context,
    Size screen,
    Rect frame,
    double scale,
    double alpha,
  ) {
    final l10n = context.l10n;
    final n = _order.length;
    final span = screen.width * 0.94;
    final left = (screen.width - span) / 2;
    final slot = span / n;
    final floor = frame.top + frame.height * _floor;
    final labelY = frame.top + frame.height * _labelY;
    final box = math.min(40 * scale, slot * 0.86);
    final zigzag = n > _oneLine;
    final next = _serving ? null : _step;

    final widgets = <Widget>[];
    for (var k = 0; k < n; k++) {
      final i = _order[k];
      final hopping = _hopIndex == i && _hop.isAnimating;
      if (_used.contains(i) && !hopping) continue;
      final ingredient = _choices[i];
      final cx = left + slot * (k + 0.5);

      var dy = 0.0;
      var turn = 0.0;
      var grow = 1.0;
      var fade = 1.0;
      var sparkle = 0.0;
      if (hopping) {
        final t = _hop.value;
        if (_hopRight) {
          // Подпрыгнул — и растаял с искорками.
          final up = Curves.easeOutCubic.transform((t / 0.42).clamp(0, 1));
          dy = -26 * scale * up;
          final melt = ((t - 0.38) / 0.62).clamp(0.0, 1.0);
          grow = 1 + 0.3 * melt;
          fade = 1 - Curves.easeIn.transform(melt);
          sparkle = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
        } else {
          // Подпрыгнул, качнулся «нет-нет» — и вернулся на место.
          final a = (t / 0.55).clamp(0.0, 1.0);
          final b = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
          dy =
              -20 * scale * math.sin(math.pi * a) -
              6 * scale * math.sin(math.pi * b);
          turn = 0.2 * math.sin(2 * math.pi * 2 * t) * (1 - t);
        }
      } else if (_hinting && i == next) {
        // Подсказка: нужный продукт мягко покачивается.
        final w = 0.5 - 0.5 * math.cos(2 * math.pi * _hint.value);
        dy = -6 * scale * w;
        grow = 1 + 0.06 * w;
      }

      final labelDrop = zigzag && k.isOdd ? 17 * scale : 0.0;
      final name = ingredientName(l10n, ingredient);

      // Тень на полу — на месте, пока продукт в прыжке.
      widgets.add(
        Positioned(
          key: ValueKey('cook-shadow-${ingredient.id}'),
          left: cx - box * 0.45,
          top: floor - 4 * scale,
          width: box * 0.9,
          height: 8 * scale,
          child: IgnorePointer(
            child: Opacity(
              opacity: alpha * fade * (1 - (-dy / (40 * scale)).clamp(0, 0.6)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF50371E).withValues(alpha: 0.28),
                      blurRadius: 5 * scale,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Продукт и подпись — одно поле для пальца.
      widgets.add(
        Positioned(
          key: ValueKey('cook-item-${ingredient.id}'),
          left: cx - slot / 2,
          top: floor - box - 10 * scale,
          width: slot,
          height: box + 10 * scale + (labelY - floor) + labelDrop + 12 * scale,
          child: Semantics(
            button: true,
            label: l10n.cookIngredient(name),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tap(i),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      widgets.add(
        Positioned(
          left: cx - box / 2,
          top: floor - box + dy,
          width: box,
          height: box,
          child: IgnorePointer(
            child: Opacity(
              opacity: (alpha * fade).clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: turn,
                alignment: Alignment.bottomCenter,
                child: Transform.scale(
                  scale: grow,
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    ingredient.image,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (sparkle > 0) {
        widgets.add(
          Positioned(
            left: cx - box,
            top: floor - box * 1.5 + dy,
            width: box * 2,
            height: box * 2,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _Sparkles(progress: sparkle, scale: scale),
              ),
            ),
          ),
        );
      }

      widgets.add(
        Positioned(
          left: cx - slot,
          top: labelY + labelDrop - 8 * scale,
          width: slot * 2,
          height: 16 * scale,
          child: IgnorePointer(
            child: Opacity(
              opacity: (alpha * (hopping && _hopRight ? fade : 1)).clamp(
                0.0,
                1.0,
              ),
              child: Center(
                child: SceneLabel(
                  text: name,
                  size: 8.5 * scale,
                  weight: 750,
                  padding: EdgeInsets.symmetric(
                    horizontal: 6 * scale,
                    vertical: 1.5 * scale,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  // --- Готовое блюдо на столе ---------------------------------------------

  List<Widget> _dish(Rect frame, double scale) {
    final place = DishArcGeometry.plate(
      _recipe.id,
      0,
      frame.size,
    ).shift(frame.topLeft);
    final t = _pop.value;
    final grow = 0.55 + 0.45 * Curves.easeOutBack.transform(t);
    final alpha =
        Curves.easeOut.transform((t / 0.45).clamp(0.0, 1.0)) *
        (1 - _leave.value);
    return [
      Positioned.fromRect(
        key: const ValueKey('cook-dish'),
        rect: place,
        child: IgnorePointer(
          child: Opacity(
            opacity: alpha,
            child: Transform.scale(
              scale: grow,
              alignment: Alignment.bottomCenter,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _PlateShadow(scale: scale)),
                  Image.asset(
                    _recipe.image,
                    key: ValueKey('cook-dish-${_recipe.id}'),
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.medium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (t < 1)
        Positioned.fromRect(
          rect: Rect.fromCenter(
            center: place.center.translate(0, place.height * 0.15),
            width: place.width * 1.7,
            height: place.width * 1.7,
          ),
          child: IgnorePointer(
            child: CustomPaint(
              painter: _Sparkles(progress: t, scale: scale * 1.8, count: 12),
            ),
          ),
        ),
    ];
  }
}

/// Тень под готовым блюдом — такая же, как под блюдами на дуге в покое.
class _PlateShadow extends CustomPainter {
  _PlateShadow({required this.scale});

  final double scale;

  static const Color _shadow = Color(0xFF50371E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final bottom = size.height;
    void oval(double rw, double rh, double opacity, double blur) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, bottom), width: rw, height: rh),
        Paint()
          ..color = _shadow.withValues(alpha: opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * scale),
      );
    }

    oval(w * 0.94, w * 0.2, 0.28, 7);
    oval(w * 0.70, w * 0.08, 0.47, 2.5);
  }

  @override
  bool shouldRepaint(_PlateShadow old) => old.scale != scale;
}

/// Искорки: четырёхлучевые звёздочки разлетаются из середины и гаснут.
class _Sparkles extends CustomPainter {
  _Sparkles({required this.progress, required this.scale, this.count = 8});

  final double progress;
  final double scale;
  final int count;

  static const List<Color> _colors = [
    Color(0xFFFFE9A8),
    Colors.white,
    Color(0xFFFFD36E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final c = size.center(Offset.zero);
    final reach = size.shortestSide * 0.48;
    final out = Curves.easeOutCubic.transform(progress);
    final fade = 1 - Curves.easeIn.transform(progress);
    for (var i = 0; i < count; i++) {
      final angle = 2 * math.pi * i / count + (i.isOdd ? 0.25 : 0);
      final dist = reach * (0.35 + 0.65 * out) * (i.isOdd ? 0.8 : 1);
      final p = c + Offset(math.cos(angle), math.sin(angle)) * dist;
      final r = (i.isOdd ? 3.2 : 4.4) * scale * (1 - 0.4 * progress);
      _star(canvas, p, r, _colors[i % _colors.length].withValues(alpha: fade));
    }
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final w = r * 0.32;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Sparkles old) => old.progress != progress;
}
