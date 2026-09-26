import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/game/pet_name.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/glass_panel.dart';
import 'package:teddy_tales/widgets/rename_pet_dialog.dart';

/// Шаг «Как зовут малыша?» на первом запуске (КП 2.3).
void main() {
  Future<String?> open(
    WidgetTester tester, {
    required Future<PetNameError?> Function(String) onSubmit,
  }) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showRenamePetDialog(
                context: context,
                current: '',
                onSubmit: onSubmit,
                firstRun: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('первый запуск: поле пустое, «Назвать» и «Позже»', (
    tester,
  ) async {
    await open(tester, onSubmit: (_) async => null);

    expect(find.text('Как зовут малыша?'), findsOneWidget);
    expect(find.text('Назвать'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget);
    expect(find.text('Отмена'), findsNothing);

    final button = tester.widget<GlassButton>(
      find.byKey(const ValueKey('name-save')),
    );
    expect(button.onPressed, isNull, reason: 'пустое имя не отправить');
  });

  testWidgets('имя уходит на сервер уже приведённым', (tester) async {
    final sent = <String>[];
    await open(
      tester,
      onSubmit: (name) async {
        sent.add(name);
        return null;
      },
    );

    await tester.enterText(find.byType(TextField), '  Тишка  ');
    await tester.pump();
    await tester.tap(find.text('Назвать'));
    await tester.pumpAndSettle();

    expect(sent, ['Тишка']);
    expect(find.byType(GlassPanel), findsNothing, reason: 'окно закрылось');
  });

  testWidgets('отказ сервера держит окно открытым', (tester) async {
    await open(tester, onSubmit: (_) async => PetNameError.rejected);

    await tester.enterText(find.byType(TextField), 'Тишка');
    await tester.pump();
    await tester.tap(find.text('Назвать'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.text('Такое имя не подойдёт малышу'), findsOneWidget);
  });
}
