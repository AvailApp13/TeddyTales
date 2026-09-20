import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear_action.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Один показатель.
class CareStat {
  const CareStat({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
    required this.action,
  });

  final String label;
  final IconData icon;
  final double value;
  final Color color;

  /// Какое действие ухода поднимает этот показатель.
  final BearAction action;
}

/// Гасить ли кольца, недоступные на текущей стадии роста.
///
/// Выключено по просьбе заказчика 20.09: «мне для теста пока нужно, чтобы
/// кнопки работали». Мытьё и игра по ТЗ аниматора открываются только со
/// второй стадии, и на свежем профиле — а он всегда новорождённый — два
/// кольца из пяти гасли и не пускали в свои комнаты. Для проверки комнат это
/// тупик: попасть в ванную было нечем.
///
/// Сам механизм замков цел и нужен по КП 3.5. Включать его обратно надо не
/// этим флагом, а правилами с сервера (КП 15.4) — иначе тестировать игру
/// снова можно будет только выращенным мишкой.
const bool kStageLocksOnStats = false;

/// Кольца показателей, спрятанные в одну кнопку (решение заказчика 20.09).
///
/// До этого пятёрка колец — еда, гигиена, сон, игра, любовь — стояла поверх
/// комнаты постоянно и вместе с процентами занимала весь верх экрана.
/// Заказчик: «вместо любви мы делаем эту кнопку, она будет прятать все».
///
/// Любовь с экрана ушла: гладить мишку можно тапом по нему самому, а
/// показатель по КП 6.1 остался жив — он растёт от поглаживаний, держит
/// характер «ласковый» (КП 7.1) и входит в общий процент на кнопке. Кольца
/// ему не нужно: в отличие от четырёх остальных, оно никуда не вело — ласка
/// происходит там, где мишка стоит.
///
/// Проценты цифрами убраны совсем: заливка кольца и так показывает долю, а
/// число рядом с ней — то же самое второй раз.
class CareStatsPanel extends StatefulWidget {
  const CareStatsPanel({
    super.key,
    required this.stats,
    required this.stage,
    this.onAction,
  });

  final BearCareStats stats;
  final BearStage stage;
  final ValueChanged<BearAction>? onAction;

  /// Высота панели: кольцо и подпись под ним.
  static const double height = _ringSize + 4 + 16;

  /// Общий уход — среднее всех пяти показателей КП 6.1, вместе с любовью.
  ///
  /// Любви нет на экране, но она входит сюда: заброшенная ласка так же
  /// тормозит рост (КП 5.7), как несъеденный обед, и по одной этой заливке
  /// должно быть видно, всё ли у мишки хорошо.
  static double totalCare(BearCareStats s) =>
      (s.food + s.hygiene + s.sleep + s.play + s.love) / 5;

  static const double _ringSize = 58;

  @override
  State<CareStatsPanel> createState() => _CareStatsPanelState();
}

class _CareStatsPanelState extends State<CareStatsPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );

  /// Открыт ли ряд. Отдельным полем, а не по значению анимации: в кадр
  /// нажатия контроллер ещё стоит на нуле, и проверка через него
  /// переключала бы состояние вхолостую.
  bool _open = false;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _slide.forward();
    } else {
      _slide.reverse();
    }
  }

  /// Выбор действия закрывает ряд: он своё дело сделал и уводит в комнату.
  void _pick(BearAction action) {
    _toggle();
    widget.onAction?.call(action);
  }

  List<CareStat> _tiles(AppLocalizations l10n) => [
    CareStat(
      label: l10n.statsFood,
      icon: Icons.restaurant,
      value: widget.stats.food,
      color: AppColors.statFood,
      action: BearAction.feed,
    ),
    CareStat(
      label: l10n.statsHygiene,
      icon: Icons.bathtub_outlined,
      value: widget.stats.hygiene,
      color: AppColors.statHygiene,
      action: BearAction.wash,
    ),
    CareStat(
      label: l10n.statsSleep,
      icon: Icons.nightlight_round,
      value: widget.stats.sleep,
      color: AppColors.statSleep,
      action: BearAction.sleep,
    ),
    CareStat(
      label: l10n.statsPlay,
      icon: Icons.sports_baseball_outlined,
      value: widget.stats.play,
      color: AppColors.statPlay,
      action: BearAction.play,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles(context.l10n);

    return SizedBox(
      height: CareStatsPanel.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Пять мест в ряд, как было с пятью кольцами: четыре показателя и
          // кнопка на месте бывшей «Любви», у самого края.
          final slot = constraints.maxWidth / 5;
          final closed = slot * 4;

          return AnimatedBuilder(
            animation: _slide,
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                // Кольца рисуются под кнопкой: они из-под неё и выезжают.
                for (var i = 0; i < tiles.length; i++)
                  ..._ring(tiles[i], i, slot, closed),
                Positioned(
                  left: closed,
                  width: slot,
                  top: 0,
                  child: Center(
                    child: _TotalButton(
                      value: CareStatsPanel.totalCare(widget.stats),
                      open: _open,
                      onTap: _toggle,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Одно кольцо на своём месте в ряду — или сложенное под кнопкой.
  List<Widget> _ring(CareStat tile, int index, double slot, double closed) {
    // Ближнее к кнопке кольцо трогается первым, дальнее последним: ряд
    // разворачивается веером, а не едет одной плитой.
    final t = CurvedAnimation(
      parent: _slide,
      curve: Interval(0.08 * (3 - index), 1, curve: Curves.easeOutCubic),
      reverseCurve: Interval(0.08 * index, 1, curve: Curves.easeInCubic),
    ).value;

    // Пока ряд сложен, колец в дереве нет вовсе: иначе под кнопкой остаются
    // четыре прозрачных кружка, и скринридер читает спрятанное меню.
    if (t <= 0) return const [];

    return [
      Positioned(
        left: closed + (index * slot - closed) * t,
        width: slot,
        top: 0,
        child: Opacity(
          opacity: t.clamp(0, 1),
          child: Center(
            child: _StatRing(
              stat: tile,
              enabled:
                  widget.onAction != null &&
                  (!kStageLocksOnStats ||
                      tile.action.isAvailableOn(widget.stage)),
              onTap: () => _pick(tile.action),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Кнопка с тремя полосками: общий уход на обводке, ряд колец внутри.
class _TotalButton extends StatelessWidget {
  const _TotalButton({
    required this.value,
    required this.open,
    required this.onTap,
  });

  final double value;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Semantics(
      button: true,
      label: open ? l10n.statsHide : l10n.statsShow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: CareStatsPanel._ringSize,
          height: CareStatsPanel._ringSize,
          child: CustomPaint(
            painter: _RingPainter(
              value: value.clamp(0, 100) / 100,
              color: AppColors.sageDark,
            ),
            child: Center(
              child: Container(
                width: CareStatsPanel._ringSize - 13,
                height: CareStatsPanel._ringSize - 13,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  open ? Icons.close_rounded : Icons.menu_rounded,
                  size: 24,
                  color: AppColors.sageDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRing extends StatelessWidget {
  const _StatRing({
    required this.stat,
    required this.enabled,
    required this.onTap,
  });

  final CareStat stat;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: CareStatsPanel._ringSize,
              height: CareStatsPanel._ringSize,
              child: CustomPaint(
                painter: _RingPainter(
                  value: stat.value.clamp(0, 100) / 100,
                  color: stat.color,
                ),
                child: Center(
                  child: Container(
                    width: CareStatsPanel._ringSize - 13,
                    height: CareStatsPanel._ringSize - 13,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(stat.icon, size: 22, color: stat.color),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _Caption(
              text: stat.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подпись со светлой обводкой: кольца лежат поверх комнаты, и на тёмном
/// участке обоев простой текст пропадёт.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.background,
          ),
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color});

  /// Доля от нуля до единицы.
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.11;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surface.withValues(alpha: 0.85);
    canvas.drawCircle(rect.center, rect.width / 2, track);

    if (value <= 0) return;

    // От двенадцати часов по часовой стрелке: так растущее значение читается
    // как заполняющийся сосуд, а не как стрелка часов.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
