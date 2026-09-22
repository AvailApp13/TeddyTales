import 'bear_rig_contract.dart';

/// Пять показателей ухода (КП 6.1) как неизменяемое значение.
///
/// Здесь намеренно нет импортов Rive и Flutter: числами владеет игровая логика,
/// и только контроллер знает, что они в итоге управляют анимацией. Так это
/// остаётся тестируемым, а будущая смена бэкенда не дотянется до рига.
class BearVitals {
  BearVitals(Map<BearNumber, double> values)
      : _values = Map.unmodifiable({
          for (final number in BearNumber.values)
            number: number.clamp(values[number] ?? number.initial),
        });

  /// Стартовые значения из спецификации рига.
  BearVitals.initial() : this(const {});

  final Map<BearNumber, double> _values;

  double operator [](BearNumber number) => _values[number]!;

  /// Показатели ухода из КП 6.1 — без производных вроде [BearNumber.careIndex]
  /// и без слотов одежды.
  static const List<BearNumber> careMeters = [
    BearNumber.food,
    BearNumber.hygiene,
    BearNumber.sleep,
    BearNumber.play,
    BearNumber.love,
  ];

  /// Общая ухоженность 0..100 — среднее пяти показателей.
  ///
  /// КП 5.7: скорость роста зависит от общего ухода, а не от одного показателя.
  double get careIndex {
    var sum = 0.0;
    for (final meter in careMeters) {
      sum += _values[meter]!;
    }
    return sum / careMeters.length;
  }

  /// Настроение покоя, выводимое из показателей (КП 4.2).
  ///
  /// Порядок проверок задаёт приоритет: голод заметнее сонливости, а
  /// неухоженность — заметнее скуки. Пороги — заглушки до подтверждения.
  BearMood get mood {
    if (this[BearNumber.food] <= _lowThreshold) return BearMood.hungry;
    if (this[BearNumber.sleep] <= _lowThreshold) return BearMood.sleepy;
    if (this[BearNumber.hygiene] <= _lowThreshold) return BearMood.messy;
    if (careIndex <= _sadThreshold) return BearMood.sad;
    if (careIndex >= _happyThreshold) return BearMood.happy;
    return BearMood.calm;
  }

  static const double _lowThreshold = 30;
  static const double _sadThreshold = 45;
  static const double _happyThreshold = 80;

  BearVitals withValues(Map<BearNumber, double> changes) =>
      BearVitals({..._values, ...changes});

  /// Применяет [BearTuning.decayPerSecond] за [elapsed].
  ///
  /// Считается от реального времени, а не от числа кадров: пропущенный кадр или
  /// свёрнутое приложение не должны менять скорость, с которой мишка голодает.
  /// Затухание не опускает показатель ниже [BearNumber.safeFloor] — это
  /// «безопасный предел» из КП 6.3, чтобы возвращение после долгого перерыва не
  /// встречало пустые шкалы.
  BearVitals decayed(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return this;
    return withValues({
      for (final entry in BearTuning.decayPerSecond.entries)
        entry.key: entry.key.clampWithFloor(this[entry.key] - entry.value * seconds),
    });
  }

  /// Применяет прибавку, которую даёт [trigger] (КП 6.4).
  BearVitals boosted(BearTrigger trigger) {
    final boost = BearTuning.boost[trigger];
    if (boost == null) return this;
    return withValues({
      for (final entry in boost.entries) entry.key: this[entry.key] + entry.value,
    });
  }

  /// Положение [number] в его диапазоне, 0..1 — то, что нужно весу blend state.
  double normalized(BearNumber number) {
    final span = number.max - number.min;
    if (span <= 0) return 0;
    return ((this[number] - number.min) / span).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is BearVitals &&
      BearNumber.values.every((n) => (other[n] - this[n]).abs() < 1e-9);

  @override
  int get hashCode => Object.hashAll(BearNumber.values.map((n) => this[n].round()));

  @override
  String toString() {
    final parts = careMeters.map((m) => '${m.path}: ${this[m].toStringAsFixed(1)}');
    return 'BearVitals(${parts.join(', ')}, care: ${careIndex.toStringAsFixed(1)})';
  }
}
