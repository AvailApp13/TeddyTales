/// Знаки зодиака: мапперы из enum в строки локализации.
///
/// `BearZodiac` в `lib/bear/bear_zodiac.dart` — доменные данные и остаётся
/// без знания о локализации (его поле `title` — русский эталон и в UI больше
/// не показывается напрямую). Всё, что видит пользователь, берётся отсюда:
/// [zodiacTitle] — название знака, [zodiacInfluence] — короткое описание
/// стартовой склонности характера (КП 7.2). Численная таблица влияний — за
/// Заказчиком ([BearZodiacInfluence]); описания здесь — витринный текст, а не
/// механика.
library;

import '../bear/bear_zodiac.dart';
import 'l10n.dart';

/// Название знака на языке интерфейса.
String zodiacTitle(AppLocalizations l10n, BearZodiac zodiac) =>
    switch (zodiac) {
      BearZodiac.aries => l10n.zodiacAries,
      BearZodiac.taurus => l10n.zodiacTaurus,
      BearZodiac.gemini => l10n.zodiacGemini,
      BearZodiac.cancer => l10n.zodiacCancer,
      BearZodiac.leo => l10n.zodiacLeo,
      BearZodiac.virgo => l10n.zodiacVirgo,
      BearZodiac.libra => l10n.zodiacLibra,
      BearZodiac.scorpio => l10n.zodiacScorpio,
      BearZodiac.sagittarius => l10n.zodiacSagittarius,
      BearZodiac.capricorn => l10n.zodiacCapricorn,
      BearZodiac.aquarius => l10n.zodiacAquarius,
      BearZodiac.pisces => l10n.zodiacPisces,
    };

/// Короткое описание стартовой склонности знака — для карточек и профиля.
String zodiacInfluence(AppLocalizations l10n, BearZodiac zodiac) =>
    switch (zodiac) {
      BearZodiac.aries => l10n.zodiacInfluenceAries,
      BearZodiac.taurus => l10n.zodiacInfluenceTaurus,
      BearZodiac.gemini => l10n.zodiacInfluenceGemini,
      BearZodiac.cancer => l10n.zodiacInfluenceCancer,
      BearZodiac.leo => l10n.zodiacInfluenceLeo,
      BearZodiac.virgo => l10n.zodiacInfluenceVirgo,
      BearZodiac.libra => l10n.zodiacInfluenceLibra,
      BearZodiac.scorpio => l10n.zodiacInfluenceScorpio,
      BearZodiac.sagittarius => l10n.zodiacInfluenceSagittarius,
      BearZodiac.capricorn => l10n.zodiacInfluenceCapricorn,
      BearZodiac.aquarius => l10n.zodiacInfluenceAquarius,
      BearZodiac.pisces => l10n.zodiacInfluencePisces,
    };
