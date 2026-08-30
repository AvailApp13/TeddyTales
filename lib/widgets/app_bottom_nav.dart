import 'package:flutter/material.dart';

import '../bear/bear_rig_spec.dart';
import '../game/app_section.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';

/// Нижняя навигация с замками по стадии роста (КП 3.5).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.current,
    required this.stage,
    required this.onSelected,
  });

  final AppSection current;
  final BearStage stage;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: AppSection.values.indexOf(current),
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.sageSoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        final section = AppSection.values[index];
        if (!section.isUnlockedAt(stage)) {
          _explainLock(context, section);
          return;
        }
        onSelected(section);
      },
      destinations: [
        for (final section in AppSection.values)
          NavigationDestination(
            icon: _Icon(section: section, stage: stage),
            label: sectionTitle(context.l10n, section),
          ),
      ],
    );
  }

  void _explainLock(BuildContext context, AppSection section) {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${sectionTitle(l10n, section)}. ${sectionLockReason(l10n, section)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.section, required this.stage});

  final AppSection section;
  final BearStage stage;

  @override
  Widget build(BuildContext context) {
    final unlocked = section.isUnlockedAt(stage);

    if (unlocked) return Icon(section.icon);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(section.icon, color: AppColors.textSecondary.withValues(alpha: 0.5)),
        const Positioned(
          right: -4,
          bottom: -2,
          child: Icon(Icons.lock, size: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
