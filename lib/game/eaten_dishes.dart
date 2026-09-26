import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/care_schedule.dart';
import 'test_stubs.dart';

/// Какие готовые блюда мишка уже съел — их нет на столе до следующего
/// голода.
///
/// Заказчик 24.09: «после поедания блюдо исчезает до момента следующего
/// голода, когда подойдёт время ещё раз кормить, — чтобы одно и то же
/// блюдо невозможно было покушать». Голод — тот же, что у напоминания
/// «мишка проголодался» (КП 13.1): шкала «Еда» дошла до порога
/// [CareSchedule.threshold]. Тогда на стол возвращаются все съеденные.
///
/// Пока шкала «Еда» закреплена на испытаниях ([kTestFood]), голод не
/// наступает, поэтому блюдо возвращается через [kTestDishReturn].
///
/// Список хранится на телефоне: перезапуск приложения блюдо не возвращает.
class EatenDishes extends ChangeNotifier {
  EatenDishes({
    SharedPreferences? prefs,
    DateTime Function()? clock,
    Map<String, DateTime>? eaten,
    this.returnAfter = kTestDishReturn,
  }) : _prefs = prefs,
       _clock = clock ?? DateTime.now,
       _eatenAt = {...?eaten};

  /// Поднимает сохранённый список. Хранилище не открылось — список живёт
  /// только до закрытия приложения, игра от этого не ломается.
  static Future<EatenDishes> open({DateTime Function()? clock}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Object catch (error) {
      debugPrint('[TeddyTales] список съеденного не сохранится: $error');
    }
    return EatenDishes(
      prefs: prefs,
      clock: clock,
      eaten: prefs == null ? null : _decode(prefs.getString(_key)),
    );
  }

  static const String _key = 'teddytales.eaten_dishes.v1';

  final SharedPreferences? _prefs;
  final DateTime Function() _clock;
  final Map<String, DateTime> _eatenAt;

  /// Через сколько блюдо возвращается само, без голода. `null` — только с
  /// голодом.
  final Duration? returnAfter;

  /// Порог голода — как у напоминания «мишка проголодался».
  static final double hungryAt = const CareSchedule().threshold;

  bool isEaten(String id) => _eatenAt.containsKey(id);

  Set<String> get eaten => _eatenAt.keys.toSet();

  /// Мишка съел блюдо — убрать его со стола.
  void eat(String id) {
    _eatenAt[id] = _clock();
    _changed();
  }

  /// Вернуть блюда, которым пора: мишка проголодался — все; на испытаниях —
  /// те, что съедены дольше [returnAfter] назад.
  void refresh({required double food}) {
    if (_eatenAt.isEmpty) return;
    if (food <= hungryAt) {
      _eatenAt.clear();
      _changed();
      return;
    }
    final after = returnAfter;
    if (after == null) return;
    final now = _clock();
    final before = _eatenAt.length;
    _eatenAt.removeWhere((_, at) => now.difference(at) >= after);
    if (_eatenAt.length != before) _changed();
  }

  void _changed() {
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    prefs
        .setString(
          _key,
          jsonEncode({
            for (final e in _eatenAt.entries)
              e.key: e.value.toUtc().toIso8601String(),
          }),
        )
        .catchError((Object error) {
          debugPrint('[TeddyTales] список съеденного не сохранился: $error');
          return false;
        });
  }

  static Map<String, DateTime>? _decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      return {
        for (final e in json.entries)
          if (e.key is String && e.value is String)
            e.key as String: DateTime.parse(e.value as String).toLocal(),
      };
    } on Object {
      return null;
    }
  }
}
