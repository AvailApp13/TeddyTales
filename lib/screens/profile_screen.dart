import 'package:flutter/material.dart';

import '../bear/bear.dart';
import '../game/game_calendar.dart';
import '../game/game_state.dart';
import '../l10n/l10n.dart';
import '../l10n/zodiac_l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Профиль питомца (КП 14.1): карточка рождения, характер, история стадий.
///
/// Экран собран по принятому прототипу (`renderProfile`) и ничего к нему не
/// добавляет. Три блока идут в том же порядке и с теми же заголовками, потому
/// что порядок здесь — это порядок пункта 14.1 КП: «карточка рождения, характер,
/// стадия, история переходов».
///
/// Данные приходят из двух источников и не дублируются: то, что задано при
/// рождении и дальше не меняется (пол, дата, знак зодиака), лежит в
/// `GameState.profile` — КП 2.4 и 2.5 отдают это серверу; то, что живёт и
/// меняется по ходу игры (стадия, характер), берётся из [BearController], у
/// которого с ригом общий источник правды.
///
/// Кошелька в шапке нет намеренно: в прототипе профиль открывается через
/// `sheetHead('Профиль', false)` — на этом экране ничего не покупают.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.game,
    required this.onOpenGrowth,
    required this.onOpenDiary,
    required this.onOpenSettings,
    this.calendar = const GameCalendar(),
    this.language = BearLanguage.ru,
  });

  /// Стадия и характер — оттуда же, откуда их берёт риг: расхождение между
  /// профилем и картинкой мишки читалось бы как ошибка.
  final BearController controller;

  /// Карточка рождения и кошелёк. Экран только читает [GameState], но
  /// подписывается на него: имя питомца по КП 14.2 меняется в настройках, и
  /// профиль обязан это увидеть без перезахода.
  final GameState game;

  /// Переход в «Рост и развитие» (КП 5), «Дневник» (КП 14.3) и «Настройки»
  /// (КП 14.2). Экран не знает про роутинг — навигацию подключает вызывающий.
  final VoidCallback onOpenGrowth;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenSettings;

  /// Перевод реального времени в игровой возраст. По КП 1.5 и 15.4 календарь
  /// настраиваемый и должен приезжать с сервера — поэтому он параметр, а не
  /// константа внутри экрана.
  final GameCalendar calendar;

  /// Язык интерфейса (КП 13.4). Влияет на формат возраста: «3 месяца 12 дней»
  /// против «3 months 12 days».
  final BearLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          // Слушаем оба: стадия растёт в контроллере, имя и профиль живут в
          // GameState.
          animation: Listenable.merge([controller, game]),
          builder: (context, _) {
            final l10n = context.l10n;
            final state = controller.state;
            final profile = game.profile;

            // Пол берём из карточки рождения, а не из `state.skin`: в риг то же
            // значение только зеркалится, а первоисточник по КП 2.4 — сервер.
            final skin = profile.skin;
            final age = calendar.ageAt(profile.birthAt);

            // История переходов (КП 14.1): всё, что мишка уже прошёл, включая
            // текущую стадию. Будущие стадии сюда не попадают — им место на
            // экране роста, где показывают, что впереди.
            final history = BearStage.values
                .where((stage) => stage.riveValue <= state.stage.riveValue)
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(title: l10n.profileTitle),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pagePadding,
                      0,
                      AppDimens.pagePadding,
                      AppDimens.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BirthCard(name: profile.name, skin: skin),

                        _SectionTitle(l10n.profileSectionBirth),
                        _InfoRows(
                          rows: [
                            _InfoRow(
                              l10n.profileSexLabel,
                              skin == BearSkin.girl
                                  ? l10n.profileSexGirl
                                  : l10n.profileSexBoy,
                            ),
                            _InfoRow(l10n.profileAgeLabel, age.format(language)),
                            _InfoRow(
                              l10n.profileZodiacLabel,
                              // ДОПУЩЕНИЕ: пока сервера нет, показываем Льва —
                              // ровно как в прототипе, чтобы строка не пустовала.
                              zodiacTitle(context.l10n, profile.zodiac ?? BearZodiac.leo),
                              // Пометка стоит только здесь: остальные две
                              // заглушки объяснены подписью внизу экрана, и три
                              // одинаковых ярлыка подряд превратили бы карточку
                              // в список недоделок.
                              isStub: profile.zodiac == null,
                            ),
                            // ЗАГЛУШКА: рост и вес — часть карточки рождения
                            // (КП 2.2), но их определяет сервер при рождении
                            // вместе с полом и знаком (КП 2.4, 2.5). Значения —
                            // из каталога TeddyTales®: «Карманный мишка
                            // Фортуна, 15 см». Когда карточка начнёт приходить
                            // с бэкенда, обе строки уедут в `PetProfile`.
                            _InfoRow(
                              l10n.profileHeightLabel,
                              l10n.profileHeightStub,
                            ),
                            _InfoRow(
                              l10n.profileWeightLabel,
                              l10n.profileWeightStub,
                            ),
                          ],
                        ),

                        _SectionTitle(l10n.profileSectionTrait),
                        _InfoRows(
                          rows: [
                            _InfoRow(
                              l10n.profileTraitNowLabel,
                              state.trait.title,
                            ),
                            // КП 7.3: характер складывается из совокупности
                            // действий за период, а не из одного действия.
                            // «3 дня» — окно `BearTraitTracker.window`; строка
                            // объясняет, почему черта не меняется от одного
                            // кормления.
                            _InfoRow(
                              l10n.profileTraitHowLabel,
                              l10n.profileTraitHowValue,
                            ),
                          ],
                        ),

                        _SectionTitle(l10n.profileSectionHistory),
                        _StageTimeline(history: history, current: state.stage),

                        _SectionTitle(l10n.profileSectionLinks),
                        _LinkTile(
                          icon: Icons.trending_up,
                          title: l10n.profileLinkGrowth,
                          subtitle: l10n.profileLinkGrowthSubtitle,
                          onTap: onOpenGrowth,
                        ),
                        const SizedBox(height: 9),
                        _LinkTile(
                          icon: Icons.menu_book_outlined,
                          title: l10n.profileLinkDiary,
                          subtitle: l10n.profileLinkDiarySubtitle,
                          onTap: onOpenDiary,
                        ),
                        const SizedBox(height: 9),
                        _LinkTile(
                          icon: Icons.settings_outlined,
                          title: l10n.profileLinkSettings,
                          subtitle: l10n.profileLinkSettingsSubtitle,
                          onTap: onOpenSettings,
                        ),

                        const SizedBox(height: 10),
                        Text(
                          l10n.profileFootnote,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                        ),
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

/// Шапка листа: круглая кнопка «назад», заголовок по центру, справа пусто.
///
/// Пустое место справа шириной с кнопку — чтобы заголовок стоял ровно по центру
/// экрана, а не съезжал влево. Та же шапка, что на экране ухода.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        8,
        AppDimens.pagePadding,
        10,
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.outline),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

/// Шапка профиля: портрет, имя, герой и цвет меха.
class _BirthCard extends StatelessWidget {
  const _BirthCard({required this.name, required this.skin});

  final String name;
  final BearSkin skin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        children: [
          // ЗАГЛУШКА: в прототипе тут стояла фотография мишки. Настоящий портрет
          // — это кадр из рига (раздел 6 ТЗ аниматора: один риг на обоих героев,
          // различия только в цвете шерсти и одежде), поэтому до сборки рига
          // показываем круг с иконкой, а не чужую картинку.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.sageSoft, width: 2),
            ),
            child: const Icon(Icons.pets, size: 40, color: AppColors.tan),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          // Герой и цвет меха — из каталога TeddyTales® (SLOW · Milk Tea,
          // JOY · White). По КП 12.1 данные в приложении должны совпадать с
          // официальным магазином, поэтому названия не переводим — локализуется
          // только слово «мех» вокруг них.
          Text(
            context.l10n.profileBirthFur(skin.heroName, skin.furColor),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Подзаголовок раздела: капслок, разрядка, приглушённый цвет.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 7),
      child: Text(
        // Капслок делается здесь, а не в тексте: так строку видно в исходнике
        // так же, как в прототипе, и её проще сверять с КП.
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Одна строка карточки: подпись слева, значение справа.
class _InfoRow {
  const _InfoRow(this.label, this.value, {this.isStub = false});

  final String label;
  final String value;

  /// Показать ярлык «заглушка» рядом со значением.
  final bool isStub;
}

/// Карточка из строк «подпись — значение» с разделителями.
class _InfoRows extends StatelessWidget {
  const _InfoRows({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        children: [
          // Идём по индексам, а не по значениям: одинаковые константные строки
          // Dart схлопывает в один объект, и сравнение «это последняя строка?»
          // по значению однажды соврало бы.
          for (var i = 0; i < rows.length; i++) ...[
            _InfoRowTile(row: rows[i]),
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

/// Отрисовка одной строки карточки.
class _InfoRowTile extends StatelessWidget {
  const _InfoRowTile({required this.row});

  final _InfoRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        // Выравнивание по базовой линии: подпись и значение разного веса и
        // размера, по центру они бы «плавали» относительно друг друга.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            row.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (row.isStub) ...[const SizedBox(width: 5), const _StubBadge()],
        ],
      ),
    );
  }
}

/// Ярлык «заглушка» — честная пометка, что значение придёт с сервера.
class _StubBadge extends StatelessWidget {
  const _StubBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.l10n.profileStubBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// История переходов между стадиями (КП 14.1): точки на вертикальной линии.
class _StageTimeline extends StatelessWidget {
  const _StageTimeline({required this.history, required this.current});

  final List<BearStage> history;
  final BearStage current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stage in history)
          // IntrinsicHeight нужен, чтобы отрезок линии дотянулся ровно до
          // следующей точки: высоту строки задаёт текст, и знать её заранее
          // нельзя. Стадий максимум пять, на стоимость это не влияет.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    // Отступ до точки равен верхнему паддингу текста — так
                    // кружок встаёт напротив первой строки названия.
                    const SizedBox(height: 8),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        // Текущая стадия выделена насыщенным зелёным,
                        // пройденные — светлым.
                        color: stage == current
                            ? AppColors.sage
                            : AppColors.sageSoft,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (stage != history.last)
                      const Expanded(
                        child: VerticalDivider(
                          width: 9,
                          thickness: 1,
                          color: AppColors.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stage.title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          stage == current
                              ? context.l10n.profileStageNow
                              : context.l10n.profileStagePassed,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Строка перехода в соседний раздел: иконка, название, пояснение.
///
/// Иконки материальные, а не эмодзи из прототипа: в прототипе эмодзи стояли
/// вынужденно (HTML без ассетов), а в приложении разделы уже нарисованы
/// иконками в нижней навигации.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Icon(icon, size: 26, color: AppColors.sage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
