/// Еда: 10 готовых блюд и 5 рецептов с мини-играми (КП 8).
library;

import 'dart:math';

import '../bear/bear_rig_spec.dart' show BearTrait;

/// То, что ставится на стол кухни дугой: готовое блюдо или рецепт. У
/// каждого — картинка тарелки без фона в ракурсе кухни.
abstract interface class TablePlate {
  String get id;
  String get image;
}

/// Цены блюд и награды рецептов с сервера (КП 15.3, 15.4): настройки
/// `dishes` и `recipes` в `game_config`, их правят в панели управления.
/// Списывает и начисляет монеты всё равно сервер — здесь только то, что
/// приложение показывает, чтобы на табло стояло то же число, что спишется.
abstract final class FoodPrices {
  static Map<String, dynamic> _dishes = const {};
  static Map<String, dynamic> _recipes = const {};

  /// Взять цены из настроек сервера: `{dishes: {id: {price, food}},
  /// recipes: {id: {reward, food}}}`. Чего нет — остаётся из каталога.
  static void apply(Map<String, dynamic> config) {
    final dishes = config['dishes'];
    final recipes = config['recipes'];
    if (dishes is Map) _dishes = Map<String, dynamic>.from(dishes);
    if (recipes is Map) _recipes = Map<String, dynamic>.from(recipes);
  }

  /// Забыть цены сервера — для тестов.
  static void reset() {
    _dishes = const {};
    _recipes = const {};
  }

  static num? _field(Map<String, dynamic> table, String id, String field) {
    final row = table[id];
    if (row is! Map) return null;
    final value = row[field];
    return value is num ? value : null;
  }

  static int? dishPrice(String id) => _field(_dishes, id, 'price')?.round();
  static double? dishFood(String id) => _field(_dishes, id, 'food')?.toDouble();
  static int? recipeReward(String id) =>
      _field(_recipes, id, 'reward')?.round();
  static double? recipeFood(String id) =>
      _field(_recipes, id, 'food')?.toDouble();
}

/// Готовое блюдо из вкладки «Готовые блюда» (КП 8.2).
class Dish implements TablePlate {
  const Dish({
    required this.id,
    required this.emoji,
    required this.title,
    required int price,
    required double foodGain,
  }) : _price = price,
       _foodGain = foodGain;

  @override
  final String id;
  final String emoji;
  final String title;

  final int _price;
  final double _foodGain;

  /// Цена в монетах. КП 8.2 задаёт вилку 5–15. Правится в панели
  /// управления (КП 15.3, 15.4) и приезжает с сервера ([FoodPrices]);
  /// значение здесь — на случай, когда сервера нет.
  int get price => FoodPrices.dishPrice(id) ?? _price;

  /// Насколько поднимается показатель «Еда» — тоже с сервера.
  double get foodGain => FoodPrices.dishFood(id) ?? _foodGain;

  /// Картинка блюда для стола на кухне: тарелка без фона, в стиле и
  /// ракурсе кухни (Higgsfield, 24.09).
  @override
  String get image => 'assets/rooms/kitchen/dishes/$id.webp';
}

/// Ингредиент мини-игры готовки.
class Ingredient {
  const Ingredient(this.id, this.emoji, this.title);

  final String id;
  final String emoji;
  final String title;

  /// Картинка продукта под столом кухни (Higgsfield, 24.09; заказчик
  /// утвердил все 23).
  String get image => 'assets/rooms/kitchen/ingredients/$id.webp';
}

/// Рецепт из вкладки «Приготовить» (КП 8.3, 8.5).
class Recipe implements TablePlate {
  const Recipe({
    required this.id,
    required this.emoji,
    required this.title,
    required this.difficulty,
    required int reward,
    required double foodGain,
    required this.steps,
    required this.distractors,
  }) : _reward = reward,
       _foodGain = foodGain;

  @override
  final String id;
  final String emoji;
  final String title;

  /// Уровень сложности 1–3, показывается звёздами (КП 8.3).
  final int difficulty;

  final int _reward;
  final double _foodGain;

  /// Награда в монетах за успешное приготовление. Правится в панели
  /// управления и приезжает с сервера ([FoodPrices]).
  int get reward => FoodPrices.recipeReward(id) ?? _reward;

  double get foodGain => FoodPrices.recipeFood(id) ?? _foodGain;

  /// Ингредиенты в правильном порядке. КП 8.4 требует именно
  /// последовательность, а не просто набор.
  final List<Ingredient> steps;

  /// Лишние ингредиенты — их выбор считается ошибкой.
  final List<Ingredient> distractors;

  /// Всё, что показывается на экране мини-игры.
  List<Ingredient> get allChoices => [...steps, ...distractors];

  /// Готовое блюдо на столе — того же размера и ракурса, что готовые блюда.
  /// Печенье, сэндвич и фруктовый салат берут картинки готовых блюд,
  /// «Курица с овощами» — готовое блюдо «Курица» (Ирина 28.09); пасты с
  /// грибами среди готовых нет — своя картинка.
  @override
  String get image => switch (id) {
    'meat' => 'assets/rooms/kitchen/dishes/chicken.webp',
    'veggie' => 'assets/rooms/kitchen/recipes/pasta_mushrooms.webp',
    'fruit_salad' => 'assets/rooms/kitchen/dishes/fruit.webp',
    _ => 'assets/rooms/kitchen/dishes/$id.webp',
  };
}

/// Каталог еды.
abstract final class FoodCatalog {
  /// Ровно 10 блюд, состав из КП 8.2.
  static const List<Dish> dishes = <Dish>[
    Dish(id: 'porridge', emoji: '🥣', title: 'Каша', price: 5, foodGain: 20),
    Dish(id: 'soup', emoji: '🍲', title: 'Суп', price: 8, foodGain: 28),
    Dish(id: 'sandwich', emoji: '🥪', title: 'Сэндвич', price: 7, foodGain: 25),
    Dish(id: 'fruit', emoji: '🍓', title: 'Фрукты', price: 6, foodGain: 18),
    // Ирина 28.09: йогурт → рыба, пирог → курица (замены, количество по
    // КП 8.2 то же — 10). Старые id остаются на сервере для прежних сборок.
    Dish(id: 'fish', emoji: '🐟', title: 'Рыба', price: 11, foodGain: 32),
    Dish(id: 'cookie', emoji: '🍪', title: 'Печенье', price: 5, foodGain: 12),
    Dish(id: 'salad', emoji: '🥗', title: 'Салат', price: 9, foodGain: 22),
    Dish(id: 'pasta', emoji: '🍝', title: 'Паста', price: 12, foodGain: 35),
    Dish(id: 'omelette', emoji: '🍳', title: 'Омлет', price: 10, foodGain: 30),
    Dish(id: 'chicken', emoji: '🍗', title: 'Курица', price: 15, foodGain: 40),
  ];

  /// Ровно 5 рецептов (КП 8.5). Состав и порядок шагов — Ирины (ответы
  /// 28.09). Механика — по КП 8.4: верный порядок, ошибка — подсказка и
  /// повтор. Продукты-обманки правдоподобные, без «рыбы в печенье» (Ирина).
  /// id `meat` и `veggie` прежние — по ним сервер считает награду.
  static const List<Recipe> recipes = <Recipe>[
    Recipe(
      id: 'cookie',
      emoji: '🍪',
      title: 'Печенье',
      difficulty: 1,
      reward: 8,
      foodGain: 14,
      steps: [
        Ingredient('butter', '🧈', 'Масло'),
        Ingredient('sugar', '🍯', 'Сахар'),
        Ingredient('egg', '🥚', 'Яйцо'),
        Ingredient('flour', '🌾', 'Мука'),
        // На утверждённой картинке печенье шоколадное (заказчик 04.10:
        // блюда не меняем, продукты подгоняем под картинку).
        Ingredient('chocolate', '🍫', 'Шоколад'),
      ],
      distractors: [
        Ingredient('bread', '🍞', 'Хлеб'),
        Ingredient('cheese', '🧀', 'Сыр'),
        Ingredient('yogurt', '🥛', 'Йогурт'),
      ],
    ),
    Recipe(
      id: 'sandwich',
      emoji: '🥪',
      title: 'Сэндвич',
      difficulty: 1,
      reward: 9,
      foodGain: 26,
      steps: [
        // Как на картинке сэндвича (заказчик 04.10): хлеб, сыр, ветчина,
        // салатный лист, помидор.
        Ingredient('bread', '🍞', 'Хлеб'),
        Ingredient('cheese', '🧀', 'Сыр'),
        Ingredient('ham', '🥓', 'Ветчина'),
        Ingredient('lettuce', '🥬', 'Салатный лист'),
        Ingredient('tomato', '🍅', 'Помидор'),
      ],
      distractors: [
        Ingredient('flour', '🌾', 'Мука'),
        Ingredient('sugar', '🍯', 'Сахар'),
        Ingredient('mushrooms', '🍄', 'Грибы'),
      ],
    ),
    Recipe(
      id: 'fruit_salad',
      emoji: '🥗',
      title: 'Фруктовый салат',
      difficulty: 2,
      reward: 14,
      foodGain: 24,
      steps: [
        // Как на картинке салата (заказчик 04.10): йогурта на ней нет, есть
        // клубника, виноград и голубика.
        Ingredient('apple', '🍎', 'Яблоко'),
        Ingredient('banana', '🍌', 'Банан'),
        Ingredient('strawberry', '🍓', 'Клубника'),
        Ingredient('grapes', '🍇', 'Виноград'),
        Ingredient('blueberries', '🫐', 'Голубика'),
      ],
      distractors: [
        Ingredient('cheese', '🧀', 'Сыр'),
        Ingredient('bread', '🍞', 'Хлеб'),
        Ingredient('potato', '🥔', 'Картофель'),
      ],
    ),
    Recipe(
      id: 'meat',
      emoji: '🍗',
      title: 'Курица с овощами',
      difficulty: 3,
      reward: 20,
      foodGain: 38,
      steps: [
        Ingredient('chicken', '🍗', 'Курица'),
        Ingredient('broccoli', '🥦', 'Брокколи'),
        Ingredient('potato', '🥔', 'Картофель'),
        Ingredient('sauce', '🥫', 'Соус'),
      ],
      distractors: [
        Ingredient('flour', '🌾', 'Мука'),
        Ingredient('sugar', '🍯', 'Сахар'),
        Ingredient('banana', '🍌', 'Банан'),
      ],
    ),
    Recipe(
      id: 'veggie',
      emoji: '🍝',
      title: 'Паста с грибами',
      difficulty: 3,
      reward: 18,
      foodGain: 32,
      steps: [
        Ingredient('pasta', '🍝', 'Паста'),
        Ingredient('mushrooms', '🍄', 'Грибы'),
        Ingredient('sour_cream', '🥣', 'Сметана'),
        Ingredient('spoon', '🥄', 'Перемешать'),
      ],
      distractors: [
        Ingredient('bread', '🍞', 'Хлеб'),
        Ingredient('apple', '🍎', 'Яблоко'),
        Ingredient('sugar', '🍯', 'Сахар'),
      ],
    ),
  ];

  static Dish dishById(String id) => dishes.firstWhere((d) => d.id == id);

  static Recipe recipeById(String id) => recipes.firstWhere((r) => r.id == id);
}

/// Любимые блюда характера (КП 7.4 — характер влияет на предпочтения в
/// еде; заказчик 01.10). Кухня каждый раз называет одно из трёх — фразой
/// мишки ([cravingText] в `food_l10n.dart`), а съеденное любимое блюдо его
/// нежит.
const Map<BearTrait, List<String>> favouriteDishesByTrait = {
  BearTrait.active: ['pasta', 'chicken', 'omelette'],
  BearTrait.curious: ['fish', 'salad', 'omelette'],
  BearTrait.affectionate: ['cookie', 'fruit', 'porridge'],
  BearTrait.calm: ['soup', 'porridge', 'fish'],
  BearTrait.independent: ['sandwich', 'chicken', 'pasta'],
  BearTrait.reserved: ['fruit', 'cookie', 'soup'],
};

/// Любимое ли блюдо [dish] у характера [trait].
bool isFavouriteDish(BearTrait trait, String dish) =>
    favouriteDishesByTrait[trait]?.contains(dish) ?? false;

/// Какое из любимых блюд мишка попросит сейчас: случайно, из тех, что ещё
/// стоят на столе ([available]); если ни одного нет — из всех любимых.
String pickCraving(
  BearTrait trait,
  Random random, {
  Iterable<String>? available,
}) {
  final all = favouriteDishesByTrait[trait] ?? const ['pasta'];
  final onTable = available == null
      ? all
      : all.where(available.contains).toList();
  final from = onTable.isEmpty ? all : onTable;
  return from[random.nextInt(from.length)];
}
