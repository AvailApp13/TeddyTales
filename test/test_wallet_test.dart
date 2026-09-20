import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_controller.dart';
import 'package:teddy_tales/game/game_state.dart';
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

    test('порога хватает на всю обстановку комнаты', () {
      // Ради этого порог и заведён: заказчик проверяет, что в комнату
      // можно поставить всё, что продаётся.
      expect(kTestWallet, greaterThan(3000));
    });
  });
}
