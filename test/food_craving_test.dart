import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart' show BearTrait;
import 'package:teddy_tales/game/food.dart';
import 'package:teddy_tales/l10n/food_l10n.dart';
import 'package:teddy_tales/l10n/l10n.dart';

/// Подсказка от характера на кухне (КП 8.1, 7.4; фразы — заказчик 01.10):
/// у каждого характера три любимых блюда из меню, мишка просит одно из них.
void main() {
  test('у каждого характера три любимых блюда, все — из меню', () {
    final menu = {for (final d in FoodCatalog.dishes) d.id};
    for (final trait in BearTrait.values) {
      final dishes = favouriteDishesByTrait[trait]!;
      expect(dishes, hasLength(3), reason: '$trait');
      expect(menu.containsAll(dishes), isTrue, reason: '$trait');
    }
  });

  test('на каждое любимое блюдо есть фраза на трёх языках', () async {
    for (final code in ['ru', 'en', 'zh']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      for (final trait in BearTrait.values) {
        for (final dish in favouriteDishesByTrait[trait]!) {
          final text = cravingText(l10n, trait, dish);
          expect(text, isNotNull, reason: '$code $trait $dish');
          expect(text, isNotEmpty, reason: '$code $trait $dish');
        }
      }
    }
  });

  test('мишка просит только любимое и только то, что на столе', () {
    final random = Random(1);
    for (var i = 0; i < 50; i++) {
      final dish = pickCraving(
        BearTrait.calm,
        random,
        available: ['soup', 'pasta', 'fish'],
      );
      expect(['soup', 'fish'], contains(dish));
    }
  });

  test('просьбы меняются, а не всегда одна и та же', () {
    final random = Random(7);
    final asked = {
      for (var i = 0; i < 60; i++) pickCraving(BearTrait.active, random),
    };
    expect(asked, {'pasta', 'chicken', 'omelette'});
  });

  test('любимых на столе нет — просит любое из любимых', () {
    final dish = pickCraving(
      BearTrait.reserved,
      Random(3),
      available: ['pasta'],
    );
    expect(favouriteDishesByTrait[BearTrait.reserved], contains(dish));
  });
}
