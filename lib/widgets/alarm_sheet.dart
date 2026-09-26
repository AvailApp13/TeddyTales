import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// Выбор времени будильника «проснёмся вместе». Заказчик 22.09: «скролл,
/// как на айфоне»; 26.09: не лист снизу, а компактное окно из матового
/// стекла прямо на одеяле, кнопки — в стиле главного экрана.
///
/// Формат времени пока 24-часовой для всех: к региону привяжем при
/// регистрации, это отдельное решение заказчика. Возвращает выбранное
/// время или `null`, если закрыли без «Готово».
Future<TimeOfDay?> showAlarmSheet({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showGlassPanel<TimeOfDay>(
    context: context,
    // На одеяле, под мишкой.
    center: const Offset(0.5, 0.71),
    width: 292,
    builder: (context) => _AlarmPanel(initial: initial),
  );
}

class _AlarmPanel extends StatefulWidget {
  const _AlarmPanel({required this.initial});

  final TimeOfDay initial;

  @override
  State<_AlarmPanel> createState() => _AlarmPanelState();
}

class _AlarmPanelState extends State<_AlarmPanel> {
  static const _step = 5;
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute - widget.initial.minute % _step;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Кружок как у колец ухода: белый, лиловая иконка сна.
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.statSleep, width: 3),
              ),
              child: const Icon(
                Icons.alarm_rounded,
                size: 18,
                color: Color(0xFF7D76B4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.bedroomAlarmHelp,
                style: sceneText(17, 800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Выбранная строка — белая капсула, как кнопки сцены.
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Wheel(
                    key: const ValueKey('alarm-hours'),
                    count: 24,
                    initial: _hour,
                    label: (i) => i.toString().padLeft(2, '0'),
                    onChanged: (i) => _hour = i,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      ':',
                      style: sceneText(30, 900, color: AppColors.textPrimary),
                    ),
                  ),
                  _Wheel(
                    key: const ValueKey('alarm-minutes'),
                    count: 60 ~/ _step,
                    initial: _minute ~/ _step,
                    label: (i) => (i * _step).toString().padLeft(2, '0'),
                    onChanged: (i) => _minute = i * _step,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: l10n.commonCancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                key: const ValueKey('alarm-done'),
                label: l10n.bedroomAlarmDone,
                icon: Icons.check_rounded,
                primary: true,
                onPressed: () => Navigator.of(
                  context,
                ).pop(TimeOfDay(hour: _hour, minute: _minute)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Барабан чисел: крутится по кругу, выбранное — крупно в центре.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.count,
    required this.initial,
    required this.label,
    required this.onChanged,
  });

  final int count;
  final int initial;
  final String Function(int index) label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      child: CupertinoPicker.builder(
        itemExtent: 44,
        diameterRatio: 1.3,
        squeeze: 1.05,
        selectionOverlay: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        scrollController: FixedExtentScrollController(
          initialItem: count * 50 + initial,
        ),
        onSelectedItemChanged: (i) => onChanged(i % count),
        childCount: count * 100,
        itemBuilder: (context, i) => Center(
          child: Text(
            label(i % count),
            style: sceneText(30, 800, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
