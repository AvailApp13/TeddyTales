import 'package:flutter/material.dart';

import '../game/game_calendar.dart';
import '../l10n/l10n.dart';
import '../l10n/sections_l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Экран «Дневник» — четыре события из жизни питомца.
///
/// **Дневника в КП нет.** Он пришёл с макета: там у него три вкладки —
/// «События», «Фотоальбом» и «Поделиться». Ближайшее, что есть в КП, — это
/// 14.1, история переходов между стадиями в профиле, то есть совсем другой
/// объём работы. Расхождение разобрано в `docs/design-review.md`, пункт 4
/// («Механики, которых нет в КП»); экран отнесён ко второй версии и собран как
/// заготовка — ровно та же роль, что и в принятом прототипе.
///
/// Поэтому здесь только лента событий. Фотоальбома и «Поделиться» нет
/// сознательно: и то и другое упирается в камеру и разрешения на съёмку, а
/// значит в отдельную работу с правами, хранением снимков и модерацией — в КП
/// это не заложено. Причина вынесена подписью внизу экрана, чтобы отсутствие
/// вкладок не выглядело недоделкой.
///
/// **ЗАГЛУШКА:** события зашиты списком, как в прототипе. Настоящий дневник
/// пишется по ходу игры (первое купание — это факт из истории ухода, первый
/// зубик — из стадий роста), то есть события должны приезжать с сервера вместе
/// с историей КП 14.1. Пока такого источника нет, показываем демонстрационную
/// ленту.
///
/// Тексты демонстрационных событий локализованы на три языка (КП 16.1) через
/// общий словарь `lib/l10n`; когда дневник утвердят как механику и события
/// поедут с сервера, ключи станут типами событий.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  /// Порядок, названия и даты — как в принятом прототипе, слово в слово.
  ///
  /// Возраст хранится числами, а не строкой «2 месяца 5 дней»: склонение
  /// считает [GameAge], тот же код, что и в шапке главного экрана. Иначе
  /// дневник и шапка разойдутся в формулировках при первой же правке правил.
  static const List<_DiaryEvent> _events = [
    _DiaryEvent(kind: _DiaryEventKind.firstBath, months: 2, days: 5),
    _DiaryEvent(kind: _DiaryEventKind.firstCrawl, months: 2, days: 20),
    _DiaryEvent(kind: _DiaryEventKind.firstTooth, months: 3, days: 2),
    _DiaryEvent(kind: _DiaryEventKind.favoriteToy, months: 3, days: 10),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(title: context.l10n.diaryTitle),
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
                    for (final event in _events) ...[
                      _DiaryRow(event: event),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.diaryFootnote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Какое именно событие показано в строке: по нему выбирается локализованное
/// название. В настоящем дневнике тип события приедет с сервера вместе с датой.
enum _DiaryEventKind { firstBath, firstCrawl, firstTooth, favoriteToy }

/// Одно событие дневника.
class _DiaryEvent {
  const _DiaryEvent({
    required this.kind,
    required this.months,
    required this.days,
  });

  final _DiaryEventKind kind;

  /// Игровой возраст питомца на момент события (КП 5, игровой календарь).
  final int months;
  final int days;

  GameAge get age => GameAge(months: months, days: days);

  String titleOf(AppLocalizations l10n) => switch (kind) {
    _DiaryEventKind.firstBath => l10n.diaryEventFirstBath,
    _DiaryEventKind.firstCrawl => l10n.diaryEventFirstCrawl,
    _DiaryEventKind.firstTooth => l10n.diaryEventFirstTooth,
    _DiaryEventKind.favoriteToy => l10n.diaryEventFavoriteToy,
  };
}

/// Строка события: миниатюра, название, игровой возраст.
class _DiaryRow extends StatelessWidget {
  const _DiaryRow({required this.event});

  final _DiaryEvent event;


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          // ЗАГЛУШКА: рамка с иконкой вместо снимка. В прототипе тут стояла
          // одна и та же картинка мишки на все четыре события — как честная
          // затычка она хуже: выглядит настоящим фото и обещает то, чего нет.
          // Пустая рамка сразу читается как «снимка ещё нет».
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppDimens.radiusChip),
              border: Border.all(color: AppColors.outline),
            ),
            child: const Icon(
              Icons.photo_outlined,
              size: 20,
              color: AppColors.tan,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.titleOf(context.l10n),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // Возраст — теми же ICU-плюралами, что и шапка главного экрана.
                  formatAge(context.l10n, event.age),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Кошелька здесь нет намеренно — как и в прототипе: дневник ничего не
/// продаёт, монеты на нём не тратятся и не начисляются.
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
