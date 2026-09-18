import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

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
