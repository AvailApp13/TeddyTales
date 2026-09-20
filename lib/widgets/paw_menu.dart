import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bear/bear_rig_spec.dart';
import '../game/app_section.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';

/// Кнопка-лапа и разлетающиеся из неё разделы.
///
/// Заменила нижнюю панель вкладок (решение заказчика 20.09). Причина у
/// заказчика была композиционная: комната поехала на весь экран, «и у нас
/// остаётся очень много свободного места», а полоса вкладок съедала низ
/// кадра ровно там, где стоит мишка.
///
/// Как это работает. Тап по лапе — она приседает и пружинит, из неё по дуге
/// вверх уходят четыре кружка: комната, магазин, обучение, мишки. Летят не
/// разом, а друг за другом, с небольшим перелётом — это и даёт ощущение
/// выброса, а не появления. Сбор — тем же путём, только быстрее и в обратном
/// порядке.
///
/// Лапа, а не три полоски: три полоски читаются как настройки, а лапа — знак
/// самой игры, он же в шапке.
class PawMenu extends StatefulWidget {
  const PawMenu({
    super.key,
    required this.stage,
    required this.onSelected,
    this.sections = const [
      AppSection.room,
      AppSection.shop,
      AppSection.learning,
      AppSection.catalog,
    ],
    this.idleTimeout = const Duration(seconds: 5),
  });

  /// Стадия роста: по ней разделы под замком (КП 3.5).
  final BearStage stage;

  /// Выбран раздел. Меню к этому моменту уже закрыто.
  final ValueChanged<AppSection> onSelected;

  /// Что вылетает из лапы. Профиль сюда не входит: он уехал в шапку.
  final List<AppSection> sections;

  /// Через сколько бездействия меню собирается обратно.
  ///
  /// Заказчик назвал пять секунд. Отсчёт идёт от последнего касания, а не от
  /// открытия: ребёнок выбирает медленнее взрослого, и меню, схлопнувшееся
  /// под занесённым пальцем, читается как поломка.
  final Duration idleTimeout;

  @override
  State<PawMenu> createState() => _PawMenuState();
}

class _PawMenuState extends State<PawMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 260),
  );

  Timer? _idle;

  /// Открыто ли меню — отдельным полем, а не по ходу анимации.
  ///
  /// Через `_fly.value > 0` не получится: в тот кадр, когда меню
  /// открывают, `forward()` уже вызван, а значение ещё ноль. Отсчёт
  /// авто-сбора при такой проверке не заводился вовсе — поймано тестом.
  bool _open = false;

  /// Радиус дуги и её края.
  ///
  /// Дуга уходит вверх и чуть влево: там свободный потолок. Вправо нельзя —
  /// это край экрана, вниз — угол, из которого лапа и растёт.
  static const double _radius = 228;
  static const double _fromDeg = -98;
  static const double _toDeg = -172;

  @override
  void dispose() {
    _idle?.cancel();
    _fly.dispose();
    super.dispose();
  }

  void _restartIdle() {
    _idle?.cancel();
    if (!_open) return;
    _idle = Timer(widget.idleTimeout, _close);
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _open = true;
      _fly.forward();
      _restartIdle();
      setState(() {});
    }
  }

  void _close() {
    _idle?.cancel();
    _idle = null;
    _open = false;
    _fly.reverse();
    if (mounted) setState(() {});
  }

  Future<void> _pick(AppSection section) async {
    if (!section.isUnlockedAt(widget.stage)) {
      _explainLock(section);
      // Замок — не выбор: меню остаётся открытым, но отсчёт начинается
      // заново, иначе оно закроется, пока человек читает пояснение.
      _restartIdle();
      return;
    }
    _close();
    widget.onSelected(section);
  }

  void _explainLock(AppSection section) {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${sectionTitle(l10n, section)}. '
            '${sectionLockReason(l10n, section)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fly,
      builder: (context, _) {
        final t = _fly.value;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Затемнение и ловушка для тапа мимо. Пока меню закрыто, слоя
            // нет вовсе — иначе он воровал бы поглаживание мишки.
            if (t > 0)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: ColoredBox(
                    color: AppColors.textPrimary.withValues(alpha: 0.38 * t),
                  ),
                ),
              ),
            // Закрытое меню не оставляет за собой невидимых кружков:
            // прозрачная кнопка всё равно попадает в озвучку экрана, и
            // человек со скринридером слышал бы четыре раздела там, где
            // на экране одна лапа.
            if (t > 0)
              for (var i = widget.sections.length - 1; i >= 0; i--)
                _petal(i, t),
            Positioned(right: 16, bottom: 24, child: _paw(t)),
          ],
        );
      },
    );
  }

  /// Один разлетевшийся кружок.
  Widget _petal(int index, double t) {
    final count = widget.sections.length;
    final section = widget.sections[index];

    // Каждый следующий стартует чуть позже предыдущего — из-за этого они
    // читаются как очередь, вылетающая из одной точки, а не как строй.
    final start = index * 0.12;
    final local = ((t - start) / (1 - start)).clamp(0.0, 1.0);
    // Перелёт: кружок проскакивает точку и возвращается. На сборе перелёта
    // нет — назад вещи не пружинят.
    final eased = _fly.status == AnimationStatus.reverse
        ? Curves.easeInCubic.transform(local)
        : Curves.easeOutBack.transform(local);

    final angle =
        (_fromDeg + (_toDeg - _fromDeg) * index / (count - 1)) * math.pi / 180;
    final distance = _radius * eased;

    return Positioned(
      right: 16 + 35 - 29 - math.cos(angle) * distance,
      bottom: 24 + 35 - 29 + math.sin(angle) * -distance,
      child: IgnorePointer(
        ignoring: local < 0.35,
        child: Opacity(
          opacity: local.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.55 + 0.45 * local,
            child: _PetalButton(
              section: section,
              locked: !section.isUnlockedAt(widget.stage),
              onTap: () => _pick(section),
            ),
          ),
        ),
      ),
    );
  }

  /// Сама лапа.
  Widget _paw(double t) {
    // Приседание: в начале нажатия кнопка уходит вниз и сжимается, потом
    // возвращается. Считается от того же хода, что и разлёт, поэтому прыжок
    // и вылет — одно движение, а не два наложенных.
    final squash = math.sin(t * math.pi) * 0.12;

    return Semantics(
      button: true,
      label: context.l10n.navSectionHome,
      child: GestureDetector(
        onTap: _toggle,
        child: Transform.translate(
          offset: Offset(0, squash * 42),
          child: Transform.scale(
            scaleX: 1 + squash * 0.7,
            scaleY: 1 - squash * 0.7,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.35, -0.45),
                  colors: [Color(0xFFAFD4AC), AppColors.sage, AppColors.sageDark],
                  stops: [0, 0.55, 1],
                ),
                border: Border.all(color: AppColors.surface, width: 3.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.sageDark.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              // Без поворота: повёрнутый крестик читается как плюс.
              child: Icon(
                t > 0.5 ? Icons.close_rounded : Icons.pets_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PetalButton extends StatelessWidget {
  const _PetalButton({
    required this.section,
    required this.locked,
    required this.onTap,
  });

  final AppSection section;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Нажимается весь кружок вместе с подписью, а не один кружок: подпись
    // лежит вплотную под ним и для пальца это одна цель.
    return Semantics(
      button: true,
      label: sectionTitle(context.l10n, section),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    section.icon,
                    size: 26,
                    color: locked
                        ? AppColors.textSecondary.withValues(alpha: 0.5)
                        : AppColors.textPrimary,
                  ),
                  if (locked)
                    const Positioned(
                      right: 6,
                      bottom: 4,
                      child: Icon(
                        Icons.lock,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                sectionTitle(context.l10n, section),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
