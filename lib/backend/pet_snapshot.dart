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
    this.account = const AccountInfo(),
    this.named = true,
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

  /// Личный кабинет: как вошли, возраст, язык (КП 1.2, 1.3).
  final AccountInfo account;

  /// Дал ли человек имя малышу (КП 2.3). `false` — приложение спросит имя
  /// на первом запуске.
  final bool named;

  factory PetSnapshot.fromJson(Map<String, dynamic> json) {
    final pet = _map(json['pet']);
    final stats = _map(json['stats']);
    final outfit = _map(json['outfit']);
    // Кошелёк живёт на кабинете (миграция 0010). Старый ответ сервера и
    // старый кеш держали его на мишке — их тоже читаем.
    final account = _map(json['account']);
    final name = _name(pet['name']);

    return PetSnapshot(
      petId: pet['id']?.toString() ?? '',
      profile: PetProfile(
        name: name,
        birthAt: _time(pet['birth_at']) ?? DateTime.now(),
        skin: _skin(pet['skin']),
        zodiac: _zodiac(pet['zodiac']),
        coins: _int(account['coins'] ?? pet['coins']),
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
      account: AccountInfo(
        isAnonymous: account['is_anonymous'] != false,
        email: _text(account['email']),
        providers: _ids(account['providers']),
        playerAge: _intOrNull(account['player_age']),
        locale: _text(account['locale']),
        registeredAt: _time(account['registered_at']),
        emailConfirmed: account['email_confirmed'] == true,
      ),
      // Имя, данное до появления отметки named_at, тоже считается: такой
      // человек уже называл малыша в профиле, спрашивать заново незачем.
      named: pet['named_at'] != null || name != PetProfile.defaultName,
    );
  }

  /// Тот же снимок с другим кабинетом — для кеша и тестов.
  PetSnapshot copyWith({Set<String>? placed, AccountInfo? account}) =>
      PetSnapshot(
        petId: petId,
        profile: profile,
        state: state,
        inventory: inventory,
        placed: placed ?? this.placed,
        eduProgress: eduProgress,
        serverTime: serverTime,
        account: account ?? this.account,
        named: named,
      );

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

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(Object? value) => value == null ? null : _int(value);

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

/// Личный кабинет пользователя: как он вошёл и что о себе сказал.
///
/// Учётная запись создаётся сама при первом запуске, без регистрации
/// (КП 1.2), — это [isAnonymous]. Вход через Apple, Google или почту
/// привязывается к ней же (КП 1.3): id не меняется, кошелёк и мишка
/// остаются, а в [providers] появляется способ входа.
class AccountInfo {
  const AccountInfo({
    this.isAnonymous = true,
    this.email,
    this.providers = const {},
    this.playerAge,
    this.locale,
    this.registeredAt,
    this.emailConfirmed = false,
  });

  /// Без привязанного входа: удалишь приложение — потеряешь мишку.
  final bool isAnonymous;

  final String? email;

  /// Способы входа: `apple`, `google`, `email`… Пусто — только анонимный.
  final Set<String> providers;

  /// Возраст игрока (КП 9.1). `null` — ещё не спрашивали.
  final int? playerAge;

  final String? locale;

  /// Когда заведена учётная запись. В этот же момент родился мишка
  /// (миграция 0011).
  final DateTime? registeredAt;

  /// Подтвердил ли человек почту по ссылке из письма.
  final bool emailConfirmed;

  bool get hasEmail => providers.contains('email') || email != null;

  bool get hasApple => providers.contains('apple');
}
