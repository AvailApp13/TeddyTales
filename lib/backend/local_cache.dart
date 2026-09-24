import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pet_snapshot.dart';

/// Последнее состояние, сохранённое на устройстве (КП 1.1).
///
/// Без него «работает без сети» означало бы «открывается с нуля»: приложение
/// показывало бы чужого новорождённого мишку вместо своего подросшего. Здесь
/// лежит снимок последнего удачного ответа сервера — тот самый, который
/// игрок видел в прошлый раз.
///
/// Это именно кеш, а не хранилище прогресса. Он никогда не отправляется
/// обратно и не считается истиной: как только сервер отвечает, его ответ
/// главнее. Разойтись они могут только в одну сторону — кеш отстаёт.
///
/// Показатели в кеше устаревают, и это нормально. Они хранятся вместе с
/// моментом, на который верны (КП 1.5): вернувшись в сеть, приложение
/// получит пересчитанные, а до тех пор локальный таймер сползает от
/// сохранённых — ровно так же, как считал бы сервер.
class LocalCache {
  LocalCache(this._prefs);

  static const String _key = 'teddytales.snapshot.v1';

  static Future<LocalCache?> open() async {
    try {
      return LocalCache(await SharedPreferences.getInstance());
    } on Object catch (error) {
      // Хранилище может не подняться: нет прав, переполнен диск, странная
      // сборка. Это не повод не запускать игру.
      debugPrint('[TeddyTales] кеш недоступен: $error');
      return null;
    }
  }

  final SharedPreferences _prefs;

  /// Кладёт снимок. Ошибки записи глотаются намеренно: не сохранился кеш —
  /// потеряется скорость запуска, но не данные, они на сервере.
  Future<void> save(PetSnapshot snapshot) async {
    try {
      await _prefs.setString(_key, jsonEncode(_toJson(snapshot)));
    } on Object catch (error) {
      debugPrint('[TeddyTales] снимок не сохранился: $error');
    }
  }

  /// Читает снимок. `null` — кеша нет или он битый.
  PetSnapshot? load() {
    final text = _prefs.getString(_key);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      return PetSnapshot.fromJson(Map<String, dynamic>.from(json));
    } on Object catch (error) {
      // Битый кеш выбрасываем: разбирать его по кускам — верный способ
      // показать игроку половину чужого состояния.
      debugPrint('[TeddyTales] кеш испорчен, выбрасываю: $error');
      unawaited(clear());
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _prefs.remove(_key);
    } on Object catch (_) {
      // Уже неважно.
    }
  }

  /// Снимок в тот же вид, в каком его присылает сервер.
  ///
  /// Форма общая намеренно: разбор один на оба источника, и структура кеша
  /// не может незаметно разойтись со структурой ответа.
  static Map<String, dynamic> _toJson(PetSnapshot s) => {
    'server_time': s.serverTime.toIso8601String(),
    'pet': {
      'id': s.petId,
      'name': s.profile.name,
      'birth_at': s.profile.birthAt.toIso8601String(),
      'skin': s.profile.skin.name,
      'zodiac': s.profile.zodiac?.name,
      'stage': s.state.stage.name,
      'trait': s.state.trait.name,
      // Точного момента кеш не знает — важно лишь, что имя уже давали.
      'named_at': s.named ? s.serverTime.toIso8601String() : null,
    },
    'account': {
      'coins': s.profile.coins,
      'is_anonymous': s.account.isAnonymous,
      'email': s.account.email,
      'providers': s.account.providers.toList(),
      'player_age': s.account.playerAge,
      'locale': s.account.locale,
    },
    'stats': {
      'food': s.state.stats.food,
      'hygiene': s.state.stats.hygiene,
      'sleep': s.state.stats.sleep,
      'play': s.state.stats.play,
      'love': s.state.stats.love,
    },
    'outfit': {
      'outfit_id': s.state.outfit.outfitId,
      'top_id': s.state.outfit.topId,
      'bottom_id': s.state.outfit.bottomId,
      'headwear_id': s.state.outfit.headwearId,
      'shoes_id': s.state.outfit.shoesId,
      'accessory_id': s.state.outfit.accessoryId,
    },
    'inventory': s.inventory.toList(),
    'placed': s.placed.toList(),
    'edu': s.eduProgress,
  };
}
