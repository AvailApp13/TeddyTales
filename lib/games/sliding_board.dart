/// Логика пятнашек (сдвижной пазл) без виджетов.
///
/// Поле n×n, одна пустая клетка, соседняя с ней плитка сдвигается на её
/// место. Перемешивание — серией случайных ХОДОВ из собранного состояния,
/// а не случайной раскладкой: половина случайных раскладок пятнашек
/// нерешаема в принципе, а «перемешали ходами» решаемо всегда.
library;

import 'dart:math';

class SlidingBoard {
  SlidingBoard(this.size, {int? seed, int shuffleMoves = 0})
    : tiles = List.generate(size * size, (i) => i) {
    if (shuffleMoves > 0) shuffle(shuffleMoves, Random(seed));
  }

  /// Сторона поля: 3 — классические восемь плиток, 4 — пятнашки.
  final int size;

  /// tiles[позиция] = номер плитки; `size*size - 1` — пустая клетка.
  /// Собрано, когда каждый номер стоит на своей позиции.
  final List<int> tiles;

  int get _blank => tiles.indexOf(size * size - 1);

  bool get isSolved {
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i] != i) return false;
    }
    return true;
  }

  /// Позиции, с которых сейчас можно ходить (соседи пустой клетки).
  List<int> get movable {
    final blank = _blank;
    final row = blank ~/ size;
    final col = blank % size;
    return [
      if (row > 0) blank - size,
      if (row < size - 1) blank + size,
      if (col > 0) blank - 1,
      if (col < size - 1) blank + 1,
    ];
  }

  /// Сдвинуть плитку с позиции [from] в пустую клетку.
  /// Возвращает `false`, если ход невозможен.
  bool moveFrom(int from) {
    if (!movable.contains(from)) return false;
    final blank = _blank;
    tiles[blank] = tiles[from];
    tiles[from] = size * size - 1;
    return true;
  }

  void shuffle(int moves, Random random) {
    var previousBlank = -1;
    for (var i = 0; i < moves; i++) {
      // Не откатываем только что сделанный ход, иначе перемешивание топчется
      // на месте и поле остаётся почти собранным.
      final options = movable.where((p) => p != previousBlank).toList();
      final from = options[random.nextInt(options.length)];
      previousBlank = _blank;
      moveFrom(from);
    }
    // Перемешивание не должно случайно вернуть собранное поле.
    if (isSolved && moves > 0) shuffle(moves, random);
  }
}
