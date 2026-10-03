import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/food.dart';

/// Цены блюд и награды рецептов из панели управления (КП 15.3, 15.4).
void main() {
  tearDown(FoodPrices.reset);

  Dish dish(String id) => FoodCatalog.dishes.firstWhere((d) => d.id == id);
  Recipe recipe(String id) =>
      FoodCatalog.recipes.firstWhere((r) => r.id == id);

  test('без сервера — цены из каталога', () {
    expect(dish('pasta').price, 12);
    expect(recipe('meat').reward, 20);
  });

  test('цена и сытость с сервера заменяют каталожные', () {
    FoodPrices.apply({
      'dishes': {
        'pasta': {'price': 14, 'food': 36},
      },
      'recipes': {
        'meat': {'reward': 22, 'food': 40},
      },
    });
    expect(dish('pasta').price, 14);
    expect(dish('pasta').foodGain, 36);
    expect(recipe('meat').reward, 22);
    expect(recipe('meat').foodGain, 40);
  });

  test('чего нет на сервере — остаётся из каталога', () {
    FoodPrices.apply({
      'dishes': {
        'pasta': {'food': 36},
      },
    });
    expect(dish('pasta').price, 12);
    expect(dish('soup').price, 8);
    expect(recipe('cookie').reward, 8);
  });
}
