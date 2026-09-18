import 'package:flutter/material.dart';

import '../game/room_kind.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Переключатель комнат: детская, кухня, ванная.
///
/// Стоит в углу сцены, а не в нижней навигации: это не раздел приложения, а
/// то же самое место, только другая комната — как повернуться в квартире, а
/// не открыть новый экран. Нижняя навигация уже несёт шесть разделов (КП
/// 3.5), седьмой в ней был бы лишним.
///
/// Три кнопки, а не список: комнат ровно три, и выбор из трёх, спрятанный в
/// меню, — это лишнее касание на ровном месте.
class RoomSwitcher extends StatelessWidget {
  const RoomSwitcher({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final RoomKind current;
  final ValueChanged<RoomKind> onSelect;

  static IconData _iconOf(RoomKind kind) => switch (kind) {
    RoomKind.nursery => Icons.crib_outlined,
    RoomKind.kitchen => Icons.countertops_outlined,
    RoomKind.bath => Icons.bathtub_outlined,
  };

  static String _titleOf(AppLocalizations l10n, RoomKind kind) =>
      switch (kind) {
        RoomKind.nursery => l10n.roomKindNursery,
        RoomKind.kitchen => l10n.roomKindKitchen,
        RoomKind.bath => l10n.roomKindBath,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // Подложка полупрозрачная: под кнопками живая комната, и глухая
        // плашка вырезала бы из неё кусок.
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in RoomKind.values)
            _RoomButton(
              icon: _iconOf(kind),
              tooltip: _titleOf(l10n, kind),
              selected: kind == current,
              onTap: () => onSelect(kind),
            ),
        ],
      ),
    );
  }
}

class _RoomButton extends StatelessWidget {
  const _RoomButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: Material(
          color: selected ? AppColors.sageSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: SizedBox(
              width: 38,
              height: 32,
              child: Icon(
                icon,
                size: 19,
                color: selected ? AppColors.sageDark : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
