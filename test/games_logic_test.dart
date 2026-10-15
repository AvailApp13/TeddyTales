import 'package:flutter_test/flutter_test.dart';
import 'package:teddy_tales/games/board_2048.dart';
import 'package:teddy_tales/games/pairs_board.dart';
import 'package:teddy_tales/games/sliding_board.dart';

void main() {
  group('Board2048', () {
    test('слияние пары и счёт', () {
      final board = Board2048.empty(seed: 1);
      board.cells[0].setAll(0, [2, 2, 0, 0]);
      board.move(MoveDirection.left);
      expect(board.cells[0][0], 4);
      expect(board.score, 4);
    });

    test('плитка сливается не больше одного раза за ход', () {
      final board = Board2048.empty(seed: 1);
      board.cells[0].setAll(0, [2, 2, 4, 0]);
      board.move(MoveDirection.left);
      // Наивная реализация сложила бы 2+2=4 и тут же 4+4=8.
      expect(board.cells[0].sublist(0, 2), [4, 4]);
    });

    test('четвёрка равных даёт две пары, а не восьмёрку', () {
      final board = Board2048.empty(seed: 1);
      board.cells[2].setAll(0, [4, 4, 4, 4]);
      board.move(MoveDirection.right);
      expect(board.cells[2][3], 8);
      expect(board.cells[2][2], 8);
      expect(board.score, 16);
    });

    test('ход без изменений не создаёт новую плитку', () {
      final board = Board2048.empty(seed: 1);
      board.cells[0][0] = 2;
      expect(board.move(MoveDirection.left), isFalse);
      final tiles = board.cells.expand((r) => r).where((v) => v != 0);
      expect(tiles.length, 1);
    });

    test('вертикальный сдвиг работает по колонкам', () {
      final board = Board2048.empty(seed: 1);
      board.cells[0][1] = 2;
      board.cells[3][1] = 2;
      board.move(MoveDirection.down);
      expect(board.cells[3][1], 4);
    });

    test('isStuck видит и заполненность, и возможные слияния', () {
      final board = Board2048.empty(seed: 1);
      var value = 2;
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          board.cells[r][c] = value;
          value += 2; // все разные — тупик
        }
      }
      expect(board.isStuck, isTrue);
      board.cells[0][1] = board.cells[0][0]; // появилась пара — уже не тупик
      expect(board.isStuck, isFalse);
    });
  });

  group('SlidingBoard', () {
    // Классический критерий решаемости пятнашек: при нечётной стороне поле
    // решаемо, когда число инверсий чётно; при чётной — когда чётность
    // инверсий противоположна чётности ряда пустой клетки снизу.
    bool solvable(SlidingBoard board) {
      final n = board.size;
      final blankValue = n * n - 1;
      var inversions = 0;
      final flat = board.tiles.where((t) => t != blankValue).toList();
      for (var i = 0; i < flat.length; i++) {
        for (var j = i + 1; j < flat.length; j++) {
          if (flat[i] > flat[j]) inversions++;
        }
      }
      if (n.isOdd) return inversions.isEven;
      final blankRowFromBottom = n - board.tiles.indexOf(blankValue) ~/ n;
      return inversions.isEven == blankRowFromBottom.isOdd;
    }

    test('перемешивание ходами даёт решаемое и несобранное поле', () {
      for (final side in [3, 4]) {
        for (var seed = 0; seed < 50; seed++) {
          final board = SlidingBoard(side, seed: seed, shuffleMoves: 80);
          expect(board.isSolved, isFalse, reason: 'seed $seed, side $side');
          expect(solvable(board), isTrue, reason: 'seed $seed, side $side');
          // Перестановка не потеряла ни одной плитки.
          expect(board.tiles.toSet().length, side * side);
        }
      }
    });

    test('ход возможен только соседом пустой клетки', () {
      final board = SlidingBoard(3);
      // Собрано: пустая — позиция 8, соседи — 5 и 7.
      expect(board.moveFrom(0), isFalse);
      expect(board.moveFrom(5), isTrue);
    });
  });

  group('PairsBoard', () {
    test('полный цикл: промах, пара, решение', () {
      final board = PairsBoard(['a', 'b'], seed: 3);
      final cards = board.cards;
      final firstA = cards.indexOf('a');
      final secondA = cards.lastIndexOf('a');
      final firstB = cards.indexOf('b');
      final secondB = cards.lastIndexOf('b');

      expect(board.flip(firstA), PairsFlip.first);
      expect(board.flip(firstB), PairsFlip.miss);
      expect(board.moves, 1);

      expect(board.flip(firstA), PairsFlip.first);
      expect(board.flip(secondA), PairsFlip.matched);
      expect(board.isMatched(firstA), isTrue);

      expect(board.flip(firstB), PairsFlip.first);
      expect(board.flip(secondB), PairsFlip.matched);
      expect(board.isSolved, isTrue);
      expect(board.moves, 3);
    });

    test('тап по собранной и по открытой карточке игнорируется', () {
      final board = PairsBoard(['a'], seed: 1);
      expect(board.flip(0), PairsFlip.first);
      expect(board.flip(0), PairsFlip.ignored);
      expect(board.flip(1), PairsFlip.matched);
      expect(board.flip(1), PairsFlip.ignored);
    });
  });
}
