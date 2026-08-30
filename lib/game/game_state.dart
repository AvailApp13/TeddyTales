import 'package:flutter/foundation.dart';

import '../bear/bear_action.dart';
import '../bear/bear_controller.dart';
import '../bear/bear_state.dart';
import 'food.dart';
import 'pet_profile.dart';
import 'shop_items.dart';

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
  }) : _profile = profile,
       _owned = owned ?? {..._startingItems},
       // Дефолт — ПУСТАЯ сцена: только стены и пол, без мебели. Решение
       // заказчика: предметы не ставить заранее, герой один в кадре, а
       // комнату каждый собирает сам через раздел «Комната».
       _placed = placed ?? {'wall_rose', 'floor_wood'};

  /// Что даётся бесплатно на старте. КП 10.8: 12 предметов бесплатно.
  static const Set<String> _startingItems = {
    'bed', 'rug', 'lamp', 'basket',
    'wall_rose', 'floor_wood', 'pillow_heart', 'plant',
    'ball', 'duck', 'cubes',
    'out_yellow',
  };

  final BearController bear;

  PetProfile _profile;
  final Set<String> _owned;
  final Set<String> _placed;
  final List<String> _cart = [];
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

  PetProfile get profile => _profile;
  int get coins => _profile.coins;

  Set<String> get owned => Set.unmodifiable(_owned);
  Set<String> get placed => Set.unmodifiable(_placed);
  List<String> get cart => List.unmodifiable(_cart);
  bool get quietHours => _quietHours;

  bool isOwned(String id) => _owned.contains(id);
  bool isPlaced(String id) => _placed.contains(id);
  bool isInCart(String id) => _cart.contains(id);
  bool isNotificationOn(String id) => _notifications[id] ?? false;

  /// Сколько уровней категории пройдено (КП 9.2, по 10 на категорию).
  int eduProgress(String categoryId) => _eduProgress[categoryId] ?? 0;

  int? get playerAge => _playerAge;

  void setPlayerAge(int age) {
    _playerAge = age.clamp(1, 120);
    notifyListeners();
  }

  int get cartTotal =>
      _cart.fold(0, (sum, id) => sum + ItemCatalog.byId(id).price);

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

  void setProfile(PetProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  // --- Еда (КП 8) ----------------------------------------------------------

  /// Покормить готовым блюдом. Возвращает `false`, если не хватило монет.
  bool feedWithDish(Dish dish) {
    if (!spend(dish.price)) return false;
    bear.feedBear(amount: dish.foodGain);
    return true;
  }

  /// Успешно приготовленное блюдо: награда монетами и кормление.
  void completeRecipe(Recipe recipe) {
    earn(recipe.reward);
    bear.feedBear(amount: recipe.foodGain);
  }

  // --- Магазин (КП 11.2) ---------------------------------------------------

  void toggleCart(String id) {
    if (_cart.remove(id)) {
      notifyListeners();
      return;
    }
    if (isOwned(id)) return;
    _cart.add(id);
    notifyListeners();
  }

  /// Покупает всё, что в корзине. `false`, если денег не хватает.
  bool checkout() {
    final total = cartTotal;
    if (total == 0 || !spend(total)) return false;
    _owned.addAll(_cart);
    _cart.clear();
    notifyListeners();
    return true;
  }

  /// Разовая покупка предмета мимо корзины.
  bool buy(String id) {
    final item = ItemCatalog.byId(id);
    if (isOwned(id) || !spend(item.price)) return false;
    _owned.add(id);
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  // --- Уведомления (КП 13.2) -----------------------------------------------

  void toggleNotification(String id) {
    _notifications[id] = !(_notifications[id] ?? false);
    notifyListeners();
  }

  void setQuietHours(bool value) {
    _quietHours = value;
    notifyListeners();
  }
}

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
