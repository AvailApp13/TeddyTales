import 'package:flutter/material.dart';

import '../audio/sounds.dart';
import '../bear/bear.dart';
import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../l10n/notifications_l10n.dart';
import 'legal_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_panel.dart';
import '../theme/app_theme.dart';
import '../widgets/sign_out_dialog.dart';

/// Настройки (КП 14.2): язык интерфейса и уведомления.
///
/// Экран собран по принятому прототипу (`renderSettings`) и ничего к нему не
/// добавляет: два блока в том же порядке, те же заголовки со ссылками на КП и
/// та же поясняющая подпись внизу.
///
/// Из четырёх пунктов КП 14.2 здесь живут только два — язык и уведомления.
/// Привязка аккаунта и правовые документы упираются в бэкенд (аккаунта, к
/// которому привязываться, пока нет), версия без сборочного пайплайна показала
/// бы константу из исходника. Про это честно сказано в подписи внизу, чтобы
/// экран не выглядел законченным раньше времени.
///
/// Кошелька в шапке нет намеренно: в прототипе настройки открываются через
/// `sheetHead('Настройки', false)` — тут ничего не покупают.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.game,
    required this.language,
    required this.onLanguageChanged,
    this.onSignOut,
  });

  /// Переключатели уведомлений и тихие часы хранятся в [GameState]
  /// (`isNotificationOn` / `toggleNotification`, `quietHours` /
  /// `setQuietHours`). Экран на него подписан, своей копии состояния не держит.
  final GameState game;

  /// Выход из аккаунта (КП 14.2). `null` — пункт не показывается.
  final VoidCallback? onSignOut;

  /// Текущий язык интерфейса (КП 16.1).
  ///
  /// Язык сюда только приходит: тот же самый выбор управляет репликами питомца
  /// (КП 13.3, 13.4) и текстами уведомлений, поэтому хранить его внутри экрана
  /// настроек нельзя — источник правды выше по дереву.
  final BearLanguage language;

  /// Пользователь выбрал другой язык. Применяет его вызывающий.
  final ValueChanged<BearLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: game,
          builder: (context, _) {
            final l10n = context.l10n;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassScreenHeader(title: l10n.settingsTitle),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pagePadding,
                      0,
                      AppDimens.pagePadding,
                      AppDimens.pagePadding,
                    ),
                    child: GlassStagger(
                      children: [
                        GlassSectionTitle(l10n.settingsSectionLanguage),
                        _LanguageRow(
                          current: language,
                          onSelected: onLanguageChanged,
                        ),

                        GlassSectionTitle(l10n.settingsSectionNotifications),
                        _TogglesCard(
                          rows: [
                            // Порядок типов не алфавитный и не случайный: он
                            // повторяет перечисление КП 13.1, чтобы список
                            // можно было сверять с договором построчно.
                            for (final kind in NotificationKind.values)
                              _ToggleRow(
                                title: notificationTitle(l10n, kind),
                                value: game.isNotificationOn(kind.id),
                                onChanged: (_) async {
                                  final ok = await game.toggleNotification(
                                    kind.id,
                                  );
                                  if (ok || !context.mounted) return;
                                  // Телефон не разрешил — без подсказки
                                  // переключатель просто «не включается».
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.notifyDenied),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            // Тихие часы (КП 13.2) стоят в той же карточке, а не
                            // отдельным блоком: для пользователя это такой же
                            // переключатель «когда меня можно беспокоить».
                            //
                            // ДОПУЩЕНИЕ: окно 22:00 — 8:00 зашито, как в
                            // прототипе. Выбор границ — это уже редактируемая
                            // экономика уведомлений, её место в панели
                            // управления (КП 15.5), а не в клиенте.
                            _ToggleRow(
                              title: l10n.settingsQuietHours,
                              value: game.quietHours,
                              onChanged: game.setQuietHours,
                            ),
                          ],
                        ),

                        // Звуки кухни (24.09). Выбор хранится на телефоне, а не
                        // в [GameState]: это настройка устройства, как громкость.
                        GlassSectionTitle(l10n.settingsSectionSound),
                        ValueListenableBuilder<bool>(
                          valueListenable: Sounds.on,
                          builder: (context, on, _) => _TogglesCard(
                            rows: [
                              _ToggleRow(
                                title: l10n.settingsSounds,
                                value: on,
                                onChanged: Sounds.setOn,
                              ),
                            ],
                          ),
                        ),

                        // Условия и политика (КП 14.2): видны и гостю, поэтому
                        // не в карточке аккаунта.
                        const SizedBox(height: 18),
                        GlassSectionTitle(l10n.settingsSectionLegal),
                        const SizedBox(height: 6),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (final doc in LegalDoc.values) ...[
                                if (doc != LegalDoc.values.first)
                                  const Divider(height: 1),
                                ListTile(
                                  key: ValueKey('legal-${doc.file}'),
                                  title: Text(doc.title(l10n)),
                                  trailing: const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                  ),
                                  onTap: () => LegalScreen.open(context, doc),
                                ),
                              ],
                            ],
                          ),
                        ),

                        if (onSignOut != null) ...[
                          const SizedBox(height: 18),
                          GlassSectionTitle(l10n.settingsSectionAccount),
                          const SizedBox(height: 6),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(l10n.settingsVersion),
                                  trailing: const Text(
                                    _appVersion,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  title: Text(
                                    l10n.settingsSignOut,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(l10n.settingsSignOutHint),
                                  trailing: const Icon(Icons.logout, size: 20),
                                  onTap: () =>
                                      confirmSignOut(context, onSignOut),
                                ),
                                if (game.onDeleteAccount != null) ...[
                                  const Divider(height: 1),
                                  ListTile(
                                    key: const ValueKey('delete-account'),
                                    title: Text(
                                      l10n.deleteAccount,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB3261E),
                                      ),
                                    ),
                                    subtitle: Text(l10n.deleteAccountHint),
                                    trailing: const Icon(
                                      Icons.delete_forever_rounded,
                                      size: 20,
                                      color: Color(0xFFB3261E),
                                    ),
                                    onTap: () =>
                                        confirmDeleteAccount(context, game),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Подзаголовок раздела: капслок, разрядка, приглушённый цвет.
/// Версия приложения. Держится строкой, а не читается из пакета: ради
/// одной подписи тянуть зависимость и асинхронную загрузку незачем.
/// Значение то же, что в `pubspec.yaml`.
const String _appVersion = '0.1.0';

/// Ряд чипов выбора языка (КП 16.1): русский, английский, китайский.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.current, required this.onSelected});

  final BearLanguage current;
  final ValueChanged<BearLanguage> onSelected;

  /// Названия языков — на самих языках, а не переводы («Русский», а не
  /// «Russian»). Иначе выбранный не тот язык невозможно вернуть обратно: чтобы
  /// найти свой пункт, надо уже понимать текущий.
  ///
  /// ЗАГЛУШКА: «中文» нарисуется квадратами, пока в сборке нет CJK-шрифта —
  /// Roboto из `pubspec.yaml` покрывает кириллицу и латиницу, иероглифов в нём
  /// нет. Локаль zh по КП 16.1 обязана работать, шрифт добавляется отдельно.
  static const Map<BearLanguage, String> _titles = {
    BearLanguage.ru: 'Русский',
    BearLanguage.en: 'English',
    BearLanguage.zh: '中文',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final language in BearLanguage.values) ...[
          _LanguageChip(
            title: _titles[language]!,
            selected: language == current,
            onTap: () => onSelected(language),
          ),
          if (language != BearLanguage.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Чип языка: выбранный залит зелёным, остальные — светлые с обводкой.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.radiusChip);

    return Material(
      color: selected ? AppColors.sage : Colors.white.withValues(alpha: 0.64),
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.sage : AppColors.outline,
            ),
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Одна строка с переключателем: подпись слева, тумблер справа.
class _ToggleRow {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
}

/// Карточка из строк-переключателей с разделителями.
class _TogglesCard extends StatelessWidget {
  const _TogglesCard({required this.rows});

  final List<_ToggleRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.64),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        children: [
          // Идём по индексам, а не по значениям: одинаковых строк тут быть не
          // должно, но сравнение «это последняя?» по значению — ловушка, в
          // которую уже наступали в профиле.
          for (var i = 0; i < rows.length; i++) ...[
            _ToggleTile(row: rows[i]),
            // Разделителя после последней строки нет — иначе он читался бы как
            // обрезанная снизу карточка.
            if (i != rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.outline),
          ],
        ],
      ),
    );
  }
}

/// Отрисовка одной строки-переключателя.
class _ToggleTile extends StatelessWidget {
  const _ToggleTile({required this.row});

  final _ToggleRow row;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // Нажатие по всей строке, а не только по тумблеру: строк девять, они
      // узкие, и целиться в переключатель пальцем на телефоне неудобно.
      onTap: () => row.onChanged(!row.value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.title,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 10),
            // Тумблер оставлен стандартным: цвета ему уже задаёт тема
            // (`switchTheme`), а привычная механика свайпа и размер зоны
            // касания важнее, чем повторение 40×23 из HTML-прототипа.
            Switch(value: row.value, onChanged: row.onChanged),
          ],
        ),
      ),
    );
  }
}
