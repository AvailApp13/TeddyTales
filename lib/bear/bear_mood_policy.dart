import 'bear_rig_spec.dart';
import 'bear_stats.dart';

/// Правило, по которому пять показателей ухода сворачиваются в один вход
/// `mood` (0–5).
///
/// ДОПУЩЕНИЕ, требует подтверждения. В документах этого правила нет: КП 6.1
/// задаёт пять показателей 0–100, ТЗ аниматора 8.1 — один вход `mood` с шестью
/// кодами. Как именно первое превращается во второе, не написано ни там, ни
/// там, а решать это надо, иначе мишка не знает, какой idle играть.
///
/// Выбранная логика — «показывать самую острую нужду»:
///
/// 1. Из трёх показателей, у которых есть свой idle (еда → `hungry`,
///    сон → `sleepy`, гигиена → `dirty`), берётся самый низкий. Если он ниже
///    [lowThreshold] — играет соответствующее состояние.
/// 2. `dirty` пропускается на стадиях 1–2: клипа `idle_dirty` для них нет
///    (раздел 7.1 ТЗ аниматора). Тогда берётся следующий кандидат.
/// 3. Иначе смотрим средний уровень: ниже [sadThreshold] — `sad`, выше
///    [happyThreshold] — `happy`, между — `normal`.
///
/// «Игра» и «любовь» своих idle не имеют и влияют только через среднее.
class BearMoodPolicy {
  const BearMoodPolicy({
    this.lowThreshold = 30,
    this.sadThreshold = 40,
    this.happyThreshold = 80,
  });

  /// Ниже этого — показатель считается «острой нуждой».
  final double lowThreshold;

  /// Средний уровень, ниже которого мишка грустит.
  final double sadThreshold;

  /// Средний уровень, выше которого мишка радуется.
  final double happyThreshold;

  BearMood resolve(BearCareStats stats, BearStage stage) {
    // Порядок важен: при равных значениях побеждает тот, что выше в списке.
    final candidates = <(double, BearMood)>[
      (stats.food, BearMood.hungry),
      (stats.sleep, BearMood.sleepy),
      (stats.hygiene, BearMood.dirty),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (value, mood) in candidates) {
      if (value >= lowThreshold) break; // дальше только более высокие
      if (mood.isAvailableOn(stage)) return mood;
    }

    final average = stats.average;
    if (average < sadThreshold) return BearMood.sad;
    if (average >= happyThreshold) return BearMood.happy;
    return BearMood.normal;
  }

  @override
  bool operator ==(Object other) =>
      other is BearMoodPolicy &&
      other.lowThreshold == lowThreshold &&
      other.sadThreshold == sadThreshold &&
      other.happyThreshold == happyThreshold;

  @override
  int get hashCode => Object.hash(lowThreshold, sadThreshold, happyThreshold);
}
