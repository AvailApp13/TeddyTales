/// Контракт между приложением и файлом рига.
///
/// Источник — раздел 8.1 «ТЗ для аниматора» (`docs/tz-animator.md`). Там же
/// зафиксировано жёстко: «Приложение управляет персонажем только через
/// перечисленные ниже входы. Никаких других способов запуска анимаций быть не
/// должно». Поэтому имена ниже — не наше предложение, а согласованный контракт;
/// менять их можно только вместе с аниматором.
///
/// Файл намеренно не импортирует `package:rive` — чтобы игровая логика и её
/// тесты не тянули за собой нативный рантайм.
abstract final class BearRigSpec {
  /// Основной риг: артборд `bear_main` + State Machine `bear_main`
  /// (разделы 8 и 9 ТЗ аниматора).
  static const String assetPath = 'assets/rive/bear_main.riv';
  static const String artboard = 'bear_main';
  static const String stateMachine = 'bear_main';

  /// Демонстрационный риг для проверки пайплайна.
  ///
  /// Это НЕ наш персонаж: сторонний интерактивный кролик со своей State Machine
  /// («State Machine 1») и своими входами (`Click`, `Down`, `Hover`,
  /// `Trigger 1`). Наши входы в нём отсутствуют, и приложение честно сообщит об
  /// этом в дев-лог.
  ///
  /// Нужен, чтобы до прихода `bear_main.riv` убедиться, что живо всё
  /// остальное: загрузка файла, выбор артборда и машины, откат на объекты по
  /// умолчанию, рендер и реакция на касания.
  static const String demoAssetPath = 'assets/rive/demo_bunny.riv';

  /// Сцена рождения — отдельный артборд и отдельный файл (раздел 7.8).
  /// В основной State Machine не входит, проигрывается один раз при старте
  /// игры. Виджета под неё пока нет: она сдаётся ещё и видеорендером, и как её
  /// показывать (Rive или mp4) — вопрос к продукту.
  static const String birthSceneAssetPath = 'assets/rive/birth_scene.riv';

  // --- Number inputs ------------------------------------------------------

  /// Текущая стадия роста, 1–5. См. [BearStage].
  static const String stage = 'stage';

  /// Код состояния, 0–5. См. [BearMood]. Это НЕ шкала 0–100:
  /// значение выбирает, какой idle играть.
  static const String mood = 'mood';

  /// Тип характера, 0–5. См. [BearTrait].
  static const String trait = 'trait';

  /// Выбор варианта анимации, 0–1 (раздел 7.6: повторные действия не должны
  /// выглядеть одинаково). Приложение выставляет его перед триггером.
  static const String variant = 'variant';

  // --- Слоты одежды (раздел 5.2, диапазоны из 8.1) ------------------------

  /// Комплект одежды, 0–8 (0 — без одежды).
  ///
  /// Комплект перекрывает [topId] и [bottomId]: надет комплект — верх и низ
  /// принудительно обнуляются, см. [BearOutfit].
  static const String outfitId = 'outfit_id';

  /// Верх — свитер, кофта, футболка. 0 — без верха.
  ///
  /// **Входа нет в разделе 8.1 ТЗ аниматора.** Он добавлен по решению от
  /// 10.08.2026: в макете магазина одежда разложена на «Наряды · Верх · Низ ·
  /// Аксессуары», и верх с низом надеваются раздельно. Запрос на изменение
  /// рига — `docs/rig-change-request.md`.
  ///
  /// Пока аниматор не добавит вход, канал молча игнорируется и мишка носит
  /// только комплекты — приложение из-за этого не падает.
  static const String topId = 'top_id';

  /// Низ — штаны, шорты, юбка. 0 — без низа. См. оговорку у [topId].
  static const String bottomId = 'bottom_id';

  /// Головной убор, 0–3.
  static const String headwearId = 'headwear_id';

  /// Обувь, 0–2.
  static const String shoesId = 'shoes_id';

  /// Аксессуар, 0–3.
  static const String accessoryId = 'accessory_id';

  /// Пол персонажа, 0 мальчик / 1 девочка. См. [BearSkin].
  ///
  /// Один общий риг на обоих героев — раздел 6 ТЗ аниматора; два набора
  /// анимаций не принимаются.
  static const String skin = 'skin';

  // --- Boolean inputs -----------------------------------------------------

  /// Включает цикл ходьбы.
  static const String isWalking = 'is_walking';

  // --- Trigger inputs -----------------------------------------------------

  static const String trgEat = 'trg_eat';
  static const String trgWash = 'trg_wash';
  static const String trgSleep = 'trg_sleep';
  static const String trgWake = 'trg_wake';
  static const String trgPlay = 'trg_play';
  static const String trgPet = 'trg_pet';
  static const String trgStageUp = 'trg_stage_up';
  static const String trgEmoHappy = 'trg_emo_happy';
  static const String trgEmoSad = 'trg_emo_sad';

  /// Именно `trg_emo_surpr`, а не `trg_emo_surprise` — так в ТЗ.
  static const String trgEmoSurprise = 'trg_emo_surpr';
  static const String trgEmoLove = 'trg_emo_love';

  /// Все триггеры контракта — для сверки рига и для дев-панели.
  static const List<String> triggers = <String>[
    trgEat,
    trgWash,
    trgSleep,
    trgWake,
    trgPlay,
    trgPet,
    trgStageUp,
    trgEmoHappy,
    trgEmoSad,
    trgEmoSurprise,
    trgEmoLove,
  ];
}

/// Стадия роста, вход `stage` (1–5).
///
/// Названия и поведение — раздел 6 ТЗ аниматора, длительности — раздел 5 КП.
/// Длительности здесь не хранятся: они настраиваются с сервера (КП 5.6), а
/// скорость роста зависит от общего ухода, а не от таймера (КП 5.7).
enum BearStage {
  /// Лежит, голова крупная, глаза чаще закрыты. ~1 день.
  newborn(1, 'Новорождённый'),

  /// Сидит и ползает. ~2 дня.
  crawling(2, 'Ползающий малыш'),

  /// Стоит неуверенно, первые шаги. 1–2 дня.
  firstSteps(3, 'Первые шаги'),

  /// Уверенно ходит, открываются все механики. До ~14 дня.
  growing(4, 'Подрастающий'),

  /// Финальные пропорции, полный набор движений.
  adult(5, 'Взрослый');

  const BearStage(this.riveValue, this.title);

  final int riveValue;
  final String title;

  /// Следующая стадия или `null`, если это уже взрослый.
  BearStage? get next {
    final index = BearStage.values.indexOf(this);
    return index + 1 < BearStage.values.length
        ? BearStage.values[index + 1]
        : null;
  }

  static BearStage fromRiveValue(int value) => BearStage.values.firstWhere(
    (stage) => stage.riveValue == value,
    orElse: () => BearStage.newborn,
  );
}

/// Код состояния покоя, вход `mood` (0–5).
///
/// Раздел 8.1 ТЗ аниматора. Значение выбирает, какой idle-клип играет; шкал
/// внутри значения нет.
enum BearMood {
  normal(0),
  happy(1),
  sad(2),
  hungry(3),
  sleepy(4),

  /// `idle_dirty` есть только для стадий 3–5 (раздел 7.1) — см.
  /// [BearMood.isAvailableOn].
  dirty(5);

  const BearMood(this.riveValue);

  final int riveValue;

  /// Доступно ли это состояние на стадии [stage].
  bool isAvailableOn(BearStage stage) {
    if (this != BearMood.dirty) return true;
    return stage.riveValue >= BearStage.firstSteps.riveValue;
  }

  static BearMood fromRiveValue(int value) => BearMood.values.firstWhere(
    (mood) => mood.riveValue == value,
    orElse: () => BearMood.normal,
  );
}

/// Тип характера, вход `trait` (0–5).
///
/// Порядок — из раздела 7.5 ТЗ аниматора («0 активный … 5 замкнутый»).
/// Совпадает с перечислением в КП 7.1.
enum BearTrait {
  active(0, 'Активный'),
  curious(1, 'Любознательный'),
  affectionate(2, 'Ласковый'),
  calm(3, 'Спокойный'),
  independent(4, 'Самостоятельный'),
  reserved(5, 'Замкнутый');

  const BearTrait(this.riveValue, this.title);

  final int riveValue;
  final String title;

  static BearTrait fromRiveValue(int value) => BearTrait.values.firstWhere(
    (trait) => trait.riveValue == value,
    orElse: () => BearTrait.active,
  );
}

/// Пол персонажа, вход `skin` (0–1). Определяется сервером при рождении
/// (КП 2.4).
///
/// Два героя игры — реальные персонажи из каталога TeddyTales®: **SLOW** с
/// мехом Milk Tea и **JOY** с белым мехом (карточка «Карманный мишка Фортуна,
/// 15 см»). Раздел 6 ТЗ аниматора требует один общий риг на обоих: различия
/// только в цвете шерсти, размере и одежде.
///
/// ДОПУЩЕНИЕ: то, что SLOW — мальчик, а JOY — девочка, нигде не написано.
/// Связка выведена из макета (главный экран показывает бежевого мишку) и из
/// фотографии JOY в юбке и с бантом. Подтвердить у Заказчика.
enum BearSkin {
  boy(0, 'SLOW', 'Milk Tea'),
  girl(1, 'JOY', 'White');

  const BearSkin(this.riveValue, this.heroName, this.furColor);

  final int riveValue;

  /// Имя героя в каталоге.
  final String heroName;

  /// Цвет меха в каталоге.
  final String furColor;

  static BearSkin fromRiveValue(int value) =>
      value == girl.riveValue ? girl : boy;
}
