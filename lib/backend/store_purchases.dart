import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Покупки за деньги через App Store и Google Play (КП 11.3).
///
/// ⚠ ЖДЁТ СОГЛАСОВАНИЯ И НАСТРОЙКИ: какие предметы премиальные и почём
/// (КП 10.8, 10.9), товары в App Store Connect / Google Play Console, ключи
/// магазинов у функции `verify-purchase`. Пока сервер отдаёт пустой список
/// товаров ([StorePurchases.products] пуст), в приложении ничего не
/// продаётся и «Восстановить покупки» не показывается. Порядок включения —
/// `docs/store-purchases.md`.
///
/// Путь покупки: магазин → [PurchaseDetails] в потоке → чек уходит на
/// сервер ([verify]) → сервер проверил у Apple / Google и выдал предмет или
/// монеты → только теперь `completePurchase`. Сервер не ответил — покупку
/// не закрываем: магазин отдаст её снова при следующем запуске, деньги не
/// пропадут.
class StorePurchases {
  StorePurchases({
    required this.verify,
    required this.catalog,
    this.onGranted,
    InAppPurchase? iap,
  }) : _iap = iap;

  /// Проверить чек на сервере. Бросает — сервер недоступен или чек не
  /// прошёл; тогда покупка остаётся открытой.
  final Future<StoreGrant> Function(StoreReceipt receipt) verify;

  /// Какие товары продаются: `product_id → что выдаётся` (сервер,
  /// `store_products()`).
  final Future<Map<String, StoreProduct>> Function() catalog;

  /// Сервер выдал покупку — обновить кошелёк и вещи на экране.
  final void Function(StoreGrant grant)? onGranted;

  InAppPurchase? _iap;
  InAppPurchase get _store => _iap ??= InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Товары с ценами магазина на языке телефона. Пусто — продаж нет.
  final ValueNotifier<List<ProductDetails>> products = ValueNotifier(const []);
  Map<String, StoreProduct> _catalog = const {};

  /// Последнее, чем кончилась покупка, — для подсказки на экране.
  final ValueNotifier<StoreOutcome?> outcome = ValueNotifier(null);

  /// Слушать магазин и загрузить товары. Без магазина (веб, эмулятор без
  /// Google Play) — тихо ничего.
  Future<void> start() async {
    if (kIsWeb) return;
    try {
      if (!await _store.isAvailable()) return;
      _sub = _store.purchaseStream.listen(
        (list) => list.forEach(handle),
        onError: (Object error) => debugPrint('[TeddyTales] магазин: $error'),
      );
      _catalog = await catalog();
      if (_catalog.isEmpty) return;
      final response = await _store.queryProductDetails(_catalog.keys.toSet());
      products.value = response.productDetails;
    } on Object catch (error) {
      debugPrint('[TeddyTales] покупки недоступны: $error');
    }
  }

  /// Купить. Предмет — один раз навсегда, монеты — сколько угодно.
  Future<bool> buy(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    final coins = _catalog[product.id]?.coins ?? 0;
    return coins > 0
        ? _store.buyConsumable(purchaseParam: param)
        : _store.buyNonConsumable(purchaseParam: param);
  }

  /// «Восстановить покупки» (КП 11.3; обязательно в App Store): магазин
  /// заново присылает купленные предметы, сервер выдаёт их без повторной
  /// оплаты.
  Future<void> restore() => _store.restorePurchases();

  /// Одна покупка из потока магазина.
  @visibleForTesting
  Future<void> handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        outcome.value = StoreOutcome.pending;
        return;
      case PurchaseStatus.canceled:
        outcome.value = StoreOutcome.canceled;
        if (purchase.pendingCompletePurchase) await _complete(purchase);
        return;
      case PurchaseStatus.error:
        outcome.value = StoreOutcome.failed;
        if (purchase.pendingCompletePurchase) await _complete(purchase);
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        break;
    }
    try {
      final grant = await verify(
        StoreReceipt(
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'apple'
              : 'google',
          productId: purchase.productID,
          transactionId: purchase.purchaseID ?? '',
          verificationData: purchase.verificationData.serverVerificationData,
        ),
      );
      onGranted?.call(grant);
      outcome.value = StoreOutcome.granted;
      if (purchase.pendingCompletePurchase) await _complete(purchase);
    } on Object catch (error) {
      // Не закрываем: магазин пришлёт покупку снова, деньги не пропадут.
      debugPrint('[TeddyTales] чек не проверен: $error');
      outcome.value = StoreOutcome.notVerified;
    }
  }

  /// Закрыть покупку в магазине. В тестах подменяется.
  @visibleForTesting
  Future<void> Function(PurchaseDetails purchase)? completeOverride;

  Future<void> _complete(PurchaseDetails purchase) =>
      completeOverride?.call(purchase) ?? _store.completePurchase(purchase);

  void dispose() {
    _sub?.cancel();
    products.dispose();
    outcome.dispose();
  }
}

/// Что продаётся за `product_id` (сервер, `store_products`).
class StoreProduct {
  const StoreProduct({this.item, this.coins = 0});

  factory StoreProduct.fromJson(Map<String, dynamic> json) => StoreProduct(
    item: json['item'] as String?,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
  );

  /// Премиальный предмет, `null` — не предмет.
  final String? item;

  /// Монеты, 0 — не монеты.
  final int coins;
}

/// Чек для сервера.
class StoreReceipt {
  const StoreReceipt({
    required this.platform,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
  });

  final String platform;
  final String productId;
  final String transactionId;
  final String verificationData;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'productId': productId,
    'transactionId': transactionId,
    'verificationData': verificationData,
  };
}

/// Что выдал сервер.
class StoreGrant {
  const StoreGrant({
    this.item,
    this.coins = 0,
    this.balance,
    this.repeat = false,
  });

  factory StoreGrant.fromJson(Map<String, dynamic> json) => StoreGrant(
    item: json['item'] as String?,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt(),
    repeat: json['status'] == 'already',
  );

  final String? item;
  final int coins;
  final int? balance;

  /// Чек уже был проведён (повтор или восстановление).
  final bool repeat;
}

enum StoreOutcome { pending, canceled, failed, granted, notVerified }
