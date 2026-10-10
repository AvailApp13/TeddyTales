import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear_action.dart';
import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'feed_burst.dart';
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
///
/// **Сам сворачивается** (заказчик 10.10). Ряд открыт при запуске, как
/// просили 21.09, но через [collapseAfter] без касаний сворачивается
/// обратно в общий круг. Общий круг висел поверх картин и потолка — ещё
/// через [tuckAfter] он уменьшается и уезжает к правому краю, наполовину
/// за край экрана, «язычком». Тап по нему — выезжает и раскрывает ряд, самый
/// низкий показатель подсвечен. Любое касание экрана ([activity])
/// начинает отсчёт заново. Если какой-то показатель ниже [lowThreshold],
/// свёрнутый круг раз в несколько секунд покачивается, а кольцо у него —
/// цвета самого низкого показателя.
class CareStatsPanel extends StatefulWidget {
  const CareStatsPanel({
    super.key,
    required this.stats,
    required this.stage,
    this.onAction,
    this.fx,
    this.activity,
    this.edgePadding = 0,
  });

  final BearCareStats stats;
  final BearStage stage;
  final ValueChanged<BearAction>? onAction;

  /// Пузырь сытости: кружок «Еда» ловит его, подпрыгивает и считает
  /// проценты вверх (заказчик 24.09).
  final FeedFx? fx;

  /// Касания по всему экрану: каждое начинает отсчёт бездействия заново.
  final Listenable? activity;

  /// Отступ ряда от краёв экрана. Сама панель — во всю ширину: свёрнутый
  /// круг уезжает к самому краю и должен нажиматься и там.
  final double edgePadding;

  /// Высота панели: кольцо и подпись под ним.
  static const double height = _ringSize + 4 + 16;

  /// Через сколько без касаний ряд сворачивается в общий круг.
  static const Duration collapseAfter = Duration(seconds: 3);

  /// Через сколько без касаний свёрнутый круг уезжает к краю.
  static const Duration tuckAfter = Duration(seconds: 5);

  /// Как часто свёрнутый круг напоминает о себе, если показатель низкий.
  static const Duration pulseEvery = Duration(seconds: 4);

  /// Ниже этого показатель просит внимания.
  static const double lowThreshold = 30;

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
    with TickerProviderStateMixin {
  // Тот же ход, что у лапы внизу справа: заказчик 20.09 — «нужно сделать
  // анимацию такую же, чтобы как она выпрыгивала».
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Общий круг уезжает к краю «язычком» и возвращается.
  late final AnimationController _tuck = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 280),
  );

  /// Покачивание свёрнутого круга, когда показатель низкий.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  /// Открыт ли ряд. Отдельным полем, а не по значению анимации: в кадр
  /// нажатия контроллер ещё стоит на нуле, и проверка через него
  /// переключала бы состояние вхолостую.
  ///
  /// **При запуске ряд открыт.** Заказчик 21.09: «когда открывается
  /// приложение — в любом случае при его открытии — это меню должно быть
  /// всегда раскрыто». С 10.10 он сам сворачивается через
  /// [CareStatsPanel.collapseAfter] без касаний.
  bool _open = true;

  /// Свёрнутый круг уехал к краю.
  bool _tucked = false;

  /// Какой показатель подсвечен после тапа по свёрнутому кругу — самый
  /// низкий. `null` — никакой.
  BearAction? _highlight;

  Timer? _idle;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    // Сразу раскрытым, без выезда: анимация при каждом запуске — это не
    // приветствие, а задержка перед тем, что человек пришёл прочитать.
    _slide.value = 1;
    widget.activity?.addListener(_onActivity);
    widget.fx?.addListener(_onFx);
    _armIdle();
  }

  @override
  void didUpdateWidget(CareStatsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity?.removeListener(_onActivity);
      widget.activity?.addListener(_onActivity);
    }
    if (oldWidget.fx != widget.fx) {
      oldWidget.fx?.removeListener(_onFx);
      widget.fx?.addListener(_onFx);
    }
    // Показатель мог упасть ниже порога или подняться.
    _syncPulse();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _pulseTimer?.cancel();
    widget.activity?.removeListener(_onActivity);
    widget.fx?.removeListener(_onFx);
    _slide.dispose();
    _tuck.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Самый низкий из четырёх показателей на экране.
  CareStat _lowest(List<CareStat> tiles) =>
      tiles.reduce((a, b) => b.value < a.value ? b : a);

  bool get _low =>
      _lowest(_tiles(context.l10n)).value < CareStatsPanel.lowThreshold;

  /// Человек коснулся экрана — отсчёт бездействия заново. Уехавший к краю
  /// круг от этого не возвращается: его достают тапом по нему самому.
  void _onActivity() => _armIdle();

  /// Пока летит пузырь сытости, ряд раскрыт — пузырю нужно кольцо «Еда».
  void _onFx() {
    final fx = widget.fx;
    if (fx == null || !mounted) return;
    if (fx.busy) {
      _idle?.cancel();
      if (!_open || _tucked) _expand(highlight: false);
    } else {
      _armIdle();
    }
  }

  void _armIdle() {
    _idle?.cancel();
    if (widget.fx?.busy ?? false) return;
    if (_open) {
      _idle = Timer(CareStatsPanel.collapseAfter, _collapse);
    } else if (!_tucked) {
      _idle = Timer(CareStatsPanel.tuckAfter, _tuckAway);
    }
  }

  void _collapse() {
    if (!mounted || !_open) return;
    setState(() {
      _open = false;
      _highlight = null;
    });
    _slide.reverse();
    _armIdle();
    _syncPulse();
  }

  void _tuckAway() {
    if (!mounted || _open || _tucked) return;
    setState(() => _tucked = true);
    _tuck.forward();
    _syncPulse();
  }

  void _expand({required bool highlight}) {
    setState(() {
      _tucked = false;
      _open = true;
      _highlight = highlight ? _lowest(_tiles(context.l10n)).action : null;
    });
    _tuck.reverse();
    _slide.forward();
    _armIdle();
    _syncPulse();
  }

  /// Тап по общему кругу: свёрнутый — выезжает и раскрывает ряд, самый
  /// низкий показатель подсвечен; раскрытый — крестиком сворачивает.
  void _toggle() {
    if (_open && !_tucked) {
      _collapse();
    } else {
      _expand(highlight: true);
    }
  }

  /// Покачивание — только у свёрнутого круга и только пока есть низкий
  /// показатель.
  void _syncPulse() {
    final want = !_open && _low;
    if (!want) {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      return;
    }
    _pulseTimer ??= Timer.periodic(CareStatsPanel.pulseEvery, (_) {
      if (mounted) _pulse.forward(from: 0);
    });
  }

  /// Выбор действия ряд не закрывает.
  ///
  /// Закрывал до 21.09 — «он своё дело сделал и уводит в комнату». Но дело
  /// его на этом и начинается: покормив, человек смотрит, сколько осталось
  /// докормить, а ряд в этот момент уезжал. Сворачивается ряд сам, когда
  /// его оставят в покое (10.10).
  void _pick(BearAction action) {
    _armIdle();
    widget.onAction?.call(action);
  }

  /// Порядок колец: игра, еда, гигиена, сон. Пятой справа стоит кнопка,
  /// которая ряд прячет.
  ///
  /// Заказчик 21.09: «игра — это основная, после еда, гигиена и в конце сон».
  /// До этого первой шла еда. Порядок здесь — решение заказчика, а не
  /// следствие чего-то в коде, поэтому менять его на свой вкус нельзя.
  List<CareStat> _tiles(AppLocalizations l10n) => [
    CareStat(
      label: l10n.statsPlay,
      icon: Icons.sports_baseball_outlined,
      value: widget.stats.play,
      color: AppColors.statPlay,
      action: BearAction.play,
    ),
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
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles(context.l10n);
    final lowest = _lowest(tiles);
    final low = lowest.value < CareStatsPanel.lowThreshold;

    return SizedBox(
      height: CareStatsPanel.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Пять мест в ряд, как было с пятью кольцами: четыре показателя и
          // кнопка на месте бывшей «Любви», у самого края. Ряд стоит с
          // отступом от краёв, а сама панель — во всю ширину.
          final pad = widget.edgePadding;
          final slot = (constraints.maxWidth - 2 * pad) / 5;
          final closed = pad + slot * 4;
          // Язычок: центр общего круга — ровно на краю экрана.
          final tuckShift = pad + slot / 2;

          return AnimatedBuilder(
            animation: Listenable.merge([_slide, _tuck, _pulse]),
            builder: (context, _) {
              final tuck = Curves.easeInOutCubic.transform(_tuck.value);
              final p = _pulse.value;
              // Покачивание: лёгкий вдох и пара наклонов, затихающих к концу.
              final pulseScale = 1 + 0.12 * math.sin(math.pi * p);
              final wobble = 0.16 * math.sin(4 * math.pi * p) * (1 - p);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Кольца рисуются под кнопкой: они из-под неё и выезжают.
                  for (var i = 0; i < tiles.length; i++)
                    ..._ring(tiles[i], i, pad, slot, closed),
                  Positioned(
                    left: closed,
                    width: slot,
                    top: 0,
                    child: Transform.translate(
                      offset: Offset(tuckShift * tuck, 0),
                      child: Transform.rotate(
                        angle: wobble,
                        child: Transform.scale(
                          scale: (1 - 0.25 * tuck) * pulseScale,
                          child: Center(
                            child: _TotalButton(
                              key: const ValueKey('care.toggle'),
                              value: CareStatsPanel.totalCare(widget.stats),
                              open: _open && !_tucked,
                              // Низкий показатель — кольцо его цвета.
                              color: low && !_open
                                  ? lowest.color
                                  : AppColors.sageDark,
                              labelOpacity: 1 - tuck,
                              squash: math.sin(_slide.value * math.pi) * 0.12,
                              onTap: _toggle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Одно кольцо на своём месте в ряду — или сложенное под кнопкой.
  List<Widget> _ring(
    CareStat tile,
    int index,
    double pad,
    double slot,
    double closed,
  ) {
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
        left: closed + (pad + index * slot - closed) * eased,
        width: slot,
        top: 0,
        child: IgnorePointer(
          ignoring: local < 0.35,
          child: Opacity(
            opacity: local,
            child: Transform.scale(
              scale: 0.55 + 0.45 * local,
              child: Center(child: _statRing(tile)),
            ),
          ),
        ),
      ),
    ];
  }
}

extension on _CareStatsPanelState {
  Widget _statRing(CareStat tile) {
    final enabled =
        widget.onAction != null &&
        (!kStageLocksOnStats || tile.action.isAvailableOn(widget.stage));
    final fx = widget.fx;
    final highlight = tile.action == _highlight;
    if (fx == null || tile.action != BearAction.feed) {
      return _StatRing(
        stat: tile,
        enabled: enabled,
        highlight: highlight,
        onTap: () => _pick(tile.action),
      );
    }
    // «Еда» слушает пузырь: пока он летит — прежний процент, после удара
    // проценты бегут вверх, кружок подпрыгивает и вспыхивает.
    return ListenableBuilder(
      listenable: fx,
      builder: (context, _) => _StatRing(
        stat: CareStat(
          label: tile.label,
          icon: tile.icon,
          value: fx.food(tile.value),
          color: tile.color,
          action: tile.action,
        ),
        enabled: enabled,
        highlight: highlight,
        onTap: () => _pick(tile.action),
        ringKey: fx.foodRing,
        bump: fx.foodBump,
        hot: fx.counting,
      ),
    );
  }
}

/// Кнопка с тремя полосками: общий уход на обводке, ряд колец внутри.
class _TotalButton extends StatelessWidget {
  const _TotalButton({
    super.key,
    required this.value,
    required this.open,
    required this.color,
    required this.labelOpacity,
    required this.squash,
    required this.onTap,
  });

  final double value;
  final bool open;

  /// Цвет кольца: обычный зелёный или цвет самого низкого показателя.
  final Color color;

  /// Подпись с процентом гаснет, когда круг уезжает к краю.
  final double labelOpacity;

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
                      color: color,
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
                          painter: _BarsPainter(open: open, color: color),
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
            Opacity(
              opacity: labelOpacity.clamp(0.0, 1.0),
              child: SceneLabel(
                text: '${value.round()}%',
                size: 10,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
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
    this.highlight = false,
    this.ringKey,
    this.bump,
    this.hot = false,
  });

  final CareStat stat;
  final bool enabled;
  final VoidCallback onTap;

  /// Самый низкий показатель, когда ряд раскрыли тапом по свёрнутому
  /// кругу: мягкое свечение его цвета.
  final bool highlight;

  /// Ключ самого кольца — по нему пузырь сытости находит цель.
  final Key? ringKey;

  /// Удар пузыря: 0…1 от удара до покоя, `null` — покой.
  final double? bump;

  /// Проценты бегут — число в подписи золотое.
  final bool hot;

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
            _bumped(
              _glow(
                SizedBox(
                  key: ringKey,
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
                trailingColor: hot ? const Color(0xFFFFE3A0) : null,
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

extension on _StatRing {
  /// Самый низкий показатель после тапа по свёрнутому кругу: кольцо чуть
  /// крупнее и светится своим цветом (заказчик 10.10).
  Widget _glow(Widget ring) {
    return AnimatedScale(
      scale: highlight ? 1.08 : 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: stat.color.withValues(alpha: highlight ? 0.75 : 0),
              blurRadius: 16,
              spreadRadius: highlight ? 3 : 0,
            ),
          ],
        ),
        child: ring,
      ),
    );
  }

  /// Кружок, по которому ударил пузырь: подпрыгнул, чуть раздулся,
  /// вспыхнул золотым ободком и, покачавшись, сел на место.
  Widget _bumped(Widget ring) {
    final t = bump;
    if (t == null) return ring;
    final b = FeedFx.bounce(t);
    final flash = math.pow(1 - t, 2).toDouble();
    return Transform.translate(
      offset: Offset(0, -9 * b),
      child: Transform.scale(
        scale: 1 + 0.13 * b,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD58A).withValues(alpha: 0.85 * flash),
                blurRadius: 16,
                spreadRadius: 3 * flash,
              ),
            ],
          ),
          child: ring,
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
