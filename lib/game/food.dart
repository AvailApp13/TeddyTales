/// Еда: 10 готовых блюд и 5 рецептов с мини-играми (КП 8).
library;

/// Готовое блюдо из вкладки «Готовые блюда» (КП 8.2).
class Dish {
  const Dish({
    required this.id,
    required this.emoji,
    required this.title,
    required this.price,
    required this.foodGain,
  });

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
}

/// Ингредиент мини-игры готовки.
class Ingredient {
  const Ingredient(this.emoji, this.title);

  final String emoji;
  final String title;
}

/// Рецепт из вкладки «Приготовить» (КП 8.3, 8.5).
class Recipe {
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
        Ingredient('🌾', 'Мука'),
        Ingredient('🍯', 'Сахар'),
        Ingredient('🧈', 'Масло'),
      ],
      distractors: [
        Ingredient('🧂', 'Соль'),
        Ingredient('🐟', 'Рыба'),
        Ingredient('🌶', 'Перец'),
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
        Ingredient('🍞', 'Хлеб'),
        Ingredient('🧀', 'Сыр'),
        Ingredient('🍅', 'Помидор'),
      ],
      distractors: [
        Ingredient('🍫', 'Шоколад'),
        Ingredient('🧅', 'Лук'),
        Ingredient('🍬', 'Конфета'),
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
        Ingredient('🍎', 'Яблоко'),
        Ingredient('🍌', 'Банан'),
        Ingredient('🍊', 'Апельсин'),
        Ingredient('🥛', 'Йогурт'),
      ],
      distractors: [
        Ingredient('🧂', 'Соль'),
        Ingredient('🌶', 'Перец'),
        Ingredient('🧅', 'Лук'),
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
        Ingredient('🍖', 'Мясо'),
        Ingredient('🧅', 'Лук'),
        Ingredient('🥕', 'Морковь'),
        Ingredient('🌿', 'Специи'),
        Ingredient('🧈', 'Масло'),
      ],
      distractors: [
        Ingredient('🍯', 'Сахар'),
        Ingredient('🍌', 'Банан'),
        Ingredient('🍫', 'Шоколад'),
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
        Ingredient('🥔', 'Картофель'),
        Ingredient('🥕', 'Морковь'),
        Ingredient('🥬', 'Капуста'),
        Ingredient('🌿', 'Зелень'),
        Ingredient('🧈', 'Масло'),
        Ingredient('🧂', 'Соль'),
      ],
      distractors: [
        Ingredient('🍫', 'Шоколад'),
        Ingredient('🍯', 'Мёд'),
        Ingredient('🍬', 'Конфета'),
      ],
    ),
  ];

  static Dish dishById(String id) => dishes.firstWhere((d) => d.id == id);

  static Recipe recipeById(String id) => recipes.firstWhere((r) => r.id == id);
}
