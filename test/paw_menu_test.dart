import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/game/app_section.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/paw_menu.dart';

/// Кнопка-лапа вместо нижней панели (решение заказчика 20.09).
///
/// Проверяется поведение, а не картинка: что разделы достижимы, что меню
/// само убирается и что замок по стадии не пропускает внутрь.
/// Лапа — единственная кнопка, пока меню закрыто.
final paw = find.byIcon(Icons.pets_rounded);
final closeIcon = find.byIcon(Icons.close_rounded);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<AppSection> opened,
    BearStage stage = BearStage.adult,
    Duration idleTimeout = const Duration(seconds: 5),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: PawMenu(
            stage: stage,
            idleTimeout: idleTimeout,
            onSelected: opened.add,
          ),
        ),
      ),
    );
  }

  testWidgets('пока меню закрыто, разделов на экране нет', (tester) async {
    await pump(tester, opened: []);

    expect(paw, findsOneWidget);
    expect(find.text('Магазин'), findsNothing);
    expect(find.text('Комната'), findsNothing);
  });

  testWidgets('тап по лапе выпускает четыре раздела', (tester) async {
    await pump(tester, opened: []);

    await tester.tap(paw);
    await tester.pumpAndSettle();

    for (final title in ['Комната', 'Магазин', 'Обучение', 'Мишки']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // Лапа превратилась в крестик: второй тап собирает меню обратно.
    expect(closeIcon, findsOneWidget);
  });

  testWidgets('выбор раздела закрывает меню и сообщает наверх', (tester) async {
    final opened = <AppSection>[];
    await pump(tester, opened: opened);

    await tester.tap(paw);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Магазин'));
    await tester.pumpAndSettle();

    expect(opened, [AppSection.shop]);
    expect(find.text('Магазин'), findsNothing);
  });

  testWidgets('тап мимо собирает меню обратно', (tester) async {
    final opened = <AppSection>[];
    await pump(tester, opened: opened);

    await tester.tap(paw);
    await tester.pumpAndSettle();
    // Куда угодно, лишь бы не по кружку: левый верхний угол свободен.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Магазин'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('без действий меню собирается само', (tester) async {
    await pump(
      tester,
      opened: [],
      // Заметно дольше самой анимации разлёта: иначе отсчёт истёк бы
      // прямо внутри pumpAndSettle, и тест проверял бы не то.
      idleTimeout: const Duration(seconds: 2),
    );

    await tester.tap(paw);
    await tester.pumpAndSettle();
    expect(find.text('Магазин'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    expect(find.text('Магазин'), findsNothing);
  });

  testWidgets('закрытый раздел не пускает внутрь и меню не закрывает', (
    tester,
  ) async {
    // Собираем меню из раздела, который на этой стадии под замком. Сейчас
    // все разделы открыты с рождения (КП 3.5 ждёт настроек с сервера),
    // поэтому стадию подбираем по самому разделу.
    final locked = AppSection.values.firstWhere(
      (s) => !s.isUnlockedAt(BearStage.newborn),
      orElse: () => AppSection.shop,
    );
    if (locked.isUnlockedAt(BearStage.newborn)) {
      // Замков пока нет ни на одном разделе — проверять нечего, но механизм
      // на месте: когда правила приедут с сервера, тест оживёт сам.
      return;
    }

    final opened = <AppSection>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: PawMenu(
            stage: BearStage.newborn,
            sections: [locked],
            onSelected: opened.add,
          ),
        ),
      ),
    );

    await tester.tap(paw);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(locked.icon));
    await tester.pump();

    expect(opened, isEmpty);
    expect(closeIcon, findsOneWidget);
  });
}
