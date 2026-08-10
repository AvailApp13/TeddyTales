import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/shop_items.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Магазин предметов (КП 11.2).
///
/// Четыре вкладки — по четырём разделам каталога КП 10: одежда (10.5), мебель
/// (10.2), декор (10.3), игрушки (10.4). Обои и полы здесь не выделены в
/// отдельные вкладки, в отличие от экрана комнаты: покупателю они такой же
/// товар, как картина или подушка, а разное поведение у них начинается только
/// при расстановке.
///
/// Покупка идёт через корзину: тап по карточке кладёт предмет в корзину и
/// вынимает обратно, платят один раз кнопкой внизу. Купленное не нажимается —
/// повторно продавать то же самое некуда, а «уже моё» должно читаться сразу.
///
/// **ДОПУЩЕНИЕ:** самой корзины в КП нет — она пришла с макета и отнесена ко
/// второй версии. Собрана, потому что без неё непонятно, как выглядит покупка
/// набора вещей; об этом сказано подписью внизу экрана, чтобы заказчик видел
/// границу договорённостей. Разовая покупка мимо корзины живёт на экране
/// комнаты и опирается на тот же `GameState`.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.game});

  /// Кошелёк, инвентарь и корзина — один источник правды на все экраны:
  /// купленное здесь должно тут же появиться в комнате и в гардеробе.
  final GameState game;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  /// Первой открывается одежда — так же, как в прототипе: это самый крупный и
  /// самый понятный ребёнку раздел каталога.
  _ShopTab _tab = _ShopTab.clothes;

  void _checkout() {
    // Количество запоминаем до оплаты: `checkout` очищает корзину.
    final count = widget.game.cart.length;

    // Кнопка при нехватке монет и так не нажимается, но решение принимает
    // `checkout` — держать здесь вторую проверку цены значило бы завести второй
    // источник правды о стоимости (КП 10.9 цены ещё будут меняться).
    if (!widget.game.checkout()) {
      _toast('Не хватает монет');
      return;
    }

    _toast('Куплено предметов: $count');
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
      // Нижняя граница обрезается: кнопка покупки прижата к краю экрана и
      // должна расходиться с системным индикатором жестов.
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.game,
          builder: (context, _) {
            final game = widget.game;
            final items = _tab.items;
            final total = game.cartTotal;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(title: 'Магазин', coins: game.coins),
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
                                // Три колонки: в магазине важнее охватить
                                // взглядом весь раздел (16 вещей в одежде и
                                // декоре), чем разглядеть отдельную карточку.
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                // Фиксированная высота вместо пропорции: иначе
                                // на планшете карточка растёт вслед за шириной
                                // и превращается в пустое поле.
                                mainAxisExtent: 108,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];

                            return _ItemTile(
                              item: item,
                              owned: game.isOwned(item.id),
                              inCart: game.isInCart(item.id),
                              onTap: () => game.toggleCart(item.id),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Корзины нет в КП — она с макета, я её отношу ко '
                          'второй версии, но собрал, чтобы было видно '
                          'поведение. Цены — плейсхолдеры (КП 10.9).',
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
                _CartBar(
                  count: game.cart.length,
                  total: total,
                  // Пустая корзина и нехватка монет гасят кнопку одинаково: в
                  // обоих случаях платить нечем или не за что, и объяснять это
                  // ребёнку всплывающей подписью после тапа хуже, чем сразу
                  // показать неактивную кнопку.
                  enabled: game.cart.isNotEmpty && total <= game.coins,
                  onTap: _checkout,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Вкладки магазина (КП 11.2).
///
/// Порядок как в прототипе — от одежды к игрушкам; он же порядок разделов
/// каталога по востребованности, а не по номеру пункта КП.
enum _ShopTab {
  clothes('Одежда'),
  furniture('Мебель'),
  decor('Декор'),
  toys('Игрушки');

  const _ShopTab(this.title);

  final String title;

  /// Товары вкладки.
  ///
  /// Берём готовые списки каталога, а не выборку по [ItemKind]: в одежде и
  /// декоре по несколько видов предметов (комплекты и раздельные вещи, обои,
  /// полы и мелкий декор), и разбивка на разделы — свойство каталога КП 10,
  /// а не следствие вида предмета.
  List<ShopItem> get items => switch (this) {
    _ShopTab.clothes => ItemCatalog.clothes,
    _ShopTab.furniture => ItemCatalog.furniture,
    _ShopTab.decor => ItemCatalog.decor,
    _ShopTab.toys => ItemCatalog.toys,
  };
}

/// Ряд вкладок во всю ширину.
class _TabsRow extends StatelessWidget {
  const _TabsRow({required this.current, required this.onSelected});

  final _ShopTab current;
  final ValueChanged<_ShopTab> onSelected;

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
          for (final tab in _ShopTab.values) ...[
            Expanded(
              child: _TabButton(
                title: tab.title,
                selected: tab == current,
                onTap: () => onSelected(tab),
              ),
            ),
            if (tab != _ShopTab.values.last) const SizedBox(width: 6),
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

/// Карточка товара: значок, название и либо цена, либо «Куплено».
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.owned,
    required this.inCart,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final bool inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppDimens.radiusCard);

    return Opacity(
      // Купленное гасим, а не прячем: по КП 3.5 ребёнок должен видеть весь
      // каталог целиком, но уже своя вещь не должна перетягивать внимание с
      // того, что ещё можно купить.
      opacity: owned ? 0.45 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: owned ? null : onTap,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                // Отобранное в корзину обводим зелёным: значок «+» в углу
                // мелкий, а при трёх колонках набранное нужно находить
                // взглядом, не вчитываясь в каждую карточку.
                color: inCart ? AppColors.sage : AppColors.outline,
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
                          item.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (owned)
                          Text(
                            'Куплено',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
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
                if (owned || inCart)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _CornerBadge(icon: owned ? Icons.check : Icons.add),
                  ),
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

/// Значок в углу карточки: галочка у купленного, плюс у отобранного в корзину.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: const BoxDecoration(
        color: AppColors.sage,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 11, color: Colors.white),
    );
  }
}

/// Кнопка оплаты во всю ширину: сумма и счётчик набранного.
class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.count,
    required this.total,
    required this.enabled,
    required this.onTap,
  });

  final int count;
  final int total;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        10,
        AppDimens.pagePadding,
        14,
      ),
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          // Погашенная кнопка остаётся зелёной, просто бледной: серый
          // «выключенный» вид из темы Material читается как поломка, а не как
          // «ещё ничего не выбрано».
          disabledBackgroundColor: AppColors.sage.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
        ),
        child: count == 0
            ? const Text(
                'Корзина пуста',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Купить за $total',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CountBadge(count: count),
                ],
              ),
      ),
    );
  }
}

/// Счётчик предметов в корзине на кнопке оплаты.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, кошелёк справа.
///
/// Кошелёк на этом экране обязателен: здесь тратят монеты (КП 11.1), и остаток
/// должен быть перед глазами в тот момент, когда набирают корзину.
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
