import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bear/bear_action.dart';
import '../bear/bear_controller.dart';
import '../game/game_state.dart';
import 'pet_snapshot.dart';
import 'progress_store.dart';

/// Отправляет действия игрока на сервер и применяет то, что он ответил.
///
/// До этого класса мост был односторонним: прогресс грузился при старте, но
/// обратно не уезжал ничего — покормил мишку, закрыл приложение, и всё
/// заново. Здесь вторая половина.
///
/// ## Что уходит на сервер
///
/// Действия ухода и обучение. Переодевание и расстановка мебели тоже
/// записываются, но своим путём — они меняют не показатели, а имущество.
///
/// Действие `learn` через общий путь НЕ отправляется. Иначе монеты за
/// уровень начислялись бы дважды: один раз серверной функцией обучения,
/// второй — как обычное событие ухода.
///
/// Кормление `feed` — тоже: мишку кормят блюдом за монеты или рецептом, и
/// сытость с деньгами считают их собственные функции (feed_dish,
/// complete_recipe). Отправь его ещё и как уход — сытость прибавилась бы
/// дважды, а монеты за «покормил» пришли бы вдобавок к списанию за блюдо.
///
/// ## Когда сети нет
///
/// Действие кладётся в очередь и ждёт. Показатели при этом двигает локальный
/// контроллер, так что мишка ведёт себя живо, а монеты не начисляются: их
/// считает только сервер (КП 11.1), и нарисовать их авансом значит отобрать
/// при следующем входе.
///
/// Очередь отправляется по порядку. «Покормить, потом умыть» и «умыть,
/// потом покормить» дают разный итог, и переставлять их местами нельзя.
class ProgressSync {
  ProgressSync({
    required this.store,
    required this.bear,
    required this.game,
    this.onSnapshot,
    this.localOnly = false,
  }) {
    bear.onAction = _onAction;
    // Гость без аккаунта и без сети (так открывается и приложение в панели
    // заказчика — там нет выхода в интернет): покупки и еда проводятся на
    // телефоне, как до сервера. Сверять их не с кем, а отказ «нет сети»
    // откатывал бы каждую покупку у него на глазах. У кого есть аккаунт —
    // деньги только через сервер (КП 11.1).
    if (!localOnly) {
      game.onBuy = buy;
      game.onDish = dish;
      game.onRecipe = (recipeId) => unawaited(recipe(recipeId));
    }
    game.onLevelDone = (categoryId, level) =>
        unawaited(levelDone(categoryId, level));
    game.onClaimGift = claimGift;
    game.onPlace = (itemId, {required placed}) =>
        unawaited(place(itemId, placed: placed));
  }

  final ProgressStore store;
  final BearController bear;
  final GameState game;

  /// Играть без сервера: гость без аккаунта и без сети.
  final bool localOnly;

  /// Вызывается после каждого успешного ответа сервера — например, чтобы
  /// положить свежий снимок в кеш на устройстве.
  final void Function(PetSnapshot snapshot)? onSnapshot;

  /// Действия, которые не доехали. Уход, блюда и рецепты — в одной
  /// очереди: все они двигают одну и ту же сытость.
  final List<_Job> _queue = [];

  /// Отправка идёт по одному: два одновременных вызова серверных функций
  /// пересчитывают показатели от одного и того же замера, и эффект второго
  /// теряется.
  bool _sending = false;

  /// Было ли последнее обращение удачным. По нему интерфейс может показать,
  /// что работает без сети.
  bool get isOnline => _online;
  bool _online = true;

  int get pendingCount => _queue.length;

  /// Действия, которые сервер учитывает как уход (КП 6.4).
  static const Set<BearAction> _careActions = {
    BearAction.wash,
    BearAction.sleep,
    BearAction.wake,
    BearAction.play,
    BearAction.pet,
    BearAction.dressUp,
    BearAction.decorate,
  };

  void _onAction(BearAction action) {
    if (!_careActions.contains(action)) return;
    _enqueue(_Job((store) => store.recordCare(action)));
  }

  Future<bool> _enqueue(_Job job) {
    _queue.add(job);
    unawaited(_drain());
    return job.done.future;
  }

  /// Блюдо за монеты (КП 8.2). `true` — сервер списал и накормил, `false`
  /// — отказал (не хватило монет, нет такого блюда).
  ///
  /// Без связи ответ ждёт, пока блюдо не уедет: монеты уже списаны на
  /// экране, и вернуть их можно только по отказу сервера.
  Future<bool> dish(String dishId) =>
      _enqueue(_Job((store) => store.feedDish(dishId)));

  /// Приготовленный рецепт (КП 8.4): награду начисляет сервер.
  Future<bool> recipe(String recipeId) =>
      _enqueue(_Job((store) => store.completeRecipe(recipeId)));

  /// Сообщает о пройденном уровне обучения (КП 9.5).
  ///
  /// Отдельно от очереди: награду считает своя функция, и порядок с
  /// действиями ухода тут не важен.
  Future<void> levelDone(String categoryId, int level) async {
    try {
      _apply(await store.completeLevel(categoryId, level));
    } on Object catch (error) {
      _offline(error);
    }
  }

  /// Подарок дня (миграция 0017). `false` — уже забран или нет связи.
  Future<bool> claimGift() async {
    try {
      _apply(await store.claimDailyGift());
      return true;
    } on Object catch (error) {
      _offline(error);
      return false;
    }
  }

  /// Покупка предмета (КП 11.1). Возвращает `false`, если сервер отказал —
  /// не хватило монет или предмет уже куплен.
  Future<bool> buy(String itemId) async {
    try {
      _apply(await store.buyItem(itemId));
      return true;
    } on Object catch (error) {
      _offline(error);
      return false;
    }
  }

  /// Переименовывает питомца (КП 2.3).
  ///
  /// Возвращает `null`, если сервер имя принял, иначе — что с ним не так.
  /// Локально имя не меняем до ответа: в отличие от покупки, здесь нечего
  /// откатывать красиво — человек увидел бы новое имя, а через секунду
  /// старое, и не понял бы, приняли его или нет.
  Future<String?> rename(String name) async {
    try {
      _apply(await store.renamePet(name));
      return null;
    } on Object catch (error) {
      _offline(error);
      return error.toString();
    }
  }

  /// Ставит предмет в комнату или убирает (КП 10.7).
  Future<void> place(String itemId, {required bool placed}) async {
    try {
      await store.setPlaced(itemId, placed: placed);
      _online = true;
    } on Object catch (error) {
      _offline(error);
    }
  }

  Future<void> _drain() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.first;
        try {
          _apply(await job.send(store));
          job.done.complete(true);
        } on Object catch (error) {
          if (error is ProgressStoreException && error.isRejected) {
            // Сервер ответил отказом. Повтор не поможет — убираем и идём
            // дальше, а тот, кто ждёт ответа, откатит своё.
            debugPrint('[TeddyTales] сервер отказал: $error');
            _online = true;
            job.done.complete(false);
            _queue.removeAt(0);
            continue;
          }
          // Не вышло — оставляем действие в очереди и прекращаем попытки.
          // Повторять сразу бессмысленно: если сети нет, она не появится
          // за миллисекунду, а очередь при этом разрослась бы до сотен
          // запросов, которые все разом уйдут при возвращении связи.
          _offline(error);
          return;
        }
        _queue.removeAt(0);
      }
    } finally {
      _sending = false;
    }
  }

  /// Пробует отправить накопленное. Зовётся, когда приложение вернулось из
  /// фона: связь к этому моменту часто уже есть.
  Future<void> retry() => _drain();

  void _apply(PetSnapshot snapshot) {
    _online = true;
    // Состояние с сервера главнее локального: показатели он пересчитал по
    // своим часам (КП 1.5), монеты начислил по своим правилам.
    // Сервер вырастил мишку (КП 5.6): стадия меняется не молча, а через
    // переход взросления — риг получает `trg_stage_up` на каждую ступень.
    final before = bear.state.stage;
    final after = snapshot.state.stage;
    if (after.riveValue > before.riveValue) {
      bear.restoreState(snapshot.state.copyWith(stage: before));
      while (bear.state.stage.riveValue < after.riveValue) {
        if (!bear.growUp()) break;
      }
      game.celebrateStage(after);
    } else {
      bear.restoreState(snapshot.state);
    }
    game.setProfile(snapshot.profile);
    game.setAccount(snapshot.account);
    game.setGrowth(snapshot.growth);
    game.setAsleep(snapshot.asleep);
    if (!snapshot.daily.isEmpty) game.setDaily(snapshot.daily);
    // Шкалы между ответами идут с теми скоростями, что прислал сервер:
    // во сне медленнее, у малыша быстрее (миграция 0016).
    if (snapshot.decay case final decay?) bear.setDecayConfig(decay);
    onSnapshot?.call(snapshot);
  }

  void _offline(Object error) {
    _online = false;
    debugPrint('[TeddyTales] действие не ушло: $error');
  }

  void dispose() {
    bear.onAction = null;
    game.onBuy = null;
    game.onDish = null;
    game.onRecipe = null;
    game.onLevelDone = null;
    game.onPlace = null;
    game.onClaimGift = null;
    _queue.clear();
  }
}

/// Одно отправление на сервер и тот, кто ждёт его итога.
class _Job {
  _Job(this.send);

  final Future<PetSnapshot> Function(ProgressStore store) send;
  final Completer<bool> done = Completer<bool>();
}
