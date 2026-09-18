import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/shop_items.dart';

/// Замена вещи в комнате (замечание заказчика 17.09).
///
/// Проверяется не сам факт подмены, а обещание, которое замена даёт
/// игроку: он не может потерять то, что у него было.
void main() {
  late BearController bear;
  late GameState game;

  GameState build({int coins = 1250}) {
    bear = BearController();
    return GameState(
      bear: bear,
      profile: PetProfile(
        name: 'Тедди',
        birthAt: DateTime(2026, 6, 1),
        coins: coins,
      ),
      owned: {'bed', 'lamp'},
      placed: {'bed'},
    );
  }

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  test('меняет своё на своё бесплатно', () {
    game = build();
    final before = game.coins;

    expect(game.replacePlaced('bed', 'lamp'), isTrue);

    expect(game.isPlaced('bed'), isFalse);
    expect(game.isPlaced('lamp'), isTrue);
    expect(game.coins, before, reason: 'за своё платить не за что');
  });

  test('покупает, если новой вещи ещё нет', () {
    game = build();
    final table = ItemCatalog.byId('table');

    expect(game.replacePlaced('bed', 'table'), isTrue);

    expect(game.isOwned('table'), isTrue);
    expect(game.isPlaced('table'), isTrue);
    expect(game.coins, 1250 - table.price);
  });

  test('при нехватке монет старая вещь остаётся на месте', () {
    // Двадцати монет не хватит ни на что: самая дешёвая вещь стоит 30.
    game = build(coins: 20);

    expect(game.replacePlaced('bed', 'table'), isFalse);

    expect(
      game.isPlaced('bed'),
      isTrue,
      reason: 'человек не должен терять кроватку за попытку посмотреть стол',
    );
    expect(game.isOwned('table'), isFalse);
    expect(game.coins, 20);
  });

  test('замена на саму себя ничего не делает', () {
    game = build();

    expect(game.replacePlaced('bed', 'bed'), isFalse);
    expect(game.isPlaced('bed'), isTrue);
  });

  test('сервер узнаёт про обе половины замены', () {
    game = build();
    final events = <(String, bool)>[];
    game.onPlace = (id, {required placed}) => events.add((id, placed));

    game.replacePlaced('bed', 'lamp');

    // Одно действие для игрока — две записи для сервера: место
    // освободилось и место занято. Без первой на сервере останутся стоять
    // обе вещи разом.
    expect(events, [('bed', false), ('lamp', true)]);
  });
}
