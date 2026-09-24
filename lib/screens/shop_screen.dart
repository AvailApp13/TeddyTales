import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/item_groups.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/item_picture.dart';
import '../widgets/item_preview.dart';
import '../widgets/scene_label.dart';

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
  const ShopScreen({super.key, required this.game, this.focusItemId});

  /// Кошелёк, инвентарь и корзина — один источник правды на все экраны:
  /// купленное здесь должно тут же появиться в комнате и в гардеробе.
  final GameState game;

  /// Открыть магазин на вкладке этого предмета.
  ///
  /// Нужен для подсказок в комнате: человек тапнул по пустому месту под
  /// кроватку и должен увидеть кроватку, а не одежду. Высыпать его в
  /// магазин «куда-то» — значит заставить искать то, на что он уже показал.
  final String? focusItemId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  /// Первой открывается одежда — так же, как в прототипе: это самый крупный и
  /// самый понятный ребёнку раздел каталога. Если пришли за конкретной
  /// вещью, открывается её вкладка.
  late _ShopTab _tab = _tabOf(widget.focusItemId) ?? _ShopTab.furniture;

  /// Выбранная подкатегория внутри вкладки. `null` — показываем всё.
  ///
  /// Заказчик 21.09: «открываешь декор, а ниже подкатегория „ковёр“».
  /// Вкладок четыре на весь каталог, и внутри декора вперемешку лежат ковры,
  /// картины, растения и подушки — найти в этой куче нужное можно только
  /// перебором.
  ItemGroup? _group;

  void _openTab(_ShopTab tab) => setState(() {
    _tab = tab;
    // Подкатегории у каждой вкладки свои: остаться с «Коврами» на мебели
    // значило бы показать пустую витрину.
    _group = null;
  });

  /// Вкладка, на которой лежит предмет. `null` — предмета нет или он не
  /// продаётся в магазине.
  static _ShopTab? _tabOf(String? itemId) {
    if (itemId == null) return null;
    for (final tab in _ShopTab.values) {
      if (tab.items.any((item) => item.id == itemId)) return tab;
    }
    return null;
  }

  void _checkout() {
    // Количество запоминаем до оплаты: `checkout` очищает корзину.
    final count = widget.game.cart.length;

    // Кнопка при нехватке монет и так не нажимается, но решение принимает
    // `checkout` — держать здесь вторую проверку цены значило бы завести второй
    // источник правды о стоимости (КП 10.9 цены ещё будут меняться).
    if (!widget.game.checkout()) {
      _toast(context.l10n.shopNotEnoughCoins);
      return;
    }

    _toast(context.l10n.shopCheckoutDone(count));
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
      // Лист магазина не плоское полотно: кремовый уходит вниз в тёплый
      // песочный, как потолок комнаты к полу. Плоская заливка рядом с
      // фотографическими комнатами и читалась как чужая страница.
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surface,
              AppColors.background,
              Color(0xFFF3E7D2),
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            // Мишку слушаем ради стадии: от неё зависит порядок витрины, и
            // переход может случиться прямо на этом экране.
            animation: Listenable.merge([widget.game, widget.game.bear]),
            builder: (context, _) {
              final game = widget.game;
              final stage = game.bear.state.stage;
              final total = game.cartTotal;

              // Витрина делится надвое: сначала то, что малышу нужно сейчас,
              // ниже — то, что пригодится потом. Замков здесь нет и быть не
              // должно (КП 11.2 не знает никаких ограничений на покупку) —
              // купить можно всё, но человеку с новорождённым первым должен
              // попадаться ночник, а не письменный стол.
              // Внутри каждой группы вперёд идут вещи со своей картинкой.
              // Позиции, на которые картинок ещё не прислали, показываются
              // значком, и вперемешку с фотографиями это читается как брак —
              // а собранные внизу они выглядят просто как «ещё не завезли».
              // Подкатегории вкладки — в том порядке, в каком они объявлены в
              // каталоге: сначала крупное, потом мелочь.
              final groups = _tab.groups;
              final shown = [
                for (final i in _tab.items)
                  if (_group == null || i.group == _group) i,
              ];
              final now = [
                for (final i in shown)
                  if (i.suitsAt(stage)) i,
              ];
              final later = [
                for (final i in shown)
                  if (!i.suitsAt(stage)) i,
              ];
              // Порядок показа раздела целиком: по нему листают в просмотре.
              final showcase = [...now, ...later];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SheetHeader(
                    title: context.l10n.shopTitle,
                    coins: game.coins,
                  ),
                  _TabsRow(current: _tab, onSelected: _openTab),
                  // Второй ряд — подкатегории этой вкладки. Один род вещей
                  // делить не на что, поэтому ряд появляется от двух.
                  if (groups.length > 1)
                    _GroupsRow(
                      groups: groups,
                      current: _group,
                      onSelected: (group) => setState(() => _group = group),
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
                          // Заголовки появляются только когда есть что
                          // разделять: на взрослой стадии подходит всё, и
                          // подпись «малышу сейчас» над единственной сеткой
                          // читалась бы как насмешка.
                          if (later.isNotEmpty && now.isNotEmpty) ...[
                            _GroupTitle(context.l10n.shopGroupNow),
                            _ItemGrid(
                              items: now,
                              showcase: showcase,
                              game: game,
                            ),
                            _GroupTitle(context.l10n.shopGroupLater),
                            _ItemGrid(
                              items: later,
                              showcase: showcase,
                              game: game,
                            ),
                          ] else
                            _ItemGrid(
                              items: now.isEmpty ? later : now,
                              showcase: showcase,
                              game: game,
                            ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.shopCartDisclaimer,
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
      ),
    );
  }
}

/// Подпись над группой витрины: капслок, разрядка, приглушённый цвет — как
/// подзаголовки разделов в профиле и настройках.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Сетка карточек товара.
class _ItemGrid extends StatelessWidget {
  const _ItemGrid({
    required this.items,
    required this.showcase,
    required this.game,
  });

  /// Что показывает эта сетка: «подходит сейчас» или «пригодится потом».
  final List<ShopItem> items;

  /// Весь раздел целиком, в порядке показа. Нужен просмотру: из него
  /// листают дальше по разделу, а не по одной группе.
  final List<ShopItem> showcase;

  final GameState game;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        // Две колонки вместо трёх: с 20.09 у товаров есть свои картинки, и
        // вещь должна быть видна, а не угадываться. Раздел теперь листают,
        // зато сразу понятно, что покупаешь.
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Фиксированная высота вместо пропорции: иначе на планшете карточка
        // растёт вслед за шириной и превращается в пустое поле.
        mainAxisExtent: 196,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return _ItemTile(
          item: item,
          owned: game.isOwned(item.id),
          inCart: game.isInCart(item.id),
          onTap: () => game.toggleCart(item.id),
          onZoom: () => showItemPreview(
            context: context,
            items: showcase,
            index: showcase.indexOf(item),
            game: game,
          ),
        );
      },
    );
  }
}

/// Вкладки магазина (КП 11.2).
///
/// Порядок как в прототипе — от одежды к игрушкам; он же порядок разделов
/// каталога по востребованности, а не по номеру пункта КП.
enum _ShopTab {
  // Порядок вкладок = порядок на экране. Мебель впереди, потому что с
  // 20.09 у неё, декора и игрушек есть настоящие картинки, а у одежды пока
  // только значки: открывать магазин со вкладки без картинок значит
  // показывать товар лицом в самый последний момент.
  furniture,
  decor,
  toys,
  clothes;

  /// Название вкладки.
  ///
  /// «Одежда» — своя строка, а не название раздела каталога: в каталоге такой
  /// категории нет (там наряды, верх, низ и т.д.), это вкладка магазина.
  String title(AppLocalizations l10n) => switch (this) {
    _ShopTab.clothes => l10n.shopTabClothes,
    _ShopTab.furniture => l10n.shopTabFurniture,
    _ShopTab.decor => l10n.shopTabDecor,
    _ShopTab.toys => l10n.shopTabToys,
  };

  /// Товары вкладки.
  ///
  /// Берём готовые списки каталога, а не выборку по [ItemKind]: в одежде и
  /// декоре по несколько видов предметов (комплекты и раздельные вещи, обои,
  /// полы и мелкий декор), и разбивка на разделы — свойство каталога КП 10,
  /// а не следствие вида предмета.
  /// Что показывает вкладка.
  ///
  /// Только вещи со своей картинкой. Остальные позиции каталога живы —
  /// комната и гардероб их знают, — но в витрину не попадают: заказчик
  /// 20.09 попросил убрать эмодзи, а карточка без картинки и без значка
  /// продаёт пустое место.
  List<ShopItem> get items => [
    for (final item in _all)
      if (item.photo) item,
  ];

  /// Есть ли что показать: вкладка без единой картинки не рисуется.
  bool get isEmpty => items.isEmpty;

  /// Подкатегории вкладки — в порядке каталога, без повторов.
  ///
  /// Считаются по товарам, а не берутся списком: подкатегория без единой
  /// картинки — это пустой чип, который ведёт в пустоту.
  List<ItemGroup> get groups {
    final found = <ItemGroup>[];
    for (final item in items) {
      if (!found.contains(item.group)) found.add(item.group);
    }
    return found;
  }

  List<ShopItem> get _all => switch (this) {
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
          for (final tab in _ShopTab.values.where((t) => !t.isEmpty)) ...[
            Expanded(
              child: _TabButton(
                title: tab.title(context.l10n),
                selected: tab == current,
                onTap: () => onSelected(tab),
              ),
            ),
            if (tab != _ShopTab.values.lastWhere((t) => !t.isEmpty))
              const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Ряд подкатегорий внутри вкладки.
///
/// Прокручивается вбок, а не переносится: в мебели родов вещей восемь, и
/// второй ряд чипов съел бы половину витрины. Первый чип — «Все»: без него
/// из подкатегории некуда вернуться, кроме как через соседнюю вкладку.
class _GroupsRow extends StatelessWidget {
  const _GroupsRow({
    required this.groups,
    required this.current,
    required this.onSelected,
  });

  final List<ItemGroup> groups;
  final ItemGroup? current;
  final ValueChanged<ItemGroup?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 0, 8, 0),
        children: [
          _GroupChip(
            title: context.l10n.shopGroupAll,
            selected: current == null,
            onTap: () => onSelected(null),
          ),
          for (final group in groups)
            _GroupChip(
              title: shopGroupName(context.l10n, group),
              selected: group == current,
              onTap: () => onSelected(group),
            ),
        ],
      ),
    );
  }
}

/// Чип одной подкатегории. Мельче и тише вкладки: это второй уровень, и
/// спорить за внимание с вкладками ему нечем.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);

    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      child: Material(
        color: selected ? AppColors.sageSoft : AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.sage : AppColors.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              title,
              style: sceneText(
                size: 12.5,
                weight: selected ? 800 : 600,
                color: selected ? AppColors.sageDark : AppColors.textSecondary,
              ),
            ),
          ),
        ),
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
    // Капсула, а не прямоугольная плашка: тот же приём, что у кнопок в
    // комнате и у подписей поверх сцены.
    final radius = BorderRadius.circular(999);

    return Material(
      color: selected ? AppColors.sage : AppColors.surface,
      borderRadius: radius,
      elevation: selected ? 3 : 0,
      shadowColor: AppColors.sageDark.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
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
            style: sceneText(
              size: 12.5,
              weight: selected ? 800 : 600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка товара: картинка, название и либо цена, либо «Куплено».
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.owned,
    required this.inCart,
    required this.onTap,
    required this.onZoom,
  });

  final ShopItem item;
  final bool owned;
  final bool inCart;
  final VoidCallback onTap;

  /// Рассмотреть вещь крупно.
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);

    return Opacity(
      // Купленное гасим, а не прячем: по КП 3.5 ребёнок должен видеть весь
      // каталог целиком, но уже своя вещь не должна перетягивать внимание с
      // того, что ещё можно купить.
      opacity: owned ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: owned ? null : onTap,
        // Долгое нажатие — то же, что лупа: привычный жест для «покажи
        // поближе», и он работает на всей площади карточки.
        onLongPress: onZoom,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            // Подушка, а не плоский прямоугольник: карточка лежит на
            // кремовом листе, и без мягкой тени вещь кажется приклеенной.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, AppColors.surface],
            ),
            border: Border.all(
              // Отобранное в корзину обводим зелёным: значок в углу мелкий,
              // а набранное нужно находить взглядом, не вчитываясь.
              color: inCart ? AppColors.sage : AppColors.outline,
              width: inCart ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.tan.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  children: [
                    Expanded(
                      // Hero по id товара: из карточки вещь вырастает на
                      // весь экран и тем же движением возвращается, так что
                      // место в витрине не теряется.
                      child: Hero(
                        tag: 'shop.item.${item.id}',
                        child: Center(child: ItemPicture(item: item)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      shopItemName(context.l10n, item.id),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sceneText(size: 12.5, weight: 700),
                    ),
                    const SizedBox(height: 5),
                    if (owned)
                      Text(
                        context.l10n.shopOwnedLabel,
                        style: sceneText(
                          size: 11,
                          weight: 700,
                          color: AppColors.sageDark,
                        ),
                      )
                    else
                      _Price(price: item.price),
                  ],
                ),
              ),
              if (owned || inCart)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _CornerBadge(icon: owned ? Icons.check : Icons.add),
                ),
              // Лупа слева, чтобы не спорить с галочкой «куплено» справа.
              // Тап по самой карточке по-прежнему кладёт вещь в корзину:
              // разглядывать хочется не каждую, а покупать — быстро.
              Positioned(top: 6, left: 6, child: _ZoomButton(onTap: onZoom)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Цена предмета: монета и число в тёплой капсуле.
///
/// ЗАГЛУШКА: сами значения по КП 10.9 утверждаются отдельно и по 15.4 правятся
/// из панели управления — здесь они просто показываются.
class _Price extends StatelessWidget {
  const _Price({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
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
          const SizedBox(width: 6),
          Text('$price', style: sceneText(size: 12, weight: 800)),
        ],
      ),
    );
  }
}

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

/// Кнопка «рассмотреть» в углу карточки.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.shopZoom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outline),
            boxShadow: [
              BoxShadow(
                color: AppColors.tan.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.zoom_in_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
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
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          elevation: 4,
          shadowColor: AppColors.sageDark.withValues(alpha: 0.55),
          // Погашенная кнопка остаётся зелёной, просто бледной: серый
          // «выключенный» вид из темы Material читается как поломка, а не как
          // «ещё ничего не выбрано».
          disabledBackgroundColor: AppColors.sage.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
        ),
        child: count == 0
            ? Text(
                context.l10n.shopCartEmpty,
                style: sceneText(size: 14, weight: 800, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.shopBuyFor(total),
                    style: sceneText(
                      size: 14,
                      weight: 800,
                      color: Colors.white,
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
              style: sceneText(size: 17, weight: 800),
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
          Text('$coins', style: sceneText(size: 12.5, weight: 800)),
        ],
      ),
    );
  }
}
