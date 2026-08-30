import 'bear_mood_policy.dart';
import 'bear_rig_spec.dart';
import 'bear_stats.dart';

/// Надетые вещи.
///
/// Значения — идентификаторы предметов внутри рига. Это не идентификаторы
/// товаров магазина: сопоставление «товар → id в риге» живёт в каталоге и в
/// границы этого модуля не входит.
///
/// Слотов шесть, а не четыре, как в разделе 5.2 ТЗ аниматора: верх и низ
/// разведены по решению от 10.08.2026. В каталоге TeddyTales® они и правда
/// продаются порознь — есть «Outfit Set» целиком, а есть отдельные вещи и
/// обувь, — и на фотографии JOY зелёная кофта надета с розовой юбкой.
/// Запрос на изменение рига — `docs/rig-change-request.md`.
///
/// Комплект и раздельные вещи взаимно исключаются: надет комплект — верх и низ
/// обнуляются, надет верх или низ — обнуляется комплект. Иначе риг получил бы
/// сочетание, которого в анимации нет: свитер поверх готового наряда.
class BearOutfit {
  const BearOutfit._({
    required this.outfitId,
    required this.topId,
    required this.bottomId,
    required this.headwearId,
    required this.shoesId,
    required this.accessoryId,
  });

  factory BearOutfit({
    int outfitId = 0,
    int topId = 0,
    int bottomId = 0,
    int headwearId = 0,
    int shoesId = 0,
    int accessoryId = 0,
  }) {
    final outfit = outfitId.clamp(0, maxOutfitId);
    final top = topId.clamp(0, maxTopId);
    final bottom = bottomId.clamp(0, maxBottomId);

    // Комплект главнее: если задан и он, и раздельные вещи, побеждает комплект.
    final wearsOutfit = outfit != 0;

    return BearOutfit._(
      outfitId: outfit,
      topId: wearsOutfit ? 0 : top,
      bottomId: wearsOutfit ? 0 : bottom,
      headwearId: headwearId.clamp(0, maxHeadwearId),
      shoesId: shoesId.clamp(0, maxShoesId),
      accessoryId: accessoryId.clamp(0, maxAccessoryId),
    );
  }

  /// Комплект целиком, 0–8 (0 — комплект не надет).
  final int outfitId;

  /// Верх, 0–8 (0 — без верха). Игнорируется, если надет [outfitId].
  final int topId;

  /// Низ, 0–8 (0 — без низа). Игнорируется, если надет [outfitId].
  final int bottomId;

  /// Головной убор, 0–3 (0 — без головного убора).
  final int headwearId;

  /// Обувь, 0–2 (0 — без обуви).
  final int shoesId;

  /// Аксессуар, 0–3 (0 — без аксессуара).
  final int accessoryId;

  static const BearOutfit none = BearOutfit._(
    outfitId: 0,
    topId: 0,
    bottomId: 0,
    headwearId: 0,
    shoesId: 0,
    accessoryId: 0,
  );

  /// Диапазоны комплектов, головных уборов, обуви и аксессуаров — из раздела
  /// 8.1 ТЗ аниматора и КП 10.5.
  static const int maxOutfitId = 8;
  static const int maxHeadwearId = 3;
  static const int maxShoesId = 2;
  static const int maxAccessoryId = 3;

  /// Сколько будет верхов и низов, ещё не решено: КП 10.5 считает одежду
  /// комплектами. До пересчёта каталога (КП 15.3) взят тот же потолок, что и у
  /// комплектов.
  static const int maxTopId = 8;
  static const int maxBottomId = 8;

  /// Надет ли комплект целиком.
  bool get wearsFullOutfit => outfitId != 0;

  BearOutfit copyWith({
    int? outfitId,
    int? topId,
    int? bottomId,
    int? headwearId,
    int? shoesId,
    int? accessoryId,
  }) {
    // Надеваем верх или низ — комплект снимается, и наоборот.
    final putsOnSeparate =
        (topId != null && topId != 0) || (bottomId != null && bottomId != 0);
    final putsOnOutfit = outfitId != null && outfitId != 0;

    return BearOutfit(
      outfitId: putsOnSeparate ? 0 : (outfitId ?? this.outfitId),
      topId: putsOnOutfit ? 0 : (topId ?? this.topId),
      bottomId: putsOnOutfit ? 0 : (bottomId ?? this.bottomId),
      headwearId: headwearId ?? this.headwearId,
      shoesId: shoesId ?? this.shoesId,
      accessoryId: accessoryId ?? this.accessoryId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BearOutfit &&
      other.outfitId == outfitId &&
      other.topId == topId &&
      other.bottomId == bottomId &&
      other.headwearId == headwearId &&
      other.shoesId == shoesId &&
      other.accessoryId == accessoryId;

  @override
  int get hashCode => Object.hash(
    outfitId,
    topId,
    bottomId,
    headwearId,
    shoesId,
    accessoryId,
  );

  @override
  String toString() =>
      'BearOutfit(outfit: $outfitId, top: $topId, bottom: $bottomId, '
      'headwear: $headwearId, shoes: $shoesId, accessory: $accessoryId)';
}

/// Полное состояние персонажа — всё, что уезжает в риг, плюс показатели ухода,
/// из которых считается `mood`.
class BearState {
  const BearState({
    this.stats = const BearCareStats(),
    this.stage = BearStage.newborn,
    this.trait = BearTrait.active,
    this.skin = BearSkin.boy,
    this.outfit = BearOutfit.none,
    this.isWalking = false,
    this.moodPolicy = const BearMoodPolicy(),
  });

  /// Пять показателей ухода (КП 6.1). В риг напрямую не уезжают.
  final BearCareStats stats;

  final BearStage stage;
  final BearTrait trait;
  final BearSkin skin;
  final BearOutfit outfit;

  /// Вход `is_walking` — включает цикл ходьбы.
  final bool isWalking;

  /// Правило свёртки показателей в `mood`.
  final BearMoodPolicy moodPolicy;

  /// Значение входа `mood`, посчитанное из показателей и стадии.
  BearMood get mood => moodPolicy.resolve(stats, stage);

  /// Умеет ли мишка ходить на текущей стадии.
  ///
  /// Раздел 7.3 ТЗ аниматора: ползание — стадия 2, шаги — стадия 3, ходьба —
  /// 4–5. Новорождённый лежит, поэтому `is_walking` для него бессмыслен.
  bool get canWalk => stage != BearStage.newborn;

  BearState copyWith({
    BearCareStats? stats,
    BearStage? stage,
    BearTrait? trait,
    BearSkin? skin,
    BearOutfit? outfit,
    bool? isWalking,
    BearMoodPolicy? moodPolicy,
  }) {
    final nextStage = stage ?? this.stage;
    final nextWalking = isWalking ?? this.isWalking;

    return BearState(
      stats: stats ?? this.stats,
      stage: nextStage,
      trait: trait ?? this.trait,
      skin: skin ?? this.skin,
      outfit: outfit ?? this.outfit,
      // Новорождённый не ходит — не даём риг в невозможное сочетание.
      isWalking: nextStage == BearStage.newborn ? false : nextWalking,
      moodPolicy: moodPolicy ?? this.moodPolicy,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BearState &&
      other.stats == stats &&
      other.stage == stage &&
      other.trait == trait &&
      other.skin == skin &&
      other.outfit == outfit &&
      other.isWalking == isWalking &&
      other.moodPolicy == moodPolicy;

  @override
  int get hashCode =>
      Object.hash(stats, stage, trait, skin, outfit, isWalking, moodPolicy);

  @override
  String toString() =>
      'BearState(stage: ${stage.name}, mood: ${mood.name}, '
      'trait: ${trait.name}, skin: ${skin.name}, walking: $isWalking, '
      '$stats, $outfit)';
}
