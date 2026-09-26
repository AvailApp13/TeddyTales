import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Окно из матового стекла поверх комнаты (заказчик 26.09): вместо листов,
/// выезжающих снизу, — компактная панель прямо в сцене. Комната видна
/// сквозь неё, размытая; кнопки и надписи — в стиле главного экрана:
/// округлый Nunito, тёмные капсулы, зелёная кнопка как лапа.
///
/// [center] — где центр панели, в долях экрана (по умолчанию — на
/// одеяле/столе, в нижней трети). Появляется с пружинкой, уходит
/// растворяясь.
Future<T?> showGlassPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Offset center = const Offset(0.5, 0.66),
  double width = 300,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x2E1E1410),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, _) {
      final size = MediaQuery.sizeOf(context);
      final w = width.clamp(0.0, size.width - 32);
      // Клавиатура поднимает панель над собой, а не прячет её.
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: CustomSingleChildLayout(
            delegate: _PanelLayout(center: center),
            child: SizedBox(
              width: w,
              child: GlassPanel(child: Builder(builder: builder)),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final pop = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: AnimatedBuilder(
          animation: pop,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 24 * (1 - pop.value)),
            child: Transform.scale(
              scale: 0.88 + 0.12 * pop.value,
              child: child,
            ),
          ),
          child: child,
        ),
      );
    },
  );
}

/// Ставит панель центром в [center] (доли экрана), но не даёт вылезти за
/// края.
class _PanelLayout extends SingleChildLayoutDelegate {
  _PanelLayout({required this.center});

  final Offset center;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    const margin = 12.0;
    final x = (size.width * center.dx - child.width / 2).clamp(
      margin,
      size.width - child.width - margin,
    );
    final y = (size.height * center.dy - child.height / 2).clamp(
      margin,
      size.height - child.height - margin,
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PanelLayout old) => old.center != center;
}

/// Сама стеклянная подложка.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  static const double radius = 28;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.28),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.42),
                    Colors.white.withValues(alpha: 0.22),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Шрифт сцены: округлый Nunito с весом по оси.
TextStyle glassText(double size, double weight, {Color color = Colors.white}) =>
    TextStyle(
      fontFamily: 'Nunito',
      fontSize: size,
      height: 1.2,
      fontVariations: [FontVariation('wght', weight)],
      color: color,
    );

/// Кнопка панели. Главная — зелёная, как лапа на главном экране; второстепенная
/// — тёмная капсула, как подписи комнат.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF86B886), AppColors.sageDark],
                    )
                  : null,
              color: primary
                  ? null
                  : AppColors.textPrimary.withValues(alpha: 0.78),
              border: primary
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                // Длинная подпись уменьшается, а не обрезается многоточием.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: glassText(15, primary ? 800 : 700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Крестик в углу стеклянного окна: белый кружок, как кнопки сцены.
class GlassCloseButton extends StatelessWidget {
  const GlassCloseButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonLabel,
      child: GestureDetector(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 20,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Заголовок стеклянного окна: крупно, округлым шрифтом, крестик справа.
class GlassTitle extends StatelessWidget {
  const GlassTitle(this.text, {super.key, this.leading, this.close = true});

  final String text;
  final Widget? leading;
  final bool close;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Text(
            text,
            style: glassText(19, 850, color: AppColors.textPrimary),
          ),
        ),
        if (close) const GlassCloseButton(),
      ],
    );
  }
}

/// Плитка внутри стекла: светлее самого стекла, мягкая кайма.
BoxDecoration glassTile({Color? color, Color? border, double radius = 16}) =>
    BoxDecoration(
      color: color ?? Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: border ?? Colors.white.withValues(alpha: 0.8),
        width: border == null ? 1 : 2,
      ),
    );

/// Поле ввода на стекле: светлая капсула, округлый шрифт.
InputDecoration glassField({String? hint, String? error, String? counter}) =>
    InputDecoration(
      hintText: hint,
      errorText: error,
      counterText: counter,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.72),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.sageDark, width: 2),
      ),
    );

// --- Экраны на фоне комнаты ---------------------------------------------------

/// Экран поверх комнаты (заказчик 26.09): профиль, рост, дневник,
/// настройки открываются не на кремовой странице, а на размытой комнате —
/// она остаётся сзади. Экран въезжает снизу, фон плавно размывается.
Route<T> glassRoute<T>(Widget screen) => PageRouteBuilder<T>(
  opaque: false,
  transitionDuration: const Duration(milliseconds: 340),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (context, _, _) => screen,
  transitionsBuilder: (context, animation, _, child) {
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: t,
            builder: (context, _) => BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 16 * t.value,
                sigmaY: 16 * t.value,
              ),
              child: ColoredBox(
                color: const Color(
                  0xFFFFF6E8,
                ).withValues(alpha: 0.38 * t.value),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: t,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(t),
            child: child,
          ),
        ),
      ],
    );
  },
);

/// Карточка экрана на фоне комнаты: светлое стекло с белой каймой.
BoxDecoration glassCard({double radius = 20}) => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.64),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
  boxShadow: [
    BoxShadow(
      color: AppColors.textPrimary.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ],
);

/// Шапка экрана: белая кнопка «назад», как кнопки сцены, и заголовок
/// округлым шрифтом.
class GlassScreenHeader extends StatelessWidget {
  const GlassScreenHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.outline, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  size: 26,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: glassText(24, 900, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок раздела — тёмная капсула, как подписи комнат.
class GlassSectionTitle extends StatelessWidget {
  const GlassSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text, style: glassText(12.5, 800)),
        ),
      ),
    );
  }
}

/// Блоки экрана появляются по очереди: каждый чуть позже предыдущего
/// выплывает снизу и проявляется.
class GlassStagger extends StatefulWidget {
  const GlassStagger({super.key, required this.children});

  final List<Widget> children;

  @override
  State<GlassStagger> createState() => _GlassStaggerState();
}

class _GlassStaggerState extends State<GlassStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _in.value = 1;
      } else {
        _in.forward();
      }
    });
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return AnimatedBuilder(
      animation: _in,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++) _staggered(i, n, widget.children[i]),
        ],
      ),
    );
  }

  Widget _staggered(int i, int n, Widget child) {
    // Первые — сразу, дальше с шагом; каждый выплывает за 40 % времени.
    final start = (i / (n + 2)).clamp(0.0, 0.6);
    final v = Curves.easeOutCubic.transform(
      ((_in.value - start) / 0.4).clamp(0.0, 1.0),
    );
    if (v >= 1) return child;
    return Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
    );
  }
}
