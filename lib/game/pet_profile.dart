import '../bear/bear_rig_spec.dart';
import '../bear/bear_zodiac.dart';

/// Карточка питомца: то, что задаётся при рождении и дальше почти не меняется
/// (КП 2.2, 2.3, 14.1).
///
/// Пол, дату рождения и знак зодиака определяет сервер (КП 2.4, 2.5); имя
/// выбирает пользователь. Монеты лежат здесь же, потому что шапка главного
/// экрана показывает их рядом с именем (КП 3.3) — полноценная экономика
/// (КП 11) в этот модуль не входит.
class PetProfile {
  const PetProfile({
    required this.name,
    required this.birthAt,
    this.skin = BearSkin.boy,
    this.zodiac,
    this.coins = 0,
    this.birthHeightCm,
    this.birthWeightG,
  });

  /// Имя питомца, 2–15 символов (КП 2.3).
  final String name;

  /// Имя-заглушка до того, как пользователь назвал питомца сам. Хранится
  /// как сентинел: UI показывает его через `petDisplayName`, переводя на
  /// язык интерфейса; своё имя пользователя показывается как есть.
  static const String defaultName = 'Мой малыш';

  /// Момент рождения — от него считается игровой возраст.
  final DateTime birthAt;

  /// Кто из двух героев: SLOW или JOY.
  final BearSkin skin;

  /// Знак зодиака по игровому календарю (КП 2.5).
  final BearZodiac? zodiac;

  /// Баланс монет (КП 11.1).
  final int coins;

  /// Рост и вес при рождении (КП 2.2) — назначает сервер (миграция 0013).
  /// `null` — сервер их ещё не прислал: карточка покажет заглушку.
  final double? birthHeightCm;
  final double? birthWeightG;

  /// Насколько мишка вырос к стадии [stage] от размеров при рождении:
  /// «Карманный мишка» 15 см и 180 г к взрослому становится примерно
  /// 25 см и 400 г (решение заказчика 25.09 — растут по стадиям).
  static double heightFactor(BearStage stage) => switch (stage) {
    BearStage.newborn => 1.0,
    BearStage.crawling => 1.15,
    BearStage.firstSteps => 1.3,
    BearStage.growing => 1.5,
    BearStage.adult => 1.65,
  };

  static double weightFactor(BearStage stage) => switch (stage) {
    BearStage.newborn => 1.0,
    BearStage.crawling => 1.3,
    BearStage.firstSteps => 1.6,
    BearStage.growing => 1.9,
    BearStage.adult => 2.2,
  };

  /// Текущий рост, см, на стадии [stage].
  double? heightAt(BearStage stage) {
    final h = birthHeightCm;
    return h == null ? null : h * heightFactor(stage);
  }

  /// Текущий вес, г, на стадии [stage].
  double? weightAt(BearStage stage) {
    final w = birthWeightG;
    return w == null ? null : w * weightFactor(stage);
  }

  static const int minNameLength = 2;
  static const int maxNameLength = 15;

  /// Проверка длины имени. Фильтр недопустимых слов (КП 2.3) — на сервере:
  /// стоп-словарь и очередь спорных живут в панели управления (КП 15.6).
  static bool isNameLengthValid(String name) {
    final trimmed = name.trim();
    return trimmed.length >= minNameLength && trimmed.length <= maxNameLength;
  }

  PetProfile copyWith({
    String? name,
    DateTime? birthAt,
    BearSkin? skin,
    BearZodiac? zodiac,
    int? coins,
    double? birthHeightCm,
    double? birthWeightG,
  }) {
    return PetProfile(
      name: name ?? this.name,
      birthAt: birthAt ?? this.birthAt,
      skin: skin ?? this.skin,
      zodiac: zodiac ?? this.zodiac,
      coins: coins ?? this.coins,
      birthHeightCm: birthHeightCm ?? this.birthHeightCm,
      birthWeightG: birthWeightG ?? this.birthWeightG,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PetProfile &&
      other.name == name &&
      other.birthAt == birthAt &&
      other.skin == skin &&
      other.zodiac == zodiac &&
      other.coins == coins &&
      other.birthHeightCm == birthHeightCm &&
      other.birthWeightG == birthWeightG;

  @override
  int get hashCode => Object.hash(
    name,
    birthAt,
    skin,
    zodiac,
    coins,
    birthHeightCm,
    birthWeightG,
  );

  @override
  String toString() => 'PetProfile($name, ${skin.heroName}, coins: $coins)';
}
