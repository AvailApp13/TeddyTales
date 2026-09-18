import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/memory_store.dart';
import 'package:teddy_tales/backend/progress_store.dart';
import 'package:teddy_tales/bear/bear_action.dart';

void main() {
  group('Работа без сети (КП 1.1)', () {
    test('вход проходит и без сервера', () async {
      final store = MemoryStore();
      expect(store.isSignedIn, isFalse);
      await store.signIn();
      expect(store.isSignedIn, isTrue);
    });

    test('действия ухода копятся, а не теряются', () async {
      final store = MemoryStore();
      await store.recordCare(BearAction.feed);
      await store.recordCare(BearAction.wash);
      await store.recordCare(BearAction.feed);

      // Порядок важен: «покормить, потом умыть» и «умыть, потом
      // покормить» дают разный итог по показателям.
      expect(store.pending, [
        BearAction.feed,
        BearAction.wash,
        BearAction.feed,
      ]);
    });

    test('монеты за накопленные действия локально не начисляются', () async {
      final store = MemoryStore();
      final before = (await store.load()).profile.coins;
      await store.recordCare(BearAction.feed);
      expect((await store.load()).profile.coins, before);
    });

    test('покупка без сети отклоняется, а не выдаётся в долг', () async {
      final store = MemoryStore();
      expect(
        () => store.buyItem('bed'),
        throwsA(isA<ProgressStoreException>()),
      );
    });

    test('пройденный уровень запоминается как действие', () async {
      final store = MemoryStore();
      await store.completeLevel('colors', 0);
      expect(store.pending, [BearAction.learn]);
    });

    test('обстановка комнаты меняется локально', () async {
      final store = MemoryStore();
      await store.setPlaced('lamp', placed: true);
      expect((await store.load()).placed, contains('lamp'));

      await store.setPlaced('lamp', placed: false);
      expect((await store.load()).placed, isNot(contains('lamp')));
    });

    test('принятый снимок становится текущим состоянием', () async {
      final store = MemoryStore();
      final saved = MemoryStore.emptySnapshot();
      store.adopt(saved);
      expect((await store.load()).petId, saved.petId);
    });
  });
}
