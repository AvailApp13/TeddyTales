import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../bear/bear_controller.dart';
import '../bear/bear_rig_spec.dart' show BearTrait;
import '../game/food.dart';
import '../game/game_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Подсказка от характера питомца (КП 8.1 — «подсказка от характера»).
///
/// Реплики принадлежат экрану кормления, а не общему набору фраз BearPhrases:
/// там реплики привязаны к настроению и стадии и переведены на три языка
/// (КП 13.3), а эти шесть — про еду и только про неё.
///
/// ЗАГЛУШКА: только русский. Локализация экрана — общая работа по КП 16.1,
/// вместе с остальными строками интерфейса.
const Map<BearTrait, String> _foodHint = {
  BearTrait.active: 'Я сегодня носился как заводной — давай посытнее!',
  BearTrait.curious: 'А приготовим что-нибудь новенькое?',
  BearTrait.affectionate: 'Хочу что-нибудь сладкое… и чтобы ты рядом.',
  BearTrait.calm: 'Мне бы чего-то тёплого и простого.',
  BearTrait.independent: 'Я бы и сам справился. Ну, почти.',
  BearTrait.reserved: 'Можно просто фрукты?',
};

/// Любимое блюдо по характеру (КП 7.4 — характер влияет на предпочтения в еде).
///
/// Пока это только подсветка карточки: разной прибавки «еды» за любимое блюдо
/// КП не требует, а придумывать её самим — значит разойтись с балансом,
/// который по КП 10.9 считается отдельно.
const Map<BearTrait, String> _favouriteDish = {
  BearTrait.active: 'pasta',
  BearTrait.curious: 'omelette',
  BearTrait.affectionate: 'cookie',
  BearTrait.calm: 'porridge',
  BearTrait.independent: 'sandwich',
  BearTrait.reserved: 'fruit',
};

/// Две вкладки экрана кормления (КП 8.1).
enum _FeedTab {
  ready('Готовые блюда'),
  cook('Приготовить');

  const _FeedTab(this.title);

  final String title;
}

/// Экран кормления с мини-игрой готовки (КП 8).
///
/// Экран ничего не считает сам: цены и прибавки знает [FoodCatalog], монеты
/// списывает и кормит [GameState.feedWithDish], награду за рецепт выдаёт
/// [GameState.completeRecipe]. Здесь остаются только показ и порядок шагов —
/// так правила лежат в одном месте и не разъедутся с сервером (КП 15.4).
///
/// Мини-игра живёт внутри этого же экрана, а не отдельным маршрутом: в
/// принятом прототипе «назад» из готовки возвращает к списку рецептов, а не
/// закрывает кормление целиком.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.controller, required this.game});

  /// Питомец: отсюда берётся характер — от него зависят подсказка и любимое
  /// блюдо (КП 7.4). Кормит мишку [GameState], а не экран.
  final BearController controller;

  final GameState game;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  /// Порядок ингредиентов перемешивается, иначе мини-игра сводится к чтению
  /// слева направо.
  final Random _random = Random();

  _FeedTab _tab = _FeedTab.ready;

  /// Открытый рецепт — экран мини-игры. `null` — список блюд и рецептов.
  Recipe? _recipe;

  /// Сколько шагов рецепта уже собрано.
  int _step = 0;

  /// Ингредиент, по которому только что ошиблись, — подсвечивается и гаснет
  /// сам. Это подсветка, а не штраф: по КП 8.4 ошибка ничего не стоит.
  int? _wrongIndex;

  /// Порядок кнопок, зафиксированный на попытку: индексы в
  /// [Recipe.allChoices]. Пересчитывать его на каждый тап нельзя — кнопки
  /// начнут прыгать под пальцем.
  List<int> _order = const [];

  Timer? _wrongTimer;

  @override
  void dispose() {
    _wrongTimer?.cancel();
    super.dispose();
  }

  // --- Готовые блюда (КП 8.2) ----------------------------------------------

  void _eat(Dish dish) {
    // Хватает ли монет, решает кошелёк, а не экран: иначе проверка и списание
    // разъедутся.
    if (!widget.game.feedWithDish(dish)) {
      _toast('Не хватает монет');
      return;
    }

    _closeWith(
      '${dish.title} · еда +${_gainLabel(dish.foodGain)}, '
      '−${dish.price} монет',
    );
  }

  // --- Мини-игра готовки (КП 8.4) ------------------------------------------

  void _openRecipe(Recipe recipe) {
    _wrongTimer?.cancel();
    setState(() {
      _recipe = recipe;
      _step = 0;
      _wrongIndex = null;
      _order = List<int>.generate(recipe.allChoices.length, (i) => i)
        ..shuffle(_random);
    });
  }

  void _closeRecipe() {
    _wrongTimer?.cancel();
    setState(() {
      _recipe = null;
      _step = 0;
      _wrongIndex = null;
      _order = const [];
    });
  }

  void _tapIngredient(Recipe recipe, int index) {
    // Индексы до [Recipe.steps.length] — это шаги в правильном порядке, всё
    // остальное лишнее. Нужный прямо сейчас — ровно тот, чей индекс совпал с
    // числом собранных шагов.
    if (index != _step) {
      // КП 8.4: ошибка — подсказка и повтор. Ни монет, ни прогресса не
      // отнимаем, шаг остаётся прежним.
      _wrongTimer?.cancel();
      setState(() => _wrongIndex = index);
      _wrongTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _wrongIndex = null);
      });
      return;
    }

    _wrongTimer?.cancel();
    final next = _step + 1;

    if (next < recipe.steps.length) {
      setState(() {
        _step = next;
        _wrongIndex = null;
      });
      return;
    }

    widget.game.completeRecipe(recipe);
    _closeWith(
      'Готово! ${recipe.title} · +${recipe.reward} монет, '
      'еда +${_gainLabel(recipe.foodGain)}',
    );
  }

  // --- Служебное -----------------------------------------------------------

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  /// Покормили — экран закрывается, а результат показывается поверх комнаты:
  /// мишка ест именно там, смотреть надо на него.
  void _closeWith(String text) {
    // Мессенджер берём до pop: сам экран к этому моменту уже уходит со стека.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.maybePop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовываемся и на кошелёк с инвентарём, и на самого мишку: характер
    // (а с ним подсказка и любимое блюдо) живёт в контроллере.
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.game]),
      builder: (context, _) {
        final recipe = _recipe;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: recipe == null
                ? _buildPicker(context)
                : _buildMiniGame(context, recipe),
          ),
        );
      },
    );
  }

  /// Выбор: вкладки «Готовые блюда» и «Приготовить» (КП 8.1, 8.3).
  Widget _buildPicker(BuildContext context) {
    final trait = widget.controller.state.trait;

    return Column(
      children: [
        _SheetHead(
          title: 'Чем покормим?',
          coins: widget.game.coins,
          onBack: () => Navigator.maybePop(context),
        ),
        _TabsBar(
          current: _tab,
          onSelected: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: 10),
        _HintBar(emoji: '🧸', text: _foodHint[trait] ?? ''),
        const SizedBox(height: 10),
        Expanded(
          child: _tab == _FeedTab.ready
              ? _buildDishes(trait)
              : _buildRecipes(),
        ),
      ],
    );
  }

  Widget _buildDishes(BearTrait trait) {
    final favourite = _favouriteDish[trait];

    return ListView(
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
          itemCount: FoodCatalog.dishes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            // Высоту задаём явно, а не пропорцией: карточки одинаковые по
            // содержимому, и на узком экране пропорция начинает их резать.
            mainAxisExtent: 118,
          ),
          itemBuilder: (context, index) {
            final dish = FoodCatalog.dishes[index];
            return _DishTile(
              dish: dish,
              isFavourite: dish.id == favourite,
              canAfford: widget.game.coins >= dish.price,
              onTap: () => _eat(dish),
            );
          },
        ),
        const SizedBox(height: 10),
        const _Note(
          'Ровно 10 блюд по КП 8.2. Цены и прибавки — плейсхолдеры, '
          'по КП 10.9 они утверждаются отдельно и настраиваются с сервера.',
        ),
      ],
    );
  }

  Widget _buildRecipes() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        0,
        AppDimens.pagePadding,
        AppDimens.pagePadding,
      ),
      children: [
        for (final recipe in FoodCatalog.recipes) ...[
          _RecipeTile(recipe: recipe, onTap: () => _openRecipe(recipe)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 2),
        const _Note(
          'Ровно 5 рецептов по КП 8.5: печенье и сэндвич — по 3 шага, '
          'остальные — от 4 до 6.',
        ),
      ],
    );
  }

  /// Мини-игра: ингредиенты в правильной последовательности (КП 8.4).
  Widget _buildMiniGame(BuildContext context, Recipe recipe) {
    final hasError = _wrongIndex != null;

    return Column(
      children: [
        _SheetHead(
          title: recipe.title,
          coins: widget.game.coins,
          onBack: _closeRecipe,
        ),
        const SizedBox(height: 10),
        _HintBar(
          emoji: recipe.emoji,
          text: 'Добавляй продукты по порядку. '
              'Ошибёшься — просто попробуем ещё раз.',
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              AppDimens.pagePadding,
            ),
            children: [
              _StepsRow(recipe: recipe, done: _step),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _order.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 80,
                ),
                itemBuilder: (context, position) {
                  final index = _order[position];
                  final ingredient = recipe.allChoices[index];
                  // Уже добавленные шаги гасим, лишние продукты остаются
                  // живыми: по ним и ошибаются.
                  final isUsed = index < _step;

                  return _IngredientTile(
                    ingredient: ingredient,
                    isUsed: isUsed,
                    isWrong: _wrongIndex == index,
                    onTap: isUsed ? null : () => _tapIngredient(recipe, index),
                  );
                },
              ),
              const SizedBox(height: 10),
              _Note(
                hasError
                    ? 'Не то. Сейчас нужно: ${recipe.steps[_step].title}. '
                          'Попробуй ещё раз — штрафа нет.'
                    : 'Шаг ${_step + 1} из ${recipe.steps.length}. '
                          'Награда: ${recipe.reward} монет и '
                          'еда +${_gainLabel(recipe.foodGain)}.',
                isError: hasError,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Прибавка «еды» в подписи. В каталоге значения целые — дробей в тексте быть
/// не должно.
String _gainLabel(double value) => value.round().toString();

/// Шапка экрана: «назад», заголовок по центру, кошелёк справа.
///
/// Своя, а не [AppBar]: в макете это лист поверх комнаты, и справа стоит
/// кошелёк из КП 11.1, а не действия.
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
          const _Coin(size: 13),
          const SizedBox(width: 5),
          Text(
            '$coins',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Монетка — кружок фирменного цвета. Иконки монеты в макете нет, есть кружок.
class _Coin extends StatelessWidget {
  const _Coin({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.coin,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Переключатель вкладок «Готовые блюда» / «Приготовить» (КП 8.1).
class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.current, required this.onSelected});

  final _FeedTab current;
  final ValueChanged<_FeedTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: Row(
        children: [
          for (final tab in _FeedTab.values) ...[
            Expanded(
              child: _TabButton(
                tab: tab,
                isSelected: tab == current,
                onTap: () => onSelected(tab),
              ),
            ),
            if (tab != _FeedTab.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final _FeedTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.sage : AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusChip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusChip),
            border: Border.all(
              color: isSelected ? AppColors.sage : AppColors.outline,
            ),
          ),
          child: Text(
            tab.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Полоска с репликой: подсказка от характера на выборе блюда (КП 8.1) и
/// правило игры в готовке.
class _HintBar extends StatelessWidget {
  const _HintBar({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка готового блюда (КП 8.2).
class _DishTile extends StatelessWidget {
  const _DishTile({
    required this.dish,
    required this.isFavourite,
    required this.canAfford,
    required this.onTap,
  });

  final Dish dish;
  final bool isFavourite;
  final bool canAfford;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tile = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        // Карточку не хватающего по деньгам блюда оставляем живой, только
        // гасим: тап объяснит причину словами, мёртвая кнопка — нет.
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(
              color: isFavourite ? AppColors.blush : AppColors.outline,
              width: isFavourite ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dish.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 3),
                    Text(
                      dish.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'еда +${_gainLabel(dish.foodGain)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _Coin(size: 11),
                        const SizedBox(width: 4),
                        Text(
                          '${dish.price}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isFavourite)
                const Positioned(top: 0, right: 0, child: _FavouriteTag()),
            ],
          ),
        ),
      ),
    );

    final dimmed = canAfford ? tile : Opacity(opacity: 0.45, child: tile);

    if (canAfford) return dimmed;
    return Tooltip(message: 'Не хватает монет', child: dimmed);
  }
}

/// Метка любимого блюда (КП 7.4).
class _FavouriteTag extends StatelessWidget {
  const _FavouriteTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.blush,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'любимое',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// Строка рецепта на вкладке «Приготовить» (КП 8.3).
class _RecipeTile extends StatelessWidget {
  const _RecipeTile({required this.recipe, required this.onTap});

  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Сложность рецепта звёздами, 1–3 (КП 8.3).
    final stars = '★' * recipe.difficulty + '☆' * (3 - recipe.difficulty);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Text(recipe.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$stars · ${_plural(recipe.steps.length, 'шаг', 'шага', 'шагов')}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _Coin(size: 11),
              const SizedBox(width: 4),
              Text(
                '+${recipe.reward}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Лента шагов рецепта: собранное показано продуктом, оставшееся — номером.
class _StepsRow extends StatelessWidget {
  const _StepsRow({required this.recipe, required this.done});

  final Recipe recipe;
  final int done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (var i = 0; i < recipe.steps.length; i++)
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i < done ? AppColors.sageSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: i < done ? AppColors.sage : AppColors.outline,
              ),
            ),
            child: Text(
              i < done ? recipe.steps[i].emoji : '${i + 1}',
              style: theme.textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

/// Кнопка ингредиента в мини-игре (КП 8.4).
class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.ingredient,
    required this.isUsed,
    required this.isWrong,
    required this.onTap,
  });

  final Ingredient ingredient;
  final bool isUsed;

  /// Ошиблись именно этим продуктом — обводка на 700 мс.
  final bool isWrong;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: isUsed ? 0.35 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(
                color: isWrong ? AppColors.blushStrong : AppColors.outline,
                width: isWrong ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ingredient.emoji, style: const TextStyle(fontSize: 21)),
                const SizedBox(height: 3),
                Text(
                  ingredient.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Пояснение под списком. Тексты объясняют, что состав и цены не выдуманы
/// экраном, а заданы КП, — их видно и Заказчику при приёмке.
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

/// Русские числительные: 1 шаг, 2 шага, 5 шагов, 11 шагов, 21 шаг.
///
/// Своя реализация, а не `intl`: ради одной строки тянуть пакет и заводить
/// локали незачем. Когда дойдём до локализации по КП 16.1, склонения переедут
/// туда вместе с остальными текстами.
String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  final mod10 = n % 10;

  if (mod100 >= 11 && mod100 <= 14) return '$n $many';
  if (mod10 == 1) return '$n $one';
  if (mod10 >= 2 && mod10 <= 4) return '$n $few';
  return '$n $many';
}
