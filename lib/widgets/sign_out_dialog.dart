import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// Подтверждение выхода из аккаунта (КП 14.2).
///
/// Живёт отдельно, потому что кнопок выхода две — в профиле и в настройках, —
/// а диалог должен быть один. Два разных подтверждения на одно действие
/// путают сильнее, чем лишний файл.
///
/// Спрашиваем обязательно: выход — единственное необратимое действие в
/// приложении, которое делается одним касанием. И говорим главное — что
/// прогресс никуда не денется: без этой строки человек читает «выйти» как
/// «стереть мишку».
Future<void> confirmSignOut(
  BuildContext context,
  VoidCallback? onSignOut,
) async {
  if (onSignOut == null) return;
  final l10n = context.l10n;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.settingsSignOutConfirmTitle),
      content: Text(l10n.settingsSignOutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settingsSignOut),
        ),
      ],
    ),
  );

  if (ok == true) onSignOut();
}

/// Удаление аккаунта (правило App Store 5.1.1). Два шага: пункт в
/// настройках → стеклянное окно, где прямо сказано, что пропадёт навсегда.
/// Главная кнопка — «Оставить»: случайное касание ничего не стирает.
Future<void> confirmDeleteAccount(BuildContext context, GameState game) async {
  final delete = game.onDeleteAccount;
  if (delete == null) return;
  final ok = await showGlassPanel<bool>(
    context: context,
    center: const Offset(0.5, 0.45),
    width: 330,
    builder: (context) {
      final l10n = context.l10n;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassTitle(l10n.deleteAccountTitle, close: false),
          const SizedBox(height: 10),
          Text(
            l10n.deleteAccountLead(petDisplayName(l10n, game.profile.name)),
            style: glassText(14.5, 650, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),
          GlassButton(
            key: const ValueKey('delete-account-keep'),
            primary: true,
            label: l10n.deleteAccountCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('delete-account-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.deleteAccountConfirm,
              style: glassText(14, 800, color: const Color(0xFFB3261E)),
            ),
          ),
        ],
      );
    },
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = context.l10n.deleteAccountFailed;
  if (await delete()) return;
  messenger?.showSnackBar(
    SnackBar(content: Text(failed), behavior: SnackBarBehavior.floating),
  );
}
