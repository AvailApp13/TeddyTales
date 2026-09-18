import 'package:supabase_flutter/supabase_flutter.dart';

import '../bear/bear_action.dart';
import 'pet_snapshot.dart';
import 'progress_store.dart';

/// Настройки подключения к бэкенду.
///
/// Публичный ключ лежит в коде намеренно — он для того и предназначен.
/// Секретом является не он, а построчная защита в базе: с этим ключом
/// клиент видит ровно свои строки и ничего сверх. Прятать его в переменную
/// окружения бессмысленно: он всё равно уедет в собранное приложение,
/// откуда его достаёт любой желающий за минуту.
///
/// Меняются оба значения через `--dart-define`, чтобы тестовый стенд можно
/// было собрать без правки кода.
abstract final class BackendConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bwvwzzquiepghebskaib.supabase.co',
  );

  /// Публикуемый ключ. Именно `sb_publishable_...`, а не старый `anon`:
  /// прежний был подписанным токеном с зашитым сроком жизни и менялся
  /// только вместе со всеми остальными ключами проекта, новый отзывается
  /// поодиночке.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_FP2uBrz1MNH8d22Gar5Igw_K3RVcpgw',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

/// Прогресс на сервере (КП 1.4).
///
/// Класс намеренно тонкий: он переводит вызовы в запросы и обратно, но сам
/// ничего не считает. Вся игровая арифметика — начисление монет, падение
/// показателей, цена предмета — живёт в функциях базы, потому что считать
/// это на клиенте значит позволить клиенту считать это как ему выгодно.
class SupabaseStore implements ProgressStore {
  SupabaseStore(this._client);

  /// Поднимает Supabase и отдаёт хранилище. Вызывается один раз при старте.
  static Future<SupabaseStore> connect() async {
    await Supabase.initialize(
      url: BackendConfig.url,
      publishableKey: BackendConfig.publishableKey,
    );
    return SupabaseStore(Supabase.instance.client);
  }

  final SupabaseClient _client;

  String? _petId;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Future<void> signIn() async {
    if (isSignedIn) return;
    try {
      await _client.auth.signInAnonymously();
    } on Object catch (error) {
      throw ProgressStoreException('Не удалось войти', cause: error);
    }
  }

  @override
  Future<PetSnapshot> load() async {
    // Идентификатор питомца заранее неизвестен: его создаёт сервер при
    // первом входе (КП 2.4). Поэтому сначала спрашиваем, какой питомец наш,
    // и только потом берём снимок.
    final id = _petId ?? await _findPet();
    return _snapshot('pet_snapshot', {'p_pet_id': id});
  }

  Future<String> _findPet() async {
    try {
      final rows = await _client.from('pets').select('id').limit(1);
      if (rows.isEmpty) {
        throw const ProgressStoreException(
          'У игрока нет питомца: триггер регистрации не отработал',
        );
      }
      return _petId = rows.first['id'].toString();
    } on ProgressStoreException {
      rethrow;
    } on Object catch (error) {
      throw ProgressStoreException('Не удалось найти питомца', cause: error);
    }
  }

  @override
  Future<PetSnapshot> recordCare(BearAction action) async {
    final id = _petId ?? await _findPet();
    return _snapshot('record_care', {
      'p_pet_id': id,
      'p_action': _actionName(action),
    });
  }

  @override
  Future<PetSnapshot> buyItem(String itemId) async {
    final id = _petId ?? await _findPet();
    return _snapshot('buy_item', {'p_pet_id': id, 'p_item_id': itemId});
  }

  @override
  Future<PetSnapshot> completeLevel(String categoryId, int level) async {
    final id = _petId ?? await _findPet();
    return _snapshot('complete_level', {
      'p_pet_id': id,
      'p_category': categoryId,
      'p_level': level,
    });
  }

  @override
  Future<PetSnapshot> renamePet(String name, {String locale = 'ru'}) async {
    final id = _petId ?? await _findPet();
    return _snapshot('rename_pet', {
      'p_pet_id': id,
      'p_name': name,
      'p_locale': locale,
    });
  }

  @override
  Future<void> setPlaced(String itemId, {required bool placed}) async {
    final player = _client.auth.currentUser?.id;
    if (player == null) {
      throw const ProgressStoreException('setPlaced без входа');
    }
    try {
      if (placed) {
        await _client.from('room_layout').upsert({
          'player_id': player,
          'item_id': itemId,
        });
      } else {
        await _client
            .from('room_layout')
            .delete()
            .eq('player_id', player)
            .eq('item_id', itemId);
      }
    } on Object catch (error) {
      throw ProgressStoreException(
        'Не удалось изменить обстановку',
        cause: error,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> config() async {
    try {
      final rows = await _client.from('game_config').select('key, value');
      return {for (final row in rows) row['key'].toString(): row['value']};
    } on Object catch (error) {
      throw ProgressStoreException(
        'Не удалось прочитать настройки',
        cause: error,
      );
    }
  }

  Future<PetSnapshot> _snapshot(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      final result = await _client.rpc<dynamic>(function, params: params);
      if (result is! Map) {
        throw ProgressStoreException('$function вернула не объект: $result');
      }
      return PetSnapshot.fromJson(Map<String, dynamic>.from(result));
    } on ProgressStoreException {
      rethrow;
    } on Object catch (error) {
      throw ProgressStoreException('Ошибка вызова $function', cause: error);
    }
  }

  /// Имя действия в базе. Совпадает с именем варианта в Dart, но проверено
  /// явно: перечисление в базе не примет незнакомое слово, и лучше увидеть
  /// это здесь, чем поймать ошибку транзакции.
  static String _actionName(BearAction action) => switch (action) {
    BearAction.feed => 'feed',
    BearAction.wash => 'wash',
    BearAction.sleep => 'sleep',
    BearAction.wake => 'wake',
    BearAction.play => 'play',
    BearAction.pet => 'pet',
    BearAction.learn => 'learn',
    BearAction.dressUp => 'dress',
    BearAction.decorate => 'decorate',
  };
}
