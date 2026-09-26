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
      return SafeArea(
        child: CustomSingleChildLayout(
          delegate: _PanelLayout(center: center),
          child: SizedBox(
            width: w,
            child: GlassPanel(child: Builder(builder: builder)),
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
TextStyle sceneText(double size, double weight, {Color color = Colors.white}) =>
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sceneText(15, primary ? 800 : 700),
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
