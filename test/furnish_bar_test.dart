import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/game/room_kind.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/furnish_bar.dart';

/// Лента своих вещей в режиме обустройства.
///
/// Заказчик 21.09: «если расстановку сделали, например, двух картин — они из
/// списка должны исчезнуть, а они остаются, будто одну и ту же вещь можно
/// поставить дважды». Вещь одна: она либо стоит в комнате, либо лежит в
/// ленте.
void main() {
  late BearController bear;
  late GameState game;

  setUp(() {
    bear = BearController();
    game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 6, 1)),
      owned: {'armchair', 'pic_bear', 'pic_heart', 'wardrobe', 'ball'},
      placed: const {},
    );
  });

  tearDown(() {
    game.dispose();
    bear.dispose();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ru'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          // Как на экране: лента перерисовывается вслед за комнатой.
          child: AnimatedBuilder(
            animation: game,
            builder: (context, _) => FurnishBar(
              game: game,
              room: RoomKind.nursery,
              picked: null,
              onPick: (_) {},
              onShop: () {},
              onDone: () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('поставленная вещь уходит из ленты', (tester) async {
    await pump(tester);
    expect(find.text('Картина мишка'), findsOneWidget);

    game.placeInSlot('nursery.wall_pic_left', 'pic_bear');
    await tester.pump();

    expect(find.text('Картина мишка'), findsNothing);
    // Вторая картина на месте: ушла именно поставленная.
    expect(find.text('Картина с сердцем'), findsOneWidget);
  });

  testWidgets('убранная из комнаты вещь возвращается в ленту', (tester) async {
    game.placeInSlot('nursery.wall_pic_left', 'pic_bear');
    await pump(tester);
    expect(find.text('Картина мишка'), findsNothing);

    game.clearSlot('nursery.wall_pic_left');
    await tester.pump();

    expect(find.text('Картина мишка'), findsOneWidget);
  });

  testWidgets('вещей без картинки в ленте нет', (tester) async {
    await pump(tester);

    // Шкаф и мячик куплены, но картинок у них нет: в ленте они выглядели
    // серыми коробками, а поставить их было всё равно нечем.
    expect(find.text('Шкаф'), findsNothing);
    expect(find.text('Мячик'), findsNothing);
    expect(find.text('Кресло'), findsOneWidget);
  });

  test('в ленте только то, чему в этой комнате есть место', () {
    final bar = FurnishBar(
      game: game,
      room: RoomKind.nursery,
      picked: null,
      onPick: (_) {},
      onShop: () {},
      onDone: () {},
    );

    expect(
      bar.items.map((item) => item.id),
      containsAll(<String>['armchair', 'pic_bear', 'pic_heart']),
    );
    for (final item in bar.items) {
      expect(item.photo, isTrue, reason: item.id);
      expect(ItemCatalog.byId(item.id).id, item.id);
    }
  });
}
