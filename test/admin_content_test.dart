import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/game/edu_tasks.dart';
import 'package:teddy_tales/game/learning_content.dart';
import 'package:teddy_tales/game/shop_items.dart';
import 'package:teddy_tales/notifications/smart_texts.dart';

/// Правки из панели управления доходят до приложения (КП 15.3, 15.4).
void main() {
  tearDown(() {
    ItemPrices.reset();
    BearPhrases.resetServer();
    NotificationTexts.reset();
    EduTasks.reset();
  });

  group('Задания обучения', () {
    List<Map<String, Object>> level(int n, {String ru = 'Вопрос'}) => [
      for (var i = 1; i <= eduTasksPerLevel; i++)
        {
          'category': 'colors',
          'level': n,
          'idx': i,
          'ru': '$ru $i',
          'en': 'Q $i',
          'zh': '问 $i',
          'options': ['1', '2', '3', '4'],
          'correct': 2,
        },
    ];

    test('полный уровень из панели заменяет уровень сборки', () {
      EduTasks.applyServer(level(1));
      final levels = EduTasks.levels('colors');
      expect(levels, hasLength(eduLevelsPerCategory));
      expect(levels[0][0].question(BearLanguage.ru), 'Вопрос 1');
      expect(levels[0][0].correct, 2);
      // Другие уровни и категории — из сборки.
      expect(levels[1], same(eduContent['colors']![1]));
      expect(EduTasks.levels('count'), same(eduContent['count']));
    });

    test('неполный или с ошибкой уровень — из сборки', () {
      final broken = level(1)..removeLast();
      final dup = level(2);
      dup[3] = {...dup[3], 'options': ['1', '1', '3', '4']};
      EduTasks.applyServer([...broken, ...dup]);
      final levels = EduTasks.levels('colors');
      expect(levels[0], same(eduContent['colors']![0]));
      expect(levels[1], same(eduContent['colors']![1]));
    });
  });

  group('Цены вещей', () {
    final item = ItemCatalog.furniture.firstWhere((i) => i.price > 0);

    test('цена из панели заменяет каталожную', () {
      final own = item.price;
      ItemPrices.apply({
        'item_prices': {item.id: own + 7},
      });
      expect(item.price, own + 7);
    });

    test('чего нет в панели или что не число — из каталога', () {
      final own = item.price;
      ItemPrices.apply({
        'item_prices': {item.id: 'дорого', 'nothing': 5},
      });
      expect(item.price, own);
    });
  });

  group('Реплики', () {
    test('переписанная в панели звучит, выключенная — нет', () {
      BearPhrases.applyServer([
        {
          'id': 'greeting_1',
          'context': 'greeting',
          'ru': 'Здравствуй!',
          'en': 'Hello!',
          'zh': '你好！',
          'enabled': true,
        },
        {'id': 'greeting_2', 'enabled': false},
      ]);
      final texts = BearPhrases.forContext(
        BearPhraseContext.greeting,
      ).map((p) => p.ru);
      expect(texts, contains('Здравствуй!'));
      expect(texts, isNot(contains('Привет! Что будем делать?')));
      // Остальные контексты — из кода.
      expect(BearPhrases.forContext(BearPhraseContext.idle), isNotEmpty);
    });

    test('выключили все реплики контекста — мишка не замолкает', () {
      BearPhrases.applyServer([
        for (final p in BearPhrases.forContext(BearPhraseContext.hungry))
          {'id': p.id, 'enabled': false},
      ]);
      expect(BearPhrases.forContext(BearPhraseContext.hungry), isNotEmpty);
    });

    test('у переписанной реплики девочка говорит текстом панели', () {
      BearPhrases.applyServer([
        {
          'id': 'greeting_1',
          'context': 'greeting',
          'ru': 'Ура, ты тут!',
          'en': 'Yay!',
          'zh': '耶！',
        },
      ]);
      final p = BearPhrases.current.firstWhere((p) => p.id == 'greeting_1');
      expect(p.text(BearLanguage.ru, girl: true), 'Ура, ты тут!');
    });
  });

  group('Тексты уведомлений', () {
    test('стартовый набор панели не перебивает живые тексты', () {
      final before = composeNotification(
        'hungry',
        name: 'Тедди',
        lang: BearLanguage.ru,
      );
      NotificationTexts.applyServer([
        {
          'kind': 'hungry',
          'title_ru': 'Малыш проголодался',
          'body_ru': 'Кажется, пора перекусить.',
          'title_en': 'Your little one is hungry',
          'body_en': 'Looks like it is time for a snack.',
          'title_zh': '宝宝饿了',
          'body_zh': '好像该吃点东西了。',
        },
      ]);
      final after = composeNotification(
        'hungry',
        name: 'Тедди',
        lang: BearLanguage.ru,
      );
      expect(after.title, before.title);
    });

    test('переписанный в панели текст звучит, с именем', () {
      NotificationTexts.applyServer([
        {
          'kind': 'hungry',
          'title_ru': '{name} ждёт обед',
          'body_ru': 'Загляни на кухню.',
          'title_en': 'Your little one is hungry',
          'body_en': 'Looks like it is time for a snack.',
        },
      ]);
      final ru = composeNotification(
        'hungry',
        name: 'Тедди',
        lang: BearLanguage.ru,
      );
      expect(ru.title, 'Тедди ждёт обед');
      expect(ru.body, 'Загляни на кухню.');
      // Английский в панели не меняли — живой текст.
      final en = composeNotification(
        'hungry',
        name: 'Teddy',
        lang: BearLanguage.en,
      );
      expect(en.title, isNot('Your little one is hungry'));
    });
  });
}
