import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Экран «Что будем делать?» — список действий ухода (КП 6.4).
///
/// Четыре пункта: покормить, купать, играть, уложить спать. Пятое действие
/// ухода, поглаживание, сюда сознательно не попало: по разделу 8.1 ТЗ
/// аниматора `trg_pet` — это «поглаживание (касание экрана)», то есть тап по
/// самому мишке на главной, а не пункт меню. Об этом сказано подписью внизу,
/// чтобы отсутствие пункта не выглядело недоделкой.
///
/// Действия, до которых мишка ещё не дорос, показываются заблокированными с
/// пояснением — КП 3.5 требует показывать закрытое, а не прятать. Условие
/// берётся из [BearActionAvailability.isAvailableOn], один источник правды с
/// панелью показателей на главной.
///
/// **ЗАГЛУШКА:** монеты за уход тут не начисляются, хотя КП 6.4 их обещает.
/// Кошелёк живёт в `GameState`, а этому экрану он не передаётся — начисление
/// подключается там же, где будет роутинг.
class CareScreen extends StatelessWidget {
  const CareScreen({
    super.key,
    required this.controller,
    required this.onOpenFeed,
  });

  /// Тот же контроллер, что и на главной: экран и запускает действия, и читает
  /// из него текущую стадию, чтобы блокировки обновились сразу после роста.
  final BearController controller;

  /// «Покормить» — единственный пункт, который не выполняет действие сразу:
  /// по КП 8 выбор блюда происходит на отдельном экране кормления, и он же
  /// вызовет `feedBear`. Здесь только переход.
  final VoidCallback onOpenFeed;

  /// Порядок и тексты — как в принятом прототипе, без переформулировок.
  ///
  /// Иконки материальные, а не эмодзи из прототипа: в прототипе эмодзи стояли
  /// вынужденно (HTML без ассетов), а в приложении те же четыре действия уже
  /// нарисованы иконками в `CareStatsPanel` — расхождение между экранами
  /// читалось бы как разные механики.
  static const List<_CareItem> _items = [
    _CareItem(
      action: BearAction.feed,
      icon: Icons.restaurant,
      color: AppColors.statFood,
      title: 'Покормить',
      subtitle: 'Вкусная еда для малыша',
    ),
    _CareItem(
      action: BearAction.wash,
      icon: Icons.bathtub_outlined,
      color: AppColors.statHygiene,
      title: 'Купать',
      subtitle: 'Пора в ванну!',
    ),
    _CareItem(
      action: BearAction.play,
      icon: Icons.sports_baseball_outlined,
      color: AppColors.statPlay,
      title: 'Играть',
      subtitle: 'Весёлые игры вместе',
    ),
    _CareItem(
      action: BearAction.sleep,
      icon: Icons.nightlight_round,
      color: AppColors.statSleep,
      title: 'Уложить спать',
      subtitle: 'Спокойной ночи, малыш',
    ),
  ];

  /// Выполняет действие и закрывает экран — как в прототипе: реакцию питомца
  /// (КП 6.4) видно на главной, задерживать пользователя в меню незачем.
  void _run(BuildContext context, BearAction action) {
    switch (action) {
      case BearAction.wash:
        controller.washBear();
      case BearAction.play:
        controller.playWithBear();
      case BearAction.sleep:
        controller.putToSleep();
      // Остальные значения перечисления на этом экране не встречаются:
      // «покормить» уходит в onOpenFeed, поглаживание — касание экрана,
      // а обучение и кастомизация живут в своих разделах.
      case BearAction.feed:
      case BearAction.pet:
      case BearAction.wake:
      case BearAction.learn:
      case BearAction.dressUp:
      case BearAction.decorate:
        return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final stage = controller.state.stage;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHeader(title: 'Что будем делать?'),
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
                        for (final item in _items) ...[
                          _CareTile(
                            item: item,
                            stage: stage,
                            onTap: item.action == BearAction.feed
                                ? onOpenFeed
                                : () => _run(context, item.action),
                          ),
                          if (item != _items.last) const SizedBox(height: 9),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Поглаживания в списке нет: по разделу 8.1 ТЗ это '
                          'касание экрана — тапните по мишке на главной.',
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

/// Пункт списка ухода.
class _CareItem {
  const _CareItem({
    required this.action,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final BearAction action;
  final IconData icon;
  final Color color;
  final String title;

  /// Показывается, только пока действие доступно: у закрытого пункта на его
  /// месте объяснение, с какой стадии он откроется.
  final String subtitle;
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Кошелька здесь нет намеренно — уход ничего не стоит, монеты за него, наоборот,
/// начисляются (КП 6.4). Пустое место справа шириной с кнопку оставлено, чтобы
/// заголовок стоял ровно по центру, а не съезжал влево.
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

/// Строка одного действия: иконка, название, пояснение.
class _CareTile extends StatelessWidget {
  const _CareTile({
    required this.item,
    required this.stage,
    required this.onTap,
  });

  final _CareItem item;
  final BearStage stage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = item.action.isAvailableOn(stage);

    // Номер стадии, а не название: так было в принятом прототипе, и он же
    // совпадает с номером на шкале роста (КП 5), где пользователь его и видит.
    final subtitle = available
        ? item.subtitle
        : 'Откроется на стадии ${item.action.minStage.riveValue}';

    return Opacity(
      opacity: available ? 1 : 0.45,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: InkWell(
          onTap: available ? onTap : null,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 26, color: item.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
