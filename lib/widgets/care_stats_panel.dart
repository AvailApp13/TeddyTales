import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear_action.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Один показатель.
class CareStat {
  const CareStat({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
    required this.action,
  });

  final String label;
  final IconData icon;
  final double value;
  final Color color;

  /// Какое действие ухода поднимает этот показатель.
  final BearAction action;
}

/// Гасить ли кольца, недоступные на текущей стадии роста.
///
/// Выключено по просьбе заказчика 20.09: «мне для теста пока нужно, чтобы
/// кнопки работали». Мытьё и игра по ТЗ аниматора открываются только со
/// второй стадии, и на свежем профиле — а он всегда новорождённый — два
/// кольца из пяти гасли и не пускали в свои комнаты. Для проверки комнат это
/// тупик: попасть в ванную было нечем.
///
/// Сам механизм замков цел и нужен по КП 3.5. Включать его обратно надо не
/// этим флагом, а правилами с сервера (КП 15.4) — иначе тестировать игру
/// снова можно будет только выращенным мишкой.
const bool kStageLocksOnStats = false;

/// Пять показателей ухода (КП 3.2, 6.1).
///
/// С 20.09 это не плитки внизу экрана, а кольца поверх комнаты под шапкой, и
/// не индикаторы, а **основная навигация**. Решение заказчика: «ванная это и
/// есть гигиена, при нажатии на гигиену он должен попадать в ванную». Тап по
/// кольцу уводит мишку туда, где этот показатель поправляют, — отдельные
/// кнопки переключения комнат после этого оказались дублями и убраны.
///
/// Кольцо, а не полоска: заливка по кругу читается с одного взгляда и не
/// требует подписи «из ста», а на круглой форме помещается иконка, которая и
/// делает кольцо кнопкой.
class CareStatsPanel extends StatelessWidget {
  const CareStatsPanel({
    super.key,
    required this.stats,
    required this.stage,
    this.onAction,
  });

  final BearCareStats stats;
  final BearStage stage;
  final ValueChanged<BearAction>? onAction;

  List<CareStat> _tiles(AppLocalizations l10n) => [
    CareStat(
      label: l10n.statsFood,
      icon: Icons.restaurant,
      value: stats.food,
      color: AppColors.statFood,
      action: BearAction.feed,
    ),
    CareStat(
      label: l10n.statsHygiene,
      icon: Icons.bathtub_outlined,
      value: stats.hygiene,
      color: AppColors.statHygiene,
      action: BearAction.wash,
    ),
    CareStat(
      label: l10n.statsSleep,
      icon: Icons.nightlight_round,
      value: stats.sleep,
      color: AppColors.statSleep,
      action: BearAction.sleep,
    ),
    CareStat(
      label: l10n.statsPlay,
      icon: Icons.sports_baseball_outlined,
      value: stats.play,
      color: AppColors.statPlay,
      action: BearAction.play,
    ),
    CareStat(
      label: l10n.statsLove,
      icon: Icons.favorite,
      value: stats.love,
      color: AppColors.statLove,
      action: BearAction.pet,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles(context.l10n);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tile in tiles)
          Flexible(
            child: _StatRing(
              stat: tile,
              enabled:
                  onAction != null &&
                  (!kStageLocksOnStats || tile.action.isAvailableOn(stage)),
              onTap: () => onAction?.call(tile.action),
            ),
          ),
      ],
    );
  }
}

class _StatRing extends StatelessWidget {
  const _StatRing({
    required this.stat,
    required this.enabled,
    required this.onTap,
  });

  final CareStat stat;
  final bool enabled;
  final VoidCallback onTap;

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _size,
              height: _size,
              child: CustomPaint(
                painter: _RingPainter(
                  value: stat.value.clamp(0, 100) / 100,
                  color: stat.color,
                ),
                child: Center(
                  child: Container(
                    width: _size - 13,
                    height: _size - 13,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(stat.icon, size: 22, color: stat.color),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _Caption(
              text: stat.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            _Caption(
              text: '${stat.value.round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подпись со светлой обводкой: кольца лежат поверх комнаты, и на тёмном
/// участке обоев простой текст пропадёт.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.background,
          ),
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color});

  /// Доля от нуля до единицы.
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.11;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surface.withValues(alpha: 0.85);
    canvas.drawCircle(rect.center, rect.width / 2, track);

    if (value <= 0) return;

    // От двенадцати часов по часовой стрелке: так растущее значение читается
    // как заполняющийся сосуд, а не как стрелка часов.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
