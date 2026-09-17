import 'package:flutter/material.dart';

import '../game/room_hints.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'room_scene_backdrop.dart';

/// Пунктирные места в комнате: «сюда можно поставить кроватку».
///
/// Слой лежит поверх мишки, но занимает только сами рамки — всё остальное
/// пространство прозрачно для касаний, и тап по мишке по-прежнему его
/// гладит. Иначе подсказка воровала бы главное действие экрана.
///
/// Габариты берутся из той же размерной сетки (`room_layout.dart`), по
/// которой рисуются поставленные предметы: рамка стоит ровно там, где встанет
/// вещь, и с приходом настоящей графики ничего не сдвинется.
class RoomHintLayer extends StatelessWidget {
  const RoomHintLayer({
    super.key,
    required this.hints,
    required this.onTap,
    this.bearModule = RoomSceneBackdrop.defaultBearModule,
  });

  final List<RoomHint> hints;

  /// Тап по месту. Купленное ставится сразу, за остальным идём в магазин —
  /// решает вызывающий, слой только сообщает, по какому месту нажали.
  final ValueChanged<RoomHint> onTap;

  final double bearModule;

  @override
  Widget build(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final module = height * bearModule;

        return Stack(
          children: [
            for (final hint in hints)
              Positioned(
                left: hint.placement.fx * width - hint.placement.w * module / 2,
                top: hint.placement.onWall
                    ? hint.placement.wallFy! * height -
                          hint.placement.h * module / 2
                    : RoomSceneBackdrop.floorLine * height -
                          hint.placement.h * module,
                width: hint.placement.w * module,
                height: hint.placement.h * module,
                child: _HintSpot(hint: hint, onTap: () => onTap(hint)),
              ),
          ],
        );
      },
    );
  }
}

/// Одно место: пунктирная рамка, плюс и название вещи.
class _HintSpot extends StatelessWidget {
  const _HintSpot({required this.hint, required this.onTap});

  final RoomHint hint;
  final VoidCallback onTap;

  /// Влезает ли подпись в рамку такого размера.
  ///
  /// Название, втиснутое в рамку уточки, превращается в серую полоску: слов
  /// не разобрать, а рамка теряет вид пустого места. Значок «плюс» понятен и
  /// без подписи — что именно встанет, человек узнает, тапнув.
  ///
  /// Условий два, потому что мест два вида. Широкие и низкие (кроватка,
  /// ковёр) держат подпись в строку. Узкие и высокие (торшер, шкаф) в строку
  /// её не берут, но двух строк по восемь букв им хватает — а без подписи
  /// высокий прямоугольник у стены вообще не читается как место под вещь.
  static bool _fitsLabel(BoxConstraints c) =>
      (c.maxWidth >= 78 && c.maxHeight >= 46) ||
      (c.maxWidth >= 44 && c.maxHeight >= 110);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = shopItemName(l10n, hint.id);
    final color = hint.owned ? AppColors.sageDark : AppColors.textSecondary;

    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedFrame(
            // Своё выделено насыщенным: это бесплатное действие, и оно должно
            // быть заметнее покупки. Покупное — спокойным, чтобы комната не
            // выглядела сплошной витриной.
            color: hint.owned ? AppColors.sage : AppColors.textSecondary,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final withLabel = _fitsLabel(constraints);

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: color),
                      if (withLabel)
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Пунктирная рамка со скруглением.
///
/// Пунктир, а не сплошная линия и не заливка: сплошная читается как готовый
/// предмет, заливка — как пятно грязи на полу. Прерывистая рамка во всех
/// интерфейсах означает одно и то же — «здесь пусто, можно положить».
class _DashedFrame extends CustomPainter {
  _DashedFrame({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(1),
      const Radius.circular(10),
    );

    // Лёгкая подложка: на пёстрых обоях один пунктир теряется.
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.06));

    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Идём по контуру и выкладываем штрихи: рисовать пунктир по сторонам
    // прямоугольника нельзя — он сломается на скруглениях.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color;
}
