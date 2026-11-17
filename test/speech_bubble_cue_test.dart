import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear.dart';
import 'package:teddy_tales/widgets/pet_speech_bubble.dart';

/// Реплики по событиям (КП 13.3). До 17.11 пузырь знал только настроение и
/// просьбу: приветствие, «после еды / мытья / игры / ласки», «проснулся» и
/// «вырос» — 13 из 32 реплик — не показывались никогда.
void main() {
  setUp(PetSpeechBubble.resetSession);

  Widget bubble({BearPhraseCue? cue, bool forgotten = false}) =>
      MaterialApp(
        home: Center(
          child: PetSpeechBubble(
            mood: BearMood.normal,
            initiative: null,
            forgotten: forgotten,
            cue: cue,
          ),
        ),
      );

  /// Какие реплики сейчас в облачке (всё облачко печатается по буквам, а
  /// размер держит полная реплика — она в дереве с первого кадра).
  Set<String> shown(WidgetTester tester) => {
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (w.data != null) w.data!,
    for (final w in tester.widgetList<RichText>(find.byType(RichText)))
      w.text.toPlainText(),
  };

  bool says(WidgetTester tester, BearPhraseContext context) {
    final texts = shown(tester);
    return BearPhrases.forContext(
      context,
    ).any((p) => texts.any((t) => t.contains(p.ru)));
  }

  testWidgets('первое облачко за запуск — приветствие', (tester) async {
    await tester.pumpWidget(bubble());
    expect(says(tester, BearPhraseContext.greeting), isTrue);
  });

  testWidgets('забытый мишка не здоровается, а жалуется', (tester) async {
    await tester.pumpWidget(bubble(forgotten: true));
    expect(says(tester, BearPhraseContext.forgotten), isTrue);
  });

  testWidgets('после приветствия — реплика по событию', (tester) async {
    await tester.pumpWidget(bubble());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Приветствие договорено и растаяло.
    await tester.pump(const Duration(seconds: 10));

    final cue = BearPhraseCue(BearPhraseContext.afterFeed, 1, DateTime.now());
    await tester.pumpWidget(bubble(cue: cue));
    expect(says(tester, BearPhraseContext.afterFeed), isTrue);
  });

  testWidgets('старый повод не вспоминается', (tester) async {
    await tester.pumpWidget(bubble());
    await tester.pump(const Duration(seconds: 10));

    final old = BearPhraseCue(
      BearPhraseContext.afterFeed,
      1,
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    await tester.pumpWidget(bubble(cue: old));
    expect(says(tester, BearPhraseContext.afterFeed), isFalse);
  });

  test('контроллер даёт повод после ухода и взросления', () {
    final bear = BearController();
    addTearDown(bear.dispose);

    bear.petBear();
    expect(bear.phraseCue?.context, BearPhraseContext.afterPet);
    final first = bear.phraseCue!.serial;

    bear.feedBear();
    expect(bear.phraseCue?.context, BearPhraseContext.afterFeed);
    expect(bear.phraseCue!.serial, greaterThan(first));

    bear.wakeBear();
    expect(bear.phraseCue?.context, BearPhraseContext.afterWake);

    bear.growUp();
    expect(bear.phraseCue?.context, BearPhraseContext.stageUp);
  });

  test('у каждой реплики есть путь в облачко', () {
    // Контексты, которые пузырь берёт из настроения и просьбы.
    final reachable = <BearPhraseContext>{
      BearPhraseContext.greeting,
      BearPhraseContext.forgotten,
      for (final m in BearMood.values) BearPhrases.contextForMood(m),
      BearPhraseContext.invitePlay,
      BearPhraseContext.inviteLearn,
      BearPhraseContext.stageUp,
      for (final a in BearAction.values)
        ?BearPhraseCue.afterAction(a),
    };
    for (final p in BearPhrases.all) {
      expect(reachable, contains(p.context), reason: p.id);
    }
  });
}
