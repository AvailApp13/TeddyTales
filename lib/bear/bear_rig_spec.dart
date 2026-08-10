/// Контракт между кодом приложения и `.riv`-файлом.
///
/// Единственное место, где захардкожены имена из Rive Editor. Если в редакторе
/// артборд, State Machine или свойства View Model названы иначе — правится
/// только этот файл, остальной код не трогается.
///
/// Источник имён: раздел 5 ТЗ (`docs/tz-rive-animation.md`). Набор свойств —
/// **шаблон, не финал**: точный список характеристик мишки и decay-таймеры это
/// открытый вопрос 8.1, ответа Руслана ещё нет.
///
/// Файл намеренно не импортирует `package:rive` — чтобы игровая логика и её
/// тесты не тянули за собой нативный рантайм. Выбор рендерера живёт в
/// [BearView.riveFactory].
abstract final class BearRigSpec {
  /// Путь к экспортированному ригу. Файла пока нет в репозитории — он появится
  /// после того, как риг будет собран в редакторе (пункт 9.3 ТЗ).
  /// До этого [BearView] показывает плейсхолдер вместо падения.
  static const String assetPath = 'assets/rive/bear.riv';

  /// Имя артборда. `null` — взять артборд по умолчанию.
  static const String? artboard = null;

  /// Имя State Machine. Из раздела 6.2 ТЗ.
  /// Если в файле такой машины нет, [BearView] откатывается на машину
  /// по умолчанию и пишет предупреждение в лог.
  static const String stateMachine = 'State Machine 1';

  // --- View Model properties (раздел 5 ТЗ) --------------------------------
  // Пути указываются через «/» для вложенных view model'ей, например
  // 'stats/hunger'. Пока плоские.

  /// Голод, 0–100.
  static const String hunger = 'hunger';

  /// Настроение, 0–100. Управляет blend state выражения морды.
  static const String mood = 'mood';

  /// Стадия роста. В риге — number (см. [BearGrowthStage]).
  static const String growthStage = 'growthStage';

  // --- Триггеры -----------------------------------------------------------
  // Имён триггеров в ТЗ нет — раздел 6.3 упоминает только абстрактный
  // `bumpTrigger.fire()`. Взяты по аналогии с `feedBear()` / `petBear()`
  // из раздела 6.4. Сверить при сборке рига.

  /// Кормление — вход в состояние `eating`.
  static const String feedTrigger = 'feed';

  /// Поглаживание.
  static const String petTrigger = 'pet';

  /// Тап по мишке — вход в состояние `tap_reaction`.
  static const String tapTrigger = 'tap';

  /// Состояния State Machine (раздел 5 ТЗ).
  ///
  /// Рантайм не переключает состояния напрямую — они выбираются переходами
  /// внутри State Machine по значениям свойств и триггерам. Список нужен для
  /// сверки рига и как документация контракта.
  static const List<String> states = <String>[
    'idle',
    'happy',
    'sad',
    'eating',
    'tap_reaction',
    'growth_transition',
  ];

  /// Control-узлы из раздела 3.4 ТЗ.
  ///
  /// Код к ним не обращается: в актуальном рантайме влияние на риг идёт через
  /// State Machine и View Model, а не через прямые ссылки на узлы, как в
  /// legacy-референсе `teddy_controller.dart`. Список — для сверки рига.
  static const List<String> controlNodes = <String>[
    'ctrl_face',
    'ctrl_eyes',
    'ctrl_pupils',
    'ctrl_mouth',
    'ctrl_nose',
    'ctrl_eyebrow_left',
    'ctrl_eyebrow_right',
  ];
}

/// Стадии роста мишки.
///
/// ЗАГЛУШКА: полный список стадий и триггеры перехода между ними — открытый
/// вопрос 8.4 ТЗ. Три стадии взяты как минимальный рабочий набор, чтобы было
/// что передавать в риг.
enum BearGrowthStage {
  cub(0),
  young(1),
  adult(2);

  const BearGrowthStage(this.riveValue);

  /// Значение, которое уезжает в number-свойство [BearRigSpec.growthStage].
  final double riveValue;

  static BearGrowthStage fromRiveValue(double value) {
    return BearGrowthStage.values.firstWhere(
      (stage) => stage.riveValue == value,
      orElse: () => BearGrowthStage.cub,
    );
  }
}
