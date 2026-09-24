import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../game/food.dart';
import '../theme/app_colors.dart';
import 'scene_label.dart';

/// Готовые блюда прямо на столе кухни — дугой, с прокруткой по кругу.
///
/// Заказчик 24.09: «при нажатии на „Готовые блюда“ они показываются сразу
/// на столе, без рамки и обводки, под каждым видна цена; прокрутка пальцем
/// влево и вправо по кругу, без стопоров». Уточнение: «паста посередине
/// перед мишкой — на столе; по бокам чуть выше, скролл полукругом; уходящее
/// блюдо уменьшается и поднимается, приходящее увеличивается и садится на
/// стол». Макет и ролик согласованы тем же днём.
///
/// Блюдо на дуге описывает одно число `s` — где оно относительно центра:
/// 0 — перед мишкой на столе, ±1 — приподнято по бокам, дальше — уходит за
/// край и гаснет. Прокрутка просто сдвигает все `s` разом, поэтому
/// промежуточные положения получаются сами: размер, высота, наклон, тень и
/// цена плавно перетекают между «стоит» и «парит».
///
/// Геометрия — в долях кадра кухни, как у остальных её слоёв
/// (`KitchenScene`): кадр 941 × 1672, задний край стола на 0.6065.
class DishCarousel extends StatefulWidget {
  const DishCarousel({
    super.key,
    required this.dishes,
    required this.onBuy,
    this.onTapElsewhere,
    this.initial = 0,
  });

  final List<Dish> dishes;

  /// Нажали на блюдо перед мишкой — купить (окно подтверждения снаружи).
  final ValueChanged<Dish> onBuy;

  /// Нажали мимо блюд — отдать касание дальше (погладить мишку).
  final VoidCallback? onTapElsewhere;

  /// Какое блюдо стоит перед мишкой при открытии.
  final int initial;

  // --- Дуга, доли кадра ------------------------------------------------------

  /// Центр стола по горизонтали и шаг до соседнего места.
  static const double centerX = 0.5;
  static const double step = 0.276;

  /// Донышко: перед мишкой — на столешнице, по бокам — приподнято.
  static const double centerBottom = 0.6754;
  static const double sideBottom = 0.6043;

  /// Ширина тарелки перед мишкой и по бокам.
  static const double centerWidth = 0.261;
  static const double sideWidth = 0.168;

  /// Плоскость стола, на которую падает тень парящего блюда.
  static const double tableShadowY = 0.673;

  /// Наклон бокового блюда к центру, радианы (≈6°).
  static const double sideTilt = 0.105;

  /// Полоса, где ловятся свайпы и касания: от верха парящих блюд до
  /// свисающей скатерти. Выше и ниже касания уходят мишке.
  static const double bandTop = 0.50;
  static const double bandBottom = 0.78;

  /// Положение блюда [index] на дуге при сдвиге [offset] — по кругу, без
  /// краёв: после последнего снова первое.
  static double slot(int index, double offset, int count) {
    final raw = index - offset;
    final half = count / 2;
    return ((raw + half) % count + count) % count - half;
  }

  @override
  State<DishCarousel> createState() => _DishCarouselState();
}

class _DishCarouselState extends State<DishCarousel>
    with SingleTickerProviderStateMixin {
  late double _offset = widget.initial.toDouble();

  // Доводка после свайпа. Создаётся сразу, а не лениво: иначе при уходе
  // с кухни без касаний её создавал бы dispose().
  late final AnimationController _snap;
  late final CurvedAnimation _curve;

  Tween<double> _snapTween = Tween(begin: 0, end: 0);

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() => setState(() => _offset = _snapTween.evaluate(_curve)));
    _curve = CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic);
  }

  int get _count => widget.dishes.length;

  /// Блюдо перед мишкой.
  int get _current => (_offset.round() % _count + _count) % _count;

  @override
  void dispose() {
    _curve.dispose();
    _snap.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _snapTween = Tween(begin: _offset, end: target);
    _snap
      ..reset()
      ..forward();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _snap.stop();
    setState(() => _offset -= details.delta.dx / (width * DishCarousel.step));
  }

  void _onDragEnd(DragEndDetails details, double width) {
    // Бросок пальцем докручивает на одно блюдо, даже если сдвинули мало.
    final velocity = details.velocity.pixelsPerSecond.dx / width;
    var target = _offset.roundToDouble();
    if (velocity.abs() > 0.8 && (target - _offset).abs() < 0.5) {
      target = velocity < 0 ? _offset.ceilToDouble() : _offset.floorToDouble();
    }
    _animateTo(target);
  }

  void _onTap(Offset local, Size size) {
    if (_snap.isAnimating) return;
    for (final hit in _hitOrder(size)) {
      if (!hit.rect.contains(local)) continue;
      if (hit.s.abs() < 0.5) {
        widget.onBuy(widget.dishes[hit.index]);
      } else {
        // Боковое — подкатываем в центр, покупают уже его.
        _animateTo(_offset + hit.s.roundToDouble());
      }
      return;
    }
    widget.onTapElsewhere?.call();
  }

  /// Где что стоит: ближние к центру — первыми (они сверху).
  List<_Placed> _hitOrder(Size size) {
    final placed = [
      for (var i = 0; i < _count; i++)
        _Placed.at(i, DishCarousel.slot(i, _offset, _count), size),
    ]..removeWhere((p) => p.alpha <= 0.01);
    placed.sort((a, b) => a.s.abs().compareTo(b.s.abs()));
    return placed;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Рисуем от дальних к ближним: центральное — поверх соседей.
        final drawn = _hitOrder(size).reversed.toList();
        final scale = size.height / 844;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              key: const ValueKey('dish-shadows'),
              child: IgnorePointer(
                child: CustomPaint(painter: _ShadowPainter(drawn)),
              ),
            ),
            // Ключи обязательны: блюда появляются и гаснут по краям, и без
            // них полоса касаний пересоздавалась бы посреди свайпа.
            for (final p in drawn) ...[
              Positioned.fromRect(
                key: ValueKey('dish-slot-${p.index}'),
                rect: p.rect,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: p.alpha,
                    child: Transform.rotate(
                      angle: p.tilt,
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        widget.dishes[p.index].image,
                        key: ValueKey('dish-${widget.dishes[p.index].id}'),
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                key: ValueKey('dish-price-${p.index}'),
                left: p.rect.center.dx - 60 * scale,
                width: 120 * scale,
                top: p.priceTop,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: p.alpha,
                    child: Center(
                      child: _PriceChip(
                        price: widget.dishes[p.index].price,
                        scale: scale,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // Касания — только в полосе стола.
            Positioned(
              key: const ValueKey('dish-carousel-band'),
              left: 0,
              right: 0,
              top: size.height * DishCarousel.bandTop,
              height:
                  size.height *
                  (DishCarousel.bandBottom - DishCarousel.bandTop),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, size.width),
                onHorizontalDragEnd: (d) => _onDragEnd(d, size.width),
                onTapUp: (d) => _onTap(
                  d.localPosition.translate(
                    0,
                    size.height * DishCarousel.bandTop,
                  ),
                  size,
                ),
              ),
            ),
            // Для тестов и озвучки: какое блюдо сейчас перед мишкой.
            Positioned(
              key: const ValueKey('dish-carousel-current'),
              left: 0,
              top: 0,
              child: Semantics(
                label: widget.dishes[_current].id,
                child: const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Блюдо на своём месте дуги: где стоит, насколько «сел» на стол.
class _Placed {
  _Placed._({
    required this.index,
    required this.s,
    required this.rect,
    required this.tilt,
    required this.alpha,
    required this.land,
    required this.priceTop,
    required this.tableY,
  });

  factory _Placed.at(int index, double s, Size size) {
    final k = math.min(s.abs(), 1.0);
    final land = 1 - k;
    final width =
        size.width *
        lerpDouble(DishCarousel.centerWidth, DishCarousel.sideWidth, k)!;
    final bottom =
        size.height *
        lerpDouble(DishCarousel.centerBottom, DishCarousel.sideBottom, k)!;
    final cx = size.width * (DishCarousel.centerX + DishCarousel.step * s);
    // Высота с запасом: тарелки ниже квадрата, картинка прижата к низу.
    final height = width;
    var alpha = lerpDouble(1, 0.92, k)!;
    if (s.abs() > 1) alpha *= math.max(0, 1 - (s.abs() - 1) / 0.6);
    return _Placed._(
      index: index,
      s: s,
      rect: Rect.fromLTWH(cx - width / 2, bottom - height, width, height),
      tilt: -DishCarousel.sideTilt * s.clamp(-1.0, 1.0),
      alpha: alpha,
      land: land,
      priceTop: bottom + size.height * lerpDouble(6, 18, land)! / 844,
      tableY: size.height * DishCarousel.tableShadowY,
    );
  }

  final int index;
  final double s;
  final Rect rect;
  final double tilt;
  final double alpha;

  /// 1 — стоит на столе перед мишкой, 0 — парит сбоку.
  final double land;
  final double priceTop;
  final double tableY;
}

/// Тени: под стоящим — плотная у донышка и мягкая пошире; под парящим —
/// бледное пятно на столе ниже него, чтобы было видно, что оно в воздухе.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.placed);

  final List<_Placed> placed;

  static const Color _shadow = Color(0xFF50371E);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 844;
    for (final p in placed) {
      final w = p.rect.width;
      final cx = p.rect.center.dx;
      final bottom = p.rect.bottom;

      void oval(double cy, double rw, double rh, double opacity, double blur) {
        if (opacity <= 0.005) return;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rw, height: rh),
          Paint()
            ..color = _shadow.withValues(alpha: opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * unit),
        );
      }

      oval(p.tableY, w * 0.85, 12 * unit, 0.20 * p.alpha * (1 - p.land), 6);
      oval(bottom, w * 0.94, w * 0.2, 0.28 * p.land, 7);
      oval(bottom, w * 0.70, w * 0.08, 0.47 * p.land, 2.5);
    }
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => true;
}

/// Цена под блюдом: монетка и число в кремовой капсуле.
class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.price, required this.scale});

  final int price;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.2),
            blurRadius: 4 * scale,
            offset: Offset(0, 1 * scale),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11 * scale,
            height: 11 * scale,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4 * scale),
          Text('$price', style: sceneText(size: 11 * scale, weight: 800)),
        ],
      ),
    );
  }
}
