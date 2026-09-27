import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Пузырь с репликой питомца и его инициативой (КП 3.4, 13.3).
///
/// Реплика держится, пока не сменится контекст: смена состояния покоя или
/// появление новой инициативы. Заказчик 27.09: пузырь над головой мишки,
/// с хвостиком к макушке, появляется красиво — всплывает и печатается по
/// буквам, как будто мишка говорит.
class PetSpeechBubble extends StatefulWidget {
  const PetSpeechBubble({
    super.key,
    required this.mood,
    required this.initiative,
    this.forgotten = false,
    this.language = BearLanguage.ru,
    this.onTap,
  });

  final BearMood mood;
  final BearInitiative? initiative;

  /// Нужда ниже 15 — реплика «Ты про меня забыл?» (`BearLife.forgotten`).
  final bool forgotten;
  final BearLanguage language;

  /// Тап по пузырю — согласиться на предложение питомца.
  final ValueChanged<BearAction>? onTap;

  @override
  State<PetSpeechBubble> createState() => _PetSpeechBubbleState();
}

class _PetSpeechBubbleState extends State<PetSpeechBubble>
    with SingleTickerProviderStateMixin {
  BearPhraseContext? _context;
  BearPhrase? _phrase;

  /// Печать: 0 — пузырь ещё не всплыл, 1 — реплика набрана целиком.
  late final AnimationController _type = AnimationController(vsync: this);

  /// Всплытие пузыря занимает первые [_rise] от анимации, дальше буквы.
  static const double _rise = 0.18;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(PetSpeechBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void dispose() {
    _type.dispose();
    super.dispose();
  }

  void _refresh() {
    final next = _resolveContext();
    if (next == _context && _phrase != null) return;
    _context = next;
    _phrase = BearPhrases.random(next);
    final chars = _phrase!.text(widget.language).length;
    // всплытие ~0,25 с, потом ~45 мс на букву
    _type
      ..duration = Duration(milliseconds: 250 + 45 * chars)
      ..forward(from: 0);
  }

  BearPhraseContext _resolveContext() {
    if (widget.forgotten) return BearPhraseContext.forgotten;
    final initiative = widget.initiative;
    if (initiative != null) {
      return switch (initiative.action) {
        BearAction.play => BearPhraseContext.invitePlay,
        BearAction.learn => BearPhraseContext.inviteLearn,
        BearAction.feed => BearPhraseContext.hungry,
        BearAction.sleep => BearPhraseContext.sleepy,
        BearAction.wash => BearPhraseContext.dirty,
        BearAction.pet => BearPhraseContext.sad,
        _ => BearPhrases.contextForMood(widget.mood),
      };
    }
    return BearPhrases.contextForMood(widget.mood);
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrase;
    if (phrase == null) return const SizedBox.shrink();

    final initiative = widget.initiative;
    final theme = Theme.of(context);
    final text = phrase.text(widget.language);

    return AnimatedBuilder(
      animation: _type,
      builder: (context, _) {
        final v = _type.value;
        final rise = Curves.easeOutBack.transform((v / _rise).clamp(0.0, 1.0));
        final typed = ((v - _rise) / (1 - _rise)).clamp(0.0, 1.0);
        final shown = (text.length * typed).round();
        final typing = shown < text.length;
        return Opacity(
          opacity: (v / (_rise * 0.6)).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + 0.3 * rise,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                    onTap: initiative == null || widget.onTap == null
                        ? null
                        : () => widget.onTap!(initiative.action),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusPill,
                        ),
                        border: Border.all(color: AppColors.outline),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite,
                            size: 13,
                            color: AppColors.heart,
                          ),
                          const SizedBox(width: 6),
                          // Ширина — по полной реплике, чтобы пузырь не рос
                          // вместе с буквами; напечатанное — поверх.
                          Flexible(
                            child: Stack(
                              children: [
                                Opacity(
                                  opacity: 0,
                                  child: Text(
                                    text,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Text(
                                  text.substring(0, shown) +
                                      (typing ? '▏' : ''),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Хвостик к макушке.
                CustomPaint(
                  size: const Size(14, 8),
                  painter: const _TailPainter(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -1)
      ..lineTo(size.width, -1)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.surface);
    canvas.drawPath(
      Path()
        ..moveTo(0, -1)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, -1),
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => false;
}
