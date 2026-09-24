import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bear/bear_action.dart';
import 'email_auth.dart';
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
class SupabaseStore implements ProgressStore, AccountAuth {
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
      await _client.auth.signInAnonymously(data: _signUpData());
    } on Object catch (error) {
      throw ProgressStoreException('Не удалось войти', cause: error);
    }
  }

  // --- Почта (КП 1.3) ------------------------------------------------------

  /// Метаданные регистрации. Пояс нужен серверу, чтобы знак зодиака
  /// считался по дате у человека, а не по Гринвичу (миграция 0011).
  static Map<String, dynamic> _signUpData() => {
    'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
  };

  @override
  Future<SignUpOutcome> signUpWithEmail(String email, String password) async {
    final AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: _signUpData(),
      );
    } on AuthException catch (error) {
      throw EmailAuthException(
        emailErrorFromCode(error.code, statusCode: error.statusCode),
        cause: error,
      );
    } on Object catch (error) {
      throw EmailAuthException(EmailAuthError.network, cause: error);
    }
    // При включённом подтверждении Supabase на занятую почту не говорит
    // «занято» — чтобы по форме нельзя было перебирать чужие адреса, — а
    // отдаёт пользователя без способов входа. Так и узнаём.
    final identities = response.user?.identities;
    if (response.session == null && identities != null && identities.isEmpty) {
      throw const EmailAuthException(EmailAuthError.alreadyRegistered);
    }
    _petId = null;
    return response.session != null
        ? SignUpOutcome.signedIn
        : SignUpOutcome.confirmEmail;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _petId = null;
    } on AuthException catch (error) {
      throw EmailAuthException(
        emailErrorFromCode(error.code, statusCode: error.statusCode),
        cause: error,
      );
    } on Object catch (error) {
      throw EmailAuthException(EmailAuthError.network, cause: error);
    }
  }

  @override
  Future<void> verifySignUpCode(String email, String code) async {
    try {
      await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email.trim(),
        token: code.trim(),
      );
      _petId = null;
    } on AuthException catch (error) {
      throw EmailAuthException(
        emailErrorFromCode(error.code, statusCode: error.statusCode),
        cause: error,
      );
    } on Object catch (error) {
      throw EmailAuthException(EmailAuthError.network, cause: error);
    }
  }

  @override
  Future<void> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
    } on AuthException catch (error) {
      throw EmailAuthException(
        emailErrorFromCode(error.code, statusCode: error.statusCode),
        cause: error,
      );
    } on Object catch (error) {
      throw EmailAuthException(EmailAuthError.network, cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    _petId = null;
    try {
      await _client.auth.signOut();
    } on Object catch (error) {
      // Без сети сервер о выходе не узнает, но на устройстве сессию снять
      // надо в любом случае — человек нажал «Выйти».
      debugPrint('[TeddyTales] выход без сервера: $error');
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Future<PetSnapshot> load() async {
    // Вход в личный кабинет. Сервер сам находит мишку того, кто вошёл
    // (кабинет создаётся вместе с учётной записью, КП 2.4), отмечает визит
    // и отдаёт снимок. Отсюда же берётся id мишки для всех действий.
    final snapshot = await _snapshot('open_account', const {});
    if (snapshot.petId.isEmpty) {
      throw const ProgressStoreException(
        'open_account вернула снимок без мишки',
      );
    }
    _petId = snapshot.petId;
    return snapshot;
  }

  Future<String> _pet() async => _petId ?? (await load()).petId;

  @override
  Future<PetSnapshot> recordCare(BearAction action) async {
    final id = await _pet();
    return _snapshot('record_care', {
      'p_pet_id': id,
      'p_action': _actionName(action),
    });
  }

  @override
  Future<PetSnapshot> buyItem(String itemId) async {
    final id = await _pet();
    return _snapshot('buy_item', {'p_pet_id': id, 'p_item_id': itemId});
  }

  @override
  Future<PetSnapshot> feedDish(String dishId) async {
    final id = await _pet();
    return _snapshot('feed_dish', {'p_pet_id': id, 'p_dish_id': dishId});
  }

  @override
  Future<PetSnapshot> completeRecipe(String recipeId) async {
    final id = await _pet();
    return _snapshot('complete_recipe', {
      'p_pet_id': id,
      'p_recipe_id': recipeId,
    });
  }

  @override
  Future<PetSnapshot> completeLevel(String categoryId, int level) async {
    final id = await _pet();
    return _snapshot('complete_level', {
      'p_pet_id': id,
      'p_category': categoryId,
      'p_level': level,
    });
  }

  @override
  Future<PetSnapshot> renamePet(String name, {String locale = 'ru'}) async {
    final id = await _pet();
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

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.rpc<dynamic>('delete_my_account');
    } on PostgrestException catch (error) {
      throw ProgressStoreException(
        'Не удалось удалить аккаунт',
        cause: error,
        code: error.code,
      );
    } on Object catch (error) {
      throw ProgressStoreException('Не удалось удалить аккаунт', cause: error);
    }
    _petId = null;
    // Учётной записи больше нет, её сессия недействительна. Выходим только
    // здесь, на устройстве: на сервере выходить уже некому.
    await _client.auth.signOut(scope: SignOutScope.local);
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
    } on PostgrestException catch (error) {
      // Сервер ответил отказом: код TT402 «не хватает монет» и прочие —
      // по ним приложение отличает отказ от обрыва связи.
      throw ProgressStoreException(
        'Ошибка вызова $function',
        cause: error,
        code: error.code,
      );
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
