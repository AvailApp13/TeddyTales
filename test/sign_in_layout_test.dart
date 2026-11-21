import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/screens/sign_in_layout.dart';

/// Экран входа: подписи не должны ложиться на мишек.
///
/// Заказчик 20.09 прислал скриншот, где строка «Плюшевый малыш…» легла
/// мишкам на лапы, и макет, как должно быть. Раньше подписи вставали от
/// края экрана и о картинке ничего не знали; теперь они привязаны к самой
/// сцене — вот эта привязка здесь и проверяется.
void main() {
  // Телефон заказчика, он же с открытой панелью просмотра (там экран ниже),
  // короткий Android и планшет.
  const phone = Size(390, 844);
  const viewer = Size(390, 682);
  const small = Size(360, 640);
  const tablet = Size(820, 1180);
  const all = [phone, viewer, small, tablet];

  SignInFrame frameOf(Size scene, {double bottomInset = 8}) => SignInFrame.of(
    scene,
    panelHeight: SignInMetrics.tight.height,
    bottomInset: bottomInset,
  );

  group('Кадр сцены', () {
    test('закрывает экран по ширине и не даёт полей сверху', () {
      for (final scene in all) {
        final rect = frameOf(scene).rect;

        expect(rect.left, lessThanOrEqualTo(0.01), reason: '$scene');
        expect(
          rect.right,
          greaterThanOrEqualTo(scene.width - 0.01),
          reason: '$scene',
        );
        expect(rect.top, lessThanOrEqualTo(0.01), reason: '$scene');
      }
    });

    test('с боков срезает не больше, чем позволено книжкам и домику', () {
      // Дальше обрезать нельзя: по краям сцены стоят книжки «Small Friends»
      // и домик с окошком, и срезанные наполовину они читаются как брак.
      for (final scene in all) {
        final rect = frameOf(scene).rect;

        expect(
          (rect.width - scene.width) / 2 / rect.width,
          lessThanOrEqualTo(signInSideCrop + 0.001),
          reason: '$scene',
        );
      }
    });

    test('мишки целиком помещаются на экран', () {
      // Полоса ковра под кадром — не беда, а вот срезанные лапы беда.
      for (final scene in all) {
        expect(
          frameOf(scene).bearsBottomY,
          lessThan(scene.height),
          reason: '$scene',
        );
      }
    });

    test('сохраняет пропорции присланной картинки', () {
      for (final scene in all) {
        final rect = frameOf(scene).rect;

        expect(
          rect.height / rect.width,
          closeTo(signInArtHeight / signInArtWidth, 0.001),
          reason: '$scene',
        );
      }
    });

    test('вверх тянется не больше, чем есть пустого поля над логотипом', () {
      for (final scene in all) {
        final rect = frameOf(scene).rect;

        expect(
          -rect.top / rect.height,
          lessThanOrEqualTo(signInLiftLimit + 0.001),
          reason: '$scene',
        );
      }
    });
  });

  group('Подзаголовок', () {
    test('стоит в просвете между логотипом и капюшоном', () {
      for (final scene in all) {
        final frame = frameOf(scene);
        final logo = frame.rect.top + signInLogoBottom * frame.rect.height;
        final bears = frame.rect.top + signInBearsTop * frame.rect.height;

        expect(frame.taglineCenterY, greaterThan(logo), reason: '$scene');
        expect(frame.taglineCenterY, lessThan(bears), reason: '$scene');
        // И просвет вообще есть: строке нужно куда-то встать.
        expect(frame.taglineBand, greaterThan(16), reason: '$scene');
      }
    });

    test('виден на экране, а не уехал за верхний край', () {
      for (final scene in all) {
        final frame = frameOf(scene);

        expect(
          frame.taglineCenterY - frame.taglineBand / 2,
          greaterThan(0),
          reason: '$scene',
        );
      }
    });
  });

  group('Панель входа', () {
    test('не залезает мишкам на лапы', () {
      // Главная просьба заказчика. Допуск в пиксель — на округление: кадр
      // тянут вверх ровно настолько, сколько панели не хватает.
      for (final scene in [phone, viewer, tablet]) {
        final frame = frameOf(scene);
        final free = scene.height - frame.bearsBottomY - 8;
        final panel = SignInMetrics.of(free).height;

        expect(panel, lessThanOrEqualTo(free + 1), reason: '$scene');
      }
    });

    test('подпись отступает от лап, а не жмётся к ним', () {
      // Заказчик 21.09: «надпись „Выберите способ входа“ не видна, так как
      // она легла на ноги мишек». Панель вставала ровно по линию лап, и
      // подпись — первая строка панели — оказывалась вплотную к ним.
      for (final scene in [phone, tablet, Size(430, 821)]) {
        final frame = frameOf(scene);
        final metrics = SignInMetrics.of(scene.height - frame.bearsBottomY - 8);

        expect(metrics.showPrompt, isTrue, reason: '$scene');
        expect(metrics.pawGap, greaterThanOrEqualTo(8), reason: '$scene');

        // Верх подписи — низ экрана минус панель плюс просвет.
        final promptTop = scene.height - 8 - metrics.height + metrics.pawGap;
        expect(
          promptTop - frame.bearsBottomY,
          greaterThanOrEqualTo(8),
          reason: '$scene',
        );
      }
    });

    test('на совсем коротком экране панель умещается под лапами', () {
      // 360 × 640 — самый тесный экран. При пяти кнопках здесь приходилось
      // жертвовать подписью «Выберите способ входа». С 24.09 кнопок три
      // (Apple, Google, почта) — места хватает и на подпись; главное, что
      // панель не залезает на мишек, а кнопка остаётся кнопкой.
      final frame = frameOf(small);
      final free = small.height - frame.bearsBottomY - 8;
      final metrics = SignInMetrics.of(free);

      expect(metrics.height, lessThanOrEqualTo(free + 1));
      expect(metrics.buttonHeight, greaterThanOrEqualTo(42));
    });

    test('кнопка нигде не мельче пальца', () {
      for (final scene in all) {
        final frame = frameOf(scene);
        final metrics = SignInMetrics.of(scene.height - frame.bearsBottomY - 8);

        expect(
          metrics.buttonHeight,
          greaterThanOrEqualTo(42),
          reason: '$scene',
        );
        expect(metrics.buttonHeight, lessThanOrEqualTo(54), reason: '$scene');
      }
    });

    test('на просторном экране разворачивается в полный рост', () {
      // Там, где места вдоволь, панель должна выглядеть как на макете, а не
      // растягиваться дальше по экрану.
      expect(SignInMetrics.of(1000).room, 1);
      expect(SignInMetrics.of(0).room, 0);
    });

    test('чем теснее, тем мельче всё сразу, а не одни кнопки', () {
      final tight = SignInMetrics.tight;
      final roomy = SignInMetrics.roomy;

      expect(roomy.buttonHeight, greaterThan(tight.buttonHeight));
      expect(roomy.gap, greaterThan(tight.gap));
      expect(roomy.promptSize, greaterThan(tight.promptSize));
      expect(roomy.skipHeight, greaterThan(tight.skipHeight));
      expect(roomy.legalSize, greaterThan(tight.legalSize));
    });
  });

  group('Без пробела между мишками и кнопками (заказчик 24.09)', () {
    test('пустота делится: сцена ниже, кнопки выше', () {
      for (final scene in all) {
        final fitted = frameOf(scene);
        final metrics = SignInMetrics.of(
          scene.height - fitted.bearsBottomY - 8,
        );
        final slack = scene.height - 8 - metrics.height - fitted.bearsBottomY;
        final (:frame, :panelTop) = fitted.settle(
          scene: scene,
          panelHeight: metrics.height,
          bottomInset: 8,
        );

        // Панель начинается прямо под лапами — со своим просветом.
        expect(panelTop, closeTo(frame.bearsBottomY, 0.01), reason: '$scene');
        // Панель не уходит за низ экрана.
        expect(
          panelTop + metrics.height,
          lessThanOrEqualTo(scene.height - 8 + 0.01),
          reason: '$scene',
        );
        // Сцена опущена не больше допустимого.
        expect(
          frame.rect.top - fitted.rect.top,
          lessThanOrEqualTo(signInDropLimit * fitted.rect.height + 0.01),
          reason: '$scene',
        );
        if (slack > 0) {
          expect(
            frame.rect.top,
            greaterThan(fitted.rect.top),
            reason: '$scene',
          );
        }
      }
    });

    test('на телефоне заказчика сцена опускается, кнопки поднимаются', () {
      final fitted = frameOf(phone);
      final metrics = SignInMetrics.of(phone.height - fitted.bearsBottomY - 8);
      final (:frame, :panelTop) = fitted.settle(
        scene: phone,
        panelHeight: metrics.height,
        bottomInset: 8,
      );
      final before = phone.height - 8 - metrics.height;

      expect(frame.rect.top, greaterThan(20), reason: 'логотип ниже');
      expect(panelTop, lessThan(before - 20), reason: 'кнопки выше');
    });
  });
}
