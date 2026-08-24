import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Экран «Рост и развитие» — пять стадий взросления (КП 5).
///
/// Список показывает всю дорогу целиком, а не только текущий шаг: КП 3.5
/// требует показывать закрытое, а не прятать, и по стадиям это особенно важно —
/// пользователю обещают вырастить питомца за две недели, значит он должен
/// видеть, сколько ещё впереди.
///
/// Названия и длительности взяты из таблицы КП 5 и совпадают с [BearStage],
/// то есть с входом `stage` рига (раздел 6 ТЗ аниматора). На макете и то и
/// другое другое — расхождение разобрано в `docs/design-review.md`, пункт 2, и
/// вынесено подписью внизу экрана, чтобы оно не потерялось.
///
/// **ЗАГЛУШКА:** кнопка «Повзрослеть» переводит стадию вручную. По КП 5.6 и 5.7
/// момент взросления считает сервер (скорость зависит от общего ухода,
/// длительности настраиваются с панели), и клиент только принимает событие.
/// Пока сервера нет, кнопка заменяет его — как и в принятом прототипе.
class GrowthScreen extends StatelessWidget {
  const GrowthScreen({super.key, required this.controller});

  /// Тот же контроллер, что и на главной: экран читает из него текущую стадию
  /// и через него же взрослеет, чтобы риг получил `trg_stage_up` до смены
  /// значения `stage` (раздел 8.2 ТЗ аниматора).
  final BearController controller;

  /// Длительности из таблицы КП 5, строка в строку с прототипом.
  ///
  /// Хранятся здесь, а не в [BearStage]: это цифры коммерческого предложения,
  /// они настраиваются с сервера (КП 5.6), а перечисление описывает контракт с
  /// ригом и меняться от настроек не должно.
  static String _durationOf(AppLocalizations l10n, BearStage stage) =>
      switch (stage) {
        BearStage.newborn => l10n.growthDurationNewborn,
        BearStage.crawling => l10n.growthDurationCrawling,
        BearStage.firstSteps => l10n.growthDurationFirstSteps,
        BearStage.growing => l10n.growthDurationGrowing,
        BearStage.adult => l10n.growthDurationAdult,
      };

  /// ЗАГЛУШКА: эмодзи вместо кадра мишки на этой стадии.
  ///
  /// В готовом экране здесь стоит рендер персонажа соответствующего возраста —
  /// те же позы, что в риге (`idle_newborn`, `crawl`, `walk_unsure`). Ассетов
  /// нет, поэтому эмодзи из прототипа: пустые квадраты читались бы хуже.
  static String _emojiOf(BearStage stage) => switch (stage) {
    BearStage.newborn => '🐣',
    BearStage.crawling => '🐻',
    BearStage.firstSteps => '🚶',
    BearStage.growing => '🧸',
    BearStage.adult => '🎓',
  };

  void _growUp(BuildContext context) {
    // growUp сам возвращает false для взрослого — кнопка в этом состоянии уже
    // погашена, но проверку не убираем: она дешевле, чем ложный тост.
    if (!controller.growUp()) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.growthNewStage(controller.state.stage.title),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final l10n = context.l10n;
            final stage = controller.state.stage;
            final isAdult = stage == BearStage.adult;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(title: l10n.growthTitle),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pagePadding,
                      0,
                      AppDimens.pagePadding,
                      AppDimens.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in BearStage.values) ...[
                          _StageRow(stage: item, current: stage),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 2),
                        FilledButton(
                          // Взрослому расти некуда: кнопка гаснет, но остаётся
                          // на месте и объясняет, почему не работает.
                          onPressed: isAdult ? null : () => _growUp(context),
                          style: FilledButton.styleFrom(
                            // Погашенная кнопка остаётся зелёной, просто
                            // бледной: серый «выключенный» вид из темы Material
                            // читается как поломка, а не как «уже вырос».
                            disabledBackgroundColor: AppColors.sage.withValues(
                              alpha: 0.45,
                            ),
                            disabledForegroundColor: Colors.white.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          child: Text(
                            // В прототипе к надписи было приписано имя триггера
                            // «(trg_stage_up)» — это отладочная пометка для
                            // сверки с ТЗ аниматора, пользователю она не нужна.
                            isAdult
                                ? l10n.growthAlreadyAdult
                                : l10n.growthGrowUp,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.growthFootnote,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Строка одной стадии: картинка, название с длительностью, отметка справа.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.current});

  final BearStage stage;

  /// Текущая стадия питомца — по ней считаются и подсветка, и отметки.
  final BearStage current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Сравниваем по riveValue, а не по индексу в values: номер стадии — это то
    // же число, которое уходит в риг и которое пользователь видит в подписях
    // вроде «Откроется на стадии 3».
    final isNow = stage == current;
    final isPassed = stage.riveValue < current.riveValue;

    final mark = isPassed
        ? l10n.growthMarkPassed
        : isNow
        ? l10n.growthMarkNow
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // Текущая стадия — единственная заливка на экране: список длинный, и
        // взгляд должен находить «где я» без чтения.
        color: isNow ? AppColors.sageSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: isNow ? AppColors.sage : AppColors.outline),
      ),
      child: Row(
        children: [
          Text(
            GrowthScreen._emojiOf(stage),
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stage.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  GrowthScreen._durationOf(l10n, stage),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (mark.isNotEmpty)
            Text(
              mark,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.sageDark,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Кошелька здесь нет намеренно — как и в прототипе: на этом экране ничего не
/// покупается, взросление монет не стоит.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        8,
        AppDimens.pagePadding,
        10,
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.outline),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          // Ширина кнопки «назад» плюс тот же зазор — заголовок остаётся ровно
          // по центру экрана.
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}
