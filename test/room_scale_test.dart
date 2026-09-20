import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/room_camera.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/room_slots.dart';
import 'package:teddy_tales/widgets/room_scene_backdrop.dart';
import 'package:teddy_tales/widgets/room_slot_layer.dart';

/// Пропорции комнаты (задача заказчика 20.09: «комната кажется гигантской»).
///
/// На полу с перспективой рост читается не величиной тела в кадре, а
/// отношением этой величины к расстоянию от ног до точки схода. Здесь
/// проверяется сама эта арифметика: она и решает, великан мишка или
/// потерявшаяся в зале игрушка.
void main() {
  group('Мишка в комнате', () {
    test('в каждой комнате мишка одного роста', () {
      // Главное обещание заказчику: «он как будто влитой». Комнаты сняты
      // разными камерами — детская с высоты взрослого, черновые кухня и
      // ванная почти с пола, — и доли кадра у них поэтому разные. А метры
      // должны совпадать, иначе переход между комнатами читался бы как
      // смена масштаба мира.
      final heights = [
        for (final room in RoomKind.values) cameraOf(room).bearMetres(),
      ];

      for (final height in heights) {
        expect(height, closeTo(1.07, 0.12));
      }
    });

    test('у самого нижнего края кадра то же тело читалось бы мельче', () {
      // Арифметика, из-за которой 20.09 комната казалась гигантской: мишка
      // стоял вплотную к зрителю, где всё выглядит крупнее своего масштаба,
      // и потому сам читался коротышкой. Проверяем, что зависимость именно
      // такая, — если знак однажды перевернут, комнату опять раздует.
      for (final room in RoomKind.values) {
        final camera = cameraOf(room);
        final atEdge =
            camera.bearHeight /
            (1.0 - camera.eyeLine) *
            camera.cameraOverWall *
            2.5;

        expect(atEdge, lessThan(camera.bearMetres()), reason: room.name);
      }
    });

    test('камеры померены, а не назначены', () {
      for (final room in RoomKind.values) {
        final camera = cameraOf(room);
        // Точка схода лежит между верхом стены и полом — иначе это не
        // комната, а вид снизу или сверху.
        expect(camera.eyeLine, greaterThan(camera.wallTop), reason: room.name);
        expect(camera.eyeLine, lessThan(camera.floorLine), reason: room.name);
        // Мишка стоит на полу, а не в стене и не за кадром.
        expect(
          camera.standLine,
          greaterThan(camera.floorLine),
          reason: room.name,
        );
        expect(camera.standLine, lessThanOrEqualTo(1.0), reason: room.name);
      }
    });

    test('голова выше стыка со стеной', () {
      for (final room in RoomKind.values) {
        final camera = cameraOf(room);
        final head = camera.standLine - camera.bearHeight;
        // Иначе мишка читался бы стоящим не в комнате, а на полоске пола
        // перед ней.
        expect(head, lessThan(camera.floorLine), reason: room.name);
      }
    });
  });

  group('Кадр комнаты на весь экран', () {
    const phone = Size(430, 932);
    const tall = Size(430, 1100);
    const short = Size(430, 500);

    test('все присланные комнаты идут со своим потолком', () {
      // 20.09 заказчик прислал все три фона нарисованными до потолка, и
      // дорисовывать больше нечего. Слой RoomCeiling оставлен: спальня, о
      // которой он говорил, может прийти и без него.
      for (final room in RoomKind.values) {
        expect(
          RoomFrame.of(phone, room).ceilingHeight,
          0,
          reason: room.name,
        );
      }
    });

    test('кадр с потолком закрывает экран целиком', () {
      final frame = RoomFrame.of(phone, RoomKind.nursery);

      expect(frame.rect.width, greaterThanOrEqualTo(phone.width));
      expect(frame.rect.height, greaterThanOrEqualTo(phone.height));
      // Прижат к низу: срезать можно потолок, но не пол.
      expect(frame.rect.bottom, phone.height);
    });

    test('пол доходит до нижнего края экрана в любой комнате', () {
      // Срезать можно потолок, но не пол: иначе мишка встанет ниже края
      // экрана, и под ним будет видна полоска фона приложения.
      for (final room in RoomKind.values) {
        for (final scene in [phone, tall, short]) {
          expect(
            RoomFrame.of(scene, room).rect.bottom,
            scene.height,
            reason: '${room.name} $scene',
          );
        }
      }
    });

    test('кадр всегда сохраняет пропорции картинки', () {
      for (final room in RoomKind.values) {
        final camera = cameraOf(room);
        for (final scene in [phone, tall, short]) {
          final frame = RoomFrame.of(scene, room);
          expect(
            frame.rect.height / frame.rect.width,
            closeTo(camera.artHeight / camera.artWidth, 0.001),
            reason: '${room.name} $scene',
          );
        }
      }
    });

    test('мишка стоит правее центра, как просил заказчик', () {
      final frame = RoomFrame.of(phone, RoomKind.nursery);

      expect(frame.bearCenterX, greaterThan(frame.centerX));
      expect(
        (frame.bearCenterX - frame.centerX) / frame.rect.width,
        closeTo(0.10, 0.001),
      );
    });

    test('ноги на полу, и пол не уходит за нижний край экрана', () {
      for (final room in RoomKind.values) {
        final frame = RoomFrame.of(phone, room);

        expect(frame.standY, greaterThan(frame.vanishingY), reason: room.name);
        expect(
          frame.standY,
          lessThanOrEqualTo(phone.height),
          reason: room.name,
        );
      }
    });
  });

  group('Что рисуется за мишкой', () {
    test('стены всегда позади', () {
      for (final slot in roomSlots.where((s) => s.onWall)) {
        expect(slotDepth(slot), SlotDepth.behind, reason: slot.id);
      }
    });

    test('задняя стена позади, коврик и игрушки впереди', () {
      expect(slotDepth(slotById('nursery.back_left')!), SlotDepth.behind);
      expect(slotDepth(slotById('nursery.back_right')!), SlotDepth.behind);
      expect(slotDepth(slotById('kitchen.toy_front')!), SlotDepth.front);
      expect(slotDepth(slotById('bath.toy_front')!), SlotDepth.front);
    });
  });

  group('Подсказки мест', () {
    test('пунктир спрятан по просьбе заказчика, но места живы', () {
      // Заказчик 20.09: «убери эти квадраты подсказки… пока спрячь, не
      // удаляй». Если однажды удалят и сами места, этот тест скажет об этом.
      expect(showSlotHints, isFalse);
      expect(roomSlots, isNotEmpty);
    });
  });
}
