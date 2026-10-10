import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/item_groups.dart';
import '../game/room_slots.dart';
import '../game/shop_items.dart';
import '../l10n/catalog_l10n.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/item_picture.dart';
import '../widgets/item_preview.dart';
import '../widgets/purchase_confirm.dart';
import '../widgets/scene_label.dart';
import '../widgets/top_toast.dart';

/// Магазин — стеклянной панелью снизу, которую можно тянуть вверх.
///
/// Заказчик 10.10: панель открывается на [ShopScreen.half] высоты — комната
/// видна сверху, и купленное встаёт в ней прямо на глазах; вверх тянется до
/// [ShopScreen.full]. Фон — матовое стекло. Закрывается только свайпом вниз
/// или крестиком: тап мимо панели её не прячет.
///
/// [onApplied] — купленное уже в комнате: экран показывает игровую, чтобы
/// вещь было видно.
Future<void> showShopSheet(
  BuildContext context, {
  required GameState game,
  String? focusItemId,
  ValueChanged<ShopItem>? onApplied,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    // Тянет панель сама панель (шапка и витрина), а не лист вокруг неё.
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Комната за панелью почти не затемнена: в ней сейчас встанет покупка.
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.08),
    builder: (context) =>
        _ShopSheet(game: game, focusItemId: focusItemId, onApplied: onApplied),
  );
}

class _ShopSheet extends StatefulWidget {
  const _ShopSheet({required this.game, this.focusItemId, this.onApplied});

  final GameState game;
  final String? focusItemId;
  final ValueChanged<ShopItem>? onApplied;

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: ShopScreen.half,
      // Дотянули до низа — панель закрывается сама (лист под ней ловит
      // это и уходит).
      minChildSize: ShopScreen.closeAt,
      maxChildSize: ShopScreen.full,
      snap: true,
      snapSizes: const [ShopScreen.half],
      expand: false,
      builder: (context, scroll) => ShopScreen(
        game: widget.game,
        focusItemId: widget.focusItemId,
        scrollController: scroll,
        sheet: _sheet,
        onApplied: widget.onApplied,
      ),
    );
  }
}

/// Магазин предметов (КП 11.2).
///
/// Два уровня (заказчик 10.10): сначала — список категорий; в категории —
/// вкладки категорий, подкатегории и витрина. «Назад» поднимает на уровень
/// вверх, а не закрывает магазин.
///
/// Вкладки — по разделам каталога КП 10: мебель (10.2), декор (10.3),
/// игрушки (10.4), одежда (10.5) — когда у неё будут картинки. Обои и полы
/// здесь не выделены в отдельные вкладки, в отличие от экрана комнаты:
/// покупателю они такой же товар, как картина или подушка.
///
/// Покупка — по одной вещи, с подтверждением (заказчик 24.09). Купленное не
/// закрывает магазин: вещь сразу встаёт в комнату (стены и пол — сразу
/// вместо прежних, вещь — на подходящее место), а человек остаётся в той же
/// категории (заказчик 10.10). Купленное не нажимается — повторно продавать
/// то же самое некуда, а «уже моё» должно читаться сразу.
class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.game,
    this.focusItemId,
    this.scrollController,
    this.sheet,
    this.onApplied,
  });

  /// Кошелёк и инвентарь — один источник правды на все экраны:
  /// купленное здесь должно тут же появиться в комнате и в гардеробе.
  final GameState game;

  /// Открыть магазин сразу в категории этого предмета.
  ///
  /// Нужен для подсказок в комнате: человек тапнул по пустому месту под
  /// кроватку и должен увидеть кроватку, а не одежду. Высыпать его в
  /// магазин «куда-то» — значит заставить искать то, на что он уже показал.
  final String? focusItemId;

  /// Прокрутка витрины — от панели: дотянули витрину до верха, и тянется
  /// уже сама панель.
  final ScrollController? scrollController;

  /// Высота панели: шапку тоже можно тянуть.
  final DraggableScrollableController? sheet;

  /// Купленное уже стоит в комнате.
  final ValueChanged<ShopItem>? onApplied;

  /// Высота панели при открытии: комната видна над ней.
  static const double half = 0.45;

  /// Панель, вытянутая вверх.
  static const double full = 0.9;

  /// Ниже — панель закрывается.
  static const double closeAt = 0.2;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  /// Открытая категория. `null` — список категорий. Если пришли за
  /// конкретной вещью, открывается её категория.
  late _ShopTab? _tab = _tabOf(widget.focusItemId);

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

  /// «Назад»: из категории — к списку категорий.
  void _up() => setState(() {
    _tab = null;
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

  /// Купить и сразу поставить в комнату (заказчик 10.10). Магазин при этом
  /// остаётся открытым на той же категории.
  Future<bool> _buy(ShopItem item) async {
    final game = widget.game;
    final l10n = context.l10n;
    final toasts = topToasts(context);
    final bought = await buyItemConfirmed(
      context: context,
      game: game,
      item: item,
      showToast: false,
    );
    if (!bought) return false;
    final name = shopItemName(l10n, item.id);

    var placed = false;
    if (item.isSurface) {
      // Стены и пол — сразу вместо прежних.
      game.togglePlaced(item.id);
      placed = true;
    } else {
      final slot = slotForBought(item, game.itemInSlot);
      if (slot != null) {
        game.placeInSlot(slot.id, item.id);
        placed = true;
      }
    }
    if (placed) widget.onApplied?.call(item);
    toasts.show(
      placed ? l10n.shopBoughtInRoom(name) : l10n.roomItemBought(name),
      icon: Icons.check_circle_rounded,
    );
    return true;
  }

  /// Тянуть панель за шапку: вниз — до половины и до закрытия, вверх — во
  /// весь рост.
  void _drag(DragUpdateDetails d) {
    final sheet = widget.sheet;
    if (sheet == null || !sheet.isAttached) return;
    sheet.jumpTo(
      (sheet.size - sheet.pixelsToSize(d.delta.dy)).clamp(
        ShopScreen.closeAt,
        ShopScreen.full,
      ),
    );
  }

  void _release(DragEndDetails d) {
    final sheet = widget.sheet;
    if (sheet == null || !sheet.isAttached) return;
    final v = d.primaryVelocity ?? 0;
    final size = sheet.size;
    double to;
    if (v > 700) {
      to = size > ShopScreen.half + 0.04 ? ShopScreen.half : ShopScreen.closeAt;
    } else if (v < -700) {
      to = ShopScreen.full;
    } else {
      to = const [
        ShopScreen.closeAt,
        ShopScreen.half,
        ShopScreen.full,
      ].reduce((a, b) => (a - size).abs() < (b - size).abs() ? a : b);
    }
    sheet.animateTo(
      to,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tab;
    return PopScope(
      // Системное «назад» из категории — к списку категорий, а не вон.
      canPop: tab == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: _GlassSheet(
        child: AnimatedBuilder(
          // Мишку слушаем ради стадии: от неё зависит порядок витрины, и
          // переход может случиться прямо на этом экране.
          animation: Listenable.merge([widget.game, widget.game.bear]),
          builder: (context, _) {
            final game = widget.game;
            final header = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _drag,
              onVerticalDragEnd: _release,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Полоска-ручка: знак, что панель тянется.
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  _SheetHeader(
                    title: tab == null
                        ? context.l10n.shopTitle
                        : tab.title(context.l10n),
                    coins: game.coins,
                    onBack: tab == null ? null : _up,
                  ),
                  if (tab != null) ...[
                    _TabsRow(current: tab, onSelected: _openTab),
                    // Второй ряд — подкатегории этой вкладки. Один род вещей
                    // делить не на что, поэтому ряд появляется от двух.
                    if (tab.groups.length > 1)
                      _GroupsRow(
                        groups: tab.groups,
                        current: _group,
                        onSelected: (group) => setState(() => _group = group),
                      ),
                  ],
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // Витрина — во всю панель: иначе короткий раздел
                    // (две картины) сжимается и повисает посередине, а
                    // пустое место над ним не тянет панель.
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: tab == null
                        ? _CategoryList(
                            key: const ValueKey('shop.categories'),
                            controller: widget.scrollController,
                            onOpen: _openTab,
                          )
                        : _Showcase(
                            key: ValueKey('shop.${tab.name}'),
                            controller: widget.scrollController,
                            tab: tab,
                            group: _group,
                            game: game,
                            onBuy: _buy,
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

/// Подложка панели: матовое стекло — размытая комната сквозь
/// полупрозрачную заливку, тонкая светлая кромка сверху.
class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.child});

  final Widget child;

  static const double _radius = 30;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_radius),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_radius),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_radius),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.62),
                  AppColors.surface.withValues(alpha: 0.72),
                  AppColors.background.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// Список категорий — первый уровень магазина.
class _CategoryList extends StatelessWidget {
  const _CategoryList({super.key, this.controller, required this.onOpen});

  final ScrollController? controller;
  final ValueChanged<_ShopTab> onOpen;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final tab in _ShopTab.values)
        if (!tab.isEmpty) tab,
    ];
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        6,
        AppDimens.pagePadding,
        AppDimens.pagePadding,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 150,
      ),
      itemCount: tabs.length,
      itemBuilder: (context, index) =>
          _CategoryTile(tab: tabs[index], onTap: () => onOpen(tabs[index])),
    );
  }
}

/// Плитка категории: две вещи из неё, название и сколько всего.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.tab, required this.onTap});

  final _ShopTab tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final items = tab.items;
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      label: tab.title(context.l10n),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, AppColors.surface],
            ),
            border: Border.all(color: AppColors.outline),
            boxShadow: [
              BoxShadow(
                color: AppColors.tan.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (items.length > 1)
                      Positioned(
                        right: 0,
                        top: 0,
                        width: 44,
                        height: 44,
                        child: ItemPicture(item: items[1]),
                      ),
                    Positioned.fill(
                      top: 10,
                      right: items.length > 1 ? 16 : 0,
                      child: Center(child: ItemPicture(item: items.first)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tab.title(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sceneText(size: 13.5, weight: 800),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.shopCategoryCount(items.length),
                style: sceneText(
                  size: 11,
                  weight: 600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Витрина категории: «подходит сейчас» и «пригодится потом».
class _Showcase extends StatelessWidget {
  const _Showcase({
    super.key,
    this.controller,
    required this.tab,
    required this.group,
    required this.game,
    required this.onBuy,
  });

  final ScrollController? controller;
  final _ShopTab tab;
  final ItemGroup? group;
  final GameState game;
  final Future<bool> Function(ShopItem item) onBuy;

  @override
  Widget build(BuildContext context) {
    final stage = game.bear.state.stage;

    // Витрина делится надвое: сначала то, что малышу нужно сейчас, ниже —
    // то, что пригодится потом. Замков здесь нет и быть не должно (КП 11.2
    // не знает никаких ограничений на покупку) — купить можно всё, но
    // человеку с новорождённым первым должен попадаться ночник, а не
    // письменный стол.
    final shown = [
      for (final i in tab.items)
        if (group == null || i.group == group) i,
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

    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        0,
        AppDimens.pagePadding,
        AppDimens.pagePadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовки появляются только когда есть что разделять: на
          // взрослой стадии подходит всё, и подпись «малышу сейчас» над
          // единственной сеткой читалась бы как насмешка.
          if (later.isNotEmpty && now.isNotEmpty) ...[
            _GroupTitle(context.l10n.shopGroupNow),
            _ItemGrid(items: now, showcase: showcase, game: game, onBuy: onBuy),
            _GroupTitle(context.l10n.shopGroupLater),
            _ItemGrid(
              items: later,
              showcase: showcase,
              game: game,
              onBuy: onBuy,
            ),
          ] else
            _ItemGrid(
              items: now.isEmpty ? later : now,
              showcase: showcase,
              game: game,
              onBuy: onBuy,
            ),
        ],
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
    required this.onBuy,
  });

  /// Что показывает эта сетка: «подходит сейчас» или «пригодится потом».
  final List<ShopItem> items;

  /// Весь раздел целиком, в порядке показа. Нужен просмотру: из него
  /// листают дальше по разделу, а не по одной группе.
  final List<ShopItem> showcase;

  final GameState game;

  /// Купить и сразу поставить в комнату.
  final Future<bool> Function(ShopItem item) onBuy;

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
          // Корзины нет (заказчик 24.09): нажал — окно «Купить?», и каждая
          // вещь покупается отдельно.
          onTap: () => onBuy(item),
          onZoom: () => showItemPreview(
            context: context,
            items: showcase,
            index: showcase.indexOf(item),
            game: game,
            onBuy: onBuy,
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
      if (item.onSale) item,
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
    required this.onTap,
    required this.onZoom,
  });

  final ShopItem item;
  final bool owned;
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
            border: Border.all(color: AppColors.outline),
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
              if (owned)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: _CornerBadge(icon: Icons.check),
                ),
              // Лупа слева, чтобы не спорить с галочкой «куплено» справа.
              // Тап по самой карточке — покупка с подтверждением.
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
          // Заказчик 09.10: бесплатное — «Бесплатно», как в ленте
          // «Обставить», а не «0» с монеткой.
          if (price == 0)
            Text(
              context.l10n.furnishFree,
              style: sceneText(
                size: 12,
                weight: 800,
                color: AppColors.sageDark,
              ),
            )
          else ...[
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

/// Шапка панели: «назад» (в категории), заголовок по центру, кошелёк и
/// крестик справа.
///
/// «Назад» поднимает на уровень вверх — из категории к списку категорий, —
/// а закрывает магазин только крестик или свайп вниз (заказчик 10.10).
/// Кошелёк на этом экране обязателен: здесь тратят монеты (КП 11.1), и остаток
/// должен быть перед глазами в тот момент, когда выбирают покупку.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.coins,
    required this.onBack,
  });

  final String title;
  final int coins;

  /// `null` — уровень верхний, «назад» некуда: кнопки нет.
  final VoidCallback? onBack;

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
          // Место под «назад» держится и без кнопки: заголовок не прыгает.
          SizedBox(
            width: 32,
            height: 32,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: onBack == null
                  ? const SizedBox.shrink()
                  : _RoundButton(
                      key: const ValueKey('shop.back'),
                      icon: Icons.chevron_left,
                      label: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onTap: onBack!,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                title,
                key: ValueKey(title),
                textAlign: TextAlign.center,
                style: sceneText(size: 17, weight: 800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Purse(coins: coins),
          const SizedBox(width: 8),
          _RoundButton(
            key: const ValueKey('shop.close'),
            icon: Icons.close_rounded,
            label: MaterialLocalizations.of(context).closeButtonLabel,
            // Закрыть совсем — с любого уровня.
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Круглая кнопка шапки: «назад» и крестик.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(icon, size: 20, color: AppColors.textPrimary),
            ),
          ),
        ),
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
