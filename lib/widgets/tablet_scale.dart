import 'package:flutter/material.dart';

/// Крупнее на планшетах (заказчик 17.11: «на планшете всё чуть побольше…
/// задать размер отдельно для планшетов, отдельно для телефонов»).
///
/// Приложение раскладывается так, будто экран в [scaleFor] раз меньше, и
/// затем целиком увеличивается до настоящего размера. Текст, кнопки, лапа,
/// кольца, листы — всё крупнее в одной пропорции, ничего не разъезжается;
/// комнаты по-прежнему на весь экран. Телефоны (короткая сторона меньше
/// [tabletFrom]) не меняются.
class TabletScale extends StatelessWidget {
  const TabletScale({super.key, required this.child});

  final Widget child;

  /// С какой короткой стороны экран считается планшетом (iPad mini — 744,
  /// самые большие телефоны — до 440).
  static const double tabletFrom = 600;

  /// Во сколько раз крупнее на планшете: iPad 11" и Android 10" — около
  /// 1,2, iPad 13" — 1,3. Подбирается здесь одним числом.
  static double scaleFor(Size screen) {
    final side = screen.shortestSide;
    if (side < tabletFrom) return 1;
    return (side / 680).clamp(1.15, 1.3);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final k = scaleFor(mq.size);
    if (k == 1) return child;
    final scoped = _TabletScope(scale: k, child: child);

    final size = mq.size / k;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.scale(
          scale: k,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: mq.copyWith(
                size: size,
                devicePixelRatio: mq.devicePixelRatio * k,
                padding: mq.padding / k,
                viewPadding: mq.viewPadding / k,
                viewInsets: mq.viewInsets / k,
                systemGestureInsets: mq.systemGestureInsets / k,
              ),
              child: scoped,
            ),
          ),
        ),
      ),
    );
  }

  /// Планшет ли это (уже внутри увеличения): для мест, которым на планшете
  /// нужно ещё крупнее остального, — верхняя строка главного экрана.
  static bool isTablet(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabletScope>() != null;
}

class _TabletScope extends InheritedWidget {
  const _TabletScope({required this.scale, required super.child});

  final double scale;

  @override
  bool updateShouldNotify(_TabletScope oldWidget) => scale != oldWidget.scale;
}

/// Ещё крупнее на планшете — в [boost] раз поверх общего увеличения
/// (заказчик 17.11: «Мой малыш, 3 месяца, 12 дней — можно сделать больше,
/// кнопки верхние тоже побольше»). Ребёнок раскладывается на ширину,
/// меньшую в [boost] раз, и растягивается на всю. На телефоне — как есть.
class TabletBoost extends StatelessWidget {
  const TabletBoost({super.key, this.boost = 1.2, required this.child});

  final double boost;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TabletScale.isTablet(context)) return child;
    return LayoutBuilder(
      // Свою ширину задаём сами: в колонке ограничения свободные, и без
      // этого FittedBox остался бы узким, ничего не увеличив.
      builder: (context, c) => SizedBox(
        width: c.maxWidth,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: SizedBox(width: c.maxWidth / boost, child: child),
        ),
      ),
    );
  }
}
