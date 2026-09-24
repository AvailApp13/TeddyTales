/// Еда: 10 готовых блюд и 5 рецептов с мини-играми (КП 8).
library;

/// То, что ставится на стол кухни дугой: готовое блюдо или рецепт. У
/// каждого — картинка тарелки без фона в ракурсе кухни.
abstract interface class TablePlate {
  String get id;
  String get image;
}

/// Готовое блюдо из вкладки «Готовые блюда» (КП 8.2).
class Dish implements TablePlate {
  const Dish({
    required this.id,
    required this.emoji,
    required this.title,
    required this.price,
    required this.foodGain,
  });

  @override
  final String id;
  final String emoji;
  final String title;

  /// Цена в монетах. КП 8.2 задаёт вилку 5–15.
  ///
  /// ЗАГЛУШКА: конкретные значения не утверждены. По КП 10.9 стоимость
  /// считается отдельно, по 15.4 приезжает из панели управления.
  final int price;

  /// Насколько поднимается показатель «Еда».
  final double foodGain;

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
    required this.reward,
    required this.foodGain,
    required this.steps,
    required this.distractors,
  });

  @override
  final String id;
  final String emoji;
  final String title;

  /// Уровень сложности 1–3, показывается звёздами (КП 8.3).
  final int difficulty;

  /// Награда в монетах за успешное приготовление.
  final int reward;

  final double foodGain;

  /// Ингредиенты в правильном порядке. КП 8.4 требует именно
  /// последовательность, а не просто набор.
  final List<Ingredient> steps;

  /// Лишние ингредиенты — их выбор считается ошибкой.
  final List<Ingredient> distractors;

  /// Всё, что показывается на экране мини-игры.
  List<Ingredient> get allChoices => [...steps, ...distractors];

  /// Готовое блюдо на столе — того же размера и ракурса, что готовые блюда.
  /// Печенье, сэндвич и фруктовый салат берут картинки готовых блюд;
  /// мясного и овощного среди готовых нет, их нарисовали отдельно (24.09).
  /// Потом их заменят картинки Ирины.
  @override
  String get image => switch (id) {
    'meat' || 'veggie' => 'assets/rooms/kitchen/recipes/$id.webp',
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
    Dish(id: 'yogurt', emoji: '🥛', title: 'Йогурт', price: 5, foodGain: 16),
    Dish(id: 'cookie', emoji: '🍪', title: 'Печенье', price: 5, foodGain: 12),
    Dish(id: 'salad', emoji: '🥗', title: 'Салат', price: 9, foodGain: 22),
    Dish(id: 'pasta', emoji: '🍝', title: 'Паста', price: 12, foodGain: 35),
    Dish(id: 'omelette', emoji: '🍳', title: 'Омлет', price: 10, foodGain: 30),
    Dish(id: 'pie', emoji: '🥧', title: 'Пирог', price: 15, foodGain: 40),
  ];

  /// Ровно 5 рецептов, состав и длина из КП 8.5: печенье и сэндвич по 2–3 шага,
  /// остальные по 4–6.
  static const List<Recipe> recipes = <Recipe>[
    Recipe(
      id: 'cookie',
      emoji: '🍪',
      title: 'Печенье',
      difficulty: 1,
      reward: 8,
      foodGain: 14,
      steps: [
        Ingredient('flour', '🌾', 'Мука'),
        Ingredient('sugar', '🍯', 'Сахар'),
        Ingredient('butter', '🧈', 'Масло'),
      ],
      distractors: [
        Ingredient('salt', '🧂', 'Соль'),
        Ingredient('fish', '🐟', 'Рыба'),
        Ingredient('pepper', '🌶', 'Перец'),
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
        Ingredient('bread', '🍞', 'Хлеб'),
        Ingredient('cheese', '🧀', 'Сыр'),
        Ingredient('tomato', '🍅', 'Помидор'),
      ],
      distractors: [
        Ingredient('chocolate', '🍫', 'Шоколад'),
        Ingredient('onion', '🧅', 'Лук'),
        Ingredient('candy', '🍬', 'Конфета'),
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
        Ingredient('apple', '🍎', 'Яблоко'),
        Ingredient('banana', '🍌', 'Банан'),
        Ingredient('orange', '🍊', 'Апельсин'),
        Ingredient('yogurt', '🥛', 'Йогурт'),
      ],
      distractors: [
        Ingredient('salt', '🧂', 'Соль'),
        Ingredient('pepper', '🌶', 'Перец'),
        Ingredient('onion', '🧅', 'Лук'),
      ],
    ),
    Recipe(
      id: 'meat',
      emoji: '🍖',
      title: 'Мясное блюдо',
      difficulty: 3,
      reward: 20,
      foodGain: 38,
      steps: [
        Ingredient('meat', '🍖', 'Мясо'),
        Ingredient('onion', '🧅', 'Лук'),
        Ingredient('carrot', '🥕', 'Морковь'),
        Ingredient('spices', '🌿', 'Специи'),
        Ingredient('butter', '🧈', 'Масло'),
      ],
      distractors: [
        Ingredient('sugar', '🍯', 'Сахар'),
        Ingredient('banana', '🍌', 'Банан'),
        Ingredient('chocolate', '🍫', 'Шоколад'),
      ],
    ),
    Recipe(
      id: 'veggie',
      emoji: '🥔',
      title: 'Овощное блюдо',
      difficulty: 3,
      reward: 18,
      foodGain: 32,
      steps: [
        Ingredient('potato', '🥔', 'Картофель'),
        Ingredient('carrot', '🥕', 'Морковь'),
        Ingredient('cabbage', '🥬', 'Капуста'),
        Ingredient('greens', '🌿', 'Зелень'),
        Ingredient('butter', '🧈', 'Масло'),
        Ingredient('salt', '🧂', 'Соль'),
      ],
      distractors: [
        Ingredient('chocolate', '🍫', 'Шоколад'),
        Ingredient('honey', '🍯', 'Мёд'),
        Ingredient('candy', '🍬', 'Конфета'),
      ],
    ),
  ];

  static Dish dishById(String id) => dishes.firstWhere((d) => d.id == id);

  static Recipe recipeById(String id) => recipes.firstWhere((r) => r.id == id);
}
