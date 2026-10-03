import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// «Напоминать о малыше?» — мягкий вопрос перед системным (КП 13.1;
/// заказчик 26.09).
///
/// Без разрешения iPhone молча не показывает ни одного напоминания, а
/// системный вопрос задаётся один раз. Поэтому сначала свой: не в первую
/// минуту знакомства, а когда мишке исполнился день. «Да» — системный
/// запрос и напоминания о голоде, игре и сне. «Не сейчас» — больше не
/// спрашиваем, включить можно в настройках (там переключатель сам спросит).
///
/// Вопрос задаётся один раз на телефоне.
Future<void> maybeAskNotifications(
  BuildContext context,
  GameState game, {
  DateTime? now,
}) async {
  if (!game.canAskNotifications) return;
  final age = (now ?? DateTime.now()).difference(game.profile.birthAt);
  if (age < askAfter) return;
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) ?? false) return;
  } on Object {
    return;
  }
  if (!context.mounted) return;
  await prefs.setBool(_askedKey, true);
  if (!context.mounted) return;
  final yes = await showGlassPanel<bool>(
    context: context,
    center: const Offset(0.5, 0.45),
    width: 330,
    builder: (context) => NotifyPrompt(game: game),
  );
  if (!context.mounted) return;
  final l10n = context.l10n;
  final granted = yes == true && await game.enableCareReminders();
  if (granted || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(yes == true ? l10n.notifyDenied : l10n.notifyAskLaterHint),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Через сколько после рождения спрашивать.
const Duration askAfter = Duration(days: 1);

const String _askedKey = 'notify_prompt_asked';

class NotifyPrompt extends StatelessWidget {
  const NotifyPrompt({super.key, required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassTitle(
          l10n.notifyAskTitle,
          close: false,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.statFood, width: 3),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              size: 18,
              color: Color(0xFFE08A2E),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.notifyAskLead(petDisplayName(l10n, game.profile.name)),
          style: glassText(14.5, 650, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                key: const ValueKey('notify-later'),
                label: l10n.notifyAskLater,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                key: const ValueKey('notify-yes'),
                primary: true,
                icon: Icons.notifications_rounded,
                label: l10n.notifyAskYes,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
