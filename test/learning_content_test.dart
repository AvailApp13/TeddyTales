import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_phrases.dart' show BearLanguage;
import 'package:teddy_tales/game/learning_content.dart';

/// Контент обучения проверяется здесь, а не только в генераторе.
///
/// Генератор живёт вне сборки: его запускают руками, и если кто-то правит
/// `learning_content.dart` напрямую — а так и будет, когда понадобится
/// поменять одно задание, — генератор об этом не узнает. Эти проверки ловят
/// поломку при обычном прогоне тестов.
void main() {
  group('Контент обучения (КП 9)', () {
    test('три категории по десять уровней', () {
      expect(eduContent.keys.toSet(), {'colors', 'count', 'world'});
      for (final entry in eduContent.entries) {
        expect(
          entry.value.length,
          eduLevelsPerCategory,
          reason: 'категория ${entry.key}',
        );
      }
    });

    test('ровно 300 заданий — столько требует КП 9.4', () {
      final total = eduContent.values
          .expand((levels) => levels)
          .fold<int>(0, (sum, tasks) => sum + tasks.length);
      expect(total, 300);
    });

    test('в каждом уровне по десять заданий', () {
      for (final entry in eduContent.entries) {
        for (var level = 0; level < entry.value.length; level++) {
          expect(
            entry.value[level].length,
            eduTasksPerLevel,
            reason: '${entry.key}, уровень ${level + 1}',
          );
        }
      }
    });

    test('четыре разных варианта, верный — среди них', () {
      for (final task in _allTasks()) {
        expect(task.options.length, 4, reason: task.question(BearLanguage.ru));
        expect(
          task.options.toSet().length,
          4,
          reason: 'повтор среди вариантов: ${task.options}',
        );
        expect(task.correct, inInclusiveRange(0, 3));
      }
    });

    test('вопрос переведён на все три языка', () {
      for (final task in _allTasks()) {
        for (final language in BearLanguage.values) {
          expect(
            task.question(language).trim(),
            isNotEmpty,
            reason: 'пустой перевод на ${language.name}',
          );
        }
      }
    });

    test('русский и английский тексты действительно разные', () {
      // Числовые задания вроде «2 + 3» на всех языках выглядят одинаково,
      // поэтому сверяем только те, где есть буквы.
      final letters = RegExp(r'[A-Za-zА-Яа-я]');
      for (final task in _allTasks()) {
        final ru = task.question(BearLanguage.ru);
        final en = task.question(BearLanguage.en);
        if (!letters.hasMatch(ru)) continue;
        expect(ru, isNot(en), reason: 'не переведено: $ru');
      }
    });
  });
}

Iterable<EduTask> _allTasks() =>
    eduContent.values.expand((levels) => levels).expand((tasks) => tasks);
