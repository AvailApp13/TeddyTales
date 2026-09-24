import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
/// И ещё (24.09): «тарелка перед мишкой закрывает лапки — так не должно
/// быть ни с одним блюдом; каждое блюдо садится плавно и не задевает
/// лапки». Поэтому:
/// - блюдо перед мишкой на 20 % меньше первого размера (заказчик 24.09:
///   «на 15–20 %»), боковые — на 6 %; глубокие миски (каша, суп, йогурт)
///   ещё меньше ([tableFit]). Стоит там же, где в согласованном макете, —
///   не у края стола. Картинки блюд не меняются. В покое ни одно
///   не касается лапок — проверено по маскам картинок
///   (`tool/check_dish_paws.py`);
/// - по пути с края на середину блюдо сначала садится на стол у края и
///   только потом едет к мишке низом;
/// - блюда ([DishPlates]) лежат поверх мишки целиком: на лету миска может
///   пройти по нему — это нормально, но ничем не срезается (заказчик
///   24.09: «никаких масок»). Касания ловит [DishCarousel] поверх всего.
///
/// Положение блюда описывает одно число `s` — где оно относительно центра:
/// 0 — перед мишкой на столе, ±1 — приподнято по бокам, дальше — уходит за
/// край и гаснет. Прокрутка сдвигает все `s` разом ([DishArc.offset]).
///
/// Геометрия — в долях кадра кухни, как у остальных её слоёв
/// (`KitchenScene`): кадр 941 × 1672, задний край стола на 0.6065,
/// передний — на 0.698.
abstract final class DishArcGeometry {
  /// Центр стола по горизонтали и шаг до соседнего места.
  static const double centerX = 0.5;
  static const double step = 0.276;

  /// Донышко: перед мишкой — на столе, там же, где в согласованном макете;
  /// по бокам — приподнято. Заказчик 24.09: «не убирать на край стола —
  /// поменять размер».
  static const double centerBottom = 0.6754;
  static const double sideBottom = 0.6043;

  /// Ширина тарелки перед мишкой и по бокам. Первые были 0.261 и 0.168;
  /// заказчик 24.09 попросил сначала на 5–7 % меньше, потом центральное —
  /// на 15–20 %: оно закрывало лапки. Центральное — на 20 %.
  static const double centerWidth = 0.209;
  static const double sideWidth = 0.158;

  /// Высокие миски уже тарелок: при общей ширине их край заходил бы на
  /// лапки. Доли подобраны по маскам с запасом 4 px кадра.
  static const Map<String, double> tableFit = {
    'porridge': 0.92,
    'soup': 0.85,
    'yogurt': 0.87,
  };

  /// С какой доли пути к краю блюдо начинает подниматься. До неё оно едет
  /// по столу — ниже лапок.
  static const double liftFrom = 0.55;

  /// Плоскость стола, на которую падает тень парящего блюда.
  static const double tableShadowY = 0.673;

  /// Наклон бокового блюда к центру, радианы (≈6°).
  static const double sideTilt = 0.105;

  /// Полоса, где ловятся свайпы и касания: от верха парящих блюд до
  /// свисающей скатерти. Выше и ниже касания уходят мишке.
  static const double bandTop = 0.50;
  static const double bandBottom = 0.78;

  /// Где стоит блюдо [dishId] при положении [s] в кадре размера [size]:
  /// квадрат, картинка в нём прижата к низу.
  static Rect plate(String dishId, double s, Size size) =>
      _Placed.at(0, s, size, tableFit[dishId] ?? 1).rect;

  /// Положение блюда [index] на дуге при сдвиге [offset] — по кругу, без
  /// краёв: после последнего снова первое.
  static double slot(int index, double offset, int count) {
    final raw = index - offset;
    final half = count / 2;
    return ((raw + half) % count + count) % count - half;
  }
}

/// Сдвиг дуги: общий для блюд в сцене и для слоя касаний.
class DishArc extends ChangeNotifier {
  DishArc({required this.count, int initial = 0})
    : _offset = initial.toDouble();

  final int count;
  double _offset;

  double get offset => _offset;
  set offset(double value) {
    if (value == _offset) return;
    _offset = value;
    notifyListeners();
  }

  /// Блюдо перед мишкой.
  int get current => (_offset.round() % count + count) % count;

  /// Все блюда на своих местах: ближние к центру — первыми.
  List<_Placed> _placed(List<Dish> dishes, Size size) {
    final placed = [
      for (var i = 0; i < count; i++)
        _Placed.at(
          i,
          DishArcGeometry.slot(i, _offset, count),
          size,
          DishArcGeometry.tableFit[dishes[i].id] ?? 1,
        ),
    ]..removeWhere((p) => p.alpha <= 0.01);
    placed.sort((a, b) => a.s.abs().compareTo(b.s.abs()));
    return placed;
  }
}

/// Блюда, тени и цены — картинка без касаний. Лежит поверх сцены кухни.
class DishPlates extends StatelessWidget {
  const DishPlates({super.key, required this.arc, required this.dishes});

  final DishArc arc;
  final List<Dish> dishes;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: arc,
          builder: (context, _) {
            final size = constraints.biggest;
            // Рисуем от дальних к ближним: центральное — поверх соседей.
            final drawn = arc._placed(dishes, size).reversed.toList();
            final scale = size.height / 844;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Ключи обязательны: блюда появляются и гаснут по краям.
                Positioned.fill(
                  key: const ValueKey('dish-shadows'),
                  child: CustomPaint(painter: _ShadowPainter(drawn)),
                ),
                for (final p in drawn) ...[
                  Positioned.fromRect(
                    key: ValueKey('dish-slot-${p.index}'),
                    rect: p.rect,
                    child: Opacity(
                      opacity: p.alpha,
                      child: Transform.rotate(
                        angle: p.tilt,
                        alignment: Alignment.bottomCenter,
                        child: Image.asset(
                          dishes[p.index].image,
                          key: ValueKey('dish-${dishes[p.index].id}'),
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    key: ValueKey('dish-price-${p.index}'),
                    left: p.rect.center.dx - 60 * scale,
                    width: 120 * scale,
                    top: p.priceTop,
                    child: Opacity(
                      opacity: p.alpha,
                      child: Center(
                        child: _PriceChip(
                          price: dishes[p.index].price,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Слой касаний поверх кухни: свайп крутит дугу, нажатие на блюдо перед
/// мишкой — покупка, на боковое — подкатить его в центр.
class DishCarousel extends StatefulWidget {
  const DishCarousel({
    super.key,
    required this.arc,
    required this.dishes,
    required this.onBuy,
    this.onTapElsewhere,
  });

  final DishArc arc;
  final List<Dish> dishes;

  /// Нажали на блюдо перед мишкой — купить (окно подтверждения снаружи).
  final ValueChanged<Dish> onBuy;

  /// Нажали мимо блюд — отдать касание дальше (погладить мишку).
  final VoidCallback? onTapElsewhere;

  @override
  State<DishCarousel> createState() => _DishCarouselState();
}

class _DishCarouselState extends State<DishCarousel>
    with SingleTickerProviderStateMixin {
  // Доводка после свайпа — пружиной. Создаётся сразу, а не лениво:
  // иначе при уходе с кухни без касаний её создавал бы dispose().
  late final AnimationController _snap;
  double _target = 0;

  /// Пружина без отскока (критическое затухание). Заказчик 24.09:
  /// «уменьшить резкость движения». Жёсткость 55 — блюдо доезжает примерно
  /// за 0.7 с, трогается и тормозит плавно, скорость пальца не теряется.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 55,
    ratio: 1,
  );

  DishArc get _arc => widget.arc;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() => _arc.offset = _snap.value)
      ..addStatusListener((status) {
        // Пружина останавливается «около» цели — ставим ровно на место.
        if (status == AnimationStatus.completed) _arc.offset = _target;
      });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  /// Доехать до [target] пружиной, начиная со скорости [velocity]
  /// (блюд в секунду).
  void _springTo(double target, {double velocity = 0}) {
    _target = target;
    _snap.value = _arc.offset;
    _snap.animateWith(SpringSimulation(_spring, _arc.offset, target, velocity));
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _snap.stop();
    _arc.offset -= details.delta.dx / (width * DishArcGeometry.step);
  }

  void _onDragEnd(DragEndDetails details, double width) {
    final stepPx = width * DishArcGeometry.step;
    // Скорость пальца в блюдах за секунду: блюдо продолжает движение с ней.
    final velocity = -details.velocity.pixelsPerSecond.dx / stepPx;
    final offset = _arc.offset;
    var target = offset.roundToDouble();
    // Бросок пальцем докручивает на одно блюдо, даже если сдвинули мало.
    if (velocity.abs() > 0.8 * width / stepPx &&
        (target - offset).abs() < 0.5) {
      target = velocity > 0 ? offset.ceilToDouble() : offset.floorToDouble();
    }
    // Быстрый бросок — не дальше соседнего блюда: иначе улетало бы мимо.
    _springTo(target, velocity: velocity.clamp(-6.0, 6.0));
  }

  void _onTap(Offset local, Size size) {
    if (_snap.isAnimating) return;
    for (final hit in _arc._placed(widget.dishes, size)) {
      if (!hit.rect.contains(local)) continue;
      if (hit.s.abs() < 0.5) {
        widget.onBuy(widget.dishes[hit.index]);
      } else {
        // Боковое — подкатываем в центр, покупают уже его.
        _springTo(_arc.offset + hit.s.roundToDouble());
      }
      return;
    }
    widget.onTapElsewhere?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            // Касания — только в полосе стола.
            Positioned(
              key: const ValueKey('dish-carousel-band'),
              left: 0,
              right: 0,
              top: size.height * DishArcGeometry.bandTop,
              height:
                  size.height *
                  (DishArcGeometry.bandBottom - DishArcGeometry.bandTop),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, size.width),
                onHorizontalDragEnd: (d) => _onDragEnd(d, size.width),
                onTapUp: (d) => _onTap(
                  d.localPosition.translate(
                    0,
                    size.height * DishArcGeometry.bandTop,
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
              child: ListenableBuilder(
                listenable: _arc,
                builder: (context, _) => Semantics(
                  label: widget.dishes[_arc.current].id,
                  child: const SizedBox.shrink(),
                ),
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

  factory _Placed.at(int index, double s, Size size, double fit) {
    final k = math.min(s.abs(), 1.0);
    final side = s < 0 ? -1.0 : 1.0;
    // По горизонтали блюдо идёт за пальцем один к одному (раньше у центра
    // оно бежало в 1.6 раза быстрее пальца — заказчик назвал это резкостью).
    // Вверх поднимается только на последнем участке пути к краю; садится
    // обратно так же плавно.
    final across = s.abs();
    final t = ((k - DishArcGeometry.liftFrom) / (1 - DishArcGeometry.liftFrom))
        .clamp(0.0, 1.0);
    final lift = t * t * (3 - 2 * t);
    final land = 1 - lift;
    final width =
        size.width *
        fit *
        lerpDouble(
          DishArcGeometry.centerWidth,
          DishArcGeometry.sideWidth,
          math.min(across, 1.0),
        )!;
    final bottom =
        size.height *
        lerpDouble(
          DishArcGeometry.centerBottom,
          DishArcGeometry.sideBottom,
          lift,
        )!;
    final cx =
        size.width *
        (DishArcGeometry.centerX + DishArcGeometry.step * side * across);
    // Высота с запасом: тарелки ниже квадрата, картинка прижата к низу.
    final height = width;
    var alpha = lerpDouble(1, 0.92, k)!;
    if (s.abs() > 1) alpha *= math.max(0, 1 - (s.abs() - 1) / 0.6);
    return _Placed._(
      index: index,
      s: s,
      rect: Rect.fromLTWH(cx - width / 2, bottom - height, width, height),
      tilt: -DishArcGeometry.sideTilt * side * lift,
      alpha: alpha,
      land: land,
      priceTop: bottom + size.height * lerpDouble(6, 18, land)! / 844,
      tableY: size.height * DishArcGeometry.tableShadowY,
    );
  }

  final int index;
  final double s;
  final Rect rect;
  final double tilt;
  final double alpha;

  /// 1 — стоит на столе, 0 — парит сбоку.
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
