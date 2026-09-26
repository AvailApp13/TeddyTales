import 'package:flutter/foundation.dart';

import '../bear/bear_action.dart';
import '../bear/bear_controller.dart';
import '../bear/bear_rig_spec.dart' show BearStage;
import '../backend/pet_snapshot.dart'
    show AccountInfo, DailyInfo, GrowthOutlook;
import 'learning_content.dart' show eduContent, eduLevelsPerCategory;
import '../bear/bear_state.dart';
import 'food.dart';
import 'pet_profile.dart';
import 'referral_info.dart';
import 'shop_items.dart';
import 'test_stubs.dart';

export 'test_stubs.dart' show kTestWallet;

/// Состояние игры вокруг персонажа: кошелёк, инвентарь, обстановка комнаты,
/// прогресс обучения, настройки уведомлений.
///
/// Персонаж живёт отдельно, в [BearController] — этот класс на него ссылается и
/// дёргает, но своим состоянием не подменяет. Граница простая: всё, что уезжает
/// в риг, принадлежит контроллеру; всё остальное — здесь.
///
/// Хранится пока только в памяти. По КП 1.4 прогресс лежит на сервере и
/// восстанавливается на новом устройстве; backend выбран (Supabase), но не
/// подключён.

class GameState extends ChangeNotifier {
  GameState({
    required this.bear,
    required PetProfile profile,
    Set<String>? owned,
    Set<String>? placed,
    int walletFloor = kTestWallet,
    AccountInfo? account,
  }) : _account = account,
       // Не «выдать 5000», а «поднять до 5000»: если на счету больше —
       // например, заработано или пришло с сервера, — отнимать нельзя.
       //
       // Порог берётся параметром, а не константой напрямую: тесты про
       // нехватку монет иначе проверяли бы не то — с полным кошельком не
       // бывает «денег не хватило».
       _walletFloor = walletFloor,
       _profile = _floored(profile, walletFloor),
       // Наборы копируются, а не берутся как есть: снаружи легко прилетает
       // неизменяемый (`const {}` из теста, `Set.unmodifiable` из ответа
       // сервера), и первая же покупка падала бы на попытке в него
       // дописать.
       _owned = {...owned ?? _startingItems},
       // Дефолт — ПУСТАЯ сцена: только стены и пол, без мебели. Решение
       // заказчика: предметы не ставить заранее, герой один в кадре, а
       // комнату каждый собирает сам через раздел «Комната».
       _placed = {
         ...placed ?? const {'wall_rose', 'floor_wood'},
       };

  /// Что даётся бесплатно на старте. КП 10.8: 12 предметов бесплатно.
  static const Set<String> _startingItems = {
    'bed',
    'rug',
    'lamp',
    'basket',
    'wall_rose',
    'floor_wood',
    'pillow_heart',
    'plant',
    'ball',
    'duck',
    'cubes',
    'out_yellow',
  };

  final BearController bear;

  // --- Точки подключения к серверу (КП 1.4) --------------------------------
  //
  // Не ссылка на хранилище, а колбэки, потому что порядок создания обратный:
  // сначала состояние игры, потом мост к серверу, который на него
  // подписывается. Со ссылкой получилось бы кольцо.
  //
  // Пока они не заданы — игра работает сама по себе, как работала до
  // появления сервера. Это и есть поведение в офлайне.

  /// Покупка предмета. Возвращает `false`, если сервер отказал.
  Future<bool> Function(String itemId)? onBuy;

  /// Блюдо за монеты. Возвращает `false`, если сервер отказал.
  Future<bool> Function(String dishId)? onDish;

  /// Приготовленный рецепт: награду начисляет сервер.
  void Function(String recipeId)? onRecipe;

  /// Пройденный уровень обучения.
  void Function(String categoryId, int level)? onLevelDone;

  /// Предмет поставлен в комнату или убран.
  void Function(String itemId, {required bool placed})? onPlace;

  final int _walletFloor;
  PetProfile _profile;
  final Set<String> _owned;

  static PetProfile _floored(PetProfile profile, int floor) =>
      profile.coins < floor ? profile.copyWith(coins: floor) : profile;
  final Set<String> _placed;

  /// Что в каком месте стоит: ключ — id слота, значение — id вещи.
  ///
  /// [_placed] остаётся как «что вообще выставлено» — на него смотрят
  /// магазин и комната, и он же уходит на сервер. Слоты — это где именно.
  final Map<String, String> _slots = {};

  final Map<String, int> _eduProgress = {};
  final Map<String, bool> _notifications = {
    for (final k in NotificationKind.values) k.id: k.onByDefault,
  };
  bool _quietHours = true;

  /// Возраст игрока. `null` — ещё не спрашивали; раздел игр спросит при
  /// первом входе. Хранится только в профиле и выбирает набор контента
  /// (см. `lib/game/audience.dart`). ЗАГЛУШКА по хранению: слоя сохранения
  /// у приложения пока нет вообще, с его появлением возраст уедет туда же,
  /// куда кошелёк и прогресс.
  int? _playerAge;

  /// Личный кабинет: как вошёл, почта, когда зарегистрирован. `null` —
  /// сервера не было (офлайн), показывать нечего.
  AccountInfo? get account => _account;
  AccountInfo? _account;

  void setAccount(AccountInfo account) {
    _account = account;
    notifyListeners();
  }

  /// Прогноз роста с сервера (КП 5.6, 5.7): для уведомления «Новая
  /// стадия» (КП 13.1). Без сервера — пустой.
  GrowthOutlook get growth => _growth;
  GrowthOutlook _growth = const GrowthOutlook();

  void setGrowth(GrowthOutlook growth) {
    _growth = growth;
    notifyListeners();
  }

  /// Подарок дня, задания дня и недели (миграция 0017).
  DailyInfo get daily => _daily;
  DailyInfo _daily = const DailyInfo();

  void setDaily(DailyInfo daily) {
    _daily = daily;
    notifyListeners();
  }

  /// Забрать подарок дня на сервере. `null` — связи с сервером нет.
  Future<bool> Function()? onClaimGift;

  Future<bool> claimGift() async => await onClaimGift?.call() ?? false;

  /// Выкупить вчерашний пропуск подарка дня за монеты (миграция 0023).
  Future<RestoreResult> Function()? onRestoreStreak;

  Future<RestoreResult> restoreStreak() async =>
      await onRestoreStreak?.call() ?? RestoreResult.failed;

  /// Идёт первый запуск: «Родился малыш!», имя, «Тебя пригласил друг?».
  /// Пока `true`, остальные окна (подарок дня, праздник монет) ждут —
  /// не открываются поверх.
  final ValueNotifier<bool> onboarding = ValueNotifier(false);

  @override
  void dispose() {
    onboarding.dispose();
    super.dispose();
  }

  /// «Пригласи друга» (миграция 0021). `null` — нет аккаунта или связи.
  Future<ReferralInfo?> Function()? onReferral;
  Future<RedeemResult> Function(String code)? onRedeemReferral;

  Future<ReferralInfo?> referral() async => await onReferral?.call();

  Future<RedeemResult> redeemReferral(String code) async =>
      await onRedeemReferral?.call(code) ?? RedeemResult.offline;

  /// Мишка подрос на сервере: на какую стадию. Главный экран показывает
  /// праздник и сбрасывает.
  BearStage? stageUp;

  void celebrateStage(BearStage stage) {
    stageUp = stage;
    notifyListeners();
  }

  /// Долго не заходил — мишка гостил у бабушки (миграция 0016). Главный
  /// экран один раз показывает встречу и сбрасывает флаг.
  bool welcomeBack = false;

  /// Спит ли мишка (сервер, миграция 0016): уложили — спит, пока не
  /// разбудят, не займутся им или не выспится сам.
  bool get asleep => _asleep;
  bool _asleep = false;

  void setAsleep(bool asleep) {
    if (asleep == _asleep) return;
    _asleep = asleep;
    notifyListeners();
  }

  PetProfile get profile => _profile;
  int get coins => _profile.coins;

  Set<String> get owned => Set.unmodifiable(_owned);
  Set<String> get placed => Set.unmodifiable(_placed);
  bool get quietHours => _quietHours;

  bool isOwned(String id) => _owned.contains(id);
  bool isPlaced(String id) => _placed.contains(id);

  /// Что стоит в этом месте. `null` — место свободно.
  String? itemInSlot(String slotId) => _slots[slotId];

  /// В каком месте стоит эта вещь. `null` — нигде.
  String? slotOf(String itemId) {
    for (final entry in _slots.entries) {
      if (entry.value == itemId) return entry.key;
    }
    return null;
  }

  Map<String, String> get slots => Map.unmodifiable(_slots);

  /// Ставит вещь в место. Вещь, которая там стояла, возвращается в
  /// инвентарь: место одно, и две вещи в нём не помещаются.
  ///
  /// Вещь, стоящая в другом месте, переезжает сюда — не раздваивается.
  void placeInSlot(String slotId, String itemId) {
    if (!isOwned(itemId)) return;

    final previous = _slots[slotId];
    if (previous == itemId) return;

    if (previous != null) {
      _placed.remove(previous);
      onPlace?.call(previous, placed: false);
    }

    final from = slotOf(itemId);
    if (from != null) _slots.remove(from);

    _slots[slotId] = itemId;
    _placed.add(itemId);

    bear.recordAction(BearAction.decorate);
    onPlace?.call(itemId, placed: true);
    notifyListeners();
  }

  /// Освобождает место.
  void clearSlot(String slotId) {
    final itemId = _slots.remove(slotId);
    if (itemId == null) return;

    _placed.remove(itemId);
    bear.recordAction(BearAction.decorate);
    onPlace?.call(itemId, placed: false);
    notifyListeners();
  }

  bool isNotificationOn(String id) => _notifications[id] ?? false;

  /// Сколько уровней категории пройдено (КП 9.2, по 10 на категорию).
  int eduProgress(String categoryId) => _eduProgress[categoryId] ?? 0;

  /// Остались ли непройденные уровни обучения — тогда есть о чём напомнить
  /// уведомлением «Задание» (КП 13.1).
  bool get hasLearningLeft =>
      eduContent.keys.any((id) => eduProgress(id) < eduLevelsPerCategory);

  int? get playerAge => _playerAge;

  void setPlayerAge(int age) {
    _playerAge = age.clamp(1, 120);
    notifyListeners();
  }

  // --- Кошелёк (КП 11.1) ---------------------------------------------------

  void earn(int amount) {
    if (amount <= 0) return;
    _profile = _profile.copyWith(coins: _profile.coins + amount);
    notifyListeners();
  }

  /// Возвращает `false`, если монет не хватило.
  bool spend(int amount) {
    if (amount <= 0 || _profile.coins < amount) return false;
    _profile = _profile.copyWith(coins: _profile.coins - amount);
    notifyListeners();
    return true;
  }

  /// Профиль с сервера. Порог кошелька держится и здесь: сервер про
  /// добавку на испытания не знает и присылал ноль после первой покупки.
  void setProfile(PetProfile profile) {
    _profile = _floored(profile, _walletFloor);
    notifyListeners();
  }

  // --- Еда (КП 8) ----------------------------------------------------------

  /// Покормить готовым блюдом. Возвращает `false`, если не хватило монет.
  ///
  /// Как и покупка предмета: на экране списывается сразу, чтобы мишка ел
  /// без задержки, а сервер списывает с кошелька кабинета по своей цене и
  /// присылает настоящий баланс (КП 11.1).
  bool feedWithDish(Dish dish) {
    if (!spend(dish.price)) return false;
    bear.feedBear(amount: dish.foodGain);

    onDish?.call(dish.id).then((ok) {
      // Сервер отказал — монеты возвращаем. Сытость поправит следующий
      // ответ сервера: съеденное на экране не отбираем.
      if (!ok) earn(dish.price);
    });
    return true;
  }

  /// Успешно приготовленное блюдо: награда монетами и кормление.
  void completeRecipe(Recipe recipe) {
    earn(recipe.reward);
    bear.feedBear(amount: recipe.foodGain);
    onRecipe?.call(recipe.id);
  }

  // --- Магазин (КП 11.2) ---------------------------------------------------

  /// Покупка предмета. Корзины нет (заказчик 24.09): каждая вещь
  /// покупается отдельно, после окна подтверждения.
  ///
  /// Списание идёт локально сразу, чтобы кнопка отвечала без задержки, а
  /// сервер подтверждает следом и присылает настоящий баланс. Цену он берёт
  /// свою (КП 11.1): присланная клиентом — это предложение купить слона за
  /// рубль.
  bool buy(String id) {
    final item = ItemCatalog.byId(id);
    if (isOwned(id) || !spend(item.price)) return false;
    _owned.add(id);
    notifyListeners();

    final ask = onBuy;
    if (ask != null) {
      ask(id).then((ok) {
        if (ok) return;
        // Сервер отказал: возвращаем как было, иначе игрок унесёт предмет,
        // которого у него нет, и увидит откат при следующем запуске.
        _owned.remove(id);
        earn(item.price);
      });
    }
    return true;
  }

  // --- Комната (КП 10.7) ---------------------------------------------------

  /// Ставит или убирает предмет. Обои и пол — единственные в своём роде,
  /// поэтому выбор одного снимает предыдущий.
  void togglePlaced(String id) {
    if (!isOwned(id)) return;

    final item = ItemCatalog.byId(id);
    if (item.kind == ItemKind.wallpaper || item.kind == ItemKind.floor) {
      _placed.removeWhere((other) => ItemCatalog.byId(other).kind == item.kind);
      _placed.add(id);
    } else if (!_placed.remove(id)) {
      _placed.add(id);
    }

    bear.recordAction(BearAction.decorate);
    onPlace?.call(id, placed: _placed.contains(id));
    notifyListeners();
  }

  /// Меняет одну вещь на другую на том же месте.
  ///
  /// Не то же самое, что «убрать» и следом «поставить». Во-первых, комната
  /// не должна мигнуть пустым местом посередине: для игрока это одно
  /// действие. Во-вторых, если новая вещь ещё не куплена и денег не хватает,
  /// старая обязана остаться на месте — иначе человек теряет то, что у него
  /// было, за попытку посмотреть другое.
  ///
  /// Возвращает `false`, если замена не состоялась.
  bool replacePlaced(String oldId, String newId) {
    if (oldId == newId) return false;
    if (!isOwned(newId) && !buy(newId)) return false;

    _placed
      ..remove(oldId)
      ..add(newId);

    bear.recordAction(BearAction.decorate);
    onPlace?.call(oldId, placed: false);
    onPlace?.call(newId, placed: true);
    notifyListeners();
    return true;
  }

  // --- Гардероб (КП 10.6) --------------------------------------------------

  /// Надевает или снимает вещь. Правило взаимного исключения комплекта и
  /// раздельных вещей живёт в [BearOutfit].
  void toggleWorn(String id) {
    if (!isOwned(id)) return;

    final item = ItemCatalog.byId(id);
    if (!item.kind.isWearable) return;

    final current = bear.state.outfit;
    final next = item.isWornIn(current)
        ? _clearSlot(current, item.kind)
        : item.applyTo(current);

    bear.setOutfit(next);
    bear.recordAction(BearAction.dressUp);
    notifyListeners();
  }

  BearOutfit _clearSlot(BearOutfit outfit, ItemKind kind) => switch (kind) {
    ItemKind.outfit => outfit.copyWith(outfitId: 0),
    ItemKind.top => outfit.copyWith(topId: 0),
    ItemKind.bottom => outfit.copyWith(bottomId: 0),
    ItemKind.headwear => outfit.copyWith(headwearId: 0),
    ItemKind.shoes => outfit.copyWith(shoesId: 0),
    ItemKind.accessory => outfit.copyWith(accessoryId: 0),
    _ => outfit,
  };

  // --- Обучение (КП 9) -----------------------------------------------------

  /// Засчитывает пройденный уровень: монеты, радость мишки, вклад в характер.
  void completeLevel(String categoryId, int level, {int reward = 10}) {
    final done = eduProgress(categoryId);
    if (level >= done) _eduProgress[categoryId] = (done + 1).clamp(0, 10);

    earn(reward);
    bear.showHappy();
    bear.recordAction(BearAction.learn);
    // Награду на сервере считает своя функция — по таблице наград, а не по
    // числу, присланному отсюда (КП 9.5, 15.4).
    onLevelDone?.call(categoryId, level);
    notifyListeners();
  }

  // --- Уведомления (КП 13.2) -----------------------------------------------

  /// Удалить аккаунт навсегда (правило App Store 5.1.1: аккаунт создаётся в
  /// приложении — значит, и удаляется в нём). `true` — удалён, приложение
  /// возвращается на стартовую страницу. `null` — без сервера пункта нет.
  Future<bool> Function()? onDeleteAccount;

  /// Привязать Apple к гостевому кабинету (КП 1.3, 14.2). `null` — пункта
  /// нет: Apple не настроена, нет сервера или Apple уже привязана.
  Future<bool> Function()? onLinkApple;

  /// Спросить у телефона разрешение на уведомления. Ставит хозяин
  /// приложения; `null` — уведомлений на этой платформе нет (веб, тесты).
  Future<bool> Function()? onAskNotifications;

  /// Можно ли вообще спрашивать про напоминания.
  bool get canAskNotifications => onAskNotifications != null;

  /// Переключатель в настройках. Включили — телефон спрашивает разрешение:
  /// без него iPhone молча не покажет ни одного напоминания (КП 13.1).
  /// Отказ — переключатель возвращается назад, результат `false`.
  Future<bool> toggleNotification(String id) async {
    final on = !(_notifications[id] ?? false);
    _notifications[id] = on;
    notifyListeners();
    final ask = onAskNotifications;
    if (!on || ask == null) return true;
    if (await ask()) return true;
    _notifications[id] = false;
    notifyListeners();
    return false;
  }

  /// «Да, напоминать» в мягком вопросе: разрешение и напоминания об уходе
  /// (голод, игра, сон). `false` — телефон не разрешил.
  Future<bool> enableCareReminders() async {
    final ask = onAskNotifications;
    if (ask == null || !await ask()) return false;
    for (final kind in const [
      NotificationKind.hungry,
      NotificationKind.play,
      NotificationKind.sleep,
    ]) {
      _notifications[kind.id] = true;
    }
    notifyListeners();
    return true;
  }

  void setQuietHours(bool value) {
    _quietHours = value;
    notifyListeners();
  }
}

/// Итог выкупа серии подарка дня.
enum RestoreResult { ok, noCoins, failed }

/// Восемь типов уведомлений (КП 13.1).
enum NotificationKind {
  hungry('hungry', 'Голоден', true),
  play('play', 'Хочет играть', true),
  sleep('sleep', 'Пора спать', true),
  task('task', 'Задание', true),
  gift('gift', 'Подарок', true),
  stage('stage', 'Новая стадия', true),
  event('event', 'Событие', false),
  shopNews('shop', 'Новинки магазина', false);

  const NotificationKind(this.id, this.title, this.onByDefault);

  final String id;
  final String title;
  final bool onByDefault;
}
