import '../bear/bear_action.dart';
import '../bear/bear_state.dart';
import '../game/pet_profile.dart';
import '../game/referral_info.dart';
import 'pet_snapshot.dart';
import 'progress_store.dart';

/// Прогресс в памяти — для работы без сети (КП 1.1) и для тестов.
///
/// Это не вторая копия игровой логики: сервер считает всерьёз, а здесь
/// сделано ровно столько, чтобы приложение не выглядело сломанным, пока сети
/// нет. Никакой арифметики экономики тут быть не должно — иначе однажды две
/// реализации разойдутся, и разойдутся молча.
///
/// Действия при этом не теряются: они копятся в [pending], и когда связь
/// вернётся, их можно отправить серверу. Подтверждать монеты за них локально
/// нельзя — начисление остаётся за сервером (КП 11.1), иначе баланс на экране
/// разъедется с настоящим.
class MemoryStore implements ProgressStore {
  MemoryStore({PetSnapshot? initial, Map<String, dynamic>? config})
    : _snapshot = initial ?? emptySnapshot(),
      _config = config ?? const {};

  PetSnapshot _snapshot;
  final Map<String, dynamic> _config;
  bool _signedIn = false;

  /// Действия, которые не доехали до сервера. Отправляются, когда связь
  /// вернётся; порядок сохраняется, потому что «покормить, потом умыть» и
  /// «умыть, потом покормить» дают разный итог по показателям.
  final List<BearAction> pending = [];

  /// Пустое состояние: новый питомец без прогресса.
  static PetSnapshot emptySnapshot() => PetSnapshot(
    petId: 'local',
    profile: PetProfile(name: PetProfile.defaultName, birthAt: DateTime.now()),
    state: const BearState(),
    inventory: const {},
    placed: const {},
    eduProgress: const {},
    serverTime: DateTime.now().toUtc(),
  );

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<void> signIn() async => _signedIn = true;

  @override
  Future<PetSnapshot> load() async => _snapshot;

  /// Кладёт снимок, полученный откуда-то ещё, — например, последний удачный
  /// ответ сервера перед потерей связи.
  void adopt(PetSnapshot snapshot) => _snapshot = snapshot;

  @override
  Future<PetSnapshot> recordCare(BearAction action) async {
    pending.add(action);
    return _snapshot;
  }

  @override
  Future<PetSnapshot> buyItem(String itemId) async {
    // Покупка без сервера не проводится вовсе: цену и списание монет знает
    // только он (КП 11.1). Показать предмет купленным, а потом отобрать при
    // следующем входе — хуже, чем честно отказать.
    throw const ProgressStoreException('Покупка недоступна без сети');
  }

  @override
  Future<PetSnapshot> feedDish(String dishId) async {
    // Как и покупка: списать монеты может только сервер (КП 11.1). Мост
    // держит блюдо в очереди и отправит, когда появится связь.
    throw const ProgressStoreException('Еда за монеты — только при связи');
  }

  @override
  Future<PetSnapshot> completeRecipe(String recipeId) async {
    throw const ProgressStoreException('Награда за рецепт — только при связи');
  }

  @override
  Future<PetSnapshot> claimDailyGift() async {
    throw const ProgressStoreException('Подарок дня — только при связи');
  }

  @override
  Future<PetSnapshot> restoreGiftStreak() async {
    throw const ProgressStoreException('Серия — только при связи');
  }

  @override
  Future<ReferralInfo> referral() async {
    throw const ProgressStoreException('Приглашения — только при связи');
  }

  @override
  Future<PetSnapshot> redeemReferral(String code) async {
    throw const ProgressStoreException('Код друга — только при связи');
  }

  @override
  Future<PetSnapshot> completeLevel(String categoryId, int level) async {
    pending.add(BearAction.learn);
    return _snapshot;
  }

  @override
  Future<PetSnapshot> renamePet(String name, {String locale = 'ru'}) async {
    // Единственное действие, которое офлайн НЕ принимается.
    //
    // Всё остальное здесь копится и досылается: покормить без связи можно,
    // сервер потом пересчитает. С именем так нельзя — его проверяет список
    // запрещённых слов, который живёт только на сервере (КП 15.6). Принять
    // имя локально значит пустить в игру то, что модератор запретил, и
    // показать человеку, что имя сохранено, когда оно не сохранено.
    //
    // Проверено живьём 18.09: до этой строки имя менялось на экране, а в
    // базе оставалось прежним.
    throw const ProgressStoreException('Имя меняется только при связи');
  }

  @override
  Future<void> setPlaced(String itemId, {required bool placed}) async {
    final next = Set<String>.from(_snapshot.placed);
    if (placed) {
      next.add(itemId);
    } else {
      next.remove(itemId);
    }
    _snapshot = _snapshot.copyWith(placed: next);
  }

  @override
  Future<Map<String, dynamic>> config() async => _config;

  @override
  Future<void> deleteAccount() async {
    throw const ProgressStoreException('Аккаунт удаляется только при связи');
  }
}
