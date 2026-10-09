import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/item_metrics.dart';
import 'package:teddy_tales/game/item_shapes.dart';
import 'package:teddy_tales/game/room_camera.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/room_render.dart';
import 'package:teddy_tales/game/room_renders.dart';
import 'package:teddy_tales/game/room_slots.dart';
import 'package:teddy_tales/game/shop_items.dart';

/// Места в комнате (решение заказчика 18.09).
///
/// Проверяется обещание, которое слоты дают игроку: вещь не вылезает за
/// отведённое ей место, не стоит в двух местах разом и не пропадает, когда
/// её сменили другой.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'bed', 'armchair', 'rug', 'ball', 'pic_bear'},
      placed: const {},
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  group('Разметка', () {
    test('у каждого места свой ключ', () {
      final ids = roomSlots.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('обставляется одна детская', () {
      // Заказчик 21.09: «кухня и ванна остаются без таких решений, они
      // статичны; на кухне будет меняться только еда на столе при покупке,
      // спальня будет меняться от возраста». Расстановка — это про детскую,
      // остальные комнаты меняются сами и не игроком.
      final furnished = [
        for (final room in RoomKind.values)
          if (slotsOf(room).isNotEmpty) room,
      ];

      expect(furnished, [RoomKind.nursery]);
    });

    test('ни одна вещь не вылезает за видимую полосу кадра', () {
      // Кадр шире экрана: телефон вытянут сильнее картинки, и по краям она
      // срезается. Самый вытянутый ходовой экран (19.5:9) оставляет от кадра
      // 0.09–0.91 по ширине — за этой полосой вещь начнёт обрезаться.
      // Заказчик 20.09 поймал это первым: кресло-цветок ушло за левый край.
      //
      // Это про картинки-наклейки на плоской детской. В 3D-комнате вещь
      // ставится готовым слоем (room_render.dart) — его проверка ниже;
      // наклейки там — временно, до перевода вещи в 3D.
      for (final slot in nurseryFlatSlots) {
        for (final item in ItemCatalog.all.where(slot.takes)) {
          final box = boxOf(slot, item);
          expect(box.left, greaterThan(0.085), reason: '${slot.id}/${item.id}');
          expect(
            box.left + box.width,
            lessThan(0.915),
            reason: '${slot.id}/${item.id}',
          );
          expect(box.top, greaterThan(0.0), reason: '${slot.id}/${item.id}');
          expect(
            box.top + box.height,
            lessThan(1.0),
            reason: '${slot.id}/${item.id}',
          );
        }
      }
    });

    test('в 3D-комнате места и готовые слои — в кадре телефона', () {
      // Места размечены в 3D (docs/room-furniture-plan.md) так, чтобы вещи
      // стояли вокруг мишки и были видны на iPhone и Android.
      for (final slot in nursery3dSlots) {
        expect(slot.x, inInclusiveRange(0.09, 0.91), reason: slot.id);
        expect(slot.y, inInclusiveRange(0.15, 0.80), reason: slot.id);
      }
      for (final entry in roomRenders.entries) {
        final r = entry.value;
        expect(r.left, greaterThanOrEqualTo(0.0), reason: entry.key);
        expect(r.top, greaterThanOrEqualTo(0.0), reason: entry.key);
        expect(r.left + r.width, lessThanOrEqualTo(1.0), reason: entry.key);
        expect(r.top + r.height, lessThanOrEqualTo(1.0), reason: entry.key);
      }
    });

    test('в 3D-комнате картинки вещей не выходят за край экрана', () {
      // Проверка 09.10: справа столик, корзины, растения срезались краем
      // экрана на 12–36 %, комод — на 19–28 %. Самый вытянутый ходовой
      // экран (iPhone 19,5:9) оставляет от кадра 0.09–0.91 по ширине.
      // Кроме места у окна: кресло там стоит у самой стены, куда его
      // поставил заказчик 09.10 («поставь его сюда»).
      for (final slot in nursery3dSlots) {
        if (slot.id == 'nursery.floor_left') continue;
        for (final item in ItemCatalog.all.where(slot.takes)) {
          if (roomRenderOf(slot.id, item.id) != null) continue;
          final box = boxOf(slot, item);
          final key = '${slot.id}/${item.id}';
          expect(box.left, greaterThanOrEqualTo(0.09), reason: key);
          expect(box.left + box.width, lessThanOrEqualTo(0.91), reason: key);
        }
      }
    });

    test('нажимается только сама вещь, а не её тень', () {
      // Проверка 09.10: нажатие по комоду, ковру и полу у ног мишки
      // открывало кресло — прямоугольник его слоя с тенью накрывал
      // полкомнаты. У каждого слоя и каждой картинки — сетка нажатия.
      for (final entry in roomRenders.entries) {
        expect(entry.value.hit, isNotNull, reason: entry.key);
      }
      for (final item in ItemCatalog.all) {
        if (metricsOf(item.id) == null) continue;
        expect(itemShapes[item.id], isNotNull, reason: item.id);
      }
      // Кресло: середина — нажимается, тень на полу справа внизу — нет.
      final chair = roomRenders['nursery.floor_left/armchair']!;
      bool at(double u, double v) => chair.hit!.contains(
        (u / 941 - chair.left) / chair.width,
        (v / 1672 - chair.top) / chair.height,
      );
      expect(at(230, 880), isTrue);
      expect(at(700, 1150), isFalse);
    });

    test('у каждого готового слоя есть файл, место и вещь', () {
      expect(roomRenders, isNotEmpty);
      for (final key in roomRenders.keys) {
        final [slotId, itemId] = key.split('/');
        final slot = slotById(slotId);
        expect(slot, isNotNull, reason: key);
        expect(slot!.takes(ItemCatalog.byId(itemId)), isTrue, reason: key);
        expect(
          File(roomRenderAsset(slotId, itemId)).existsSync(),
          isTrue,
          reason: key,
        );
      }
    });

    test('к каждому месту подходит хоть одна вещь каталога', () {
      for (final slot in roomSlots) {
        expect(
          ItemCatalog.all.any(slot.takes),
          isTrue,
          reason: 'в ${slot.id} нечего поставить',
        );
      }
    });
  });

  group('Размер вещи задаёт её величина и глубина', () {
    test('кресло встаёт тем же размером, каким оно на готовом фоне', () {
      // Сверка с картинкой, которую заказчик прислал обставленной: кресло на
      // ней занимает 0.34 ширины кадра и стоит на линии 0.598. Это и есть
      // «ровно так, как смотрелось, когда фон уже был готовый с мебелью».
      // Про плоскую детскую: в 3D-комнате кресло — готовый слой.
      final box = boxOf(
        nurseryFlatSlots.firstWhere((s) => s.id == 'nursery.floor_left'),
        ItemCatalog.byId('armchair'),
      );

      expect(box.width, closeTo(0.34, 0.03));
      expect(box.top + box.height, closeTo(0.60, 0.001));
    });

    test('пропорции вещи — её собственные', () {
      final camera = cameraOf(RoomKind.nursery);
      final box = boxOf(
        slotById('nursery.floor_right')!,
        ItemCatalog.byId('bed'),
      );

      // Картинка обрезана впритык к вещи, поэтому её пропорция и есть
      // пропорция кроватки. Растянутая, она перестала бы быть кроваткой.
      final aspect = itemMetrics['bed']!.aspect;
      final inPixels =
          box.height * camera.artHeight / (box.width * camera.artWidth);
      expect(inPixels, closeTo(aspect, 0.001));
    });

    test('дальше — мельче: одна и та же вещь в разной глубине', () {
      final far = boxOf(
        slotById('nursery.corner_right')!,
        ItemCatalog.byId('teddy'),
      );
      final near = boxOf(
        slotById('nursery.toy_right')!,
        ItemCatalog.byId('teddy'),
      );

      // Тот же мишка-игрушка в углу у задней стены и у ног мишки. Без
      // перспективы они выходили одинаковыми, и комната читалась плоской.
      expect(near.width, greaterThan(far.width * 1.3));
    });

    test('мишка выше кресла и ниже стены', () {
      final camera = cameraOf(RoomKind.nursery);

      // Мишка — 1.15 м (полэкрана на линии 0.80), кресло — 0.64 м, стена —
      // 2.5 м. Если размерный ряд врёт, врёт он прежде всего здесь.
      final chair = itemMetrics['armchair']!;
      expect(chair.heightMetres, inInclusiveRange(0.55, 0.75));
      expect(camera.cameraMetres, closeTo(0.97, 0.05));
    });

    test('кроватка больше не занимает полкадра', () {
      final box = boxOf(
        slotById('nursery.floor_right')!,
        ItemCatalog.byId('bed'),
      );

      // Ровно та жалоба заказчика, с которой всё началось: «поставил туда
      // какую-то кровать большую». У задней стены полутораметровая кроватка
      // занимает меньше половины ширины кадра — как и положено.
      expect(box.width, lessThan(0.45));
    });

    test('картина висит на стене, а не стоит на полу', () {
      final box = boxOf(
        slotById('nursery.wall_pic_left')!,
        ItemCatalog.byId('pic_bear'),
      );
      final slot = slotById('nursery.wall_pic_left')!;

      // Центр картинки — на линии места, а не её низ: висящая вещь держится
      // серединой.
      expect(box.top + box.height / 2, closeTo(slot.y, 0.001));
      // И она выше стыка стены с полом.
      expect(
        box.top + box.height,
        lessThan(cameraOf(RoomKind.nursery).floorLine),
      );
    });

    test('вещь не всюду помещается', () {
      // Место — это не только «где», но и «сколько тут места». Кроватку в
      // полтора метра некуда ставить в угол под растение.
      final corner = slotById('nursery.corner_right')!;
      expect(corner.takes(ItemCatalog.byId('bed')), isFalse);
      expect(corner.takes(ItemCatalog.byId('plant')), isTrue);
    });

    test('у задней стены справа — ни кресла, ни кроватки', () {
      // Заказчик 09.10: «там максимум должны становиться тумбочки, которые
      // у нас есть, какие-то шкафчики, цветы, пальмы».
      // Домики — тоже сюда (ответ заказчика на проверку 09.10).
      final right = slotById('nursery.floor_right')!;
      for (final id in ['armchair', 'armchair_bean', 'swing', 'bed']) {
        expect(right.takes(ItemCatalog.byId(id)), isFalse, reason: id);
      }
      for (final id in [
        'dresser',
        'table',
        'plant',
        'flowers_daisy',
        'dollhouse',
        'house_felt',
      ]) {
        expect(right.takes(ItemCatalog.byId(id)), isTrue, reason: id);
      }
    });

    test('у мишки — только игрушки', () {
      // Заказчик 09.10: цветы в вазах — у задней стены и справа, а не на
      // полу рядом с мишкой.
      for (final id in ['nursery.toy_left', 'nursery.toy_right']) {
        final slot = slotById(id)!;
        for (final toy in ['teddy', 'bunny', 'cubes', 'pyramid']) {
          expect(slot.takes(ItemCatalog.byId(toy)), isTrue, reason: '$id/$toy');
        }
        for (final other in ['flowers_daisy', 'flowers_orchid', 'plant']) {
          expect(
            slot.takes(ItemCatalog.byId(other)),
            isFalse,
            reason: '$id/$other',
          );
        }
      }
    });

    test('каждой вещи с картинкой есть место — кроме кроватки', () {
      // Кроватка — заглушка до замены (заказчик 09.10: «убирать не надо,
      // мы её заменим»), места ей пока нет. Остальное купленное должно
      // куда-то вставать — иначе вещь в «Интерьере» есть, а поставить некуда.
      final homeless = [
        for (final item in ItemCatalog.all)
          if (item.onSale &&
              item.group.placeable &&
              metricsOf(item.id) != null &&
              !roomSlots.any((s) => s.takes(item)))
            item.id,
      ];
      expect(homeless, ['bed']);
    });

    test('на месте у окна — только сидячие места', () {
      // Заказчик 09.10: «там только кресла — подвесное, не подвесное».
      final left = slotById('nursery.floor_left')!;
      for (final id in [
        'armchair',
        'armchair_bean',
        'armchair_wing',
        'swing',
      ]) {
        expect(left.takes(ItemCatalog.byId(id)), isTrue, reason: id);
      }
      for (final id in ['table', 'plant', 'teddy', 'pic_bear', 'dollhouse']) {
        expect(left.takes(ItemCatalog.byId(id)), isFalse, reason: id);
      }
    });

    test('вещь без картинки в комнату не ставится', () {
      // Рисовать нечем: до 20.09 такие вещи были эмодзи, а эмодзи заказчик
      // попросил убрать совсем.
      for (final slot in roomSlots) {
        expect(slot.takes(ItemCatalog.byId('wardrobe')), isFalse);
        expect(slot.takes(ItemCatalog.byId('ball')), isFalse);
      }
    });
  });

  group('Что где стоит', () {
    test('вещь встаёт в место', () {
      game.placeInSlot('nursery.floor_left', 'bed');

      expect(game.itemInSlot('nursery.floor_left'), 'bed');
      expect(game.isPlaced('bed'), isTrue);
      expect(game.slotOf('bed'), 'nursery.floor_left');
    });

    test('новая вещь вытесняет прежнюю', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.floor_left', 'armchair');

      expect(game.itemInSlot('nursery.floor_left'), 'armchair');
      // Кроватка вернулась в инвентарь, а не растворилась.
      expect(game.isOwned('bed'), isTrue);
      expect(game.isPlaced('bed'), isFalse);
    });

    test('вещь не стоит в двух местах разом', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.floor_right', 'bed');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
      expect(game.itemInSlot('nursery.floor_right'), 'bed');
    });

    test('некупленное поставить нельзя', () {
      game.placeInSlot('nursery.floor_left', 'wardrobe');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
    });

    test('место освобождается', () {
      game.placeInSlot('nursery.floor_left', 'bed');
      game.clearSlot('nursery.floor_left');

      expect(game.itemInSlot('nursery.floor_left'), isNull);
      expect(game.isPlaced('bed'), isFalse);
      expect(game.isOwned('bed'), isTrue);
    });

    test('сервер узнаёт про обе половины замены', () {
      final events = <(String, bool)>[];
      game.onPlace = (id, {required placed}) => events.add((id, placed));

      game.placeInSlot('nursery.floor_left', 'bed');
      game.placeInSlot('nursery.floor_left', 'armchair');

      // Без первой записи на сервере остались бы стоять обе вещи разом.
      expect(events, [('bed', true), ('bed', false), ('armchair', true)]);
    });
  });
}
