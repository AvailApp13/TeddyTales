/// Локализация названий типов уведомлений (КП 13.1).
///
/// Сами типы объявлены в [NotificationKind] (`lib/game/game_state.dart`):
/// там `title` — эталонная русская строка-данные, она остаётся на месте как
/// перечень КП 13.1. Интерфейс же берёт название отсюда — по ключу словаря
/// `lib/l10n`, чтобы список в настройках переключался вместе с языком.
///
/// У типов пока нет описаний — когда появятся, рядом добавится
/// `notificationDescription` по той же схеме.
library;

import '../game/game_state.dart' show NotificationKind;
import 'gen/app_localizations.dart';

/// Локализованное название типа уведомления для текущего языка.
String notificationTitle(AppLocalizations l10n, NotificationKind kind) =>
    switch (kind) {
      NotificationKind.hungry => l10n.settingsNotifHungry,
      NotificationKind.play => l10n.settingsNotifPlay,
      NotificationKind.sleep => l10n.settingsNotifSleep,
      NotificationKind.task => l10n.settingsNotifTask,
      NotificationKind.gift => l10n.settingsNotifGift,
      NotificationKind.stage => l10n.settingsNotifStage,
      NotificationKind.event => l10n.settingsNotifEvent,
      NotificationKind.shopNews => l10n.settingsNotifShopNews,
    };
