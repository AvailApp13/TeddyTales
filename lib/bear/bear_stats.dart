import 'bear_rig_spec.dart';

/// Игровые характеристики мишки.
///
/// ЗАГЛУШКА до ответа по открытому вопросу 8.1 ТЗ: точный список характеристик
/// (голод? настроение? чистота? энергия?) и их decay-таймеры не подтверждены.
/// Здесь только то, что явно названо в разделе 5 ТЗ: `hunger`, `mood`,
/// `growthStage`. Механика пренебрежения/болезни (вопрос 8.2) не реализована —
/// не выдумываем.
///
/// Класс намеренно не знает про Rive и Flutter: его можно гонять в тестах без
/// нативных библиотек `rive_native`.
class BearStats {
  const BearStats({
    this.hunger = 50,
    this.mood = 50,
    this.growthStage = BearGrowthStage.cub,
  });

  /// Голод, 0–100. Больше — сытнее.
  ///
  /// Направление шкалы выбрано так, чтобы 0 = «плохо», 100 = «хорошо» — как у
  /// [mood]. В риге это удобно: обе величины можно скармливать blend state
  /// одинаково. Если в редакторе окажется наоборот («100 = голоден»),
  /// инвертировать нужно здесь, а не в биндинге.
  final double hunger;

  /// Настроение, 0–100. Управляет blend state выражения морды (раздел 5 ТЗ).
  final double mood;

  /// Стадия роста.
  final BearGrowthStage growthStage;

  static const double min = 0;
  static const double max = 100;

  BearStats copyWith({
    double? hunger,
    double? mood,
    BearGrowthStage? growthStage,
  }) {
    return BearStats(
      hunger: clamp(hunger ?? this.hunger),
      mood: clamp(mood ?? this.mood),
      growthStage: growthStage ?? this.growthStage,
    );
  }

  /// Приводит значение характеристики в допустимый диапазон 0–100.
  static double clamp(double value) => value.clamp(min, max);

  @override
  bool operator ==(Object other) =>
      other is BearStats &&
      other.hunger == hunger &&
      other.mood == mood &&
      other.growthStage == growthStage;

  @override
  int get hashCode => Object.hash(hunger, mood, growthStage);

  @override
  String toString() =>
      'BearStats(hunger: $hunger, mood: $mood, growthStage: ${growthStage.name})';
}

/// Скорость затухания характеристик, единиц шкалы в секунду.
///
/// ЗАГЛУШКА: конкретные таймеры — открытый вопрос 8.1 ТЗ. Значения по умолчанию
/// подобраны только чтобы decay был заметен в дев-сборке (полная шкала примерно
/// за час), а не как продуктовый баланс.
///
/// Отдельный вопрос — **где** живёт decay. Раздел 5 ТЗ описывает его как
/// Luau-скрипт внутри Rive (паттерн Sasquatch). Если решим оставить его там,
/// приложение не должно считать его второй раз: передавайте
/// [BearDecayConfig.disabled] в [BearController].
class BearDecayConfig {
  const BearDecayConfig({
    this.hungerPerSecond = 100 / 3600,
    this.moodPerSecond = 100 / 5400,
  });

  /// Decay выключен — значения меняются только явными вызовами.
  /// Использовать, если затухание считает Luau-скрипт внутри рига.
  const BearDecayConfig.disabled() : hungerPerSecond = 0, moodPerSecond = 0;

  final double hungerPerSecond;
  final double moodPerSecond;

  bool get isEnabled => hungerPerSecond != 0 || moodPerSecond != 0;

  /// Применяет затухание за [elapsed] к [stats].
  ///
  /// Настроение дополнительно проседает, когда мишка голоден: связь голода и
  /// настроения в ТЗ не описана, но без неё `hunger` ни на что не влияет.
  /// Помечено как допущение — снести одной строкой, если Руслан скажет иначе.
  BearStats apply(BearStats stats, Duration elapsed) {
    if (!isEnabled || elapsed <= Duration.zero) return stats;

    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final hunger = stats.hunger - hungerPerSecond * seconds;

    // ДОПУЩЕНИЕ (не из ТЗ): голодный мишка грустит быстрее.
    final isHungry = hunger < 25;
    final moodRate = isHungry ? moodPerSecond * 2 : moodPerSecond;
    final mood = stats.mood - moodRate * seconds;

    return stats.copyWith(hunger: hunger, mood: mood);
  }
}
