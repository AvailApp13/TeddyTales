import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:teddy_tales/backend/store_purchases.dart';

/// Покупки за деньги (КП 11.3): покупку закрываем только после того, как
/// сервер проверил чек и выдал её.
void main() {
  PurchaseDetails purchase(PurchaseStatus status) => PurchaseDetails(
    purchaseID: 'T1',
    productID: 'premium.sofa',
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'app_store',
    ),
    transactionDate: '0',
    status: status,
  )..pendingCompletePurchase = true;

  StorePurchases make({
    required Future<StoreGrant> Function(StoreReceipt) verify,
    List<StoreGrant>? granted,
    List<String>? completed,
  }) {
    final store = StorePurchases(
      verify: verify,
      catalog: () async => const {},
      onGranted: granted?.add,
    )..completeOverride = (p) async => completed?.add(p.productID);
    addTearDown(store.dispose);
    return store;
  }

  test('куплено → чек на сервер → выдано → покупка закрыта', () async {
    final receipts = <StoreReceipt>[];
    final granted = <StoreGrant>[];
    final completed = <String>[];
    final store = make(
      verify: (r) async {
        receipts.add(r);
        return const StoreGrant(item: 'sofa', balance: 120);
      },
      granted: granted,
      completed: completed,
    );
    await store.handle(purchase(PurchaseStatus.purchased));
    expect(receipts.single.productId, 'premium.sofa');
    expect(receipts.single.transactionId, 'T1');
    expect(receipts.single.verificationData, 'server');
    expect(granted.single.item, 'sofa');
    expect(completed, ['premium.sofa']);
    expect(store.outcome.value, StoreOutcome.granted);
  });

  test('сервер не проверил — покупка остаётся открытой', () async {
    final completed = <String>[];
    final store = make(
      verify: (_) async => throw Exception('offline'),
      completed: completed,
    );
    await store.handle(purchase(PurchaseStatus.restored));
    expect(completed, isEmpty);
    expect(store.outcome.value, StoreOutcome.notVerified);
  });

  test('отмена — без сервера, закрыта', () async {
    var asked = 0;
    final completed = <String>[];
    final store = make(
      verify: (_) async {
        asked++;
        return const StoreGrant();
      },
      completed: completed,
    );
    await store.handle(purchase(PurchaseStatus.canceled));
    expect(asked, 0);
    expect(completed, ['premium.sofa']);
    expect(store.outcome.value, StoreOutcome.canceled);
  });

  test('ответ сервера: повтор чека', () {
    final grant = StoreGrant.fromJson({
      'status': 'already',
      'item': 'sofa',
      'coins': 0,
      'balance': 90,
    });
    expect(grant.repeat, isTrue);
    expect(grant.balance, 90);
    expect(StoreProduct.fromJson({'coins': 500}).coins, 500);
  });
}
