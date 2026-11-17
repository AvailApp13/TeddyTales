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
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
