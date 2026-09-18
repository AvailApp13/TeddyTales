import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/bear_zodiac.dart';
import 'package:teddy_tales/game/pet_profile.dart';

/// Ответ сервера — ровно в том виде, в каком его отдаёт `pet_snapshot()`.
/// Списан с живого вызова, а не придуман: придуманный образец проверяет
/// только то, что разбор согласуется сам с собой.
Map<String, dynamic> _serverJson() => {
  'server_time': '2026-09-16T16:30:00.123456+00:00',
  'pet': {
    'id': 'b1e0c8aa-2f3e-4d51-9a77-1c2f4e8a0d31',
    'name': 'Тишка',
    'name_status': 'approved',
    'birth_at': '2026-09-10T08:15:00+00:00',
    'skin': 'girl',
    'zodiac': 'leo',
    'stage': 'growing',
    'stage_changed_at': '2026-09-14T08:15:00+00:00',
    'trait': 'curious',
    'coins': 1250,
    'created_at': '2026-09-10T08:15:00+00:00',
  },
  'stats': {
    'food': 62.5,
    'hygiene': 80,
    'sleep': 70.25,
    'play': 90,
    'love': 100,
  },
  'outfit': {
    'outfit_id': 0,
    'top_id': 3,
    'bottom_id': 2,
    'headwear_id': 1,
    'shoes_id': 0,
    'accessory_id': 0,
  },
  'inventory': ['bed', 'rug', 'lamp'],
  'placed': ['wall_rose', 'floor_wood'],
  'edu': {'colors': 3, 'count': 1},
};

void main() {
  group('Разбор состояния с сервера (КП 1.4)', () {
    test('полный ответ разбирается во все поля', () {
      final snapshot = PetSnapshot.fromJson(_serverJson());

      expect(snapshot.petId, 'b1e0c8aa-2f3e-4d51-9a77-1c2f4e8a0d31');
      expect(snapshot.profile.name, 'Тишка');
      expect(snapshot.profile.coins, 1250);
      expect(snapshot.profile.skin, BearSkin.girl);
      expect(snapshot.profile.zodiac, BearZodiac.leo);

      expect(snapshot.state.stage, BearStage.growing);
      expect(snapshot.state.trait, BearTrait.curious);
      expect(snapshot.state.stats.food, 62.5);
      expect(snapshot.state.stats.love, 100);

      expect(snapshot.state.outfit.topId, 3);
      expect(snapshot.state.outfit.bottomId, 2);
      expect(snapshot.state.outfit.headwearId, 1);

      expect(snapshot.inventory, {'bed', 'rug', 'lamp'});
      expect(snapshot.placed, {'wall_rose', 'floor_wood'});
      expect(snapshot.eduProgress, {'colors': 3, 'count': 1});
    });

    test('время сервера приводится к UTC', () {
      final snapshot = PetSnapshot.fromJson(_serverJson());
      expect(snapshot.serverTime.isUtc, isTrue);
      expect(snapshot.serverTime.hour, 16);
    });

    test('пустой ответ не роняет разбор', () {
      // Так выглядит ответ, если схема откатилась или функция вернула
      // пустой объект. Приложение обязано показать хоть что-то.
      final snapshot = PetSnapshot.fromJson(const {});

      expect(snapshot.petId, '');
      expect(snapshot.profile.name, PetProfile.defaultName);
      expect(snapshot.profile.coins, 0);
      expect(snapshot.state.stage, BearStage.newborn);
      expect(snapshot.state.stats.food, 100);
      expect(snapshot.inventory, isEmpty);
      expect(snapshot.eduProgress, isEmpty);
    });

    test('неизвестные значения перечислений заменяются на безопасные', () {
      // Такое приходит, когда в базу добавили вариант, а приложение ещё
      // старое. Показать новорождённого лучше, чем не показать ничего.
      final json = _serverJson();
      json['pet'] = {
        ...json['pet'] as Map<String, dynamic>,
        'stage': 'teenager',
        'trait': 'grumpy',
        'skin': 'robot',
        'zodiac': 'ophiuchus',
      };

      final snapshot = PetSnapshot.fromJson(json);
      expect(snapshot.state.stage, BearStage.newborn);
      expect(snapshot.state.trait, BearTrait.active);
      expect(snapshot.state.skin, BearSkin.boy);
      expect(snapshot.profile.zodiac, isNull);
    });

    test('числа, присланные строками, читаются', () {
      // PostgREST отдаёт `numeric` строкой, и это регулярно ломает клиентов.
      final json = _serverJson();
      json['stats'] = {'food': '45.5', 'hygiene': '80', 'sleep': 70};
      json['pet'] = {...json['pet'] as Map<String, dynamic>, 'coins': '640'};

      final snapshot = PetSnapshot.fromJson(json);
      expect(snapshot.state.stats.food, 45.5);
      expect(snapshot.state.stats.hygiene, 80);
      expect(snapshot.profile.coins, 640);
    });

    test('пустое имя заменяется на имя по умолчанию', () {
      final json = _serverJson();
      json['pet'] = {...json['pet'] as Map<String, dynamic>, 'name': '   '};
      expect(PetSnapshot.fromJson(json).profile.name, PetProfile.defaultName);
    });

    test('комплект одежды отменяет раздельные вещи', () {
      // То же правило, что в BearOutfit: сервер такого сочетания не
      // пришлёт, но проверка ограничения стоит и здесь.
      final json = _serverJson();
      json['outfit'] = {'outfit_id': 4, 'top_id': 3, 'bottom_id': 2};

      final outfit = PetSnapshot.fromJson(json).state.outfit;
      expect(outfit.outfitId, 4);
      expect(outfit.topId, 0);
      expect(outfit.bottomId, 0);
    });
  });
}
