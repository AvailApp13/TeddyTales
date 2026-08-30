/// Экраны взрослых мини-игр: пятнашки с фото мишки, 2048 и «Память».
///
/// Уточнение владельца продукта: основная аудитория — 18+, поэтому вместо
/// детских квизов здесь классический взрослый казуал. Пазл собирается из
/// фотографии героя бренда — это одновременно и игра, и витрина каталога.
///
/// Каждый экран получает колбэк [onWin] и сам ничего не начисляет: монеты и
/// радость мишки — забота `GameState.completeLevel`, как во всей игре.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'board_2048.dart';
import 'pairs_board.dart';
import 'sliding_board.dart';

/// Фото героя для пазла. Квадратный кадр мальчика SLOW в голубом капюшоне.
const String _heroImage = 'assets/images/bear_hero.jpg';

// --- Пятнашки: пазл из фото мишки ------------------------------------------

class SlidingPuzzleScreen extends StatefulWidget {
  const SlidingPuzzleScreen({
    super.key,
    required this.level,
    required this.onWin,
  });

  /// Номер уровня 0–9: от него растут поле и длина перемешивания.
  final int level;
  final VoidCallback onWin;

  @override
  State<SlidingPuzzleScreen> createState() => _SlidingPuzzleScreenState();
}

class _SlidingPuzzleScreenState extends State<SlidingPuzzleScreen> {
  late SlidingBoard _board;

  /// 3×3 на первых пяти уровнях, дальше 4×4. Перемешивание удлиняется с
  /// уровнем — этого достаточно, чтобы сложность росла ощутимо.
  int get _side => widget.level < 5 ? 3 : 4;

  @override
  void initState() {
    super.initState();
    _board = SlidingBoard(
      _side,
      shuffleMoves: 20 + widget.level * 12,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _tap(int position) {
    if (_board.isSolved) return;
    setState(() => _board.moveFrom(position));
    if (_board.isSolved) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        widget.onWin();
        Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _board.size;
    final solved = _board.isSolved;

    final l10n = context.l10n;

    return GameScaffold(
      title: l10n.gamePuzzleTitle(widget.level + 1),
      hint: solved ? l10n.gamePuzzleSolvedHint : l10n.gamePuzzleHint,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: AppColors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: n * n,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
            ),
            itemBuilder: (context, position) {
              final tile = _board.tiles[position];
              final isBlank = tile == n * n - 1;
              // Пустую клетку в собранном поле тоже показываем фрагментом —
              // фото становится целым.
              if (isBlank && !solved) {
                return const ColoredBox(color: AppColors.surfaceMuted);
              }
              final row = tile ~/ n;
              final col = tile % n;
              return GestureDetector(
                onTap: () => _tap(position),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.surface.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  position: DecorationPosition.foreground,
                  // Кадрируем явно: растягиваем фото на всё поле n×n и
                  // сдвигаем так, чтобы в клетку попал её собственный кусок.
                  // Приём с Align/widthFactor здесь не работает: сетка сама
                  // задаёт размер плитки, и Align не ужимает окно просмотра.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.maxWidth;
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned(
                            left: -col * side,
                            top: -row * side,
                            width: side * n,
                            height: side * n,
                            child: Image.asset(_heroImage, fit: BoxFit.cover),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- 2048 -------------------------------------------------------------------

class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key, required this.level, required this.onWin});

  final int level;
  final VoidCallback onWin;

  /// Целевая плитка по уровням: с 32 на разогрев до честных 2048.
  static const List<int> targets = [
    32, 64, 128, 128, 256, 256, 512, 512, 1024, 2048, //
  ];

  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen> {
  late Board2048 _board;
  bool _won = false;

  int get _target => Game2048Screen.targets[widget.level];

  @override
  void initState() {
    super.initState();
    _board = Board2048(seed: DateTime.now().millisecondsSinceEpoch);
  }

  void _swipe(MoveDirection direction) {
    if (_won) return;
    final moved = _board.move(direction);
    if (!moved) return;
    setState(() {});
    if (_board.maxTile >= _target) {
      _won = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        widget.onWin();
        Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return GameScaffold(
      title: l10n.game2048Title(widget.level + 1),
      hint: _won
          ? l10n.game2048WonHint(_target)
          : _board.isStuck
          ? l10n.game2048StuckHint
          : l10n.game2048Hint(_target, _board.score),
      onRestart: _board.isStuck
          ? () => setState(() {
              _board = Board2048(
                seed: DateTime.now().millisecondsSinceEpoch,
              );
            })
          : null,
      child: GestureDetector(
        // Определяем направление по завершении жеста: одно событие на свайп.
        onHorizontalDragEnd: (d) => _swipe(
          (d.primaryVelocity ?? 0) < 0
              ? MoveDirection.left
              : MoveDirection.right,
        ),
        onVerticalDragEnd: (d) => _swipe(
          (d.primaryVelocity ?? 0) < 0 ? MoveDirection.up : MoveDirection.down,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: AppColors.outline),
            ),
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: Board2048.size,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final row in _board.cells)
                  for (final value in row) _Tile2048(value: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile2048 extends StatelessWidget {
  const _Tile2048({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    // Чем старше плитка, тем гуще фирменный шалфей; после 256 — румяна.
    final color = switch (value) {
      0 => AppColors.surface,
      2 || 4 => AppColors.sageSoft,
      8 || 16 => AppColors.sage,
      32 || 64 => AppColors.sageDark,
      128 || 256 => AppColors.tan,
      _ => AppColors.blushStrong,
    };
    final dark = value >= 8;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDimens.radiusChip),
      ),
      child: value == 0
          ? null
          : FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
    );
  }
}

// --- Память -----------------------------------------------------------------

class PairsScreen extends StatefulWidget {
  const PairsScreen({super.key, required this.level, required this.onWin});

  final int level;
  final VoidCallback onWin;

  @override
  State<PairsScreen> createState() => _PairsScreenState();
}

class _PairsScreenState extends State<PairsScreen> {
  /// Символы пар — предметы из мира мишки, не детские «где красный».
  static const List<String> _symbols = [
    '🧸', '🧶', '🍯', '🫖', '🧺', '🌻', '🍪', '🎁', '🧦', '🕯️', '🌙', '☕',
  ];

  late PairsBoard _board;

  /// Открытая пара, которую надо показать и закрыть. Пока она видна, другие
  /// тапы игнорируются — иначе можно листать поле без запоминания.
  (int, int)? _revealedMiss;

  int get _pairCount => min(4 + widget.level, _symbols.length);

  @override
  void initState() {
    super.initState();
    final symbols = [..._symbols]..shuffle(Random());
    _board = PairsBoard(symbols.take(_pairCount).toList());
  }

  void _tap(int index) {
    if (_revealedMiss != null || _board.isSolved) return;
    final first = _board.openIndex;
    final result = _board.flip(index);
    setState(() {});

    switch (result) {
      case PairsFlip.miss:
        _revealedMiss = (first!, index);
        Future.delayed(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          setState(() => _revealedMiss = null);
        });
      case PairsFlip.matched:
        if (_board.isSolved) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            widget.onWin();
            Navigator.of(context).pop();
          });
        }
      case PairsFlip.first || PairsFlip.ignored:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = _pairCount <= 6 ? 3 : 4;

    final l10n = context.l10n;

    return GameScaffold(
      title: l10n.gamePairsTitle(widget.level + 1),
      hint: _board.isSolved
          ? l10n.gamePairsSolvedHint(_board.moves)
          : l10n.gamePairsHint(_board.moves),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _board.cards.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final revealed = _revealedMiss;
          final faceUp =
              _board.isOpen(index) ||
              (revealed != null &&
                  (index == revealed.$1 || index == revealed.$2));

          return GestureDetector(
            onTap: () => _tap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: faceUp ? AppColors.surface : AppColors.sageSoft,
                borderRadius: BorderRadius.circular(AppDimens.radiusChip),
                border: Border.all(
                  color: _board.isMatched(index)
                      ? AppColors.sage
                      : AppColors.outline,
                  width: _board.isMatched(index) ? 2 : 1,
                ),
              ),
              child: Text(
                faceUp ? _board.cards[index] : '❔',
                style: const TextStyle(fontSize: 26),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Общий каркас экрана игры ----------------------------------------------

/// Шапка, подсказка и контент — одинаковые для всех трёх игр.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    required this.hint,
    required this.child,
    this.onRestart,
  });

  final String title;
  final String hint;
  final Widget child;

  /// Показать кнопку «Заново» (2048 в тупике).
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
                    shape: const CircleBorder(
                      side: BorderSide(color: AppColors.outline),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.maybePop(context),
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
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
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
                  child,
                  const SizedBox(height: 10),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  if (onRestart != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onRestart,
                      child: Text(context.l10n.gameRestart),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
