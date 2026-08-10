import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../game/game_calendar.dart';
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
/// **ДОПУЩЕНИЕ:** тексты только на русском, хотя КП 16.1 требует три языка.
/// Строк дневника нет ни в КП, ни в словаре реплик ([BearPhrases]), переводить
/// нечего — вернёмся к этому, когда дневник утвердят как механику.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  /// Порядок, названия и даты — как в принятом прототипе, слово в слово.
  ///
  /// Возраст хранится числами, а не строкой «2 месяца 5 дней»: склонение
  /// считает [GameAge], тот же код, что и в шапке главного экрана. Иначе
  /// дневник и шапка разойдутся в формулировках при первой же правке правил.
  static const List<_DiaryEvent> _events = [
    _DiaryEvent(title: 'Первое купание', months: 2, days: 5),
    _DiaryEvent(title: 'Научился ползать', months: 2, days: 20),
    _DiaryEvent(title: 'Первый зубик', months: 3, days: 2),
    _DiaryEvent(title: 'Любимая игрушка', months: 3, days: 10),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(title: 'Дневник'),
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
                      'Дневника нет в КП — он с макета. Отнесён ко второй '
                      'версии, собран как заготовка. Фотоальбом и «Поделиться» '
                      'потребуют камеры и прав на съёмку. Миниатюра события — '
                      'заглушка: настоящие снимки появятся вместе с '
                      'фотоальбомом.',
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

/// Одно событие дневника.
class _DiaryEvent {
  const _DiaryEvent({
    required this.title,
    required this.months,
    required this.days,
  });

  final String title;

  /// Игровой возраст питомца на момент события (КП 5, игровой календарь).
  final int months;
  final int days;

  GameAge get age => GameAge(months: months, days: days);
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
                  event.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.age.format(BearLanguage.ru),
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
