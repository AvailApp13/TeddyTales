/// Витрина сайта TeddyTales в разделе «Мишки» (КП 12).
///
/// Решение Ирины 14.10: покупают на сайте teddytales.com. Приложение
/// показывает их товары — фото, цены, размеры, наличие (КП 12.1, 12.2) — и
/// по «Купить на сайте» открывает страницу товара. Адрес, оплата и доставка
/// — на сайте (КП 12.3, 12.4), заказ сразу в их системе продаж (КП 12.5).
///
/// Товары сервер раз в час забирает с сайта (миграция 0030,
/// `store_catalog()`); приложение читает сервер, а не сайт. Откуда берётся
/// показанное, по порядку:
/// 1. последняя сохранённая витрина — без сети (КП 1.1);
/// 2. снимок в сборке (`assets/catalog/store_snapshot.json`) — первый
///    запуск без сети и превью-артефакт, где запросы к серверу закрыты;
/// 3. свежая с сервера — подменяет показанное, как только придёт.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Раздел витрины — по типу товара на сайте (миграция 0030).
enum StoreSection {
  bears,
  clothes,
  friends;

  static StoreSection? fromName(Object? name) {
    for (final section in values) {
      if (section.name == name) return section;
    }
    return null;
  }
}

/// Вариант товара: цвет, комплект, персонаж — как на сайте.
@immutable
class StoreVariant {
  const StoreVariant({
    required this.id,
    required this.title,
    required this.price,
    required this.available,
    this.compareAt,
    this.image,
  });

  factory StoreVariant.fromJson(Map<String, dynamic> json) => StoreVariant(
    id: (json['id'] as num).toInt(),
    title: json['title']?.toString() ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    compareAt: (json['compare_at'] as num?)?.toDouble(),
    available: json['available'] == true,
    image: json['image'] as String?,
  );

  final int id;
  final String title;
  final double price;

  /// Цена до скидки — только если она выше нынешней.
  final double? compareAt;
  final bool available;

  /// Своя фотография варианта, если сайт её задал.
  final String? image;
}

/// Товар витрины (КП 12.2).
@immutable
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.handle,
    required this.title,
    required this.section,
    required this.tags,
    required this.price,
    required this.priceMax,
    required this.available,
    required this.images,
    required this.variants,
    required this.position,
    this.compareAt,
  });

  static StoreProduct? fromJson(Map<String, dynamic> json) {
    final section = StoreSection.fromName(json['category']);
    if (section == null) return null;
    return StoreProduct(
      id: (json['id'] as num).toInt(),
      handle: json['handle'].toString(),
      title: json['title']?.toString() ?? '',
      section: section,
      tags: [for (final tag in json['tags'] as List? ?? const []) '$tag'],
      price: (json['price'] as num?)?.toDouble() ?? 0,
      priceMax: (json['price_max'] as num?)?.toDouble() ?? 0,
      compareAt: (json['compare_at'] as num?)?.toDouble(),
      available: json['available'] == true,
      images: [for (final url in json['images'] as List? ?? const []) '$url'],
      variants: [
        for (final variant in json['variants'] as List? ?? const [])
          StoreVariant.fromJson(Map<String, dynamic>.from(variant as Map)),
      ],
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  final int id;

  /// Адрес на сайте: `/products/<handle>`.
  final String handle;

  /// Название как на сайте — по-английски: переводить двести названий
  /// товаров чужого магазина значило бы разойтись с ним.
  final String title;
  final StoreSection section;
  final List<String> tags;

  /// Самый дешёвый вариант, долларов США.
  final double price;
  final double priceMax;
  final double? compareAt;

  /// Есть ли хоть один вариант в наличии.
  final bool available;
  final List<String> images;
  final List<StoreVariant> variants;

  /// Порядок как на сайте: свежие сверху.
  final int position;

  static final RegExp _sizeTag = RegExp(
    r'^(\d+)(?:\s*-\s*(\d+))?\s*cm$',
    caseSensitive: false,
  );
  static final RegExp _sizeInTitle = RegExp(
    r'(\d+)\s*cm',
    caseSensitive: false,
  );

  /// Метки сайта, которые и так видны вкладкой: показывать их на карточке
  /// незачем.
  static const Set<String> _sectionTags = {
    'lina bear',
    'lina friends',
    'wardrobe',
  };

  /// Размер в сантиметрах строкой — «30» или «12–15». Из меток сайта, а
  /// если метки нет — из названия («Pocket Series (15CM)»).
  String? get size {
    for (final tag in tags) {
      final match = _sizeTag.firstMatch(tag.trim());
      if (match != null) {
        final to = match.group(2);
        return to == null ? match.group(1) : '${match.group(1)}–$to';
      }
    }
    return _sizeInTitle.firstMatch(title)?.group(1);
  }

  /// Метки для карточки (КП 12.2: мех, серия, одежда): без размеров и без
  /// названий разделов.
  List<String> get badges => [
    for (final tag in tags)
      if (!_sizeTag.hasMatch(tag.trim()) &&
          !_sectionTags.contains(tag.trim().toLowerCase()))
        tag.trim(),
  ];

  /// Выбор на сайте есть, только если вариантов больше одного: единственный
  /// вариант Shopify называет «Default Title».
  bool get hasChoice => variants.length > 1;

  /// Вариант, который предложить первым: первый в наличии.
  StoreVariant? get firstChoice {
    for (final variant in variants) {
      if (variant.available) return variant;
    }
    return variants.isEmpty ? null : variants.first;
  }

  /// Миниатюра из снимка для веба: `web/store/thumbs/<id>.jpg`. В превью-
  /// артефакте картинки с CDN магазина закрыты, а эти лежат рядом со
  /// страницей.
  String get webThumb => 'store/thumbs/$id.jpg';
}

/// Цена строкой — как на сайте: «$59.90».
String storePrice(double usd) => '\$${usd.toStringAsFixed(2)}';

/// Картинка магазина нужной ширины: CDN Shopify сам уменьшает по `width`.
String storeImage(String url, int width) =>
    '$url${url.contains('?') ? '&' : '?'}width=$width';

/// Витрина целиком: адрес магазина, метка «из приложения», товары.
@immutable
class StoreCatalog {
  const StoreCatalog({
    required this.store,
    required this.utm,
    required this.products,
    this.syncedAt,
  });

  factory StoreCatalog.fromJson(Map<String, dynamic> json) => StoreCatalog(
    store: Uri.parse(json['url']?.toString() ?? 'https://teddytales.com'),
    utm: json['utm']?.toString() ?? 'teddytales_app',
    syncedAt: DateTime.tryParse(json['synced_at']?.toString() ?? ''),
    products: [
      for (final raw in json['products'] as List? ?? const [])
        ?StoreProduct.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
  );

  final Uri store;
  final String utm;
  final DateTime? syncedAt;
  final List<StoreProduct> products;

  /// Товары раздела: что есть в наличии — сверху, дальше порядок сайта.
  List<StoreProduct> section(StoreSection section) {
    final list = [
      for (final product in products)
        if (product.section == section) product,
    ];
    list.sort((a, b) {
      if (a.available != b.available) return a.available ? -1 : 1;
      return a.position.compareTo(b.position);
    });
    return list;
  }

  /// Страница товара на сайте с выбранным вариантом и меткой «из
  /// приложения»: по `utm_source` магазин видит в своей статистике, сколько
  /// покупок пришло из игры, по `utm_campaign` — на каком языке.
  Uri productUrl(
    StoreProduct product, {
    StoreVariant? variant,
    String? language,
  }) => _withUtm(
    '/products/${product.handle}',
    variant: product.hasChoice ? variant : null,
    language: language,
  );

  /// Главная магазина — когда показать нечего.
  Uri homeUrl({String? language}) => _withUtm('/', language: language);

  Uri _withUtm(String path, {StoreVariant? variant, String? language}) =>
      store.replace(
        path: path,
        queryParameters: {
          if (variant != null) 'variant': '${variant.id}',
          'utm_source': utm,
          'utm_medium': 'catalog',
          if (language != null) 'utm_campaign': language,
        },
      );
}

/// Запрос витрины к серверу. Подменяется в тестах.
typedef StoreCatalogFetch = Future<Map<String, dynamic>> Function();

/// Откуда экран берёт витрину — см. порядок в начале файла.
class StoreCatalogRepository {
  StoreCatalogRepository({StoreCatalogFetch? fetch, AssetBundle? bundle})
    : _fetch = fetch ?? _fetchFromServer,
      _bundle = bundle ?? rootBundle;

  static const String snapshotAsset = 'assets/catalog/store_snapshot.json';
  static const String _cacheKey = 'teddytales.store_catalog.v1';
  static const Duration timeout = Duration(seconds: 12);

  final StoreCatalogFetch _fetch;
  final AssetBundle _bundle;

  /// Что показать сразу: последняя сохранённая витрина, а если её нет —
  /// снимок из сборки.
  Future<StoreCatalog?> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        return StoreCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } on Object catch (error) {
      debugPrint('Витрина: сохранённая не читается — $error');
    }
    try {
      final raw = await _bundle.loadString(snapshotAsset);
      return StoreCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      debugPrint('Витрина: снимка в сборке нет — $error');
      return null;
    }
  }

  /// Свежая витрина с сервера; сохраняется для показа без сети. Пустую не
  /// принимает: пустой ответ — сбой, а не закрытый магазин.
  Future<StoreCatalog> refresh() async {
    final json = await _fetch().timeout(timeout);
    final catalog = StoreCatalog.fromJson(json);
    if (catalog.products.isEmpty) {
      throw StateError('Витрина с сервера пустая');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(json));
    } on Object catch (error) {
      debugPrint('Витрина: не сохранилась — $error');
    }
    return catalog;
  }

  static Future<Map<String, dynamic>> _fetchFromServer() async {
    final data = await Supabase.instance.client.rpc<dynamic>('store_catalog');
    return Map<String, dynamic>.from(data as Map);
  }
}
