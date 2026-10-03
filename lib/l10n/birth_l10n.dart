/// Реплики сцены рождения: маппер из шага сценария в строку локализации.
///
/// Сценарий (`BirthSceneScript`) — чистые данные: тайминги и id шага. Тексты
/// живут в ARB под ключами `birthCue*`, и этот маппер — единственное место,
/// где id встречается со строкой. Добавился шаг в [BirthSceneCueId] — switch
/// перестанет компилироваться и напомнит завести ключ.
library;

import '../bear/birth_scene_script.dart';
import 'l10n.dart';

/// Текст субтитра для шага [id] на языке интерфейса.
String birthCueText(AppLocalizations l10n, BirthSceneCueId id) => switch (id) {
  BirthSceneCueId.cradle => l10n.birthCueCradle,
  BirthSceneCueId.stars => l10n.birthCueStars,
  BirthSceneCueId.firstBreath => l10n.birthCueFirstBreath,
  BirthSceneCueId.awakening => l10n.birthCueAwakening,
  BirthSceneCueId.firstCry => l10n.birthCueFirstCry,
  BirthSceneCueId.finale => l10n.birthCueFinale,
};
