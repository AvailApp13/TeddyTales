import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass_panel.dart' show glassText;

/// Уведомление внутри приложения — сверху, из матового стекла.
///
/// Заказчик 10.10: строка «Куплено: Корзина со звездой» выезжала снизу
/// (SnackBar) и перекрывала лапу и полосу эмоций. Теперь плашка выезжает
/// сверху, под статус-баром (с учётом выреза и Dynamic Island), держится
/// около двух секунд и уезжает обратно вверх. Свайп вверх убирает её
/// раньше. Несколько уведомлений подряд не ложатся друг на друга, а идут
/// по очереди.
///
/// Стекло — то же, что у панели магазина: размытая комната сквозь
/// полупрозрачную заливку и тонкая светлая кромка.
void showTopToast(
  BuildContext context,
  String message, {
  IconData? icon,
  Duration duration = TopToasts.defaultDuration,
  String? actionLabel,
  VoidCallback? onAction,
}) => topToasts(context).show(
  message,
  icon: icon,
  duration: duration,
  actionLabel: actionLabel,
  onAction: onAction,
);

/// Очередь уведомлений приложения. Берётся заранее, до `await`, когда
/// после него экрана, с которого показывают, может уже не быть.
TopToasts topToasts(BuildContext context) =>
    TopToasts._(Overlay.maybeOf(context, rootOverlay: true));

class TopToasts {
  const TopToasts._(this._overlay);

  final OverlayState? _overlay;

  /// Сколько плашка держится на экране.
  static const Duration defaultDuration = Duration(seconds: 2);

  void show(
    String message, {
    IconData? icon,
    Duration duration = defaultDuration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = _overlay;
    if (overlay == null || !overlay.mounted) return;
    final queue = _queues[overlay] ??= _ToastQueue(overlay);
    queue.add(
      _ToastData(
        message: message,
        icon: icon,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}

/// Своя очередь у каждого Overlay: держится, пока жив он сам.
final Expando<_ToastQueue> _queues = Expando('top-toasts');

class _ToastData {
  const _ToastData({
    required this.message,
    required this.duration,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _ToastQueue {
  _ToastQueue(this.overlay);

  final OverlayState overlay;
  final Queue<_ToastData> _pending = Queue();
  OverlayEntry? _current;

  /// Ждут ли своей очереди другие: тогда текущая плашка уходит раньше.
  bool get busy => _pending.isNotEmpty;

  void add(_ToastData data) {
    // То же самое подряд не копим: второе «Куплено: …» в очереди — шум.
    final last = _pending.isNotEmpty ? _pending.last : null;
    if (last != null && last.message == data.message) return;
    _pending.add(data);
    if (_current == null) _next();
  }

  void _next() {
    if (_pending.isEmpty || !overlay.mounted) {
      _current = null;
      return;
    }
    final data = _pending.removeFirst();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        data: data,
        queue: this,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (identical(_current, entry)) _current = null;
          _next();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.data,
    required this.queue,
    required this.onDone,
  });

  final _ToastData data;
  final _ToastQueue queue;
  final VoidCallback onDone;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  /// Выезд сверху и уход обратно вверх.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 240),
  );

  /// Сколько плашка стоит. Таймер, а не анимация: пока плашка просто
  /// висит, кадры не нужны. Уходит вместе с плашкой ([dispose]).
  Timer? _hold;

  bool _leaving = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _slide.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_leaving) {
        // Ждут другие — эта уходит раньше, чтобы очередь не копилась.
        final hold = widget.queue.busy
            ? const Duration(milliseconds: 1200)
            : widget.data.duration;
        _hold = Timer(hold, _leave);
      } else if (status == AnimationStatus.dismissed && _leaving) {
        widget.onDone();
      }
    });
    _slide.forward();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _slide.dispose();
    super.dispose();
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _hold?.cancel();
    _slide.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final data = widget.data;

    return Positioned(
      left: 12,
      right: 12,
      top: top + 6,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, child) {
              final t = _leaving
                  ? Curves.easeInCubic.transform(_slide.value)
                  : Curves.easeOutCubic.transform(_slide.value);
              return Opacity(
                opacity: _slide.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -(1 - t) * 90 + _drag.clamp(-200, 0)),
                  child: child,
                ),
              );
            },
            // Свайп вверх — убрать раньше времени.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
              onVerticalDragEnd: (d) {
                final fling = (d.primaryVelocity ?? 0) < -200;
                if (fling || _drag < -16) {
                  _leave();
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: Semantics(
                liveRegion: true,
                child: _GlassToast(
                  message: data.message,
                  icon: data.icon,
                  actionLabel: data.actionLabel,
                  onAction: data.onAction == null
                      ? null
                      : () {
                          data.onAction!();
                          _leave();
                        },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сама плашка: матовое стекло, как у панели магазина.
class _GlassToast extends StatelessWidget {
  const _GlassToast({
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.72),
                    AppColors.surface.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: AppColors.sageDark),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      message,
                      style: glassText(14, 700, color: AppColors.textPrimary),
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.sageDark,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        actionLabel!,
                        style: glassText(13.5, 800, color: AppColors.sageDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
