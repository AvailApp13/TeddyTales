import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/backend/pet_snapshot.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/game_state.dart';
import 'package:teddy_tales/game/pet_profile.dart';
import 'package:teddy_tales/l10n/l10n.dart';
import 'package:teddy_tales/widgets/daily_sheet.dart';

/// «Сегодня» (миграция 0017): подарок из календаря на 7 дней, три задания
/// дня и задание недели. Всё считает сервер — здесь разбор его ответа и
/// окно.
void main() {
  // Так отвечает сервер: третий день календаря ждёт, одно задание сделано.
  const serverDaily = {
    'day': '2026-09-25',
    'gift': {
      'available': true,
      'next_day': 3,
      'claimed_day': 2,
      'rewards': [10, 15, 20, 25, 30, 35, 50],
    },
    'tasks': [
      {'id': 'cook', 'target': 1, 'progress': 1, 'done': true, 'reward': 15},
      {'id': 'pet', 'target': 3, 'progress': 1, 'done': false, 'reward': 10},
      {
        'id': 'meal_on_time',
        'target': 2,
        'progress': 0,
        'done': false,
        'reward': 15,
      },
    ],
    'weekly': {'days_done': 2, 'target': 5, 'reward': 50, 'claimed': false},
  };

  test('ответ сервера разбирается целиком', () {
    final daily = PetSnapshot.fromJson(const {'daily': serverDaily}).daily;
    expect(daily.giftAvailable, isTrue);
    expect(daily.giftNextDay, 3);
    expect(daily.giftRewards, [10, 15, 20, 25, 30, 35, 50]);
    expect(daily.tasks.map((t) => t.id), ['cook', 'pet', 'meal_on_time']);
    expect(daily.tasks.first.done, isTrue);
    expect(daily.weeklyDone, 2);
    // Кеш хранит то же самое.
    final again = DailyInfo.fromJson(daily.toJson());
    expect(again.tasks.map((t) => t.progress), [1, 1, 0]);
    // Старый сервер без «daily» — пусто, окно скажет про связь.
    expect(PetSnapshot.fromJson(const {}).daily.isEmpty, isTrue);
  });

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('окно: календарь, «Забрать» и задания', (tester) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 9, 1)),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    game.setDaily(DailyInfo.fromJson(serverDaily));
    var claims = 0;
    game.onClaimGift = () async {
      claims++;
      return true;
    };

    await tester.pumpWidget(wrap(DailySheet(game: game)));
    expect(find.byKey(const ValueKey('daily-gift-7')), findsOneWidget);
    expect(find.text('Забрать +20'), findsOneWidget);
    expect(find.text('Приготовь блюдо'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.textContaining('2 из 5'), findsOneWidget);

    // «Забрать» открывает конверт; подарок забирается касанием по нему.
    await tester.tap(find.byKey(const ValueKey('daily-claim')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Нажми на конверт, чтобы открыть'), findsOneWidget);
    expect(claims, 0);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.pump();
    expect(claims, 1);
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tap(find.byKey(const ValueKey('gift-collect')));
    await tester.pumpAndSettle();

    // Сервер ответил: подарок забран — кнопка гаснет.
    game.setDaily(
      DailyInfo.fromJson({
        ...serverDaily,
        'gift': {
          'available': false,
          'next_day': 4,
          'claimed_day': 3,
          'rewards': [10, 15, 20, 25, 30, 35, 50],
        },
      }),
    );
    await tester.pump();
    expect(
      find.text('Подарок забран — завтра будет следующий'),
      findsOneWidget,
    );
  });

  testWidgets('вчера пропуск — серию можно выкупить за 30 монет', (
    tester,
  ) async {
    final bear = BearController();
    final game = GameState(
      bear: bear,
      profile: PetProfile(name: 'Тедди', birthAt: DateTime(2026, 9, 1)),
    );
    addTearDown(game.dispose);
    addTearDown(bear.dispose);
    DailyInfo broken({required bool restore}) => DailyInfo.fromJson({
      'gift': {
        'available': true,
        'next_day': restore ? 1 : 4,
        'claimed_day': 3,
        'rewards': [20, 20, 20, 20, 20, 20, 70],
        'can_restore': restore,
        'restore_price': 30,
      },
    });
    game.setDaily(broken(restore: true));
    var calls = 0;
    game.onRestoreStreak = () async {
      calls++;
      game.setDaily(broken(restore: false));
      return RestoreResult.ok;
    };
    await tester.pumpWidget(wrap(DailySheet(game: game)));
    expect(
      find.text('Вчера пропущен день — серия прервалась.'),
      findsOneWidget,
    );
    expect(find.text('Вернуть за 30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-restore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(find.text('Серия вернулась!'), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-restore')), findsNothing);
    expect(find.text('Забрать +20'), findsOneWidget);
  });
}
