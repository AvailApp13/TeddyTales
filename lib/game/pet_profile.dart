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

  static const int minNameLength = 2;
  static const int maxNameLength = 15;

  /// Проверка длины имени. Фильтр недопустимых слов (КП 2.3) — на сервере:
  /// стоп-словарь и очередь спорных живут в панели управления (КП 15.6).
  static bool isNameLengthValid(String name) {
    final trimmed = name.trim();
    return trimmed.length >= minNameLength &&
        trimmed.length <= maxNameLength;
  }

  PetProfile copyWith({
    String? name,
    DateTime? birthAt,
    BearSkin? skin,
    BearZodiac? zodiac,
    int? coins,
  }) {
    return PetProfile(
      name: name ?? this.name,
      birthAt: birthAt ?? this.birthAt,
      skin: skin ?? this.skin,
      zodiac: zodiac ?? this.zodiac,
      coins: coins ?? this.coins,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PetProfile &&
      other.name == name &&
      other.birthAt == birthAt &&
      other.skin == skin &&
      other.zodiac == zodiac &&
      other.coins == coins;

  @override
  int get hashCode => Object.hash(name, birthAt, skin, zodiac, coins);

  @override
  String toString() => 'PetProfile($name, ${skin.heroName}, coins: $coins)';
}
