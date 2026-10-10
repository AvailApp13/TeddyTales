import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/notifications/smart_texts.dart';

/// Живые тексты уведомлений (утверждено 25.09): с именем, по характеру,
/// с чередованием; несколько причин — одним текстом.
void main() {
  test('имя мишки в тексте, варианты чередуются', () {
    final a = composeNotification(
      'hungry',
      name: 'Тедди',
      lang: BearLanguage.ru,
    );
    final b = composeNotification(
      'hungry',
      name: 'Тедди',
      lang: BearLanguage.ru,
      seed: 1,
    );
    expect(a.title, 'Тедди проголодался');
    expect(b.title, isNot(a.title));
    expect('${b.title} ${b.body}', contains('Тедди'));
  });

  test('несколько причин — одна фраза', () {
    final ru = composeNotification(
      'hungry+sleep',
      name: 'Тедди',
      lang: BearLanguage.ru,
    );
    expect(ru.title, 'Тедди зовёт тебя');
    expect(ru.body, 'Тедди проголодался и хочет спать.');
    final en = composeNotification(
      'play+hungry+sleep',
      name: 'Teddy',
      lang: BearLanguage.en,
    );
    expect(en.body, 'Teddy wants to play, is hungry and is sleepy.');
  });

  test('«скучает» — по характеру', () {
    final affectionate = composeNotification(
      'miss',
      name: 'Тедди',
      lang: BearLanguage.ru,
      trait: BearTrait.affectionate,
    );
    expect(affectionate.body, contains('обнимашек'));
    final active = composeNotification(
      'miss',
      name: 'Тедди',
      lang: BearLanguage.ru,
      trait: BearTrait.active,
    );
    expect(active.body, isNot(affectionate.body));
  });

  test('имя по умолчанию заменяется словом «малыш» на языке', () {
    expect(
      notificationName('Мой малыш', BearLanguage.en, 'Мой малыш'),
      'Your little one',
    );
    expect(notificationName('Тишка', BearLanguage.ru, 'Мой малыш'), 'Тишка');
  });

  test('все виды есть на трёх языках', () {
    for (final lang in BearLanguage.values) {
      for (final kind in [
        'hungry',
        'play',
        'sleep',
        'task',
        'gift',
        'stage',
        'miss',
        'away',
        'week',
        'event',
      ]) {
        final copy = composeNotification(kind, name: 'X', lang: lang);
        expect(copy.title, isNotEmpty, reason: '$lang $kind');
        expect(copy.body, isNotEmpty, reason: '$lang $kind');
      }
    }
  });

  test('нарастание идёт под переключателями «Хочет играть» и «Подарок»', () {
    expect(switchOf('miss'), 'play');
    expect(switchOf('away'), 'gift');
    expect(switchOf('week'), 'gift');
    expect(switchOf('hungry'), 'hungry');
  });
}
