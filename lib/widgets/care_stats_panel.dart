import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear_action.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'scene_label.dart';

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
/// Проценты заказчик просил сохранить, но мелко: подпись и число стоят
/// одной строкой под кольцом, число — светлее и на пункт меньше. Двумя
/// строками, как раньше, ряд получался громоздким.
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
  // Тот же ход, что у лапы внизу справа: заказчик 20.09 — «нужно сделать
  // анимацию такую же, чтобы как она выпрыгивала».
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Открыт ли ряд. Отдельным полем, а не по значению анимации: в кадр
  /// нажатия контроллер ещё стоит на нуле, и проверка через него
  /// переключала бы состояние вхолостую.
  ///
  /// **При запуске ряд открыт.** Заказчик 21.09: «когда открывается
  /// приложение — в любом случае при его открытии — это меню должно быть
  /// всегда раскрыто; по желанию человек нажимает справа крестик, тогда оно
  /// только прячется. Как он поел, сколько ему нужно поесть ещё — они
  /// должны быть видны сразу». Спрятанные за кнопкой показатели надо было
  /// сначала найти, а они и есть главное, за чем сюда заходят.
  bool _open = true;

  @override
  void initState() {
    super.initState();
    // Сразу раскрытым, без выезда: анимация при каждом запуске — это не
    // приветствие, а задержка перед тем, что человек пришёл прочитать.
    _slide.value = 1;
  }

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

  /// Выбор действия ряд не закрывает.
  ///
  /// Закрывал до 21.09 — «он своё дело сделал и уводит в комнату». Но дело
  /// его на этом и начинается: покормив, человек смотрит, сколько осталось
  /// докормить, а ряд в этот момент уезжал. Прячет его теперь только
  /// крестик.
  void _pick(BearAction action) => widget.onAction?.call(action);

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
                      key: const ValueKey('care.toggle'),
                      value: CareStatsPanel.totalCare(widget.stats),
                      open: _open,
                      squash: math.sin(_slide.value * math.pi) * 0.12,
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
    // Почерк лапы: каждое следующее кольцо стартует чуть позже предыдущего,
    // на вылете проскакивает своё место и возвращается, на сборе — просто
    // уезжает: назад вещи не пружинят.
    // Ближнее к кнопке кольцо трогается первым: очередь читается как вылет
    // из-под кнопки, а не как гонка, где дальний стартовал раньше всех.
    final start = (3 - index) * 0.12;
    final local = ((_slide.value - start) / (1 - start)).clamp(0.0, 1.0);
    final eased = _slide.status == AnimationStatus.reverse
        ? Curves.easeInCubic.transform(local)
        : Curves.easeOutBack.transform(local);

    // Пока ряд сложен, колец в дереве нет вовсе: иначе под кнопкой остаются
    // четыре прозрачных кружка, и скринридер читает спрятанное меню.
    if (local <= 0) return const [];

    return [
      Positioned(
        left: closed + (index * slot - closed) * eased,
        width: slot,
        top: 0,
        child: IgnorePointer(
          ignoring: local < 0.35,
          child: Opacity(
            opacity: local,
            child: Transform.scale(
              scale: 0.55 + 0.45 * local,
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
        ),
      ),
    ];
  }
}

/// Кнопка с тремя полосками: общий уход на обводке, ряд колец внутри.
class _TotalButton extends StatelessWidget {
  const _TotalButton({
    super.key,
    required this.value,
    required this.open,
    required this.squash,
    required this.onTap,
  });

  final double value;
  final bool open;

  /// Приседание: в начале нажатия кнопка уходит вниз и сжимается, потом
  /// возвращается. Считается от того же хода, что и вылет колец, поэтому
  /// прыжок и разлёт — одно движение, а не два наложенных.
  final double squash;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, squash * 22),
              child: Transform.scale(
                scaleX: 1 + squash * 0.7,
                scaleY: 1 - squash * 0.7,
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
                        // Полоски рисуем сами: у материаловской иконки они
                        // толще и в кружке выглядят тяжело.
                        child: CustomPaint(
                          painter: _BarsPainter(
                            open: open,
                            color: AppColors.sageDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Общий уход стоит подписью под кнопкой — на одной строке с
            // подписями колец, мелко и без слова «всего».
            SceneLabel(
              text: '${value.round()}%',
              size: 10,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Три полоски, а в открытом виде — косой крест.
///
/// Переход между ними идёт по тому же ходу, что и вылет колец: средняя
/// полоска тает, верхняя и нижняя сходятся в крест.
class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.open, required this.color});

  final bool open;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = color;

    final center = size.center(Offset.zero);
    const half = 8.0;
    const step = 5.0;

    if (open) {
      canvas.drawLine(
        center + const Offset(-6, -6),
        center + const Offset(6, 6),
        paint,
      );
      canvas.drawLine(
        center + const Offset(6, -6),
        center + const Offset(-6, 6),
        paint,
      );
      return;
    }

    for (final dy in [-step, 0.0, step]) {
      canvas.drawLine(
        center + Offset(-half, dy),
        center + Offset(half, dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.open != open || old.color != color;
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
            const SizedBox(height: 5),
            // Подпись и процент одной строкой в капсуле: проценты заказчик
            // просил сохранить, но мелко. Двумя строками, как было до 20.09,
            // ряд занимал треть потолка комнаты.
            // Самая длинная подпись — «Гигиена 100%» — в своё место в ряду
            // не влезает и обрезалась многоточием. Ужимаем её целиком, а не
            // режем: процент в ней важнее красоты кегля.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: SceneLabel(
                text: stat.label,
                trailing: '${stat.value.round()}%',
                size: 10,
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
              ),
            ),
          ],
        ),
      ),
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
