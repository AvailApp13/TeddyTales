import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_phrases.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/birth_scene_script.dart';

void main() {
  group('BearPhrases — состав (КП 13.3)', () {
    test('ровно 30 реплик', () {
      expect(BearPhrases.all, hasLength(30));
    });

    test('идентификаторы уникальны', () {
      final ids = BearPhrases.all.map((p) => p.id).toSet();

      expect(ids, hasLength(BearPhrases.all.length));
    });

    test('каждая реплика переведена на три языка (КП 13.4)', () {
      for (final phrase in BearPhrases.all) {
        for (final language in BearLanguage.values) {
          expect(
            phrase.text(language),
            isNotEmpty,
            reason: 'нет перевода ${language.name} для ${phrase.id}',
          );
        }
      }
    });

    test('переводы не совпадают друг с другом дословно', () {
      for (final phrase in BearPhrases.all) {
        expect(
          {phrase.ru, phrase.en, phrase.zh},
          hasLength(3),
          reason: 'подозрительно одинаковые переводы у ${phrase.id}',
        );
      }
    });

    test('для каждого контекста есть хотя бы одна реплика', () {
      for (final context in BearPhraseContext.values) {
        expect(
          BearPhrases.forContext(context),
          isNotEmpty,
          reason: 'нет реплик для ${context.name}',
        );
      }
    });
  });

  group('BearPhrases — выбор', () {
    test('каждому состоянию покоя соответствует контекст', () {
      for (final mood in BearMood.values) {
        final context = BearPhrases.contextForMood(mood);
        expect(BearPhrases.forContext(context), isNotEmpty);
      }
    });

    test('random возвращает реплику своего контекста', () {
      final random = Random(42);

      for (var i = 0; i < 20; i++) {
        final phrase = BearPhrases.random(
          BearPhraseContext.hungry,
          random: random,
        );
        expect(phrase, isNotNull);
        expect(phrase!.context, BearPhraseContext.hungry);
      }
    });
  });

  group('BirthSceneScript (КП 2.1)', () {
    const script = BirthSceneScript();

    test('длительность в диапазоне 20–30 секунд', () {
      expect(script.duration.inSeconds, greaterThanOrEqualTo(20));
      expect(script.duration.inSeconds, lessThanOrEqualTo(30));
    });

    test('«Пропустить» появляется через 5 секунд', () {
      expect(script.canSkipAt(const Duration(seconds: 4)), isFalse);
      expect(script.canSkipAt(const Duration(seconds: 5)), isTrue);
    });

    test('субтитры покрывают всю сцену без разрывов', () {
      for (var second = 0; second < script.duration.inSeconds; second++) {
        expect(
          script.cueAt(Duration(seconds: second)),
          isNotNull,
          reason: 'нет субтитра на $second-й секунде',
        );
      }
    });

    test('субтитры не накладываются друг на друга', () {
      final cues = script.cues;

      for (var i = 1; i < cues.length; i++) {
        expect(cues[i].start, greaterThanOrEqualTo(cues[i - 1].end));
      }
    });

    // Тексты субтитров переехали в ARB (ключи birthCue*, см.
    // lib/l10n/birth_l10n.dart): совпадение ключей трёх языков проверяет
    // gen-l10n, здесь остаётся проверить сам сценарий.
    test('каждому субтитру отвечает свой шаг сценария', () {
      final ids = script.cues.map((cue) => cue.id).toSet();
      expect(ids, hasLength(script.cues.length));
    });

    test('сцена заканчивается на своей длительности', () {
      expect(script.isFinishedAt(const Duration(seconds: 25)), isFalse);
      expect(script.isFinishedAt(script.duration), isTrue);
    });
  });
}
