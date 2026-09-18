import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Экран «Моя комната» — редактор обстановки (КП 10.7).
///
/// Четыре вкладки соответствуют четырём наборам предметов комнаты: мебель
/// (КП 10.2), декор, обои и полы (КП 10.3). Игрушки и одежда сюда не попадают:
/// игрушки берутся в руки на главной, одежда живёт в гардеробе (КП 10.6) —
/// смешивать их с обстановкой значило бы дать один и тот же предмет в двух
/// местах с разным поведением.
///
/// Купленное и поставленное — это два разных состояния, и в прототипе это
/// сознательно один и тот же тап: пока предмет не куплен, тап покупает его
/// (цена видна прямо на карточке), после покупки тот же тап ставит его в
/// комнату или убирает. Отдельной кнопки «поставить» нет — по КП 10.8 часть
/// предметов даётся бесплатно, и для ребёнка разница между «моё» и «стоит в
/// комнате» должна читаться без второго уровня управления.
///
/// **ЗАГЛУШКА:** сетки мест и предпросмотра комнаты здесь нет — предмет просто
/// помечается поставленным. Об этом сказано подписью внизу экрана, чтобы
/// незаконченность была видна заказчику, а не выглядела багом.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.game});

  /// Кошелёк, инвентарь и обстановка — всё в одном источнике правды.
  /// Экран ничего не хранит у себя, кроме выбранной вкладки: покупка на этом
  /// экране должна тут же отражаться в магазине и наоборот.
  final GameState game;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  _RoomTab _tab = _RoomTab.furniture;

  /// Тап по карточке: не куплено — покупаем, куплено — ставим или убираем.
  void _onTap(ShopItem item) {
    final game = widget.game;
    final l10n = context.l10n;
    final name = shopItemName(l10n, item.id);

    if (!game.isOwned(item.id)) {
      // Карточка недоступных по деньгам предметов и так не нажимается, но
      // проверку возвращает сам `buy` — дублировать условие с ценой здесь
      // значило бы завести второй источник правды о стоимости (КП 10.9 цены
      // ещё будут меняться).
      if (!game.buy(item.id)) {
        _toast(l10n.roomNotEnoughCoins);
        return;
      }
      _toast(l10n.roomItemBought(name));
      return;
    }

    game.togglePlaced(item.id);

    // ДОПУЩЕНИЕ: результат читаем после вызова, а не переворачиваем флаг сами.
    // Обои и пол по правилу из `GameState` единственные в своём роде: повторный
    // тап по уже выбранным обоям их не снимает, комната не может остаться без
    // стен. Прототип этого не различал и сказал бы «убрано» — подпись была бы
    // неправдой.
    _toast(
      game.isPlaced(item.id)
          ? l10n.roomItemPlaced(name)
          : l10n.roomItemRemoved(name),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: widget.game,
          builder: (context, _) {
            final items = ItemCatalog.ofKind(_tab.kind);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(
                  title: context.l10n.roomTitle,
                  coins: widget.game.coins,
                ),
                _TabsRow(
                  current: _tab,
                  onSelected: (tab) => setState(() => _tab = tab),
                ),
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
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                // Две колонки, а не три как в магазине: у
                                // обстановки длинные названия («Книжная
                                // полка», «Пол ковролин»), в узкой карточке они
                                // рвутся на три строки.
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                // Фиксированная высота вместо пропорции: иначе
                                // на планшете карточка растёт вслед за шириной
                                // и превращается в пустое поле.
                                mainAxisExtent: 104,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final owned = widget.game.isOwned(item.id);

                            return _ItemTile(
                              item: item,
                              owned: owned,
                              placed: widget.game.isPlaced(item.id),
                              // Некупленное и неподъёмное по цене показываем
                              // приглушённым, но не прячем: КП 3.5 требует
                              // показывать закрытое, чтобы было к чему копить.
                              enabled: owned || widget.game.coins >= item.price,
                              onTap: () => _onTap(item),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.roomFooterNote,
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

/// Вкладки экрана комнаты.
///
/// Обои и пол вынесены из декора в отдельные вкладки, хотя в каталоге КП 10.3
/// это один раздел: они ведут себя иначе — не добавляются к обстановке, а
/// заменяют предыдущие, и мешать их с картинами и подушками в одном списке
/// сбивает.
enum _RoomTab {
  furniture(ItemKind.furniture),
  decor(ItemKind.decor),
  walls(ItemKind.wallpaper),
  floor(ItemKind.floor);

  const _RoomTab(this.kind);

  final ItemKind kind;
}

/// Ряд вкладок во всю ширину.
class _TabsRow extends StatelessWidget {
  const _TabsRow({required this.current, required this.onSelected});

  final _RoomTab current;
  final ValueChanged<_RoomTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        0,
        AppDimens.pagePadding,
        10,
      ),
      child: Row(
        children: [
          for (final tab in _RoomTab.values) ...[
            Expanded(
              child: _TabButton(
                // Вкладки комнаты один в один совпадают с разделами каталога —
                // названия берём оттуда же, а не заводим отдельные ключи.
                title: shopCategoryTitle(context.l10n, tab.kind),
                selected: tab == current,
                onTap: () => onSelected(tab),
              ),
            ),
            if (tab != _RoomTab.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.radiusChip);

    return Material(
      color: selected ? AppColors.sage : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.sage : AppColors.outline,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка предмета: значок, название и либо цена, либо состояние.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.owned,
    required this.placed,
    required this.enabled,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final bool placed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppDimens.radiusCard);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                // Поставленное обводим зелёным: галочка в углу мелкая, а
                // выбранные обои и пол нужно находить взглядом сразу.
                color: placed ? AppColors.sage : AppColors.outline,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ЗАГЛУШКА: эмодзи вместо иллюстрации предмета.
                        // Отрисовка 52 предметов — отдельная работа по КП 10,
                        // эмодзи стоят из прототипа, чтобы карточки были
                        // различимы.
                        Text(
                          item.emoji,
                          style: const TextStyle(fontSize: 26, height: 1.1),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          shopItemName(context.l10n, item.id),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (owned)
                          Text(
                            placed
                                ? context.l10n.roomSelectedLabel
                                : context.l10n.roomOwnedLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: AppColors.sageDark,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          _Price(price: item.price),
                      ],
                    ),
                  ),
                ),
                if (placed)
                  const Positioned(top: 5, right: 5, child: _PlacedBadge()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Цена предмета: монета и число.
///
/// ЗАГЛУШКА: сами значения по КП 10.9 утверждаются отдельно и по 15.4 правятся
/// из панели управления — здесь они просто показываются.
class _Price extends StatelessWidget {
  const _Price({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: const BoxDecoration(
            color: AppColors.coin,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$price',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Галочка в углу карточки поставленного предмета.
class _PlacedBadge extends StatelessWidget {
  const _PlacedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: const BoxDecoration(
        color: AppColors.sage,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 11, color: Colors.white),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, кошелёк справа.
///
/// Кошелёк здесь нужен, в отличие от экрана ухода: на этом экране тратят
/// монеты (КП 11.1), и остаток должен быть перед глазами в момент покупки.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.coins});

  final String title;
  final int coins;

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
          const SizedBox(width: 10),
          _Purse(coins: coins),
        ],
      ),
    );
  }
}

/// Остаток монет в шапке.
class _Purse extends StatelessWidget {
  const _Purse({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$coins',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
