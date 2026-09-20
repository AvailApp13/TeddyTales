import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
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
  /// Высота камеры над полом, в долях высоты стены. Померено по фону:
  /// точка схода 0.447, стык стены с полом 0.564, верх стены 0.079.
  const cameraOverWall =
      (RoomSceneBackdrop.horizon - RoomSceneBackdrop.eyeLine) / (0.564 - 0.079);

  /// Во сколько высот камеры читается тело ростом [bodyHeight] кадра,
  /// стоящее на линии пола [standLine].
  double heightInCameras(double bodyHeight, double standLine) =>
      bodyHeight / (standLine - RoomSceneBackdrop.eyeLine);

  /// Рост в метрах при потолке 2.5 м.
  double metres(double bodyHeight, double standLine) =>
      heightInCameras(bodyHeight, standLine) * cameraOverWall * 2.5;

  const bear = RoomSceneBackdrop.heroHeight; // утверждено 18.09, не трогаем

  group('Мишка в комнате', () {
    test('камера стоит низко — вровень с ребёнком', () {
      // Если однажды фон переснимут с камерой взрослого, линию пола
      // придётся пересчитать, и этот тест скажет об этом первым.
      expect(cameraOverWall * 2.5, closeTo(0.60, 0.05));
    });

    test('у самого края кадра мишка читался игрушкой в зале', () {
      // Так было до 20.09: 0.92 — нижний край сцены.
      expect(metres(bear, 0.92), lessThan(0.75));
    });

    test('на утверждённой линии — ростом с трёхлетку', () {
      expect(metres(bear, RoomSceneBackdrop.standLine), closeTo(1.07, 0.1));
    });

    test('мишка стоит на полу, а не в стене и не за кадром', () {
      expect(
        RoomSceneBackdrop.standLine,
        greaterThan(RoomSceneBackdrop.horizon),
      );
      expect(RoomSceneBackdrop.standLine, lessThan(1.0));
    });
  });

  group('Кадр комнаты на весь экран', () {
    // Заказчик 20.09: комната на весь телефон, сверху потолок, а мишка
    // остаётся «влитым» — то есть его соотношение к комнате не зависит от
    // того, какой у человека телефон.
    const phone = Size(430, 932);
    const tall = Size(430, 1100);
    const short = Size(430, 500);

    test('кадр вписан по ширине и прижат к низу', () {
      final frame = RoomFrame.of(phone);

      expect(frame.rect.width, phone.width);
      expect(frame.rect.bottom, phone.height);
      expect(frame.rect.height, closeTo(430 * 1120 / 896, 0.01));
    });

    test('рост мишки не зависит от высоты телефона', () {
      // Главное обещание заказчику: «он как будто влитой».
      expect(RoomFrame.of(phone).bearHeight, RoomFrame.of(tall).bearHeight);
      expect(RoomFrame.of(phone).bearHeight, RoomFrame.of(short).bearHeight);
    });

    test('чем выше телефон, тем больше полоса под потолок', () {
      expect(
        RoomFrame.of(tall).ceilingHeight,
        greaterThan(RoomFrame.of(phone).ceilingHeight),
      );
      // На коротком экране потолка нет вовсе: у картинки срезается верх, но
      // пол и мишка остаются на месте.
      expect(RoomFrame.of(short).ceilingHeight, 0);
      expect(RoomFrame.of(short).rect.bottom, short.height);
    });

    test('мишка стоит правее центра, как просил заказчик', () {
      final frame = RoomFrame.of(phone);

      expect(frame.bearCenterX, greaterThan(frame.centerX));
      expect(
        (frame.bearCenterX - frame.centerX) / frame.rect.width,
        closeTo(0.10, 0.001),
      );
    });

    test('ноги на линии пола, голова выше стыка со стеной', () {
      final frame = RoomFrame.of(phone);
      final head = frame.standY - frame.bearHeight;

      expect(frame.standY, greaterThan(frame.vanishingY));
      expect(frame.standY, lessThanOrEqualTo(phone.height));
      // Голова выше линии пола у задней стены — иначе мишка читался бы
      // стоящим не в комнате, а на полоске пола перед ней.
      expect(
        head,
        lessThan(frame.rect.top + RoomSceneBackdrop.horizon * frame.rect.height),
      );
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
      expect(slotDepth(slotById('nursery.rug')!), SlotDepth.front);
      expect(slotDepth(slotById('nursery.toy_front')!), SlotDepth.front);
    });

    test('в каждой комнате есть и те, и другие', () {
      // Пустой заход означал бы, что комната размечена по одну сторону от
      // мишки: тогда он либо закрывает собой всё, либо стоит перед пустотой.
      for (final room in RoomKind.values) {
        final slots = slotsOf(room);
        expect(
          slots.map(slotDepth).toSet(),
          {SlotDepth.behind, SlotDepth.front},
          reason: room.name,
        );
      }
    });
  });
}
