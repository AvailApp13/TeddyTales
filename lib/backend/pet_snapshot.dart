import '../bear/bear_rig_spec.dart';
import '../bear/bear_stats.dart';
import '../bear/bear_state.dart';
import '../bear/bear_zodiac.dart';
import '../game/pet_profile.dart';

/// Состояние игрока целиком, как его отдаёт сервер одним запросом (КП 1.4).
///
/// Разбор вынесен в отдельный класс с тестами не из любви к слоям. Это
/// граница, где данные перестают быть нашими: за ней JSON, пришедший по
/// сети, и любое поле в нём может оказаться не того типа, пустым или
/// отсутствовать — после правки схемы, после отката миграции, после сбоя.
/// Разбор, размазанный по экранам, падал бы каждый раз в новом месте.
///
/// Поэтому правило здесь одно: **ни одно отсутствующее поле не роняет
/// приложение**. Нет показателей — берём значения по умолчанию, нет
/// гардероба — мишка голый, нет прогресса обучения — он нулевой. Пустой
/// экран лучше сообщения об ошибке, а сообщение об ошибке лучше вылета.
class PetSnapshot {
  const PetSnapshot({
    required this.petId,
    required this.profile,
    required this.state,
    required this.inventory,
    required this.placed,
    required this.eduProgress,
    required this.serverTime,
  });

  /// Идентификатор питомца — с ним ходят все действия ухода и покупки.
  final String petId;

  final PetProfile profile;
  final BearState state;

  /// Что куплено (КП 10.8) и что расставлено в комнате (КП 10.7).
  final Set<String> inventory;
  final Set<String> placed;

  /// Сколько уровней пройдено по категориям (КП 9.2).
  final Map<String, int> eduProgress;

  /// Момент по серверным часам, на который снимок верен (КП 1.5).
  ///
  /// Держится рядом с данными, потому что показатели уже пересчитаны на
  /// него: сравнив с часами телефона, можно узнать расхождение, не
  /// доверяя ни тем ни другим по отдельности.
  final DateTime serverTime;

  factory PetSnapshot.fromJson(Map<String, dynamic> json) {
    final pet = _map(json['pet']);
    final stats = _map(json['stats']);
    final outfit = _map(json['outfit']);

    return PetSnapshot(
      petId: pet['id']?.toString() ?? '',
      profile: PetProfile(
        name: _name(pet['name']),
        birthAt: _time(pet['birth_at']) ?? DateTime.now(),
        skin: _skin(pet['skin']),
        zodiac: _zodiac(pet['zodiac']),
        coins: _int(pet['coins']),
      ),
      state: BearState(
        stats: BearCareStats(
          food: _double(stats['food'], 100),
          hygiene: _double(stats['hygiene'], 100),
          sleep: _double(stats['sleep'], 100),
          play: _double(stats['play'], 100),
          love: _double(stats['love'], 100),
        ),
        stage: _enumOf(BearStage.values, pet['stage'], BearStage.newborn),
        trait: _enumOf(BearTrait.values, pet['trait'], BearTrait.active),
        skin: _skin(pet['skin']),
        outfit: BearOutfit(
          outfitId: _int(outfit['outfit_id']),
          topId: _int(outfit['top_id']),
          bottomId: _int(outfit['bottom_id']),
          headwearId: _int(outfit['headwear_id']),
          shoesId: _int(outfit['shoes_id']),
          accessoryId: _int(outfit['accessory_id']),
        ),
      ),
      inventory: _ids(json['inventory']),
      placed: _ids(json['placed']),
      eduProgress: _progress(json['edu']),
      serverTime: _time(json['server_time']) ?? DateTime.now(),
    );
  }

  // --- Разбор отдельных значений ------------------------------------------
  //
  // Все читалки ниже терпимы к мусору намеренно: сервер может прислать
  // число строкой, строку числом, null вместо значения. Падать на этом
  // нельзя — за неверным полем стоит живой игрок со своим прогрессом.

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static String _name(Object? value) {
    final name = value?.toString().trim() ?? '';
    return name.isEmpty ? PetProfile.defaultName : name;
  }

  static int _int(Object? value) => switch (value) {
    int v => v,
    num v => v.round(),
    String v => int.tryParse(v) ?? 0,
    _ => 0,
  };

  static double _double(Object? value, double fallback) => switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v) ?? fallback,
    _ => fallback,
  };

  static DateTime? _time(Object? value) {
    if (value is DateTime) return value;
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    // Время с сервера приходит со смещением, приводим к UTC: иначе
    // сравнение с локальными часами даст разницу в часовой пояс.
    return DateTime.tryParse(text)?.toUtc();
  }

  static BearSkin _skin(Object? value) =>
      _enumOf(BearSkin.values, value, BearSkin.boy);

  static BearZodiac? _zodiac(Object? value) {
    final name = value?.toString();
    if (name == null || name.isEmpty) return null;
    for (final zodiac in BearZodiac.values) {
      if (zodiac.name == name) return zodiac;
    }
    return null;
  }

  /// Ищет вариант перечисления по имени. Имена в базе совпадают с именами
  /// в Dart буква в букву — ради этого они там и заведены так.
  static T _enumOf<T extends Enum>(List<T> values, Object? value, T fallback) {
    final name = value?.toString();
    for (final item in values) {
      if (item.name == name) return item;
    }
    return fallback;
  }

  static Set<String> _ids(Object? value) =>
      value is List ? value.map((item) => item.toString()).toSet() : <String>{};

  static Map<String, int> _progress(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): _int(entry.value),
    };
  }
}
