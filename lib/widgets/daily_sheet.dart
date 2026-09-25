import 'package:flutter/material.dart';

import '../backend/pet_snapshot.dart' show DailyInfo, DailyTask;
import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'gift_reveal.dart';

/// «Сегодня»: подарок дня, задания дня и задание недели (заказчик 25.09,
/// миграция 0017; КП 11.1 — монеты за вход и достижения, КП 13.1 —
/// «Подарок» и «Задание»).
///
/// Открывается сам при входе, если подарок ещё не забран, и из профиля.
/// Всё считает сервер: календарь, задания, награды. Экран только
/// показывает и отправляет «Забрать».
Future<void> showDailySheet(BuildContext context, GameState game) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              12,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.dailyTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                if (daily.isEmpty)
                  Text(
                    l10n.dailyOffline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  )
                else ...[
                  _GiftCalendar(daily: daily),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('daily-claim'),
                    onPressed: daily.giftAvailable && !_claiming
                        ? _claim
                        : null,
                    child: Text(
                      daily.giftAvailable
                          ? l10n.dailyGiftClaim(_rewardOf(daily))
                          : l10n.dailyGiftClaimed,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    l10n.dailyTasksTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final task in daily.tasks) _TaskRow(task: task),
                  const SizedBox(height: 10),
                  Text(
                    daily.weeklyClaimed
                        ? l10n.dailyWeeklyDone
                        : l10n.dailyWeekly(
                            daily.weeklyTarget,
                            daily.weeklyDone,
                            daily.weeklyReward,
                          ),
                    key: const ValueKey('daily-weekly'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: day < today || (!daily.giftAvailable && day == today)
                      ? AppColors.sageSoft
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: day == today ? AppColors.sage : AppColors.outline,
                    width: day == today ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.dailyGiftDay(day),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day <= daily.giftRewards.length
                          ? '${daily.giftRewards[day - 1]}'
                          : '',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
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
              style: TextStyle(
                color: AppColors.textPrimary,
                decoration: task.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            '${task.progress}/${task.target}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+${task.reward}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.sageDark,
            ),
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
