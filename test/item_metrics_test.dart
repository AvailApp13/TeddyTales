import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/item_metrics.dart';
import 'package:teddy_tales/game/shop_items.dart';

/// Размеры вещей (задача заказчика 20.09 «расстановка должна быть правильной»).
///
/// Таблица размеров говорит, какой ширины вещь в метрах и какой она формы.
/// Форма — не выдумка, а свойство картинки: комната считает по ней высоту.
/// Разъедутся таблица и картинка — вещь встанет растянутой или сплюснутой, и
/// заметить это на глаз будет тем труднее, чем меньше вещь.
void main() {
  test('у каждой вещи с картинкой есть размер', () {
    for (final item in ItemCatalog.all) {
      if (!item.photo) continue;
      expect(
        metricsOf(item.id),
        isNotNull,
        reason: 'нет размера у ${item.id}',
      );
    }
  });

  test('в таблице нет размеров от несуществующих вещей', () {
    final ids = {for (final item in ItemCatalog.all) item.id};
    for (final id in itemMetrics.keys) {
      expect(ids, contains(id));
    }
  });

  test('пропорция в таблице — это пропорция картинки', () async {
    for (final entry in itemMetrics.entries) {
      final file = File('assets/shop/items/${entry.key}.webp');
      expect(file.existsSync(), isTrue, reason: 'нет картинки ${entry.key}');

      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final aspect = frame.image.height / frame.image.width;
      frame.image.dispose();
      codec.dispose();

      expect(
        entry.value.aspect,
        closeTo(aspect, 0.005),
        reason: 'у ${entry.key} в таблице ${entry.value.aspect}, '
            'а картинка ${aspect.toStringAsFixed(3)}',
      );
    }
  });

  test('картинка обрезана впритык к вещи', () async {
    // Поле вокруг вещи ломает размер: комната меряет вещь по краям файла, и
    // лишние пустые точки превращаются в лишние сантиметры. До 21.09 поле
    // было у каждой вещи своё — отсюда и разнобой на экране заказчика.
    for (final id in itemMetrics.keys) {
      final codec = await ui.instantiateImageCodec(
        await File('assets/shop/items/$id.webp').readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = (await image.toByteData())!;

      var left = image.width, right = -1, top = image.height, bottom = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final alpha = data.getUint8((y * image.width + x) * 4 + 3);
          if (alpha <= 8) continue;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
      image.dispose();
      codec.dispose();

      expect(left, lessThanOrEqualTo(1), reason: '$id: поле слева');
      expect(top, lessThanOrEqualTo(1), reason: '$id: поле сверху');
      expect(right, greaterThanOrEqualTo(image.width - 2),
          reason: '$id: поле справа');
      expect(bottom, greaterThanOrEqualTo(image.height - 2),
          reason: '$id: поле снизу');
    }
  });
}
