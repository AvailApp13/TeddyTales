import 'package:flutter/material.dart';

import '../game/room_kind.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// Мишка спит, а человек ушёл из спальни (заказчик 26.09): в комнате его
/// нет, посередине — стеклянная панель «Мишка спит» с двумя кнопками.
/// «Разбудить и позвать …» — по комнате и времени суток; «Пусть спит» —
/// обратно в спальню. Не лист снизу и без затемнения: меню и кольца
/// остаются под рукой.
class SleepingElsewhere extends StatelessWidget {
  const SleepingElsewhere({
    super.key,
    required this.room,
    required this.sleep,
    required this.onWake,
    required this.onLetSleep,
    this.now,
  });

  final RoomKind room;

  /// Шкала «Сон», 0–100.
  final double sleep;
  final VoidCallback onWake;
  final VoidCallback onLetSleep;

  /// Который час — для завтрака/обеда/ужина и «сейчас ночь». По умолчанию
  /// время телефона.
  final DateTime? now;

  /// Ниже этого — «ещё не выспался».
  static const double rested = 80;

  /// Подпись главной кнопки: кухня — по времени суток (6–11 завтрак,
  /// 11–16 обед, 16–21 ужин, ночью перекус), игровая — играть, душ —
  /// купаться.
  static String wakeLabel(
    AppLocalizations l10n,
    RoomKind room,
    int hour,
  ) => switch (room) {
    RoomKind.kitchen when hour >= 6 && hour < 11 => l10n.sleepAwayWakeBreakfast,
    RoomKind.kitchen when hour >= 11 && hour < 16 => l10n.sleepAwayWakeLunch,
    RoomKind.kitchen when hour >= 16 && hour < 21 => l10n.sleepAwayWakeDinner,
    RoomKind.kitchen => l10n.sleepAwayWakeSnack,
    RoomKind.bath => l10n.sleepAwayWakeBath,
    _ => l10n.sleepAwayWakePlay,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final time = now ?? DateTime.now();
    final night = time.hour >= 22 || time.hour < 8;
    final warning = night
        ? l10n.sleepAwayNight
        : sleep < rested
        ? l10n.sleepAwayTired(sleep.round())
        : null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
      ),
      child: SizedBox(
        width: 320,
        child: GlassPanel(
          key: const ValueKey('sleeping-elsewhere'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Кружок как кольцо «Сон»: белый, лиловая луна.
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.statSleep, width: 3),
                    ),
                    child: const Icon(
                      Icons.nightlight_round,
                      size: 20,
                      color: Color(0xFF7D76B4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.sleepAwayTitle,
                          style: glassText(
                            20,
                            900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          l10n.sleepAwayLead,
                          style: glassText(
                            13,
                            650,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (warning != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('sleeping-warning'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: glassTile(radius: 14),
                  child: Text(
                    warning,
                    style: glassText(13, 700, color: const Color(0xFF7D76B4)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              GlassButton(
                key: const ValueKey('sleeping-wake'),
                primary: true,
                icon: Icons.wb_sunny_rounded,
                label: wakeLabel(l10n, room, time.hour),
                onPressed: onWake,
              ),
              const SizedBox(height: 8),
              GlassButton(
                key: const ValueKey('sleeping-let'),
                icon: Icons.bedtime_rounded,
                label: l10n.sleepAwayLetSleep,
                onPressed: onLetSleep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
