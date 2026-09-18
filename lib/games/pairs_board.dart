/// Логика игры «Память» (найди пару) без виджетов.
///
/// Поле из карточек рубашкой вверх, за ход открываются две; совпали —
/// остаются открытыми, нет — закрываются. Считаем ходы: из них виджет
/// делает оценку прохождения.
library;

import 'dart:math';

enum PairsFlip {
  /// Открыта первая карточка хода.
  first,

  /// Открыта вторая, и это пара — обе остаются лежать лицом.
  matched,

  /// Открыта вторая, и это не пара — виджету пора показать обе и закрыть.
  miss,

  /// Тап мимо: по уже открытой или уже собранной карточке.
  ignored,
}

class PairsBoard {
  PairsBoard(List<String> symbols, {int? seed})
    : cards = [...symbols, ...symbols]..shuffle(Random(seed));

  /// Карточки: по два экземпляра каждого символа.
  final List<String> cards;

  final Set<int> _matched = {};
  int? _openIndex;
  int moves = 0;

  bool get isSolved => _matched.length == cards.length;
  bool isMatched(int index) => _matched.contains(index);
  bool isOpen(int index) => index == _openIndex || isMatched(index);
  int? get openIndex => _openIndex;

  PairsFlip flip(int index) {
    if (isMatched(index) || index == _openIndex) return PairsFlip.ignored;

    final first = _openIndex;
    if (first == null) {
      _openIndex = index;
      return PairsFlip.first;
    }

    moves++;
    _openIndex = null;
    if (cards[first] == cards[index]) {
      _matched.addAll([first, index]);
      return PairsFlip.matched;
    }
    return PairsFlip.miss;
  }
}
