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
  }) {
    bear.onAction = _onAction;
    game.onBuy = buy;
    game.onLevelDone = (categoryId, level) =>
        unawaited(levelDone(categoryId, level));
    game.onPlace = (itemId, {required placed}) =>
        unawaited(place(itemId, placed: placed));
  }

  final ProgressStore store;
  final BearController bear;
  final GameState game;

  /// Вызывается после каждого успешного ответа сервера — например, чтобы
  /// положить свежий снимок в кеш на устройстве.
  final void Function(PetSnapshot snapshot)? onSnapshot;

  /// Действия, которые не доехали.
  final List<BearAction> _queue = [];

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
    BearAction.feed,
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
    _queue.add(action);
    unawaited(_drain());
  }

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
        final action = _queue.first;
        try {
          _apply(await store.recordCare(action));
        } on Object catch (error) {
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
    bear.restoreState(snapshot.state);
    game.setProfile(snapshot.profile);
    onSnapshot?.call(snapshot);
  }

  void _offline(Object error) {
    _online = false;
    debugPrint('[TeddyTales] действие не ушло: $error');
  }

  void dispose() {
    bear.onAction = null;
    game.onBuy = null;
    game.onLevelDone = null;
    game.onPlace = null;
    _queue.clear();
  }
}
