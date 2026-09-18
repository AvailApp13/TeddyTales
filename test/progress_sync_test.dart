import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/memory_store.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/backend/progress_store.dart';
import 'package:teddy_tales/backend/progress_sync.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/bear/bear_state.dart';
import 'package:teddy_tales/bear/bear_stats.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';

/// Хранилище-протокол: запоминает, что у него просили, и отвечает так, как
/// велено в тесте. Настоящий сервер для этих проверок не нужен — важно не
/// что он посчитает, а что мост отправит и как поступит с ответом.
class _FakeStore implements ProgressStore {
  _FakeStore({this.failing = false});

  bool failing;
  final List<BearAction> care = [];
  final List<String> bought = [];
  final List<(String, int)> levels = [];
  final List<(String, bool)> placed = [];

  PetSnapshot answer = _snapshotWith(coins: 100);

  @override
  bool get isSignedIn => true;

  @override
  Future<void> signIn() async {}

  @override
  Future<PetSnapshot> load() async => answer;

  @override
  Future<PetSnapshot> recordCare(BearAction action) async {
    if (failing) throw const ProgressStoreException('нет сети');
    care.add(action);
    return answer;
  }

  @override
  Future<PetSnapshot> buyItem(String itemId) async {
    if (failing) throw const ProgressStoreException('нет сети');
    bought.add(itemId);
    return answer;
  }

  @override
  Future<PetSnapshot> completeLevel(String categoryId, int level) async {
    if (failing) throw const ProgressStoreException('нет сети');
    levels.add((categoryId, level));
    return answer;
  }

  @override
  Future<PetSnapshot> renamePet(String name, {String locale = 'ru'}) async =>
      answer;

  @override
  Future<void> setPlaced(String itemId, {required bool placed}) async {
    if (failing) throw const ProgressStoreException('нет сети');
    this.placed.add((itemId, placed));
  }

  @override
  Future<Map<String, dynamic>> config() async => const {};
}

PetSnapshot _snapshotWith({required int coins}) => PetSnapshot(
  petId: 'pet',
  profile: PetProfile(
    name: 'Тишка',
    birthAt: DateTime.utc(2026, 9, 1),
    coins: coins,
  ),
  state: const BearState(stats: BearCareStats(food: 77)),
  inventory: const {},
  placed: const {},
  eduProgress: const {},
  serverTime: DateTime.utc(2026, 9, 16),
);

({BearController bear, GameState game, _FakeStore store, ProgressSync sync})
_setUp({bool failing = false}) {
  final bear = BearController();
  final game = GameState(
    bear: bear,
    profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
  );
  final store = _FakeStore(failing: failing);
  final sync = ProgressSync(store: store, bear: bear, game: game);
  return (bear: bear, game: game, store: store, sync: sync);
}

void main() {
  group('Отправка прогресса на сервер (КП 1.4)', () {
    test('действие ухода уходит, откуда бы его ни позвали', () async {
      final it = _setUp();
      it.bear.feedBear();
      await Future<void>.delayed(Duration.zero);
      expect(it.store.care, [BearAction.feed]);
    });

    test('тап по мишке тоже доезжает', () async {
      final it = _setUp();
      it.bear.petBear();
      await Future<void>.delayed(Duration.zero);
      expect(it.store.care, [BearAction.pet]);
    });

    test('порядок действий сохраняется', () async {
      final it = _setUp();
      it.bear.feedBear();
      it.bear.washBear();
      it.bear.playWithBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(it.store.care, [
        BearAction.feed,
        BearAction.wash,
        BearAction.play,
      ]);
    });

    test('обучение идёт своим путём, а не как уход', () async {
      final it = _setUp();
      it.game.completeLevel('colors', 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.levels, [('colors', 2)]);
      // Иначе монеты за уровень начислились бы дважды.
      expect(it.store.care, isNot(contains(BearAction.learn)));
    });

    test('ответ сервера главнее локального состояния', () async {
      final it = _setUp();
      it.store.answer = _snapshotWith(coins: 999);
      it.bear.feedBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.game.coins, 999, reason: 'баланс берётся у сервера');
      expect(it.bear.stats.food, 77, reason: 'показатели тоже');
    });
  });

  group('Когда сети нет (КП 1.1)', () {
    test('действия не теряются, а ждут в очереди', () async {
      final it = _setUp(failing: true);
      it.bear.feedBear();
      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.care, isEmpty);
      expect(it.sync.pendingCount, 2);
      expect(it.sync.isOnline, isFalse);
    });

    test('накопленное уходит, когда связь вернулась', () async {
      final it = _setUp(failing: true);
      it.bear.feedBear();
      it.bear.playWithBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      it.store.failing = false;
      await it.sync.retry();

      expect(it.store.care, [BearAction.feed, BearAction.play]);
      expect(it.sync.pendingCount, 0);
      expect(it.sync.isOnline, isTrue);
    });

    test('очередь не растёт бесконечно от одной неудачи', () async {
      final it = _setUp(failing: true);
      it.bear.feedBear();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Одна попытка — одно действие в очереди, без лавины повторов.
      expect(it.sync.pendingCount, 1);
    });
  });

  group('Покупка (КП 11.1)', () {
    test('успешная покупка подтверждается сервером', () async {
      final it = _setUp();
      it.game.earn(500);
      // Предмет намеренно не из стартового набора: то, что уже принадлежит
      // игроку, купить нельзя, и проверка прошла бы вхолостую.
      final ok = it.game.buy('table');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ok, isTrue);
      expect(it.store.bought, ['table']);
      expect(it.game.isOwned('table'), isTrue);
    });

    test('отказ сервера откатывает покупку', () async {
      final it = _setUp(failing: true);
      it.game.earn(500);
      final before = it.game.coins;

      it.game.buy('table');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        it.game.isOwned('table'),
        isFalse,
        reason: 'предмет, которого сервер не дал, оставлять нельзя',
      );
      expect(it.game.coins, before, reason: 'монеты вернулись');
    });
  });

  test('после dispose мост больше не слушает', () async {
    final it = _setUp();
    it.sync.dispose();
    it.bear.feedBear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(it.store.care, isEmpty);
  });

  test('снимок отдаётся наружу для кеша', () async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
    );
    final saved = <PetSnapshot>[];
    ProgressSync(
      store: _FakeStore(),
      bear: bear,
      game: game,
      onSnapshot: saved.add,
    );

    bear.feedBear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(saved, hasLength(1));
  });

  test('хранилище в памяти подходит мосту как есть', () async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
    );
    final sync = ProgressSync(store: MemoryStore(), bear: bear, game: game);

    bear.feedBear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(sync.pendingCount, 0, reason: 'память принимает всё');
  });
}
