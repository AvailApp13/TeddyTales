import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Выбор времени будильника «проснёмся вместе»: лист снизу с колесом,
/// как на iPhone. Заказчик 22.09: «открывается такой скролл, как на
/// айфоне, в какое время поставить».
///
/// Формат времени пока 24-часовой для всех: к региону привяжем при
/// регистрации, это отдельное решение заказчика. Возвращает выбранное
/// время или `null`, если закрыли без «Готово».
Future<TimeOfDay?> showAlarmSheet({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _AlarmSheet(initial: initial),
  );
}

class _AlarmSheet extends StatefulWidget {
  const _AlarmSheet({required this.initial});

  final TimeOfDay initial;

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> {
  late TimeOfDay _time = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Компактно: одна строка сверху, колесо, две кнопки — заказчик
            // 22.09 про циферблат: «очень громоздкий, давай в 50%».
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.statSleep,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.alarm_outlined,
                    size: 18,
                    color: AppColors.surface,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.bedroomAlarmHelp,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Колесо в кремовой рамке: барабан сам по себе прозрачный, и
            // без подложки выделенная строка теряется на светлом листе.
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 5,
                  initialDateTime: DateTime(
                    now.year,
                    now.month,
                    now.day,
                    widget.initial.hour,
                    widget.initial.minute - widget.initial.minute % 5,
                  ),
                  onDateTimeChanged: (value) => _time = TimeOfDay(
                    hour: value.hour,
                    minute: value.minute,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusPill),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_time),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sageDark,
                      foregroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusPill),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l10n.bedroomAlarmDone),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
