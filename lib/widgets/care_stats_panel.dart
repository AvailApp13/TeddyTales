import 'package:flutter/material.dart';

import '../bear/bear_action.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Одна плитка показателя.
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

/// Панель пяти показателей ухода (КП 3.2, 6.1).
///
/// Значения 0–100%, подпись и иконка — как на макете. Тап по плитке запускает
/// соответствующее действие ухода: на макете список действий живёт на отдельном
/// экране «Что будем делать?», но кнопки, ведущей туда, в макете не видно, а
/// показатели напрашиваются на роль такой кнопки.
///
/// **ДОПУЩЕНИЕ:** тап по плитке = действие. Если по замыслу плитки только
/// показывают, а действия открываются иначе, снимается параметром [onAction].
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

  List<CareStat> get _tiles => [
    CareStat(
      label: 'Еда',
      icon: Icons.restaurant,
      value: stats.food,
      color: AppColors.statFood,
      action: BearAction.feed,
    ),
    CareStat(
      label: 'Гигиена',
      icon: Icons.bathtub_outlined,
      value: stats.hygiene,
      color: AppColors.statHygiene,
      action: BearAction.wash,
    ),
    CareStat(
      label: 'Сон',
      icon: Icons.nightlight_round,
      value: stats.sleep,
      color: AppColors.statSleep,
      action: BearAction.sleep,
    ),
    CareStat(
      label: 'Игра',
      icon: Icons.sports_baseball_outlined,
      value: stats.play,
      color: AppColors.statPlay,
      action: BearAction.play,
    ),
    CareStat(
      label: 'Любовь',
      icon: Icons.favorite,
      value: stats.love,
      color: AppColors.statLove,
      action: BearAction.pet,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tile in _tiles) ...[
          Expanded(
            child: _StatTile(
              stat: tile,
              enabled:
                  onAction != null && tile.action.isAvailableOn(stage),
              onTap: () => onAction?.call(tile.action),
            ),
          ),
          if (tile != _tiles.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.stat,
    required this.enabled,
    required this.onTap,
  });

  final CareStat stat;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(stat.icon, size: 22, color: stat.color),
                const SizedBox(height: 6),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${stat.value.round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
