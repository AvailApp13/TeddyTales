import 'package:flutter/material.dart';

import 'scene_label.dart';

/// Сонные буквы над кроватью: z, z, z — всплывают и тают.
///
/// Заказчик 21.09: «в спальне, где мишка в кровати лежит, сделать анимацию
/// дыхания и моргания глаз, будто он хочет спать, и над головой z-z-z, типа
/// он засыпает».
///
/// Дыхание и моргание отсюда не сделать: в спальне мишка нарисован прямо на
/// фоне, одной картинкой вместе с кроватью и подушками. Чтобы грудь
/// поднималась, а веки опускались, мишка должен быть либо отдельным слоем,
/// либо живым ригом — это следующий шаг, и в ТЗ аниматора он уже описан
/// (`idle_sleepy` и `act_sleep`).
///
/// А буквы рисуются поверх картинки и ничего от неё не требуют. Отсюда и
/// решение сделать сначала их: комната оживает сегодня, а не когда соберётся
/// поза «лёжа».
///
/// Рисуются шрифтом приложения, а не эмодзи 💤: эмодзи заказчик просил убрать
/// из игры совсем (20.09), и на тёмной стене спальни оно выглядело бы
/// наклейкой из другого приложения.
class SleepZzz extends StatefulWidget {
  const SleepZzz({super.key});

  /// Откуда буквы начинают путь и где тают — в долях кадра комнаты.
  ///
  /// Снято по картинке спальни: кончик колпака на 0.49 × 0.40, справа от него
  /// до рамки с месяцем (0.71) стена пустая. Буквы идут в этот просвет по
  /// диагонали вверх — так их видно и ничего не закрывают.
  static const Offset from = Offset(0.575, 0.395);
  static const Offset to = Offset(0.665, 0.245);

  /// Сколько длится путь одной буквы и сколько их в воздухе разом.
  static const Duration travel = Duration(milliseconds: 4200);
  static const int count = 3;

  @override
  State<SleepZzz> createState() => _SleepZzzState();
}

class _SleepZzzState extends State<SleepZzz>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: SleepZzz.travel,
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => Stack(
              children: [
                for (var i = 0; i < SleepZzz.count; i++) _letter(i, w, h),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Одна буква на своём месте пути.
  Widget _letter(int index, double width, double height) {
    // Буквы идут вереницей: каждая стартует, когда предыдущая прошла треть
    // пути. Иначе они всплывают кучей и читаются как одна клякса.
    final t = (_loop.value - index / SleepZzz.count) % 1.0;

    // Взлёт замедляется к концу — так вернее читается «уплывает», а не
    // «улетает». Прозрачность: быстро проступить, долго таять.
    final rise = Curves.easeOutSine.transform(t);
    final fade = t < 0.18 ? t / 0.18 : (1 - (t - 0.18) / 0.82).clamp(0.0, 1.0);

    final from = SleepZzz.from;
    final to = SleepZzz.to;
    final x = (from.dx + (to.dx - from.dx) * rise) * width;
    final y = (from.dy + (to.dy - from.dy) * rise) * height;

    // Дальняя буква крупнее ближней: она «ближе к зрителю» и заодно
    // подсказывает направление.
    final size = width * (0.052 + 0.028 * rise);

    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: fade * 0.92,
        child: Transform.rotate(
          angle: 0.12 - 0.24 * rise,
          child: Text(
            'z',
            style: sceneText(size: size, weight: 800, color: Colors.white)
                .copyWith(
                  height: 1,
                  shadows: const [
                    Shadow(
                      color: Color(0x66203040),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
