/// Пять показателей ухода, 0–100 (КП 6.1 и панель показателей на главном
/// экране, КП 3.2).
///
/// Это состояние приложения, а не рига: в риг они не уезжают. Из них
/// выводится единственный вход `mood` — см. `bear_mood_policy.dart`.
///
/// Класс не знает про Rive и Flutter: тестируется без нативных библиотек.
class BearCareStats {
  const BearCareStats({
    this.food = 100,
    this.hygiene = 100,
    this.sleep = 100,
    this.play = 100,
    this.love = 100,
  });

  /// Еда. Низкое значение → `mood = hungry`.
  final double food;

  /// Гигиена. Низкое значение → `mood = dirty` (только стадии 3–5).
  final double hygiene;

  /// Сон. Низкое значение → `mood = sleepy`.
  final double sleep;

  /// Игра. Своего idle-состояния нет — влияет на общий фон (happy/sad).
  final double play;

  /// Любовь. Своего idle-состояния нет — влияет на общий фон (happy/sad).
  final double love;

  static const double min = 0;
  static const double max = 100;

  /// Все пять значений в порядке панели показателей.
  List<double> get all => <double>[food, hygiene, sleep, play, love];

  /// Средний уровень ухода. По нему выбирается `happy` / `sad`.
  double get average => all.reduce((a, b) => a + b) / all.length;

  BearCareStats copyWith({
    double? food,
    double? hygiene,
    double? sleep,
    double? play,
    double? love,
  }) {
    return BearCareStats(
      food: clamp(food ?? this.food),
      hygiene: clamp(hygiene ?? this.hygiene),
      sleep: clamp(sleep ?? this.sleep),
      play: clamp(play ?? this.play),
      love: clamp(love ?? this.love),
    );
  }

  static double clamp(double value) => value.clamp(min, max);

  @override
  bool operator ==(Object other) =>
      other is BearCareStats &&
      other.food == food &&
      other.hygiene == hygiene &&
      other.sleep == sleep &&
      other.play == play &&
      other.love == love;

  @override
  int get hashCode => Object.hash(food, hygiene, sleep, play, love);

  @override
  String toString() =>
      'BearCareStats(food: $food, hygiene: $hygiene, sleep: $sleep, '
      'play: $play, love: $love)';
}

/// Скорость падения показателей, единиц шкалы в секунду.
///
/// ЗАГЛУШКА. По КП 15.4 скорости показателей настраиваются из панели
/// управления и хранятся на сервере, а по КП 1.5 время игры серверное —
/// перевод часов на телефоне не должен ускорять игру. Значения по умолчанию
/// подобраны только чтобы видеть движение в дев-сборке.
///
/// Когда появится backend (открытый вопрос: стек не подтверждён), этот объект
/// должен приезжать с сервера, а не жить в коде.
class BearDecayConfig {
  const BearDecayConfig({
    this.foodPerSecond = 100 / 14400, // полная шкала за 4 часа
    this.hygienePerSecond = 100 / 28800,
    this.sleepPerSecond = 100 / 21600,
    this.playPerSecond = 100 / 28800,
    this.lovePerSecond = 100 / 36000,
    this.floor = 20,
  });

  /// Затухание выключено — значения меняются только явными действиями.
  const BearDecayConfig.disabled()
    : foodPerSecond = 0,
      hygienePerSecond = 0,
      sleepPerSecond = 0,
      playPerSecond = 0,
      lovePerSecond = 0,
      floor = 0;

  final double foodPerSecond;
  final double hygienePerSecond;
  final double sleepPerSecond;
  final double playPerSecond;
  final double lovePerSecond;

  /// Безопасный предел (КП 6.3): при долгом отсутствии показатели не падают
  /// ниже этого уровня. Болезней и смерти в игре нет (КП 6.2), поэтому дно
  /// именно мягкое.
  ///
  /// Значение 20 — плейсхолдер, настраивается с сервера (КП 15.4).
  final double floor;

  bool get isEnabled =>
      foodPerSecond != 0 ||
      hygienePerSecond != 0 ||
      sleepPerSecond != 0 ||
      playPerSecond != 0 ||
      lovePerSecond != 0;

  /// Применяет затухание за [elapsed].
  ///
  /// Показатель, уже опустившийся ниже [floor] (например, его специально
  /// уронили в дев-панели), не поднимается — предел только не даёт падать
  /// дальше.
  BearCareStats apply(BearCareStats stats, Duration elapsed) {
    if (!isEnabled || elapsed <= Duration.zero) return stats;

    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;

    double decayed(double value, double rate) {
      final next = value - rate * seconds;
      return next < floor ? (value < floor ? value : floor) : next;
    }

    return stats.copyWith(
      food: decayed(stats.food, foodPerSecond),
      hygiene: decayed(stats.hygiene, hygienePerSecond),
      sleep: decayed(stats.sleep, sleepPerSecond),
      play: decayed(stats.play, playPerSecond),
      love: decayed(stats.love, lovePerSecond),
    );
  }
}
