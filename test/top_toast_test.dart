import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/widgets/top_toast.dart';

/// Уведомления сверху вместо SnackBar снизу (заказчик 10.10).
///
/// Плашка выезжает под статус-баром, стоит около двух секунд и уезжает;
/// свайп вверх убирает её раньше; несколько подряд идут по очереди, не
/// накладываясь.
void main() {
  late BuildContext ctx;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 880));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // Статус-бар с вырезом: плашка должна встать ниже него. Отступ — над
        // навигатором, там, где плашки и живут.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 47)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
  }

  testWidgets('выезжает сверху под статус-баром и уходит через 2 с', (
    tester,
  ) async {
    await pump(tester);
    showTopToast(ctx, 'Куплено: Стол');
    await tester.pumpAndSettle();

    expect(find.text('Куплено: Стол'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final box = tester.getRect(find.text('Куплено: Стол'));
    // Сверху, а не у лапы внизу.
    expect(box.top, greaterThan(47));
    expect(box.bottom, lessThan(140));

    await tester.pump(TopToasts.defaultDuration);
    await tester.pumpAndSettle();
    expect(find.text('Куплено: Стол'), findsNothing);
  });

  testWidgets('несколько подряд — по очереди, не друг на друге', (
    tester,
  ) async {
    await pump(tester);
    showTopToast(ctx, 'первое');
    showTopToast(ctx, 'второе');
    await tester.pumpAndSettle();

    expect(find.text('первое'), findsOneWidget);
    expect(find.text('второе'), findsNothing);

    // Очередь ждёт — первое уходит раньше обычного.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('первое'), findsNothing);
    expect(find.text('второе'), findsOneWidget);

    await tester.pump(TopToasts.defaultDuration);
    await tester.pumpAndSettle();
    expect(find.text('второе'), findsNothing);
  });

  testWidgets('свайп вверх убирает раньше времени', (tester) async {
    await pump(tester);
    showTopToast(ctx, 'смахни меня');
    await tester.pumpAndSettle();

    await tester.drag(find.text('смахни меня'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(find.text('смахни меня'), findsNothing);
  });
}
