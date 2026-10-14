import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/catalog/store_catalog.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/screens/catalog_screen.dart';

/// «Мишки» — витрина сайта TeddyTales (решение Ирины 14.10, миграция 0030):
/// разбор ответа `store_catalog()`, порядок, размеры и метки, ссылка на сайт
/// с меткой «из приложения», запасной снимок и сам экран.
void main() {
  // Так отвечает store_catalog(): товары в порядке сайта, разделы по типу.
  Map<String, dynamic> serverCatalog() => {
    'url': 'https://teddytales.com',
    'utm': 'teddytales_app',
    'synced_at': '2026-10-14T04:03:32.309013+00:00',
    'products': [
      {
        'id': 2,
        'handle': 'story-bear-30cm',
        'title': 'Story Bear Everest (30cm)',
        'category': 'bears',
        'tags': ['Lina Bear', '30cm', 'Story Bear'],
        'price': 129.9,
        'price_max': 139.9,
        'compare_at': null,
        'available': false,
        'images': ['https://cdn.shopify.com/s/files/story.webp?v=1'],
        'variants': [
          {'id': 21, 'title': 'Everest', 'price': 129.9, 'available': false},
          {'id': 22, 'title': 'Serendipity', 'price': 139.9, 'available': false},
        ],
        'position': 1,
      },
      {
        'id': 1,
        'handle': 'lina-bear-15cm',
        'title': 'Lina Bear Milk Tea (15CM)',
        'category': 'bears',
        'tags': ['Lina Bear', 'Mohair'],
        'price': 55.9,
        'price_max': 55.9,
        'available': true,
        'images': ['https://cdn.shopify.com/s/files/lina.webp?v=1'],
        'variants': [
          {'id': 11, 'title': 'Default Title', 'price': 55.9, 'available': true},
        ],
        'position': 2,
      },
      {
        'id': 3,
        'handle': 'british-gazette-outfit-set-m30cm',
        'title': 'British Gazette Outfit Set-M(30cm)',
        'category': 'clothes',
        'tags': ['30cm', 'Couple Collection', 'Wardrobe'],
        'price': 59.9,
        'price_max': 59.9,
        'available': true,
        'images': [
          'https://cdn.shopify.com/s/files/gazette.webp?v=1',
          'https://cdn.shopify.com/s/files/female.webp?v=1',
          'https://cdn.shopify.com/s/files/male.webp?v=1',
        ],
        'variants': [
          {
            'id': 31,
            'title': 'Female Set',
            'price': 59.9,
            'available': true,
            'image': 'https://cdn.shopify.com/s/files/female.webp?v=7',
          },
          {
            'id': 32,
            'title': 'Male Set',
            'price': 59.9,
            'available': true,
            'image': 'https://cdn.shopify.com/s/files/male.webp?v=7',
          },
        ],
        'position': 3,
      },
      {
        'id': 4,
        'handle': 'lina-meow-calico-puff',
        'title': 'Lina Meow Calico Puff',
        'category': 'friends',
        'tags': ['Lina Friends', '12-15cm', 'Lina Meow'],
        'price': 69.9,
        'price_max': 69.9,
        'compare_at': 89.9,
        'available': true,
        'images': <String>[],
        'variants': [
          {'id': 41, 'title': 'Default Title', 'price': 69.9, 'available': true},
        ],
        'position': 4,
      },
      // Подарочная карта: сервер её прячет, но и чужой раздел не ломает
      // разбор.
      {
        'id': 5,
        'handle': 'gift-card',
        'title': 'Gift Card',
        'category': null,
        'price': 10,
        'price_max': 100,
        'available': true,
        'position': 5,
      },
    ],
  };

  group('разбор витрины', () {
    final catalog = StoreCatalog.fromJson(serverCatalog());

    test('товары по разделам, без скрытых', () {
      expect(catalog.products, hasLength(4));
      expect(catalog.store, Uri.parse('https://teddytales.com'));
      expect(catalog.syncedAt, isNotNull);
      expect(catalog.section(StoreSection.clothes).single.id, 3);
      expect(catalog.section(StoreSection.friends).single.id, 4);
    });

    test('в разделе сначала то, что есть в наличии', () {
      expect(catalog.section(StoreSection.bears).map((p) => p.id), [1, 2]);
    });

    test('размер — из меток, иначе из названия', () {
      final byId = {for (final p in catalog.products) p.id: p};
      expect(byId[1]!.size, '15');
      expect(byId[2]!.size, '30');
      expect(byId[3]!.size, '30');
      expect(byId[4]!.size, '12–15');
    });

    test('метки без размеров и названий разделов', () {
      final byId = {for (final p in catalog.products) p.id: p};
      expect(byId[1]!.badges, ['Mohair']);
      expect(byId[3]!.badges, ['Couple Collection']);
      expect(byId[4]!.badges, ['Lina Meow']);
    });

    test('первым предлагается вариант в наличии', () {
      final byId = {for (final p in catalog.products) p.id: p};
      expect(byId[3]!.firstChoice!.id, 31);
      // Всё раскуплено — первый вариант, сайт скажет, когда вернётся.
      expect(byId[2]!.firstChoice!.id, 21);
      expect(byId[1]!.hasChoice, isFalse);
    });

    test('ссылка на товар: вариант и метка «из приложения»', () {
      final byId = {for (final p in catalog.products) p.id: p};
      final gazette = byId[3]!;
      final url = catalog.productUrl(
        gazette,
        variant: gazette.variants.last,
        language: 'ru',
      );
      expect(url.host, 'teddytales.com');
      expect(url.path, '/products/british-gazette-outfit-set-m30cm');
      expect(url.queryParameters, {
        'variant': '32',
        'utm_source': 'teddytales_app',
        'utm_medium': 'catalog',
        'utm_campaign': 'ru',
      });
      // У товара без выбора вариант в ссылку не идёт.
      final lina = byId[1]!;
      final plain = catalog.productUrl(lina, variant: lina.firstChoice);
      expect(plain.queryParameters.containsKey('variant'), isFalse);
      expect(catalog.homeUrl().path, '/');
    });

    test('цена и картинка нужной ширины', () {
      expect(storePrice(59.9), '\$59.90');
      expect(
        storeImage('https://cdn.shopify.com/a.webp?v=1', 480),
        'https://cdn.shopify.com/a.webp?v=1&width=480',
      );
      expect(
        storeImage('https://cdn.shopify.com/a.webp', 480),
        'https://cdn.shopify.com/a.webp?width=480',
      );
    });
  });

  group('откуда берётся витрина', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('без сохранённой — снимок из сборки', () async {
      final repo = StoreCatalogRepository(
        fetch: () async => throw StateError('нет сети'),
        bundle: _Bundle(jsonEncode(serverCatalog())),
      );
      final saved = await repo.saved();
      expect(saved!.products, hasLength(4));
    });

    test('свежая с сервера сохраняется и показывается без сети', () async {
      final online = StoreCatalogRepository(
        fetch: () async => serverCatalog(),
        bundle: _Bundle(null),
      );
      expect((await online.refresh()).products, hasLength(4));

      final offline = StoreCatalogRepository(
        fetch: () async => throw StateError('нет сети'),
        bundle: _Bundle(null),
      );
      expect((await offline.saved())!.products, hasLength(4));
    });

    test('пустой ответ — сбой, сохранённая не затирается', () async {
      final repo = StoreCatalogRepository(
        fetch: () async => {'url': 'https://teddytales.com', 'products': []},
        bundle: _Bundle(null),
      );
      await expectLater(repo.refresh(), throwsStateError);
      expect(await repo.saved(), isNull);
    });
  });

  group('экран «Мишки»', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<List<Uri>> pumpCatalog(
      WidgetTester tester, {
      bool opens = true,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final bear = BearController();
      addTearDown(bear.dispose);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: CatalogScreen(
            controller: bear,
            repository: StoreCatalogRepository(
              fetch: () async => serverCatalog(),
              bundle: _Bundle(null),
            ),
            openLink: (uri) async {
              opened.add(uri);
              return opens;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('вкладки, карточки и «Нет в наличии»', (tester) async {
      await pumpCatalog(tester);
      expect(find.text('Мишки TeddyTales'), findsOneWidget);
      expect(find.text('Мишки'), findsOneWidget);
      expect(find.text('Одежда'), findsOneWidget);
      expect(find.text('Друзья'), findsOneWidget);
      expect(find.text('Lina Bear Milk Tea (15CM)'), findsOneWidget);
      expect(find.text('Story Bear Everest (30cm)'), findsOneWidget);
      expect(find.text('Нет в наличии'), findsOneWidget);
      expect(find.text('от \$129.90'), findsOneWidget);
      expect(find.text('15 см · Mohair'), findsOneWidget);

      await tester.tap(find.text('Друзья'));
      await tester.pumpAndSettle();
      expect(find.text('Lina Meow Calico Puff'), findsOneWidget);
      expect(find.text('Lina Bear Milk Tea (15CM)'), findsNothing);
      // Цена до скидки — зачёркнутая.
      expect(find.text('\$89.90'), findsOneWidget);
    });

    testWidgets('вариант на странице товара уходит в ссылку', (tester) async {
      final opened = await pumpCatalog(tester);
      await tester.tap(find.text('Одежда'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('British Gazette Outfit Set-M(30cm)'));
      await tester.pumpAndSettle();

      expect(find.text('Вариант'), findsOneWidget);
      await tester.tap(find.text('Male Set'));
      await tester.pumpAndSettle();
      final buy = find.text('Купить на сайте TeddyTales');
      await tester.ensureVisible(buy);
      await tester.tap(buy);
      await tester.pump();

      expect(opened, hasLength(1));
      expect(opened.single.path, '/products/british-gazette-outfit-set-m30cm');
      expect(opened.single.queryParameters['variant'], '32');
      expect(opened.single.queryParameters['utm_source'], 'teddytales_app');
      expect(opened.single.queryParameters['utm_campaign'], 'ru');
    });

    testWidgets('раскупленное — «Посмотреть на сайте»', (tester) async {
      final opened = await pumpCatalog(tester, opens: false);
      await tester.tap(find.text('Story Bear Everest (30cm)'));
      await tester.pumpAndSettle();

      expect(find.text('Купить на сайте TeddyTales'), findsNothing);
      final view = find.text('Посмотреть на сайте');
      await tester.ensureVisible(view);
      await tester.tap(view);
      await tester.pump();
      expect(opened.single.queryParameters['variant'], '21');
      // Сайт не открылся — уведомление сверху.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Не получилось открыть сайт TeddyTales'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}

/// Сборка со снимком витрины (или без него — `null`).
class _Bundle extends CachingAssetBundle {
  _Bundle(this._text);

  final String? _text;

  @override
  Future<ByteData> load(String key) async {
    final text = _text;
    if (text == null) throw FlutterError('Нет $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}
