import 'bear_phrases.dart' show BearLanguage;

/// Субтитр сцены рождения: текст и отрезок времени, на котором он показан.
class BirthSceneCue {
  const BirthSceneCue({
    required this.start,
    required this.end,
    required this.ru,
    required this.en,
    required this.zh,
  });

  final Duration start;
  final Duration end;
  final String ru;
  final String en;
  final String zh;

  bool isVisibleAt(Duration position) => position >= start && position < end;

  String text(BearLanguage language) => switch (language) {
    BearLanguage.ru => ru,
    BearLanguage.en => en,
    BearLanguage.zh => zh,
  };
}

/// Сценарий субтитров к сцене рождения (КП 2.1: «ролик 20–30 секунд, субтитры
/// на языке пользователя, кнопка „Пропустить“ после 5 секунд»).
///
/// Реплики положены на шесть тактов сцены из раздела 7.8 ТЗ аниматора:
/// кроватка → атмосфера → первый вдох → пробуждение → первый плач → финал.
///
/// **Черновик на согласование.** Сцена ещё не собрана, поэтому тайминги
/// подогнаны под середину допустимого диапазона (26 секунд). Когда придёт
/// `birth_scene.riv` или его видеорендер, тайминги нужно свести с реальными
/// тактами анимации — [duration] и границы реплик правятся здесь.
///
/// Сама сцена сдаётся без текста: субтитры накладывает приложение (раздел 7.8
/// ТЗ аниматора).
class BirthSceneScript {
  const BirthSceneScript({
    this.duration = const Duration(seconds: 26),
    this.skipAvailableAfter = const Duration(seconds: 5),
    this.cues = defaultCues,
  });

  /// Полная длительность сцены.
  final Duration duration;

  /// Через сколько показывать кнопку «Пропустить» (КП 2.1 — после 5 секунд).
  final Duration skipAvailableAfter;

  final List<BirthSceneCue> cues;

  static const List<BirthSceneCue> defaultCues = <BirthSceneCue>[
    BirthSceneCue(
      start: Duration.zero,
      end: Duration(seconds: 5),
      ru: 'Тёплая кроватка. Кто-то тихо дышит под одеялом…',
      en: 'A warm little bed. Someone is breathing softly under the blanket…',
      zh: '温暖的小床。被子下有人在轻轻呼吸……',
    ),
    BirthSceneCue(
      start: Duration(seconds: 5),
      end: Duration(seconds: 10),
      ru: 'Звёздочки кружатся в мягком свете.',
      en: 'Little stars drift in the soft light.',
      zh: '小星星在柔和的光里飘着。',
    ),
    BirthSceneCue(
      start: Duration(seconds: 10),
      end: Duration(seconds: 14),
      ru: 'Первый вдох…',
      en: 'The first breath…',
      zh: '第一次呼吸……',
    ),
    BirthSceneCue(
      start: Duration(seconds: 14),
      end: Duration(seconds: 18),
      ru: 'Малыш открывает глаза и осматривается.',
      en: 'The little one opens their eyes and looks around.',
      zh: '小家伙睁开眼睛，四处张望。',
    ),
    BirthSceneCue(
      start: Duration(seconds: 18),
      end: Duration(seconds: 22),
      ru: 'Первый плач — он зовёт тебя.',
      en: 'The first cry — calling out for you.',
      zh: '第一声啼哭——他在呼唤你。',
    ),
    BirthSceneCue(
      start: Duration(seconds: 22),
      end: Duration(seconds: 26),
      ru: 'Он успокоился. Здравствуй, малыш.',
      en: 'Calm at last. Hello, little one.',
      zh: '他安静下来了。你好呀，小家伙。',
    ),
  ];

  /// Субтитр на позиции [position] или `null`, если в этот момент текста нет.
  BirthSceneCue? cueAt(Duration position) {
    for (final cue in cues) {
      if (cue.isVisibleAt(position)) return cue;
    }
    return null;
  }

  bool canSkipAt(Duration position) => position >= skipAvailableAfter;

  bool isFinishedAt(Duration position) => position >= duration;
}
