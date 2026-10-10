import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Звуки кухни (заказчик 24.09): жевание, пузырь сытости, монеты, готовка.
///
/// Файлы синтезированы `tool/make_sfx.py` — чужих записей нет, лицензий не
/// нужно. Длины совпадают с анимациями, см. там.
enum Sfx {
  /// «Блоп» — пузырик вырос из тарелки.
  bubbleBorn('bubble_born'),

  /// Лёгкий свист, пока пузырь летит змейкой.
  bubbleFly('bubble_fly'),

  /// «Пуньк» — пузырь лопнул о кружок «Еда».
  bubblePop('bubble_pop'),

  /// Перелив вверх, пока растут проценты.
  fill('fill'),

  /// Монеты ушли — звон потише.
  coinsSpend('coins_spend'),

  /// Монеты пришли (награда за готовку) — звон повеселее.
  coinsEarn('coins_earn'),

  /// Два укуса и жевание — под движение челюсти в `act_eat`.
  chew('chew'),

  /// Нужный продукт растворился: «бульк» с искорками.
  cookRight('cook_right'),

  /// Не тот продукт: «ым-ым».
  cookWrong('cook_wrong');

  const Sfx(this.file);

  final String file;
}

/// Проигрыватель звуков. До [Sounds.start] молчит — так в тестах звук не
/// нужен и не мешает.
///
/// Звук можно выключить в настройках; выбор хранится на телефоне.
/// На iPhone звуки уважают беззвучный режим и не глушат музыку в других
/// приложениях: это игровые эффекты, а не плеер.
class Sounds {
  Sounds._();

  static const String _key = 'teddytales.sound_on.v1';

  /// Включён ли звук. Настройки подписаны на него.
  static final ValueNotifier<bool> on = ValueNotifier<bool>(true);

  static SharedPreferences? _prefs;
  static Map<Sfx, AudioPlayer>? _players;

  /// Поднимает выбор из настроек и заранее загружает звуки, чтобы первый
  /// «блоп» не опаздывал. Ошибки не роняют игру — она просто молчит.
  static Future<void> start() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      on.value = _prefs?.getBool(_key) ?? true;
    } on Object catch (error) {
      debugPrint('[TeddyTales] выбор звука не сохранится: $error');
    }
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          respectSilence: true,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } on Object catch (error) {
      debugPrint('[TeddyTales] звук: $error');
    }
    final players = <Sfx, AudioPlayer>{};
    for (final sfx in Sfx.values) {
      final player = AudioPlayer(playerId: 'sfx-${sfx.file}');
      players[sfx] = player;
      try {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('audio/${sfx.file}.mp3'));
      } on Object catch (error) {
        debugPrint('[TeddyTales] звук ${sfx.file}: $error');
      }
    }
    _players = players;
  }

  static Future<void> setOn(bool value) async {
    on.value = value;
    if (!value) {
      for (final sfx in Sfx.values) {
        stop(sfx);
      }
    }
    try {
      await _prefs?.setBool(_key, value);
    } on Object catch (error) {
      debugPrint('[TeddyTales] выбор звука не сохранился: $error');
    }
  }

  /// Тесты слушают, какие звуки и когда просили сыграть.
  @visibleForTesting
  static ValueChanged<Sfx>? debugOnPlay;

  /// Сыграть с начала. Если этот же звук ещё звучит — начинается заново.
  static void play(Sfx sfx) {
    if (on.value) debugOnPlay?.call(sfx);
    final player = _players?[sfx];
    if (player == null || !on.value) return;
    // В браузере звук разрешён только после первого касания; до него
    // `resume` отказывает — это не ошибка игры.
    player
        .seek(Duration.zero)
        .then((_) => player.resume())
        .catchError((Object _) {});
  }

  static void stop(Sfx sfx) {
    _players?[sfx]?.stop().catchError((Object _) {});
  }
}
