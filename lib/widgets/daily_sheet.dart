import 'package:flutter/material.dart';

import '../backend/pet_snapshot.dart' show DailyInfo, DailyTask;
import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'gift_reveal.dart';
import 'glass_panel.dart';
import 'scene_label.dart';

/// «Сегодня»: подарок дня, задания дня и задание недели (заказчик 25.09,
/// миграция 0017; КП 11.1 — монеты за вход и достижения, КП 13.1 —
/// «Подарок» и «Задание»).
///
/// Открывается сам при входе, если подарок ещё не забран, и из профиля.
/// Всё считает сервер: календарь, задания, награды. Экран только
/// показывает и отправляет «Забрать».
///
/// Заказчик 26.09: не лист снизу, а окно из матового стекла посреди
/// комнаты, в стиле главного экрана.
Future<void> showDailySheet(BuildContext context, GameState game) =>
    showGlassPanel<void>(
      context: context,
      center: const Offset(0.5, 0.55),
      width: 360,
      builder: (_) => DailySheet(game: game),
    );

class DailySheet extends StatefulWidget {
  const DailySheet({super.key, required this.game});

  final GameState game;

  @override
  State<DailySheet> createState() => _DailySheetState();
}

class _DailySheetState extends State<DailySheet> {
  bool _claiming = false;

  bool _restoring = false;

  /// Вчера пропущен день — выкупить серию за монеты (миграция 0023).
  Future<void> _restore() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _restoring = true);
    final result = await widget.game.restoreStreak();
    if (!mounted) return;
    setState(() => _restoring = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          RestoreResult.ok => l10n.dailyStreakRestored,
          RestoreResult.noCoins => l10n.dailyStreakNoCoins,
          RestoreResult.failed => l10n.dailyGiftFailed,
        }),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    var failed = false;
    // Конверт (дни 1–6) или коробка (день 7) — открытие само забирает
    // подарок на сервере и показывает, что внутри (миграция 0020).
    await showGiftReveal(
      context,
      box: widget.game.daily.giftNextDay == 7,
      claim: () async {
        if (!await widget.game.claimGift()) {
          failed = true;
          return null;
        }
        final daily = widget.game.daily;
        return GiftOutcome(coins: daily.lastCoins);
      },
    );
    if (!mounted) return;
    setState(() => _claiming = false);
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.dailyGiftFailed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.game,
      builder: (context, _) {
        final daily = widget.game.daily;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassTitle(
                  l10n.dailyTitle,
                  leading: const _Badge(icon: Icons.card_giftcard_rounded),
                ),
                const SizedBox(height: 12),
                if (daily.isEmpty)
                  Text(
                    l10n.dailyOffline,
                    textAlign: TextAlign.center,
                    style: glassText(14, 600, color: AppColors.textSecondary),
                  )
                else ...[
                  _GiftCalendar(daily: daily),
                  const SizedBox(height: 10),
                  if (daily.canRestore && daily.giftAvailable) ...[
                    _StreakRestore(
                      price: daily.restorePrice,
                      busy: _restoring,
                      onRestore: _restore,
                    ),
                    const SizedBox(height: 10),
                  ],
                  GlassButton(
                    key: const ValueKey('daily-claim'),
                    primary: true,
                    icon: daily.giftAvailable
                        ? Icons.card_giftcard_rounded
                        : Icons.check_rounded,
                    onPressed: daily.giftAvailable && !_claiming
                        ? _claim
                        : null,
                    label: daily.giftAvailable
                        ? l10n.dailyGiftClaim(_rewardOf(daily))
                        : l10n.dailyGiftClaimed,
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SceneLabel(
                      text: l10n.dailyTasksTitle,
                      size: 12.5,
                      weight: 800,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: glassTile(),
                    child: Column(
                      children: [
                        for (final task in daily.tasks) _TaskRow(task: task),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    daily.weeklyClaimed
                        ? l10n.dailyWeeklyDone
                        : l10n.dailyWeekly(
                            daily.weeklyTarget,
                            daily.weeklyDone,
                            daily.weeklyReward,
                          ),
                    key: const ValueKey('daily-weekly'),
                    style: glassText(12.5, 650, color: AppColors.textPrimary),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static int _rewardOf(DailyInfo daily) {
    final i = daily.giftNextDay - 1;
    return i >= 0 && i < daily.giftRewards.length ? daily.giftRewards[i] : 0;
  }
}

/// Семь дней календаря: забранные — зелёные, сегодняшний — с рамкой.
class _GiftCalendar extends StatelessWidget {
  const _GiftCalendar({required this.daily});

  final DailyInfo daily;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Сегодня уже забран — сегодняшний день тот, что забран; иначе — тот,
    // что будет следующим. До него всё забрано.
    final today = daily.giftAvailable
        ? daily.giftNextDay
        : daily.giftClaimedDay;
    return Row(
      children: [
        for (var day = 1; day <= 7; day++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                key: ValueKey('daily-gift-$day'),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: glassTile(
                  radius: 14,
                  color: day < today || (!daily.giftAvailable && day == today)
                      ? AppColors.sage.withValues(alpha: 0.55)
                      : null,
                  border: day == today ? AppColors.sageDark : null,
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.dailyGiftDay(day),
                      style: glassText(10, 650, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day <= daily.giftRewards.length
                          ? '${daily.giftRewards[day - 1]}'
                          : '',
                      style: glassText(
                        day == 7 ? 16 : 15,
                        900,
                        color: day == 7
                            ? const Color(0xFFC0392B)
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final DailyTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      key: ValueKey('daily-task-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            task.done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: task.done ? AppColors.sageDark : AppColors.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dailyTaskTitle(l10n, task.id),
              style: glassText(14, 650, color: AppColors.textPrimary).copyWith(
                decoration: task.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            '${task.progress}/${task.target}',
            style: glassText(
              13,
              650,
              color: AppColors.textSecondary,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 10),
          Text(
            '+${task.reward}',
            style: glassText(14, 850, color: AppColors.sageDark),
          ),
        ],
      ),
    );
  }
}

/// Название задания дня на языке интерфейса.
String dailyTaskTitle(AppLocalizations l10n, String id) => switch (id) {
  'pet' => l10n.dailyTaskPet,
  'play' => l10n.dailyTaskPlay,
  'wash' => l10n.dailyTaskWash,
  'feed' => l10n.dailyTaskFeed,
  'cook' => l10n.dailyTaskCook,
  'learn' => l10n.dailyTaskLearn,
  'meal_on_time' => l10n.dailyTaskMealOnTime,
  'bedtime' => l10n.dailyTaskBedtime,
  _ => id,
};

/// Серия прервалась вчера — её можно выкупить (заказчик 25.09: «как трата
/// монет — мне нравится»). Монет за пропущенный день не дают.
class _StreakRestore extends StatelessWidget {
  const _StreakRestore({
    required this.price,
    required this.busy,
    required this.onRestore,
  });

  final int price;
  final bool busy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: glassTile(border: AppColors.blushStrong),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.dailyStreakBroken,
              style: glassText(13, 650, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          GlassButton(
            key: const ValueKey('daily-restore'),
            onPressed: busy ? null : onRestore,
            icon: Icons.monetization_on,
            label: l10n.dailyStreakRestore(price),
          ),
        ],
      ),
    );
  }
}

/// Кружок-значок у заголовка: белый, как кольца ухода.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.blushStrong, width: 3),
      ),
      child: Icon(icon, size: 18, color: const Color(0xFFD42A33)),
    );
  }
}
