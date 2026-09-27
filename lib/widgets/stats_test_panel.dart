import 'package:flutter/material.dart';

import '../bear/bear_controller.dart';

/// ⚠ ПРОВЕРОЧНАЯ ПАНЕЛЬ ПОКАЗАТЕЛЕЙ — снять перед публикацией (заказчик
/// 27.09: «живой мишка»). Показатели закреплены заглушками, сами не
/// падают; кнопки роняют их по −25, «Всё ↑» возвращает — так за минуту
/// видно всю цепочку: сытый → просит → голодный → покормили → рад.
class StatsTestPanel extends StatelessWidget {
  const StatsTestPanel({super.key, required this.controller});

  final BearController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.state.stats;
        return Column(
          key: const ValueKey('stats-test-panel'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Btn(
              'Еда ↓ ${s.food.round()}',
              () => controller.nudgeStats(food: -25),
            ),
            _Btn(
              'Сон ↓ ${s.sleep.round()}',
              () => controller.nudgeStats(sleep: -25),
            ),
            _Btn(
              'Гигиена ↓ ${s.hygiene.round()}',
              () => controller.nudgeStats(hygiene: -25),
            ),
            _Btn(
              'Игра ↓ ${s.play.round()}',
              () => controller.nudgeStats(play: -25),
            ),
            _Btn(
              'Всё ↑',
              () => controller.nudgeStats(
                food: 100,
                sleep: 100,
                hygiene: 100,
                play: 100,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: GestureDetector(
        key: ValueKey('stats-test-$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x33000000)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF3B2A1E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
