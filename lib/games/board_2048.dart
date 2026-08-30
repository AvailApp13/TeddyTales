/// Логика 2048 без единого виджета — тестируется обычными юнитами.
///
/// Правила классические: свайп сдвигает все плитки до упора, равные соседи
/// по направлению движения сливаются (каждая плитка — не больше одного
/// слияния за ход), после результативного хода появляется новая плитка
/// 2 (90%) или 4 (10%).
library;

import 'dart:math';

enum MoveDirection { left, right, up, down }

class Board2048 {
  Board2048({int? seed}) : _random = Random(seed) {
    _spawn();
    _spawn();
  }

  /// Пустая доска для тестов: плитки раскладываются вручную.
  Board2048.empty({int? seed}) : _random = Random(seed);

  static const int size = 4;

  final Random _random;

  /// Строки сверху вниз, в строке слева направо. 0 — пусто.
  final List<List<int>> cells = List.generate(
    size,
    (_) => List.filled(size, 0),
  );

  int score = 0;

  int get maxTile =>
      cells.expand((row) => row).reduce((a, b) => a > b ? a : b);

  /// Сдвиг всей доски. Возвращает `true`, если хоть что-то сдвинулось или
  /// слилось, — только тогда появляется новая плитка.
  bool move(MoveDirection direction) {
    var changed = false;

    for (var line = 0; line < size; line++) {
      final before = _readLine(direction, line);
      final after = _collapse(before);
      if (!_same(before, after)) {
        changed = true;
        _writeLine(direction, line, after);
      }
    }

    if (changed) _spawn();
    return changed;
  }

  /// Ходов не осталось: пустых клеток нет и ни одна пара соседей не равна.
  bool get isStuck {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final value = cells[r][c];
        if (value == 0) return false;
        if (c + 1 < size && cells[r][c + 1] == value) return false;
        if (r + 1 < size && cells[r + 1][c] == value) return false;
      }
    }
    return true;
  }

  /// Сжатие одной линии по направлению движения: нули выкинуть, равных
  /// соседей слить слева направо, добить нулями до длины.
  List<int> _collapse(List<int> line) {
    final tiles = [
      for (final v in line)
        if (v != 0) v,
    ];
    final out = <int>[];
    var i = 0;
    while (i < tiles.length) {
      if (i + 1 < tiles.length && tiles[i] == tiles[i + 1]) {
        final merged = tiles[i] * 2;
        out.add(merged);
        score += merged;
        i += 2;
      } else {
        out.add(tiles[i]);
        i += 1;
      }
    }
    while (out.length < size) {
      out.add(0);
    }
    return out;
  }

  /// Линия в порядке «по направлению свайпа»: первый элемент — куда едут.
  List<int> _readLine(MoveDirection d, int index) => switch (d) {
    MoveDirection.left => [for (var c = 0; c < size; c++) cells[index][c]],
    MoveDirection.right => [
      for (var c = size - 1; c >= 0; c--) cells[index][c],
    ],
    MoveDirection.up => [for (var r = 0; r < size; r++) cells[r][index]],
    MoveDirection.down => [
      for (var r = size - 1; r >= 0; r--) cells[r][index],
    ],
  };

  void _writeLine(MoveDirection d, int index, List<int> line) {
    for (var i = 0; i < size; i++) {
      switch (d) {
        case MoveDirection.left:
          cells[index][i] = line[i];
        case MoveDirection.right:
          cells[index][size - 1 - i] = line[i];
        case MoveDirection.up:
          cells[i][index] = line[i];
        case MoveDirection.down:
          cells[size - 1 - i][index] = line[i];
      }
    }
  }

  void _spawn() {
    final empty = <(int, int)>[
      for (var r = 0; r < size; r++)
        for (var c = 0; c < size; c++)
          if (cells[r][c] == 0) (r, c),
    ];
    if (empty.isEmpty) return;
    final (r, c) = empty[_random.nextInt(empty.length)];
    cells[r][c] = _random.nextInt(10) == 0 ? 4 : 2;
  }

  bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
