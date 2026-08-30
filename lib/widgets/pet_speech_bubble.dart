import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Пузырь с репликой питомца и его инициативой (КП 3.4, 13.3).
///
/// Реплика держится, пока не сменится контекст: на макете это спокойная
/// подпись под мишкой, а не бегущая строка. Смена контекста — смена состояния
/// покоя или появление новой инициативы.
class PetSpeechBubble extends StatefulWidget {
  const PetSpeechBubble({
    super.key,
    required this.mood,
    required this.initiative,
    this.language = BearLanguage.ru,
    this.onTap,
  });

  final BearMood mood;
  final BearInitiative? initiative;
  final BearLanguage language;

  /// Тап по пузырю — согласиться на предложение питомца.
  final ValueChanged<BearAction>? onTap;

  @override
  State<PetSpeechBubble> createState() => _PetSpeechBubbleState();
}

class _PetSpeechBubbleState extends State<PetSpeechBubble> {
  BearPhraseContext? _context;
  BearPhrase? _phrase;

  @override
  void didUpdateWidget(PetSpeechBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final next = _resolveContext();
    if (next == _context && _phrase != null) return;

    _context = next;
    _phrase = BearPhrases.random(next);
  }

  BearPhraseContext _resolveContext() {
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

    // Прижат к левому краю: пузырь живёт в левом верхнем углу сцены,
    // зеркально кнопке «Что будем делать?» — по центру он утыкался в капюшон.
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          onTap: initiative == null || widget.onTap == null
              ? null
              : () => widget.onTap!(initiative.action),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, size: 16, color: AppColors.heart),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    phrase.text(widget.language),
                    style: theme.textTheme.bodyMedium,
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
