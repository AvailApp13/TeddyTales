import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/memory_store.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/backend/progress_store.dart';
import 'package:teddy_tales/backend/progress_sync.dart';
import 'package:teddy_tales/bear/bear_action.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_state.dart';
import 'package:teddy_tales/bear/bear_stats.dart';
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';

import 'bear_controller_test.dart' show FakeRig;

/// Хранилище-протокол: запоминает, что у него просили, и отвечает так, как
/// велено в тесте. Настоящий сервер для этих проверок не нужен — важно не
/// что он посчитает, а что мост отправит и как поступит с ответом.
class _FakeStore implements ProgressStore {
  _FakeStore({this.failing = false});

  bool failing;

  /// Отказ сервера кодом (например, TT402), а не обрыв связи.
  String? rejectWith;
  final List<String> dishes = [];
  final List<String> recipes = [];
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
  Future<PetSnapshot> feedDish(String dishId) async {
    if (failing) throw const ProgressStoreException('нет сети');
    final code = rejectWith;
    if (code != null) throw ProgressStoreException('отказ', code: code);
    dishes.add(dishId);
    return answer;
  }

  @override
  Future<PetSnapshot> completeRecipe(String recipeId) async {
    if (failing) throw const ProgressStoreException('нет сети');
    recipes.add(recipeId);
    return answer;
  }

  @override
  Future<void> deleteAccount() async {}

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

  int gifts = 0;

  @override
  Future<PetSnapshot> claimDailyGift() async {
    if (failing) throw const ProgressStoreException('нет сети');
    gifts++;
    return answer;
  }
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
    // Без добавки на испытания: здесь проверяется, что баланс приходит с
    // сервера как есть.
    walletFloor: 0,
  );
  final store = _FakeStore(failing: failing);
  final sync = ProgressSync(store: store, bear: bear, game: game);
  return (bear: bear, game: game, store: store, sync: sync);
}

void main() {
  group('Отправка прогресса на сервер (КП 1.4)', () {
    test('действие ухода уходит, откуда бы его ни позвали', () async {
      final it = _setUp();
      it.bear.washBear();
      await Future<void>.delayed(Duration.zero);
      expect(it.store.care, [BearAction.wash]);
    });

    test('тап по мишке тоже доезжает', () async {
      final it = _setUp();
      it.bear.petBear();
      await Future<void>.delayed(Duration.zero);
      expect(it.store.care, [BearAction.pet]);
    });

    test('порядок действий сохраняется', () async {
      final it = _setUp();
      it.bear.petBear();
      it.bear.washBear();
      it.bear.playWithBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(it.store.care, [BearAction.pet, BearAction.wash, BearAction.play]);
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
      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.game.coins, 999, reason: 'баланс берётся у сервера');
      expect(it.bear.stats.food, 77, reason: 'показатели тоже');
    });
  });

  group('Мишка взрослеет на сервере (КП 5.6, 5.7)', () {
    test('новая стадия с сервера идёт через переход взросления', () async {
      final it = _setUp();
      final rig = FakeRig();
      it.bear.attachRig(rig);
      // Сервер за время отсутствия дорастил новорождённого до «первых
      // шагов» — две ступени, два перехода.
      it.store.answer = PetSnapshot(
        petId: 'pet',
        profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
        state: const BearState(stage: BearStage.firstSteps),
        inventory: const {},
        placed: const {},
        eduProgress: const {},
        serverTime: DateTime.utc(2026, 9, 16),
        growth: GrowthOutlook(
          progress: 0.25,
          nextStageAt: DateTime.utc(2026, 9, 17, 12),
        ),
      );
      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.bear.state.stage, BearStage.firstSteps);
      expect(
        rig.firedNames.where((n) => n == BearRigSpec.trgStageUp),
        hasLength(2),
      );
      expect(it.game.growth.nextStageAt, DateTime.utc(2026, 9, 17, 12));
      // Главный экран покажет праздник новой стадии.
      expect(it.game.stageUp, BearStage.firstSteps);
    });

    test('сон и скорости с сервера доходят до игры и шкал', () async {
      final it = _setUp();
      it.store.answer = PetSnapshot(
        petId: 'pet',
        profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
        state: const BearState(),
        inventory: const {},
        placed: const {},
        eduProgress: const {},
        serverTime: DateTime.utc(2026, 9, 16),
        asleep: true,
        rates: const {'food': 2.5, 'sleep': -12, 'floor': 20},
      );
      it.bear.putToSleep(amount: 10);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.care, [BearAction.sleep]);
      expect(it.game.asleep, isTrue);
      expect(it.bear.decay.sleepPerSecond, closeTo(-12 / 3600, 1e-12));
    });

    test('подарок дня уходит на сервер', () async {
      final it = _setUp();
      expect(await it.game.claimGift(), isTrue);
      expect(it.store.gifts, 1);
    });

    test('та же стадия — без перехода', () async {
      final it = _setUp();
      final rig = FakeRig();
      it.bear.attachRig(rig);
      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rig.firedNames, isNot(contains(BearRigSpec.trgStageUp)));
    });
  });

  group('Когда сети нет (КП 1.1)', () {
    test('действия не теряются, а ждут в очереди', () async {
      final it = _setUp(failing: true);
      it.bear.petBear();
      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.care, isEmpty);
      expect(it.sync.pendingCount, 2);
      expect(it.sync.isOnline, isFalse);
    });

    test('накопленное уходит, когда связь вернулась', () async {
      final it = _setUp(failing: true);
      it.bear.washBear();
      it.bear.playWithBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      it.store.failing = false;
      await it.sync.retry();

      expect(it.store.care, [BearAction.wash, BearAction.play]);
      expect(it.sync.pendingCount, 0);
      expect(it.sync.isOnline, isTrue);
    });

    test('очередь не растёт бесконечно от одной неудачи', () async {
      final it = _setUp(failing: true);
      it.bear.washBear();
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

  group('Еда из кошелька кабинета (КП 8.2, 8.4)', () {
    test('блюдо уходит на сервер, а не как «покормил»', () async {
      final it = _setUp();
      it.game.earn(100);
      expect(it.game.feedWithDish(FoodCatalog.dishes.first), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.dishes, [FoodCatalog.dishes.first.id]);
      // Иначе сытость прибавилась бы дважды, а за «покормил» пришли бы
      // монеты вдобавок к списанию.
      expect(it.store.care, isEmpty);
      expect(it.game.coins, 100, reason: 'баланс — с сервера');
    });

    test('рецепт уходит на сервер, награду считает он', () async {
      final it = _setUp();
      it.game.completeRecipe(FoodCatalog.recipes.first);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.store.recipes, [FoodCatalog.recipes.first.id]);
      expect(it.store.care, isEmpty);
    });

    test('отказ сервера возвращает монеты и не держит очередь', () async {
      final it = _setUp();
      it.game.earn(50);
      it.store.rejectWith = ProgressStoreException.notEnoughCoins;

      it.game.feedWithDish(FoodCatalog.dishes.first);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(it.game.coins, 50, reason: 'монеты вернулись');
      expect(it.sync.pendingCount, 0);
      expect(it.sync.isOnline, isTrue, reason: 'отказ — не обрыв связи');

      it.bear.washBear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(it.store.care, [BearAction.wash], reason: 'очередь идёт дальше');
    });

    test('без сети блюдо ждёт в очереди, монеты не возвращаются', () async {
      final it = _setUp(failing: true);
      it.game.earn(50);
      final price = FoodCatalog.dishes.first.price;

      it.game.feedWithDish(FoodCatalog.dishes.first);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(it.sync.pendingCount, 1);
      expect(it.game.coins, 50 - price);

      it.store.failing = false;
      await it.sync.retry();
      expect(it.store.dishes, [FoodCatalog.dishes.first.id]);
    });
  });

  test('гость без сети: покупка остаётся, на сервер не идёт', () async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тишка', birthAt: DateTime.utc(2026, 9, 1)),
    );
    final store = _FakeStore(failing: true);
    ProgressSync(store: store, bear: bear, game: game, localOnly: true);

    expect(game.buy('table'), isTrue);
    expect(game.buy('dresser'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(game.isOwned('table'), isTrue);
    expect(game.isOwned('dresser'), isTrue);
    expect(store.bought, isEmpty);
  });

  test('после dispose мост больше не слушает', () async {
    final it = _setUp();
    it.sync.dispose();
    it.bear.washBear();
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

    bear.washBear();
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
