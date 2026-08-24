import 'dart:async';

import 'package:flutter/material.dart';

import '../game/audience.dart';
import '../game/game_state.dart';
import '../games/adult_games.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Задание: вопрос и четыре варианта ответа, один из которых верный.
///
/// Варианты — эмодзи или короткие строки, как в принятом прототипе: до чтения
/// малыш ещё не дорос, ответ выбирается по картинке.
class _EduTask {
  const _EduTask({
    required this.question,
    required this.options,
    required this.correct,
  });

  final String question;
  final List<String> options;

  /// Индекс верного варианта в [options].
  final int correct;
}

/// Категория обучения: три штуки, названия из КП 9.1.
class _EduCategory {
  const _EduCategory({
    required this.id,
    required this.emoji,
    required this.title,
    required this.tasks,
  });

  /// Ключ прогресса в [GameState.eduProgress] — тот же, что в прототипе.
  final String id;

  final String emoji;
  final String title;
  final List<_EduTask> tasks;
}

/// Контент обучения — ЗАГЛУШКА на девять заданий.
///
/// По КП 9.4 движок рассчитан на 300 заданий, а сам контент даёт Заказчик через
/// панель управления. То есть этот список — не финальные данные, а образец
/// формата: когда появится API контента (КП 15.4), список уезжает на сервер, а
/// экран остаётся прежним. Пока заданий меньше, чем уровней, они повторяются по
/// кругу — ровно как в прототипе, который заказчик принял.
///
/// Тексты вопросов и наборы вариантов перенесены из прототипа дословно,
/// переформулировок нет.
const List<_EduCategory> _categories = [
  _EduCategory(
    id: 'colors',
    emoji: '🎨',
    title: 'Цвета и формы',
    tasks: [
      _EduTask(
        question: 'Где красный?',
        options: ['🔴', '🟢', '🔵', '🟡'],
        correct: 0,
      ),
      _EduTask(
        question: 'Где круг?',
        options: ['🔺', '⬛️', '🔵', '⬜️'],
        correct: 2,
      ),
      _EduTask(
        question: 'Где зелёный?',
        options: ['🟣', '🟢', '🟠', '⚫️'],
        correct: 1,
      ),
    ],
  ),
  _EduCategory(
    id: 'count',
    emoji: '🔢',
    title: 'Счёт и простая логика',
    tasks: [
      _EduTask(
        question: 'Сколько яблок? 🍎🍎🍎',
        options: ['2', '3', '4', '5'],
        correct: 1,
      ),
      _EduTask(
        question: 'Что больше?',
        options: ['🐘', '🐭', '🐜', '🐝'],
        correct: 0,
      ),
      _EduTask(
        question: 'Что дальше? 1, 2, 3…',
        options: ['5', '4', '7', '9'],
        correct: 1,
      ),
    ],
  ),
  _EduCategory(
    id: 'world',
    emoji: '🌍',
    title: 'Окружающий мир',
    tasks: [
      _EduTask(
        question: 'Кто живёт в воде?',
        options: ['🐟', '🐈', '🐦', '🐴'],
        correct: 0,
      ),
      _EduTask(
        question: 'Что светит днём?',
        options: ['🌙', '⭐️', '☀️', '💡'],
        correct: 2,
      ),
      _EduTask(
        question: 'Где растут яблоки?',
        options: ['🌳', '🌊', '🏔', '🏠'],
        correct: 0,
      ),
    ],
  ),
];

/// Уровней в каждой категории (КП 9.2). Три категории по десять — те самые
/// 30 уровней из заголовка раздела 9 КП.
const int _levelsPerCategory = 10;

/// Взрослая категория: та же строка списка, но вместо квиза открывается
/// собственный экран игры.
class _AdultCategory {
  const _AdultCategory({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String id;
  final String emoji;
  final String title;
  final String subtitle;

  /// Экран уровня. [onWin] обязан позвать `GameState.completeLevel`.
  final Widget Function(int level, VoidCallback onWin) builder;
}

/// Взрослый набор (аудитория 18+, см. `docs/tz-app.md» — «Аудитория»):
/// пазл с фото героя — это ещё и витрина каталога, дальше классика
/// взрослого казуала. Ключи прогресса свои, с детскими не пересекаются.
final List<_AdultCategory> _adultCategories = [
  _AdultCategory(
    id: 'puzzle',
    emoji: '🧩',
    title: 'Пазлы',
    subtitle: 'Соберите фото мишки',
    builder: (level, onWin) => SlidingPuzzleScreen(level: level, onWin: onWin),
  ),
  _AdultCategory(
    id: 'logic',
    emoji: '🎯',
    title: 'Головоломки',
    subtitle: '2048 в фирменных цветах',
    builder: (level, onWin) => Game2048Screen(level: level, onWin: onWin),
  ),
  _AdultCategory(
    id: 'memory',
    emoji: '🃏',
    title: 'Память',
    subtitle: 'Найдите пары',
    builder: (level, onWin) => PairsScreen(level: level, onWin: onWin),
  ),
];

/// Награда за пройденный уровень (КП 9.5 — монеты за обучение).
///
/// Значение дублирует умолчание [GameState.completeLevel] и передаётся туда
/// явно: подпись в тосте берётся из этой же константы, чтобы обещанное и
/// начисленное не разъехались.
const int _levelReward = 10;

/// Экран обучения (КП 9): категории → уровни → задание.
///
/// Три вложенных состояния живут внутри одного экрана, а не отдельными
/// маршрутами, — так было в принятом прототипе: «назад» из задания возвращает
/// к сетке уровней, «назад» из сетки — к списку категорий, и только третий
/// «назад» закрывает обучение.
///
/// Экран ничего не начисляет сам: монеты, радость мишки и вклад в характер
/// (КП 9.5) делает [GameState.completeLevel] — один источник правды с остальной
/// игрой, как и на экране кормления.
class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key, required this.game});

  /// Прогресс по категориям и кошелёк. Питомца экран дёргает не напрямую, а
  /// через [GameState]: анимация радости на верный ответ (КП 9.3) — часть
  /// `completeLevel`.
  final GameState game;

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  /// Открытая категория. `null` — показываем список категорий.
  _EduCategory? _category;

  /// Открытая взрослая категория. Взрослый уровень — отдельный экран через
  /// Navigator, поэтому третьего состояния, как у детского квиза, здесь нет.
  _AdultCategory? _adultCategory;

  /// Открытый уровень внутри категории. `null` — показываем сетку уровней.
  int? _level;

  /// Вариант, по которому только что тапнули. `null` — ещё не отвечали.
  int? _answered;

  /// Ответ верный и мы ждём закрытия задания. Нужен, чтобы за эти 700 мс
  /// нельзя было тапнуть по верному варианту второй раз: в прототипе такой
  /// повторный тап начислял монеты ещё раз.
  bool _solved = false;

  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  // --- Переходы внутри экрана ----------------------------------------------

  void _openCategory(_EduCategory category) {
    setState(() => _category = category);
  }

  void _closeCategory() {
    setState(() => _category = null);
  }

  void _openLevel(int level) {
    _closeTimer?.cancel();
    setState(() {
      _level = level;
      _answered = null;
      _solved = false;
    });
  }

  void _closeLevel() {
    _closeTimer?.cancel();
    setState(() {
      _level = null;
      _answered = null;
      _solved = false;
    });
  }

  // --- Задание (КП 9.3) ----------------------------------------------------

  void _answer(_EduCategory category, _EduTask task, int index) {
    if (_solved) return;

    setState(() => _answered = index);

    // Неверный ответ: подсказка внизу и повтор. Ни монет, ни прогресса не
    // отнимаем и уровень не закрываем — КП 9.3 прямо требует «без штрафа».
    if (index != task.correct) return;

    final level = _level;
    if (level == null) return;

    widget.game.completeLevel(category.id, level, reward: _levelReward);
    _solved = true;

    // Пауза, чтобы успели прочитаться зелёная подсветка ответа и реакция
    // мишки, и только потом возврат к сетке уровней.
    _closeTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _closeLevel();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Верно! +$_levelReward монет'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовываемся на кошелёк и на прогресс обучения: и то и другое меняет
    // completeLevel, а не сам экран.
    return AnimatedBuilder(
      animation: widget.game,
      builder: (context, _) {
        final age = widget.game.playerAge;
        final category = _category;
        final level = _level;

        // Возраст ещё не спрашивали — раздел начинается с этого вопроса.
        // Это и есть «регистрация» возрастной развилки: КП входа без
        // регистрации (1.2) не даёт другой точки спросить.
        if (age == null) {
          return Scaffold(
            body: SafeArea(bottom: false, child: _buildAgeGate(context)),
          );
        }

        if (Audience.forAge(age) == Audience.adult) {
          final adult = _adultCategory;
          return PopScope(
            canPop: adult == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              setState(() => _adultCategory = null);
            },
            child: Scaffold(
              body: SafeArea(
                bottom: false,
                child: adult == null
                    ? _buildAdultCategories(context)
                    : _buildAdultLevels(context, adult),
              ),
            ),
          );
        }

        return PopScope(
          // Системная «назад» должна повторять кнопку в шапке: сначала выйти из
          // задания, потом из категории, и только потом закрыть экран.
          canPop: category == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_level != null) {
              _closeLevel();
              return;
            }
            _closeCategory();
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: switch ((category, level)) {
                (null, _) => _buildCategories(context),
                (final c?, null) => _buildLevels(context, c),
                (final c?, final l?) => _buildQuiz(context, c, l),
              },
            ),
          ),
        );
      },
    );
  }

  // --- Возрастная развилка ---------------------------------------------------

  /// Первый вход: спрашиваем возраст игрока. Взрослый вариант — первым:
  /// основная аудитория 18+ (см. `docs/tz-app.md`, «Аудитория»).
  Widget _buildAgeGate(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _SheetHead(
          title: 'Игры',
          coins: widget.game.coins,
          onBack: () => Navigator.maybePop(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              8,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              Text(
                'Кто будет играть?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'От возраста зависит набор игр. Поменять можно в любой момент.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _AgeOption(
                emoji: '🧸',
                title: 'Взрослый',
                subtitle: 'Пазлы с мишками, 2048, память',
                onTap: () => widget.game.setPlayerAge(18),
              ),
              const SizedBox(height: 8),
              _AgeOption(
                emoji: '🎈',
                title: 'Ребёнок до ${Audience.adultFrom}',
                subtitle: 'Цвета и формы, счёт, окружающий мир',
                onTap: () => widget.game.setPlayerAge(6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Взрослый набор --------------------------------------------------------

  Widget _buildAdultCategories(BuildContext context) {
    return Column(
      children: [
        _SheetHead(
          title: 'Игры',
          coins: widget.game.coins,
          onBack: () => Navigator.maybePop(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              for (final category in _adultCategories) ...[
                _AdultCategoryTile(
                  category: category,
                  done: widget.game.eduProgress(category.id),
                  onTap: () => setState(() => _adultCategory = category),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdultLevels(BuildContext context, _AdultCategory category) {
    final done = widget.game.eduProgress(category.id);

    return Column(
      children: [
        _SheetHead(
          title: category.title,
          coins: widget.game.coins,
          onBack: () => setState(() => _adultCategory = null),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _levelsPerCategory,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final isDone = index < done;
                  final isLocked = index > done;

                  return _LevelTile(
                    number: index + 1,
                    isDone: isDone,
                    onTap: isLocked
                        ? null
                        : () => _openAdultLevel(category, index),
                  );
                },
              ),
              const SizedBox(height: 10),
              const _Note(
                'Уровень пройден — монеты в кошелёк, следующий открывается. '
                'Сложность растёт с номером уровня.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openAdultLevel(_AdultCategory category, int level) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => category.builder(level, () {
          widget.game.completeLevel(category.id, level, reward: _levelReward);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Уровень пройден! +$_levelReward монет'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }),
      ),
    );
  }

  /// Список категорий с прогрессом N/10 (КП 9.1, 9.2).
  Widget _buildCategories(BuildContext context) {
    return Column(
      children: [
        _SheetHead(
          title: 'Обучение',
          coins: widget.game.coins,
          onBack: () => Navigator.maybePop(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              for (final category in _categories) ...[
                _CategoryTile(
                  category: category,
                  done: widget.game.eduProgress(category.id),
                  onTap: () => _openCategory(category),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Сетка из десяти уровней категории (КП 9.2).
  Widget _buildLevels(BuildContext context, _EduCategory category) {
    final done = widget.game.eduProgress(category.id);

    return Column(
      children: [
        _SheetHead(
          title: category.title,
          coins: widget.game.coins,
          onBack: _closeCategory,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _levelsPerCategory,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  // Открыт ровно один следующий уровень: пройденные — позади,
                  // остальные закрыты. Закрытые показываем, а не прячем
                  // (КП 3.5), чтобы видна была вся десятка.
                  final isDone = index < done;
                  final isLocked = index > done;

                  return _LevelTile(
                    number: index + 1,
                    isDone: isDone,
                    onTap: isLocked ? null : () => _openLevel(index),
                  );
                },
              ),
              const SizedBox(height: 10),
              const _Note(
                'По 10 уровней в каждой категории (КП 9.2). Движок рассчитан '
                'на 300 заданий, контент даёт Заказчик через панель (КП 9.4) — '
                'здесь по три задания на категорию для примера.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Само задание с вариантами ответа (КП 9.3).
  Widget _buildQuiz(BuildContext context, _EduCategory category, int level) {
    // Заданий пока меньше, чем уровней, поэтому крутим их по кругу — так же,
    // как в прототипе. С приходом контента из панели (КП 9.4) остаток исчезнет
    // сам: заданий станет столько же, сколько уровней.
    final task = category.tasks[level % category.tasks.length];
    final answered = _answered;
    final isWrong = answered != null && answered != task.correct;

    return Column(
      children: [
        _SheetHead(
          title: '${category.title} · уровень ${level + 1}',
          coins: widget.game.coins,
          onBack: _closeLevel,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
                child: Text(
                  task.question,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: task.options.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  // Высота фиксированная: варианты — одиночные эмодзи или
                  // цифры, пропорция под них подстраивалась бы вхолостую.
                  mainAxisExtent: 72,
                ),
                itemBuilder: (context, index) {
                  return _AnswerTile(
                    label: task.options[index],
                    isCorrect: answered == index && index == task.correct,
                    isWrong: answered == index && index != task.correct,
                    onTap: () => _answer(category, task, index),
                  );
                },
              ),
              const SizedBox(height: 10),
              _Note(
                isWrong
                    ? 'Не угадали. Попробуйте ещё раз — штрафа нет (КП 9.3).'
                    : 'Верный ответ — анимация радости и награда.',
                isError: isWrong,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Шапка экрана: «назад», заголовок по центру, кошелёк справа.
///
/// Своя, а не [AppBar]: в макете это лист поверх комнаты. Кошелёк тут есть
/// (в прототипе обучение открывалось с кошельком), потому что уровень приносит
/// монеты по КП 9.5 — баланс должен меняться на глазах.
class _SheetHead extends StatelessWidget {
  const _SheetHead({
    required this.title,
    required this.coins,
    required this.onBack,
  });

  final String title;
  final int coins;
  final VoidCallback onBack;

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
          _BackButton(onTap: onBack),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _CoinPill(coins: coins),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.chevron_left,
            size: 22,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Кошелёк в шапке (КП 11.1).
class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            // Иконки монеты в макете нет, есть кружок фирменного цвета.
            decoration: const BoxDecoration(
              color: AppColors.coin,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$coins',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Строка категории: эмодзи, название, «10 уровней» и прогресс N/10.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.done,
    required this.onTap,
  });

  final _EduCategory category;
  final int done;
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
              Text(category.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_levelsPerCategory уровней',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$done/$_levelsPerCategory',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.sageDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плитка уровня в сетке.
///
/// Три звезды у пройденного — ЗАГЛУШКА: КП 9.2 говорит про «счёт звёзд», но по
/// каким условиям даётся одна, две или три, нигде не сказано, и в прототипе
/// звёзд всегда три. Когда правило появится, меняется только эта плитка.
class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.number,
    required this.isDone,
    required this.onTap,
  });

  final int number;
  final bool isDone;

  /// `null` — уровень ещё закрыт.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: isDone ? AppColors.sageSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusChip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusChip),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusChip),
              border: Border.all(
                color: isDone ? AppColors.sage : AppColors.outline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$number',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isDone)
                  const Text(
                    '★★★',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.2,
                      letterSpacing: -1,
                      color: AppColors.coin,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Вариант ответа: крупная кнопка с эмодзи или короткой строкой.
class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  final String label;

  /// Тапнули по этому варианту, и он верный — зелёная заливка.
  final bool isCorrect;

  /// Тапнули по этому варианту, и он неверный — розовая обводка. Подсветка
  /// держится до следующего тапа: это подсказка, а не штраф (КП 9.3).
  final bool isWrong;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCorrect ? AppColors.sageSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(
              color: isWrong
                  ? AppColors.blushStrong
                  : isCorrect
                  ? AppColors.sage
                  : AppColors.outline,
              width: isWrong || isCorrect ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }
}

/// Пояснение под списком. Тексты объясняют, что содержимое экрана задано КП, а
/// не выдумано, — их видно и Заказчику при приёмке.
class _Note extends StatelessWidget {
  const _Note(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isError ? AppColors.blushStrong : AppColors.textSecondary,
        height: 1.5,
      ),
    );
  }
}

/// Вариант ответа на вопрос «кто будет играть».
class _AgeOption extends StatelessWidget {
  const _AgeOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
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
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка взрослой категории: как детская, но с подзаголовком-описанием.
class _AdultCategoryTile extends StatelessWidget {
  const _AdultCategoryTile({
    required this.category,
    required this.done,
    required this.onTap,
  });

  final _AdultCategory category;
  final int done;
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
              Text(category.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$done/$_levelsPerCategory',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.sageDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
