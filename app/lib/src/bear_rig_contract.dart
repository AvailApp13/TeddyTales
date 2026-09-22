// GENERATED FILE - DO NOT EDIT BY HAND.
//
// Source of truth: rig/bear_rig.json
// Regenerate:      cd tools && npm run gen:dart
//
// Every name below must exist verbatim in the Rive file. The lab
// (tools/ -> npm run lab) checks a .riv against the same spec, so a mismatch
// is caught before it reaches the app.

/// Names and ranges taken from the rig spec, shared by the Rive file,
/// the lab and this app.
abstract final class BearRig {
  BearRig._();

  /// Spec version this contract was generated from.
  static const int specVersion = 1;

  /// Flutter asset key for the exported Rive file.
  static const String asset = 'assets/rive/bear.riv';

  /// Artboards, one per hero (KP 2.4 - server picks the gender).
  static const String artboardBoy = 'Bear_Boy';
  static const String artboardGirl = 'Bear_Girl';

  /// Artboard used when the hero's gender is not known yet.
  static const String artboardDefault = 'Bear_Boy';

  /// State machine to run.
  static const String stateMachine = 'State Machine 1';

  /// View model backing the state machine.
  static const String viewModel = 'BearVM';
}

/// Number properties on the bear view model, with the ranges the rig expects.
enum BearNumber {
  /// Еда. 0 - голоден, 100 - сыт.
  /// Range 0..100, default 80. (spec, kp:6.1)
  food('food', 0.0, 100.0, 80.0, 20.0),
  /// Гигиена. 0 - неухожен, 100 - чистый.
  /// Range 0..100, default 80. (spec, kp:6.1)
  hygiene('hygiene', 0.0, 100.0, 80.0, 20.0),
  /// Сон. 0 - истощён, 100 - выспался.
  /// Range 0..100, default 80. (spec, kp:6.1)
  sleep('sleep', 0.0, 100.0, 80.0, 20.0),
  /// Игра. 0 - скучает, 100 - наигрался.
  /// Range 0..100, default 80. (spec, kp:6.1)
  play('play', 0.0, 100.0, 80.0, 20.0),
  /// Любовь. 0 - обделён вниманием, 100 - обласкан.
  /// Range 0..100, default 80. (spec, kp:6.1)
  love('love', 0.0, 100.0, 80.0, 20.0),
  /// Среднее пяти показателей. Считает приложение, риг только потребляет - чтобы формула менялась с сервера (КП 15.4), а не в .riv.
  /// Range 0..100, default 80. (derived, kp:5.7)
  careIndex('care_index', 0.0, 100.0, 80.0, 0.0),
  /// Слот «комплект». 0 - пусто, 1..8 - комплекты (КП 10.5).
  /// Range 0..8, default 0. (derived, kp:4.9+10.5)
  outfitBody('outfit_body', 0.0, 8.0, 0.0, 0.0),
  /// Слот «головной убор». 0 - пусто, 1..3.
  /// Range 0..3, default 0. (derived, kp:4.9+10.5)
  outfitHead('outfit_head', 0.0, 3.0, 0.0, 0.0),
  /// Слот «обувь». 0 - пусто, 1..2.
  /// Range 0..2, default 0. (derived, kp:4.9+10.5)
  outfitFeet('outfit_feet', 0.0, 2.0, 0.0, 0.0),
  /// Слот «аксессуар». 0 - пусто, 1..3.
  /// Range 0..3, default 0. (derived, kp:4.9+10.5)
  outfitAccessory('outfit_accessory', 0.0, 3.0, 0.0, 0.0);

  const BearNumber(this.path, this.min, this.max, this.initial, this.safeFloor);

  /// Property path as it appears in the Rive view model.
  final String path;
  final double min;
  final double max;
  final double initial;

  /// Floor that decay may not cross, so a long absence cannot empty the
  /// meters (KP 6.3). Direct player action may still go lower.
  final double safeFloor;

  /// Clamps [value] into this property's declared range.
  double clamp(double value) => value.clamp(min, max);

  /// Clamps [value] but never below [safeFloor] - used by decay.
  double clampWithFloor(double value) => value.clamp(safeFloor, max);
}

/// Текущая стадия роста. Длительности настраиваются с сервера (КП 5.6). (spec, kp:5.1-5.5)
///
/// Bound to the Rive enum `stage` via property `stage`.
enum BearStage {
  /// Новорождённый (1 день)
  newborn('newborn'),
  /// Ползающий малыш (~2 дня)
  crawler('crawler'),
  /// Первые шаги (1-2 дня)
  firstSteps('first_steps'),
  /// Подрастающий (до ~14 дня)
  growing('growing'),
  /// Взрослый (постоянно)
  adult('adult');

  const BearStage(this.wireName);

  /// Exact spelling of the value inside the Rive file.
  final String wireName;

  /// The view model property this enum is bound to.
  static const String property = 'stage';

  /// Value the rig starts at.
  static const BearStage initial = BearStage.newborn;

  /// Parses a value coming back from Rive or the backend.
  static BearStage? fromWire(String value) {
    for (final candidate in values) {
      if (candidate.wireName == value) return candidate;
    }
    return null;
  }
}

/// Тип характера. Влияет на покой, реакции и инициативы (КП 7.4). (spec, kp:7.1)
///
/// Bound to the Rive enum `trait` via property `trait`.
enum BearTrait {
  /// активный
  active('active'),
  /// любознательный
  curious('curious'),
  /// ласковый
  affectionate('affectionate'),
  /// спокойный
  calm('calm'),
  /// самостоятельный
  independent('independent'),
  /// замкнутый
  reserved('reserved');

  const BearTrait(this.wireName);

  /// Exact spelling of the value inside the Rive file.
  final String wireName;

  /// The view model property this enum is bound to.
  static const String property = 'trait';

  /// Value the rig starts at.
  static const BearTrait initial = BearTrait.calm;

  /// Parses a value coming back from Rive or the backend.
  static BearTrait? fromWire(String value) {
    for (final candidate in values) {
      if (candidate.wireName == value) return candidate;
    }
    return null;
  }
}

/// Итоговое настроение покоя. Вычисляется приложением из пяти показателей, а не хранится на сервере. (derived, kp:4.2)
///
/// Bound to the Rive enum `mood` via property `mood`.
enum BearMood {
  /// спокойное
  calm('calm'),
  /// радостное
  happy('happy'),
  /// грустное
  sad('sad'),
  /// голодное
  hungry('hungry'),
  /// сонное
  sleepy('sleepy'),
  /// неухоженное
  messy('messy');

  const BearMood(this.wireName);

  /// Exact spelling of the value inside the Rive file.
  final String wireName;

  /// The view model property this enum is bound to.
  static const String property = 'mood';

  /// Value the rig starts at.
  static const BearMood initial = BearMood.calm;

  /// Parses a value coming back from Rive or the backend.
  static BearMood? fromWire(String value) {
    for (final candidate in values) {
      if (candidate.wireName == value) return candidate;
    }
    return null;
  }
}

/// Trigger properties on the bear view model.
enum BearTrigger {
  /// Кормление. feedBear()
  /// (spec, kp:4.3)
  feed('feed'),
  /// Умывание. washBear()
  /// (spec, kp:4.3)
  wash('wash'),
  /// Укладывание спать. Имя с суффиксом, чтобы не конфликтовать с показателем sleep.
  /// (spec, kp:4.3)
  sleepAction('sleep_action'),
  /// Пробуждение.
  /// (spec, kp:4.3)
  wake('wake'),
  /// Игра. Суффикс по той же причине, что и у sleep_action.
  /// (spec, kp:4.3)
  playAction('play_action'),
  /// Поглаживание. petBear()
  /// (spec, kp:4.3)
  pet('pet'),
  /// Касание питомца на главном экране.
  /// (spec, kp:3.1)
  tap('tap'),
  /// Переход на следующую стадию: 2-3 секунды со свечением.
  /// (spec, kp:4.5)
  grow('grow'),
  /// Пузырь инициативы - питомец сам предлагает активность.
  /// (spec, kp:3.4)
  initiative('initiative'),
  /// Радость.
  /// (spec, kp:4.8)
  emoteJoy('emote_joy'),
  /// Огорчение.
  /// (spec, kp:4.8)
  emoteUpset('emote_upset'),
  /// Удивление.
  /// (spec, kp:4.8)
  emoteSurprise('emote_surprise'),
  /// Проявление любви.
  /// (spec, kp:4.8)
  emoteLove('emote_love');

  const BearTrigger(this.path);

  /// Property path as it appears in the Rive view model.
  final String path;
}

/// States declared by the rig spec. Useful for assertions and debug overlays;
/// the runtime drives transitions through the view model, not by name.
enum BearState {
  /// Покой: дыхание, моргание, микродвижения ушей и головы.
  idle('idle'),
  /// Перемещение: ползание, первые шаги, ходьба, развороты.
  move('move'),
  /// Действие ухода.
  careAction('care_action'),
  /// Эмоциональный акцент.
  emotionAccent('emotion_accent'),
  /// Поведение, характерное для типа характера.
  traitBehaviour('trait_behaviour'),
  /// Взросление со свечением, 2-3 секунды.
  growthTransition('growth_transition');

  const BearState(this.stateName);

  final String stateName;
}

/// PLACEHOLDER tuning values. Скорости затухания настраиваются из панели управления (КП 15.4) и здесь не зафиксированы. Значения ниже - заглушки для лаборатории и стенда, в продакшен не идут. Безопасный предел (КП 6.3) берётся из safeFloor каждого показателя.
abstract final class BearTuning {
  BearTuning._();

  /// Units lost per second while the app is in the foreground.
  static const Map<BearNumber, double> decayPerSecond = {
    BearNumber.food: 0.60,
    BearNumber.hygiene: 0.35,
    BearNumber.sleep: 0.45,
    BearNumber.play: 0.50,
    BearNumber.love: 0.40,
  };

  /// Units gained when the matching trigger fires.
  static const Map<BearTrigger, Map<BearNumber, double>> boost = {
    BearTrigger.feed: {BearNumber.food: 30.0, BearNumber.love: 3.0},
    BearTrigger.wash: {BearNumber.hygiene: 35.0},
    BearTrigger.sleepAction: {BearNumber.sleep: 40.0},
    BearTrigger.wake: {BearNumber.sleep: 5.0, BearNumber.play: 5.0},
    BearTrigger.playAction: {BearNumber.play: 30.0, BearNumber.love: 5.0},
    BearTrigger.pet: {BearNumber.love: 25.0},
    BearTrigger.tap: {BearNumber.love: 2.0},
    BearTrigger.emoteLove: {BearNumber.love: 5.0},
  };
}
