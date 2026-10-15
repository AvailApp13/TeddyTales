import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/bear/bear_rig_spec.dart';
import 'package:teddy_tales/bear/rive_bear_trial.dart';
import 'package:teddy_tales/widgets/emotion_test_strip.dart';

/// Второй герой (заказчик 14.10): файл рига по полу и проверочная плитка
/// «Мальчик / Девочка» в ленте эмоций.
void main() {
  test('файл и артборд рига — по герою', () {
    expect(bearAsset(BearSkin.boy), kTrialBearAsset);
    expect(bearAsset(BearSkin.girl), kGirlBearAsset);
    expect(bearArtboard(BearSkin.boy), 'Bear_Boy');
    expect(bearArtboard(BearSkin.girl), 'Bear_Girl');
  });

  test('проверочный герой подменяет настоящего, пока выбран', () {
    final cue = BearFaceCue();
    addTearDown(cue.dispose);
    expect(cue.heroOr(BearSkin.boy), BearSkin.boy);
    cue.hero.value = BearSkin.girl;
    expect(cue.heroOr(BearSkin.boy), BearSkin.girl);
    cue.hero.value = null;
    expect(cue.heroOr(BearSkin.girl), BearSkin.girl);
  });

  testWidgets('плитка героя первая в ленте и переключает героя', (
    tester,
  ) async {
    final cue = BearFaceCue();
    addTearDown(cue.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: EmotionTestStrip(cue: cue),
          ),
        ),
      ),
    );
    expect(find.text('Мальчик'), findsOneWidget);
    expect(find.text('Улыбка'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emotion-test-hero')));
    await tester.pump();
    expect(cue.hero.value, BearSkin.girl);
    expect(find.text('Девочка'), findsOneWidget);
    // эмоции не трогаются
    expect(cue.face, isNull);

    await tester.tap(find.byKey(const ValueKey('emotion-test-hero')));
    await tester.pump();
    expect(cue.hero.value, BearSkin.boy);
  });
}
