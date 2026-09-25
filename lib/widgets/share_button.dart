import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Кнопка «Поделиться» в шапке (заказчик 25.09): стрелка, которая раз в
/// три секунды плавно превращается в подарочек — он шевелится и снова
/// становится стрелкой. Открывает окно «поделиться мишкой + код друга».
class ShareButton extends StatefulWidget {
  const ShareButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton>
    with SingleTickerProviderStateMixin {
  // Цикл: 3 с стрелка → 0,3 с переход → 1,4 с подарок шевелится →
  // 0,3 с обратно.
  static const _arrow = 3000;
  static const _fade = 300;
  static const _wiggle = 1400;
  static const _period = _arrow + _fade + _wiggle + _fade;

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _period),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.shareAction,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.outline, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('header-share'),
          onTap: widget.onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final ms = _loop.value * _period;
                // 0 — стрелка, 1 — подарок.
                final gift = ms < _arrow
                    ? 0.0
                    : ms < _arrow + _fade
                    ? (ms - _arrow) / _fade
                    : ms < _arrow + _fade + _wiggle
                    ? 1.0
                    : 1 - (ms - _arrow - _fade - _wiggle) / _fade;
                final w = ((ms - _arrow - _fade) / _wiggle).clamp(0.0, 1.0);
                // Шевеление: покачивается и подпрыгивает, затухая.
                final angle = math.sin(w * math.pi * 6) * 0.28 * (1 - w * 0.6);
                final hop = -math.sin(w * math.pi * 3).abs() * 3 * (1 - w);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 1 - gift,
                      child: Transform.scale(
                        scale: 1 - 0.4 * gift,
                        child: const Icon(
                          Icons.ios_share_rounded,
                          size: 19,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: gift,
                      child: Transform.translate(
                        offset: Offset(0, hop),
                        child: Transform.rotate(
                          angle: angle,
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * gift,
                            child: const Icon(
                              Icons.card_giftcard_rounded,
                              size: 21,
                              color: Color(0xFFD42A33),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
