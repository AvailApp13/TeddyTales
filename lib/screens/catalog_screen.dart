import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bear/bear.dart';
import '../catalog/store_catalog.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/top_toast.dart';

/// Открывает страницу магазина.
typedef StoreLinkOpener = Future<bool> Function(Uri uri);

/// На телефоне — окном браузера поверх приложения (Safari View Controller,
/// Custom Tabs): купил, закрыл — снова в игре. В вебе — новой вкладкой.
Future<bool> openStoreLink(Uri uri) => launchUrl(
  uri,
  mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
  webOnlyWindowName: '_blank',
);

/// Раздел «Мишки» — витрина сайта TeddyTales (КП 12).
///
/// Решение Ирины 14.10: покупают на их сайте. Здесь — их товары с фото,
/// ценами, размерами и наличием (КП 12.1, 12.2), по вкладкам как на сайте:
/// мишки, одежда, друзья. «Купить на сайте» открывает страницу товара с
/// выбранным вариантом; адрес, оплата и доставка — там (КП 12.3–12.5).
/// Откуда берутся товары — `lib/catalog/store_catalog.dart`.
///
/// Цены в долларах, кошелька в шапке нет: монеты (КП 11.1) на настоящую
/// игрушку не тратятся.
///
/// На взрослой стадии сверху — «Твой малыш вырос»: выращенный питомец и есть
/// повод заказать настоящего. Каталог открыт с первого дня (КП 12.1).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.controller,
    this.repository,
    this.openLink = openStoreLink,
  });

  /// Тот же контроллер, что и на главной: экран читает из него только стадию,
  /// чтобы понять, показывать ли блок «малыш вырос».
  final BearController controller;

  /// Откуда брать витрину; в тестах — подменная.
  final StoreCatalogRepository? repository;
  final StoreLinkOpener openLink;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final StoreCatalogRepository _repository =
      widget.repository ?? StoreCatalogRepository();

  StoreCatalog? _catalog;
  bool _loading = true;
  StoreSection _section = StoreSection.bears;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Сразу — сохранённая витрина или снимок из сборки, следом — свежая с
  /// сервера. Сервер не ответил — остаётся показанное.
  Future<void> _load() async {
    final saved = await _repository.saved();
    if (!mounted) return;
    if (saved != null) setState(() => _catalog = saved);
    try {
      final fresh = await _repository.refresh();
      if (mounted) setState(() => _catalog = fresh);
    } on Object catch (error) {
      debugPrint('Витрина: сервер не ответил — $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalog = _catalog;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final isAdult = widget.controller.state.stage == BearStage.adult;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(title: l10n.catalogTitle),
                Expanded(
                  child: catalog == null || catalog.products.isEmpty
                      ? _EmptyState(
                          loading: _loading,
                          onOpenSite: () => _open(
                            (catalog ?? _fallbackCatalog).homeUrl(
                              language: _language(context),
                            ),
                          ),
                        )
                      : _showcase(context, catalog, isAdult),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _showcase(BuildContext context, StoreCatalog catalog, bool isAdult) {
    final products = catalog.section(_section);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return CustomScrollView(
      slivers: [
        if (isAdult)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
            sliver: SliverToBoxAdapter(child: _GrownUpBanner()),
          ),
        SliverToBoxAdapter(
          child: _SectionTabs(
            current: _section,
            onSelected: (section) => setState(() => _section = section),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            12,
            AppDimens.pagePadding,
            0,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Фото товара 5 : 6, как на сайте, и под ним три строки.
              childAspectRatio: 0.58,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ProductCard(
                product: products[index],
                onTap: () => _openProduct(catalog, products[index]),
              ),
              childCount: products.length,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pagePadding,
            14,
            AppDimens.pagePadding,
            AppDimens.pagePadding + bottom,
          ),
          sliver: const SliverToBoxAdapter(child: _SiteNote()),
        ),
      ],
    );
  }

  void _openProduct(StoreCatalog catalog, StoreProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProductScreen(
          catalog: catalog,
          product: product,
          openLink: _open,
        ),
      ),
    );
  }

  /// Открыть страницу магазина; не вышло — сказать об этом сверху.
  Future<bool> _open(Uri uri) async {
    final toasts = topToasts(context);
    final failed = context.l10n.catalogOpenFailed;
    var opened = false;
    try {
      opened = await widget.openLink(uri);
    } on Object catch (error) {
      debugPrint('Витрина: не открылась ссылка $uri — $error');
    }
    if (!opened) toasts.show(failed);
    return opened;
  }
}

/// Язык интерфейса — в метку ссылки (`utm_campaign`): магазину видно, на
/// каком языке играют покупатели.
String _language(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// Адрес магазина, пока витрины нет вовсе: тот же, что в миграции 0030.
final StoreCatalog _fallbackCatalog = StoreCatalog(
  store: Uri.parse('https://teddytales.com'),
  utm: 'teddytales_app',
  products: const [],
);

String _sectionTitle(AppLocalizations l10n, StoreSection section) =>
    switch (section) {
      StoreSection.bears => l10n.catalogTabBears,
      StoreSection.clothes => l10n.catalogTabClothes,
      StoreSection.friends => l10n.catalogTabFriends,
    };

/// Вкладки витрины — как «Готовые блюда / Приготовить» на кухне.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.current, required this.onSelected});

  final StoreSection current;
  final ValueChanged<StoreSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: Row(
        children: [
          for (final section in StoreSection.values) ...[
            Expanded(
              child: _TabButton(
                title: _sectionTitle(l10n, section),
                isSelected: section == current,
                onTap: () => onSelected(section),
              ),
            ),
            if (section != StoreSection.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.sage : AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusChip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusChip),
            border: Border.all(
              color: isSelected ? AppColors.sage : AppColors.outline,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Цена карточки: «от» — если у вариантов цены разные.
String _priceLabel(AppLocalizations l10n, StoreProduct product) =>
    product.priceMax > product.price
    ? l10n.catalogPriceFrom(storePrice(product.price))
    : storePrice(product.price);

/// Строка под ценой: размер и первая метка сайта (мех, серия).
String _metaLine(AppLocalizations l10n, StoreProduct product) {
  final size = product.size;
  return [
    if (size != null) l10n.catalogSizeLabel(size),
    if (product.badges.isNotEmpty) product.badges.first,
  ].join(' · ');
}

/// Карточка товара в сетке (КП 12.2): фото, название, цена, размер.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final StoreProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final compareAt = product.compareAt;

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 5 / 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StoreImage.thumb(product),
                  if (!product.available)
                    const Positioned(left: 8, top: 8, child: _SoldOutBadge()),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            _priceLabel(l10n, product),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (compareAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            storePrice(compareAt),
                            style: _metaStyle(theme)?.copyWith(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(l10n, product),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle(theme),
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

TextStyle? _metaStyle(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  fontSize: 10.5,
  color: AppColors.textSecondary,
);

/// Плашка «Нет в наличии» поверх фото.
class _SoldOutBadge extends StatelessWidget {
  const _SoldOutBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        context.l10n.catalogSoldOut,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Фото товара с CDN магазина.
///
/// В вебе миниатюра сначала берётся из снимка рядом со страницей
/// (`web/store/thumbs/`): в превью-артефакте чужие картинки закрыты.
/// Нет её — с CDN; не загрузилось — спокойная заглушка.
class _StoreImage extends StatelessWidget {
  const _StoreImage({
    required this.product,
    required this.url,
    required this.width,
    required this.localFirst,
    required this.localFallback,
  });

  /// Миниатюра для сетки.
  factory _StoreImage.thumb(StoreProduct product) => _StoreImage(
    product: product,
    url: product.images.isEmpty ? null : product.images.first,
    width: 480,
    localFirst: kIsWeb,
    localFallback: false,
  );

  /// Кадр галереи на странице товара.
  factory _StoreImage.large(StoreProduct product, int index) => _StoreImage(
    product: product,
    url: index < product.images.length ? product.images[index] : null,
    width: 1000,
    localFirst: false,
    localFallback: kIsWeb && index == 0,
  );

  final StoreProduct product;
  final String? url;
  final int width;
  final bool localFirst;
  final bool localFallback;

  @override
  Widget build(BuildContext context) {
    Widget local(Widget orElse) => Image.network(
      product.webThumb,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => orElse,
    );

    final source = url;
    final remote = source == null
        ? const _ImagePlaceholder()
        : Image.network(
            storeImage(source, width),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const _ImagePlaceholder(),
            errorBuilder: (context, error, stack) => localFallback
                ? local(const _ImagePlaceholder())
                : const _ImagePlaceholder(),
          );
    return localFirst ? local(remote) : remote;
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.cream,
      child: Center(
        child: Icon(Icons.image_outlined, color: AppColors.tan, size: 28),
      ),
    );
  }
}

/// Подпись под витриной: где оформляется покупка.
class _SiteNote extends StatelessWidget {
  const _SiteNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.catalogSiteNote,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        height: 1.5,
      ),
    );
  }
}

/// Витрины нет совсем: первый запуск без сети и без снимка.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loading, required this.onOpenSite});

  final bool loading;
  final VoidCallback onOpenSite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.pagePadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.catalogEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onOpenSite,
              child: Text(l10n.catalogOpenSite),
            ),
          ],
        ),
      ),
    );
  }
}

/// Страница товара: галерея, варианты и «Купить на сайте» (КП 12.2).
class _ProductScreen extends StatefulWidget {
  const _ProductScreen({
    required this.catalog,
    required this.product,
    required this.openLink,
  });

  final StoreCatalog catalog;
  final StoreProduct product;
  final StoreLinkOpener openLink;

  @override
  State<_ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<_ProductScreen> {
  late StoreVariant? _variant = widget.product.firstChoice;
  final PageController _pages = PageController();
  int _page = 0;

  StoreProduct get _product => widget.product;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Выбрали вариант — галерея листает к его фото, если сайт его задал.
  void _select(StoreVariant variant) {
    setState(() => _variant = variant);
    final image = variant.image;
    if (image == null || !_pages.hasClients) return;
    final index = _product.images.indexWhere(
      (url) => url.split('?').first == image.split('?').first,
    );
    if (index >= 0) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _buy() {
    widget.openLink(
      widget.catalog.productUrl(
        _product,
        variant: _variant,
        language: _language(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final variant = _variant;
    final price = variant?.price ?? _product.price;
    final compareAt = variant == null ? _product.compareAt : variant.compareAt;
    final available = variant?.available ?? _product.available;
    final size = _product.size;
    final images = _product.images;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(title: _sectionTitle(l10n, _product.section)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppDimens.pagePadding,
                  0,
                  AppDimens.pagePadding,
                  AppDimens.pagePadding + bottom,
                ),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                    child: AspectRatio(
                      aspectRatio: 5 / 6,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PageView.builder(
                            controller: _pages,
                            itemCount: images.isEmpty ? 1 : images.length,
                            onPageChanged: (page) =>
                                setState(() => _page = page),
                            itemBuilder: (context, index) =>
                                _StoreImage.large(_product, index),
                          ),
                          if (images.length > 1)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 10,
                              child: _PageDots(
                                count: images.length,
                                current: _page,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _product.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        storePrice(price),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (compareAt != null && compareAt > price) ...[
                        const SizedBox(width: 8),
                        Text(
                          storePrice(compareAt),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!available) const _SoldOutBadge(),
                    ],
                  ),
                  if (size != null || _product.badges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (size != null)
                          _InfoChip(text: l10n.catalogSizeLabel(size)),
                        for (final badge in _product.badges)
                          _InfoChip(text: badge),
                      ],
                    ),
                  ],
                  if (_product.hasChoice) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.catalogVariant,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final option in _product.variants)
                          _VariantChip(
                            variant: option,
                            isSelected: option.id == variant?.id,
                            onTap: () => _select(option),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (available)
                    FilledButton.icon(
                      onPressed: _buy,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(
                        l10n.catalogBuyOnSite,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _buy,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l10n.catalogViewOnSite),
                    ),
                  const SizedBox(height: 12),
                  const _SiteNote(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Точки под галереей: на каком кадре.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.surface
                  : AppColors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// Метка товара: размер, мех, серия.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Вариант товара. Нет в наличии — зачёркнут, но выбрать можно: страница
/// на сайте покажет, когда он вернётся.
class _VariantChip extends StatelessWidget {
  const _VariantChip({
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  final StoreVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.sage : AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusChip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusChip),
            border: Border.all(
              color: isSelected ? AppColors.sage : AppColors.outline,
            ),
          ),
          child: Text(
            variant.title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              decoration: variant.available
                  ? TextDecoration.none
                  : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}

/// Блок над витриной на взрослой стадии.
///
/// Текст дословно из прототипа: он про питомца, а не про товар, и поэтому стоит
/// выше карточек — сначала повод, потом витрина.
class _GrownUpBanner extends StatelessWidget {
  const _GrownUpBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.cream,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.sageSoft, width: 2),
            ),
            // ЗАГЛУШКА: эмодзи вместо портрета питомца. Здесь должен стоять
            // кадр из рига во взрослой стадии — с той же шкурой и одеждой, что
            // на главной. Ассетов нет, эмодзи стоит из прототипа.
            child: const Center(
              child: Text('🧸', style: TextStyle(fontSize: 44)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.catalogGrownTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            context.l10n.catalogGrownSubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Кошелька здесь нет намеренно: настоящего мишку берут за доллары на сайте
/// TeddyTales, игровые монеты (КП 11.1) к этой покупке отношения не имеют, и
/// показывать их рядом с ценой в долларах значило бы предлагать расплатиться
/// ими.
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
