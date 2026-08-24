/// Мапперы enum → локализованные подписи.
///
/// Enum'ы (`AppSection`, `BearStage`, `BearMood`, `BearTrait`, `BearSkin`)
/// хранят русские `title` только для дев-целей: `bear_rig_spec.dart` — контракт
/// рига и не редактируется, а `app_section.dart` использует `title` в
/// отладочной панели. UI обязан брать подписи через функции этого файла.
library;

import '../bear/bear_rig_spec.dart';
import '../game/app_section.dart';
import '../game/game_calendar.dart';
import 'l10n.dart';

/// Название раздела нижней навигации.
String sectionTitle(AppLocalizations l10n, AppSection s) => switch (s) {
  AppSection.home => l10n.navSectionHome,
  AppSection.room => l10n.navSectionRoom,
  AppSection.shop => l10n.navSectionShop,
  AppSection.learning => l10n.navSectionLearning,
  AppSection.catalog => l10n.navSectionCatalog,
  AppSection.profile => l10n.navSectionProfile,
};

/// Пояснение к замку раздела: «Откроется на стадии …».
String sectionLockReason(AppLocalizations l10n, AppSection s) =>
    l10n.navLockReason(stageTitle(l10n, s.minStage));

/// Название стадии роста.
String stageTitle(AppLocalizations l10n, BearStage stage) => switch (stage) {
  BearStage.newborn => l10n.stageNewborn,
  BearStage.crawling => l10n.stageCrawling,
  BearStage.firstSteps => l10n.stageFirstSteps,
  BearStage.growing => l10n.stageGrowing,
  BearStage.adult => l10n.stageAdult,
};

/// Название состояния (idle-настроения).
String moodTitle(AppLocalizations l10n, BearMood mood) => switch (mood) {
  BearMood.normal => l10n.moodNormal,
  BearMood.happy => l10n.moodHappy,
  BearMood.sad => l10n.moodSad,
  BearMood.hungry => l10n.moodHungry,
  BearMood.sleepy => l10n.moodSleepy,
  BearMood.dirty => l10n.moodDirty,
};

/// Название типа характера.
String traitTitle(AppLocalizations l10n, BearTrait trait) => switch (trait) {
  BearTrait.active => l10n.traitActive,
  BearTrait.curious => l10n.traitCurious,
  BearTrait.affectionate => l10n.traitAffectionate,
  BearTrait.calm => l10n.traitCalm,
  BearTrait.independent => l10n.traitIndependent,
  BearTrait.reserved => l10n.traitReserved,
};

/// Имя героя каталога (SLOW / JOY). Бренд-имена не переводятся, но живут в
/// ARB, чтобы вся подпись собиралась одним механизмом.
String skinHeroName(AppLocalizations l10n, BearSkin skin) => switch (skin) {
  BearSkin.boy => l10n.skinSlow,
  BearSkin.girl => l10n.skinJoy,
};

/// Возраст питомца: «3 месяца 12 дней» — на ICU-плюралах вместо русской
/// логики склонений из [GameAge.format].
String formatAge(AppLocalizations l10n, GameAge age) {
  if (age.months == 0) return l10n.ageDays(age.days);
  if (age.days == 0) return l10n.ageMonths(age.months);
  return l10n.ageMonthsDays(age.months, age.days);
}
