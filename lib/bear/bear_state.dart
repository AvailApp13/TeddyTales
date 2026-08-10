import 'bear_mood_policy.dart';
import 'bear_rig_spec.dart';
import 'bear_stats.dart';

/// Надетые вещи — четыре независимых слота (раздел 5.2 ТЗ аниматора).
///
/// Значения — идентификаторы предметов внутри рига, диапазоны из раздела 8.1.
/// Это не идентификаторы товаров магазина: сопоставление «товар → id в риге»
/// живёт в каталоге и в границы этого модуля не входит.
class BearOutfit {
  const BearOutfit({
    this.outfitId = 0,
    this.headwearId = 0,
    this.shoesId = 0,
    this.accessoryId = 0,
  });

  /// Комплект, 0–8 (0 — без одежды).
  final int outfitId;

  /// Головной убор, 0–3 (0 — без головного убора).
  final int headwearId;

  /// Обувь, 0–2 (0 — без обуви).
  final int shoesId;

  /// Аксессуар, 0–3 (0 — без аксессуара).
  final int accessoryId;

  static const BearOutfit none = BearOutfit();

  static const int maxOutfitId = 8;
  static const int maxHeadwearId = 3;
  static const int maxShoesId = 2;
  static const int maxAccessoryId = 3;

  BearOutfit copyWith({
    int? outfitId,
    int? headwearId,
    int? shoesId,
    int? accessoryId,
  }) {
    return BearOutfit(
      outfitId: (outfitId ?? this.outfitId).clamp(0, maxOutfitId),
      headwearId: (headwearId ?? this.headwearId).clamp(0, maxHeadwearId),
      shoesId: (shoesId ?? this.shoesId).clamp(0, maxShoesId),
      accessoryId: (accessoryId ?? this.accessoryId).clamp(0, maxAccessoryId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BearOutfit &&
      other.outfitId == outfitId &&
      other.headwearId == headwearId &&
      other.shoesId == shoesId &&
      other.accessoryId == accessoryId;

  @override
  int get hashCode =>
      Object.hash(outfitId, headwearId, shoesId, accessoryId);

  @override
  String toString() =>
      'BearOutfit(outfit: $outfitId, headwear: $headwearId, '
      'shoes: $shoesId, accessory: $accessoryId)';
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
