/// Локализация каталога еды (КП 16.1).
///
/// Данные в `lib/game/food.dart` остаются русским эталоном и не меняются;
/// экраны берут видимые названия отсюда — по id блюда/рецепта и по
/// эталонному русскому названию ингредиента. Если для значения нет ключа
/// (например, в каталог добавили новое блюдо, а ARB ещё не пополнили),
/// показывается русское значение из данных — экран не падает и не пустует.
library;

import '../bear/bear_rig_spec.dart' show BearTrait;
import '../game/food.dart';
import 'gen/app_localizations.dart';

/// Название готового блюда по [Dish.id].
String dishName(AppLocalizations l10n, String id) => switch (id) {
  'porridge' => l10n.dishPorridge,
  'soup' => l10n.dishSoup,
  'sandwich' => l10n.dishSandwich,
  'fruit' => l10n.dishFruit,
  'fish' => l10n.dishFish,
  'cookie' => l10n.dishCookie,
  'salad' => l10n.dishSalad,
  'pasta' => l10n.dishPasta,
  'omelette' => l10n.dishOmelette,
  'chicken' => l10n.dishChicken,
  _ => _dishFallback(id),
};

/// Короткое описание блюда для табло на скатерти (заказчик 24.09):
/// «Паста — с томатным соусом». Нет ключа — пустая строка, табло покажет
/// одно название.
String dishDescription(AppLocalizations l10n, String id) => switch (id) {
  'porridge' => l10n.dishDescPorridge,
  'soup' => l10n.dishDescSoup,
  'sandwich' => l10n.dishDescSandwich,
  'fruit' => l10n.dishDescFruit,
  'fish' => l10n.dishDescFish,
  'cookie' => l10n.dishDescCookie,
  'salad' => l10n.dishDescSalad,
  'pasta' => l10n.dishDescPasta,
  'omelette' => l10n.dishDescOmelette,
  'chicken' => l10n.dishDescChicken,
  _ => '',
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
      'Яйцо' => l10n.ingredientEgg,
      'Курица' => l10n.ingredientChicken,
      'Брокколи' => l10n.ingredientBroccoli,
      'Соус' => l10n.ingredientSauce,
      'Паста' => l10n.ingredientPasta,
      'Грибы' => l10n.ingredientMushrooms,
      'Сметана' => l10n.ingredientSourCream,
      'Перемешать' => l10n.ingredientMix,
      'Ветчина' => l10n.ingredientHam,
      'Салатный лист' => l10n.ingredientLettuce,
      'Клубника' => l10n.ingredientStrawberry,
      'Виноград' => l10n.ingredientGrapes,
      'Голубика' => l10n.ingredientBlueberries,
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

/// Подсказка от характера на кухне (КП 8.1): мишка просит одно из своих
/// любимых блюд ([favouriteDishesByTrait]). Фразы утверждены заказчиком
/// 01.10. Для блюда не из любимых — `null`.
String? cravingText(AppLocalizations l10n, BearTrait trait, String dish) =>
    switch ((trait, dish)) {
      (BearTrait.active, 'pasta') => l10n.cravingActivePasta,
      (BearTrait.active, 'chicken') => l10n.cravingActiveChicken,
      (BearTrait.active, 'omelette') => l10n.cravingActiveOmelette,
      (BearTrait.curious, 'fish') => l10n.cravingCuriousFish,
      (BearTrait.curious, 'salad') => l10n.cravingCuriousSalad,
      (BearTrait.curious, 'omelette') => l10n.cravingCuriousOmelette,
      (BearTrait.affectionate, 'cookie') => l10n.cravingAffectionateCookie,
      (BearTrait.affectionate, 'fruit') => l10n.cravingAffectionateFruit,
      (BearTrait.affectionate, 'porridge') => l10n.cravingAffectionatePorridge,
      (BearTrait.calm, 'soup') => l10n.cravingCalmSoup,
      (BearTrait.calm, 'porridge') => l10n.cravingCalmPorridge,
      (BearTrait.calm, 'fish') => l10n.cravingCalmFish,
      (BearTrait.independent, 'sandwich') => l10n.cravingIndependentSandwich,
      (BearTrait.independent, 'chicken') => l10n.cravingIndependentChicken,
      (BearTrait.independent, 'pasta') => l10n.cravingIndependentPasta,
      (BearTrait.reserved, 'fruit') => l10n.cravingReservedFruit,
      (BearTrait.reserved, 'cookie') => l10n.cravingReservedCookie,
      (BearTrait.reserved, 'soup') => l10n.cravingReservedSoup,
      _ => null,
    };
