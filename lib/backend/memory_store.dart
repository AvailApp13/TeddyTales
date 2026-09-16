import '../bear/bear_action.dart';
import '../bear/bear_state.dart';
import '../game/pet_profile.dart';
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
  Future<PetSnapshot> completeLevel(String categoryId, int level) async {
    pending.add(BearAction.learn);
    return _snapshot;
  }

  @override
  Future<void> setPlaced(String itemId, {required bool placed}) async {
    final next = Set<String>.from(_snapshot.placed);
    if (placed) {
      next.add(itemId);
    } else {
      next.remove(itemId);
    }
    _snapshot = PetSnapshot(
      petId: _snapshot.petId,
      profile: _snapshot.profile,
      state: _snapshot.state,
      inventory: _snapshot.inventory,
      placed: next,
      eduProgress: _snapshot.eduProgress,
      serverTime: _snapshot.serverTime,
    );
  }

  @override
  Future<Map<String, dynamic>> config() async => _config;
}
