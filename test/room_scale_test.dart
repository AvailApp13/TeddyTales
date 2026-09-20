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

    test('у самого края кадра мишка читался бы игрушкой в зале', () {
      // Так было до 20.09 на черновом фоне: 0.92 — нижний край сцены.
      final draft = cameraOf(RoomKind.kitchen);
      final atEdge =
          draft.bearHeight / (0.92 - draft.eyeLine) * draft.cameraOverWall * 2.5;

      expect(atEdge, lessThan(0.75));
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

    test('нарисованный потолок нужен только комнатам без своего', () {
      // Детская пришла от заказчика сразу с потолком — дорисовывать нечего.
      expect(RoomFrame.of(phone, RoomKind.nursery).ceilingHeight, 0);
      expect(
        RoomFrame.of(phone, RoomKind.kitchen).ceilingHeight,
        greaterThan(0),
      );
    });

    test('кадр с потолком закрывает экран целиком', () {
      final frame = RoomFrame.of(phone, RoomKind.nursery);

      expect(frame.rect.width, greaterThanOrEqualTo(phone.width));
      expect(frame.rect.height, greaterThanOrEqualTo(phone.height));
      // Прижат к низу: срезать можно потолок, но не пол.
      expect(frame.rect.bottom, phone.height);
    });

    test('кадр без потолка вписан по ширине и прижат к низу', () {
      final frame = RoomFrame.of(phone, RoomKind.kitchen);
      final camera = cameraOf(RoomKind.kitchen);

      expect(frame.rect.width, phone.width);
      expect(frame.rect.bottom, phone.height);
      expect(
        frame.rect.height,
        closeTo(430 * camera.artHeight / camera.artWidth, 0.01),
      );
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
