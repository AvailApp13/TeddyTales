import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'bedroom_scene.dart';
import 'scene_label.dart';

/// Сонные буквы над кроватью: z, z, z — всплывают и тают.
///
/// Заказчик 21.09: «в спальне, где мишка в кровати лежит, сделать анимацию
/// дыхания и моргания глаз, будто он хочет спать, и над головой z-z-z, типа
/// он засыпает».
///
/// Заказчик 22.09: буквы не должны идти всё время, пока открыта спальня, —
/// «только исключительно при кнопке, чтобы он уснул… во время того, когда
/// появляется облако». Поэтому буквы ждут того же момента, что и облако
/// мыслей: мишку уложили, глаза закрылись, и только тогда первая z
/// всплывает от головы. По «Разбудить» гаснут.
///
/// Рисуются шрифтом приложения, а не эмодзи 💤: эмодзи заказчик просил убрать
/// из игры совсем (20.09), и на тёмной стене спальни оно выглядело бы
/// наклейкой из другого приложения.
class SleepZzz extends StatefulWidget {
  const SleepZzz({super.key, required this.shown});

  /// Спит ли мишка: буквы идут только во сне.
  final bool shown;

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

  /// Сколько буквы гаснут, когда мишку разбудили.
  static const Duration fadeOut = Duration(milliseconds: 450);

  @override
  State<SleepZzz> createState() => _SleepZzzState();
}

class _SleepZzzState extends State<SleepZzz>
    with SingleTickerProviderStateMixin {
  /// Часы полёта: секунды с момента, когда буквы пошли. Не зацикленный
  /// контроллер, а счётчик, чтобы первая буква всплыла от головы, а не все
  /// три возникли разом на середине пути.
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _time = ValueNotifier(0);

  /// Если разбудили — буквы не обрываются, а тают на месте.
  double _fading = 0;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.shown) _start();
  }

  @override
  void didUpdateWidget(SleepZzz old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) return;
    _wait?.cancel();
    if (widget.shown) {
      // Как и облако: ждём, пока мишка закроет глаза.
      _wait = Timer(BedroomScene.fallAsleep, () {
        if (mounted && widget.shown) _start();
      });
    } else if (_ticker.isActive) {
      _fading = _time.value;
    }
  }

  void _start() {
    _fading = 0;
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (_fading > 0 && t - _fading > SleepZzz.fadeOut.inMilliseconds / 1e3) {
      _ticker.stop();
      _fading = 0;
      _time.value = 0;
      return;
    }
    _time.value = t;
  }

  @override
  void dispose() {
    _wait?.cancel();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, time, _) {
              if (time == 0) return const SizedBox.shrink();
              final gone = _fading > 0
                  ? 1 -
                      ((time - _fading) * 1e3 / SleepZzz.fadeOut.inMilliseconds)
                          .clamp(0.0, 1.0)
                  : 1.0;
              return Stack(
                children: [
                  for (var i = 0; i < SleepZzz.count; i++)
                    _letter(i, time, gone, w, h),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Одна буква на своём месте пути.
  Widget _letter(int index, double time, double gone, double width,
      double height) {
    // Буквы идут вереницей: каждая стартует, когда предыдущая прошла треть
    // пути. Иначе они всплывают кучей и читаются как одна клякса. Пока
    // очередь буквы не подошла — её нет.
    final travel = SleepZzz.travel.inMilliseconds / 1e3;
    final lap = time / travel - index / SleepZzz.count;
    if (lap < 0) return const SizedBox.shrink();
    final t = lap % 1.0;

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
        opacity: fade * gone * 0.92,
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
