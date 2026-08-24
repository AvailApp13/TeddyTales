/// Локализация каталога еды (КП 16.1).
///
/// Данные в `lib/game/food.dart` остаются русским эталоном и не меняются;
/// экраны берут видимые названия отсюда — по id блюда/рецепта и по
/// эталонному русскому названию ингредиента. Если для значения нет ключа
/// (например, в каталог добавили новое блюдо, а ARB ещё не пополнили),
/// показывается русское значение из данных — экран не падает и не пустует.
library;

import '../game/food.dart';
import 'gen/app_localizations.dart';

/// Название готового блюда по [Dish.id].
String dishName(AppLocalizations l10n, String id) => switch (id) {
  'porridge' => l10n.dishPorridge,
  'soup' => l10n.dishSoup,
  'sandwich' => l10n.dishSandwich,
  'fruit' => l10n.dishFruit,
  'yogurt' => l10n.dishYogurt,
  'cookie' => l10n.dishCookie,
  'salad' => l10n.dishSalad,
  'pasta' => l10n.dishPasta,
  'omelette' => l10n.dishOmelette,
  'pie' => l10n.dishPie,
  _ => _dishFallback(id),
};

/// Название рецепта по [Recipe.id].
String recipeName(AppLocalizations l10n, String id) => switch (id) {
  'cookie' => l10n.recipeCookie,
  'sandwich' => l10n.recipeSandwich,
  'fruit_salad' => l10n.recipeFruitSalad,
  'meat' => l10n.recipeMeat,
  'veggie' => l10n.recipeVeggie,
  _ => _recipeFallback(id),
};

/// Название ингредиента мини-игры готовки.
///
/// У [Ingredient] нет id, поэтому ключ подбирается по эталонному русскому
/// [Ingredient.title] из каталога.
String ingredientName(AppLocalizations l10n, Ingredient ingredient) =>
    switch (ingredient.title) {
      'Мука' => l10n.ingredientFlour,
      'Сахар' => l10n.ingredientSugar,
      'Масло' => l10n.ingredientButter,
      'Соль' => l10n.ingredientSalt,
      'Рыба' => l10n.ingredientFish,
      'Перец' => l10n.ingredientPepper,
      'Хлеб' => l10n.ingredientBread,
      'Сыр' => l10n.ingredientCheese,
      'Помидор' => l10n.ingredientTomato,
      'Шоколад' => l10n.ingredientChocolate,
      'Лук' => l10n.ingredientOnion,
      'Конфета' => l10n.ingredientCandy,
      'Яблоко' => l10n.ingredientApple,
      'Банан' => l10n.ingredientBanana,
      'Апельсин' => l10n.ingredientOrange,
      'Йогурт' => l10n.ingredientYogurt,
      'Мясо' => l10n.ingredientMeat,
      'Морковь' => l10n.ingredientCarrot,
      'Специи' => l10n.ingredientSpices,
      'Картофель' => l10n.ingredientPotato,
      'Капуста' => l10n.ingredientCabbage,
      'Зелень' => l10n.ingredientGreens,
      'Мёд' => l10n.ingredientHoney,
      // Фолбэк — русское значение из данных.
      _ => ingredient.title,
    };

String _dishFallback(String id) {
  for (final dish in FoodCatalog.dishes) {
    if (dish.id == id) return dish.title;
  }
  return id;
}

String _recipeFallback(String id) {
  for (final recipe in FoodCatalog.recipes) {
    if (recipe.id == id) return recipe.title;
  }
  return id;
}
