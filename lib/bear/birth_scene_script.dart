/// Шесть тактов сцены рождения из раздела 7.8 ТЗ аниматора:
/// кроватка → атмосфера → первый вдох → пробуждение → первый плач → финал.
///
/// Сценарий хранит только тайминги и id шага; сам текст субтитра лежит в ARB
/// (ключи `birthCue*`) и достаётся маппером `birthCueText` из
/// `lib/l10n/birth_l10n.dart` — так реплики переводятся вместе с остальным
/// интерфейсом, а данные сцены остаются чистыми данными.
enum BirthSceneCueId { cradle, stars, firstBreath, awakening, firstCry, finale }

/// Субтитр сцены рождения: шаг сценария и отрезок времени, на котором он
/// показан.
class BirthSceneCue {
  const BirthSceneCue({
    required this.start,
    required this.end,
    required this.id,
  });

  final Duration start;
  final Duration end;

  /// Какой шаг сценария идёт на этом отрезке — по нему выбирается текст.
  final BirthSceneCueId id;

  bool isVisibleAt(Duration position) => position >= start && position < end;
}

/// Сценарий субтитров к сцене рождения (КП 2.1: «ролик 20–30 секунд, субтитры
/// на языке пользователя, кнопка „Пропустить“ после 5 секунд»).
///
/// Реплики положены на шесть тактов сцены из раздела 7.8 ТЗ аниматора.
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
      id: BirthSceneCueId.cradle,
    ),
    BirthSceneCue(
      start: Duration(seconds: 5),
      end: Duration(seconds: 10),
      id: BirthSceneCueId.stars,
    ),
    BirthSceneCue(
      start: Duration(seconds: 10),
      end: Duration(seconds: 14),
      id: BirthSceneCueId.firstBreath,
    ),
    BirthSceneCue(
      start: Duration(seconds: 14),
      end: Duration(seconds: 18),
      id: BirthSceneCueId.awakening,
    ),
    BirthSceneCue(
      start: Duration(seconds: 18),
      end: Duration(seconds: 22),
      id: BirthSceneCueId.firstCry,
    ),
    BirthSceneCue(
      start: Duration(seconds: 22),
      end: Duration(seconds: 26),
      id: BirthSceneCueId.finale,
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
