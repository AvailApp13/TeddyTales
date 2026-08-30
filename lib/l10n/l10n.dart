/// Точка входа локализации: генерат + связка с [BearLanguage].
///
/// Весь интерфейс берёт строки только отсюда: `context.l10n.<ключ>`.
/// Русские тексты — эталон в `app_ru.arb`, переводы — `app_en.arb` и
/// `app_zh.arb`. После правки ARB: `flutter gen-l10n`.
library;

import 'package:flutter/widgets.dart';

import '../bear/bear_phrases.dart' show BearLanguage;
import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension BearLanguageLocale on BearLanguage {
  /// Локаль интерфейса. Язык у приложения один на всё: и реплики питомца,
  /// и экраны переключаются одним значением из настроек.
  Locale get locale => switch (this) {
    BearLanguage.ru => const Locale('ru'),
    BearLanguage.en => const Locale('en'),
    BearLanguage.zh => const Locale('zh'),
  };
}

extension L10nContext on BuildContext {
  /// Короткий доступ к строкам: `context.l10n.commonBack`.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
