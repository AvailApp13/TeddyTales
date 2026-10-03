import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/test_stubs.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';

/// Кошелёк на время испытаний (просьба заказчика 20.09).
///
/// «Чтобы всегда на счету при заходе было по 5000 монет» — иначе обстановку
/// не проверить: весь каталог стоит больше, а зарабатываются монеты уходом,
/// то есть временем.
GameState make({required int coins}) => GameState(
  bear: BearController(),
  profile: PetProfile(
    name: PetProfile.defaultName,
    birthAt: DateTime.now(),
    skin: BearSkin.boy,
    coins: coins,
  ),
);

void main() {
  group('Кошелёк для испытаний', () {
    test('пустой счёт поднимается до порога', () {
      expect(make(coins: 0).coins, kTestWallet);
      expect(make(coins: 1250).coins, kTestWallet);
    });

    test('накопленное сверх порога не отнимается', () {
      // Поднимаем до порога, а не выдаём ровно столько: заработанное или
      // пришедшее с сервера трогать нельзя.
      expect(make(coins: kTestWallet + 700).coins, kTestWallet + 700);
    });

    test('снимок с сервера не опускает счёт ниже порога', () {
      // Сервер про добавку не знает и после первого блюда присылал ноль:
      // второе блюдо было не купить (заказчик 23.09: «почему я могу купить
      // только одну еду»). Баланс общий: еда, магазин, что угодно.
      final game = make(coins: 0);
      expect(game.feedWithDish(FoodCatalog.dishes.first), isTrue);
      game.setProfile(game.profile.copyWith(coins: 0));
      expect(game.coins, kTestWallet);
      expect(game.feedWithDish(FoodCatalog.dishes.last), isTrue);
      expect(game.feedWithDish(FoodCatalog.dishes.last), isTrue);
    });

    test('показатель «Еда» закреплён на время испытаний', () {
      // Заказчик 23.09: «зафиксируй, к примеру, на 87 %, но есть он может
      // сколько угодно». Ни кормление, ни сервер его не двигают.
      final bear = BearController(pinnedFood: kTestFood);
      expect(bear.state.stats.food, kTestFood);
      bear.feedBear(amount: 40);
      expect(bear.state.stats.food, kTestFood);
      bear.restoreState(
        bear.state.copyWith(stats: bear.state.stats.copyWith(food: 0)),
      );
      expect(bear.state.stats.food, kTestFood);
      // Без параметра контроллер живой — на нём держатся остальные тесты.
      expect(BearController().state.stats.food, isNot(kTestFood));
    });

    test('порога хватает на всю обстановку комнаты', () {
      // Ради этого порог и заведён: заказчик проверяет, что в комнату
      // можно поставить всё, что продаётся.
      expect(kTestWallet, greaterThan(3000));
    });
  });
}
