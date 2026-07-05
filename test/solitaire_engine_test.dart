import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arabic_connections/models.dart';
import 'package:arabic_connections/solitaire/solitaire_engine.dart';

Level _buildLevel(int categoryCount, {int number = 1}) {
  final categories = List.generate(
    categoryCount,
    (c) => Category(
        id: 'c$c', name: 'Category $c', color: Colors.primaries[c % 18]),
  );
  final words = <WordItem>[];
  for (var c = 0; c < categoryCount; c++) {
    for (var w = 0; w < kWordsPerCategory; w++) {
      words.add(WordItem(id: 'c${c}w$w', text: 'word-$c-$w', categoryId: 'c$c'));
    }
  }
  return Level(
    number: number,
    title: 'Test',
    categories: categories,
    words: words,
  );
}

int _cardsOnBoard(SolitaireEngine e) =>
    e.columns.fold<int>(0, (a, c) => a + c.length) + e.stockCount;

/// Plays greedily (foundation moves via hints, drawing when stuck) to verify a
/// deal is winnable through the public API.
bool _greedyWin(SolitaireEngine e) {
  var guard = 0;
  while (!e.isWon && guard++ < 1000) {
    final move = e.suggestMove();
    if (move != null) {
      e.playToFoundation(move.source, move.columnIndex, move.foundationIndex);
    } else if (!e.drawFromStock()) {
      return false;
    }
  }
  return e.isWon;
}

void main() {
  group('deal', () {
    test('foundations are pre-labeled and locked; all cards dealt', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      expect(e.foundations.length, 4);
      for (final f in e.foundations) {
        expect(f.unlocked, isFalse);
        expect(f.isComplete, isFalse);
      }
      // 4 categories × (1 category card + 4 words) = 20 cards.
      expect(_cardsOnBoard(e), 20);
      for (final col in e.columns) {
        if (col.isEmpty) continue;
        expect(col.last.faceUp, isTrue);
        for (var i = 0; i < col.length - 1; i++) {
          expect(col[i].faceUp, isFalse);
        }
      }
    });

    test('supports 5 and 6 category levels', () {
      final five = SolitaireEngine(_buildLevel(5, number: 3), random: Random(2));
      expect(five.foundations.length, 5);
      expect(_cardsOnBoard(five), 25);

      final six = SolitaireEngine(_buildLevel(6, number: 6), random: Random(3));
      expect(six.foundations.length, 6);
      expect(_cardsOnBoard(six), 30);
    });
  });

  group('foundation locking', () {
    test('a category card unlocks its matching foundation', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      // Early levels place category cards on the column tops.
      final top = e.tableauTop(0)!;
      expect(top.isCategory, isTrue);
      final fi = e.foundationIndexForCategory(top.categoryId);
      expect(e.canPlaceOnFoundation(top, fi), isTrue);

      final result = e.playToFoundation(CardSource.tableau, 0, fi);
      expect(result.outcome, PlaceOutcome.unlocked);
      expect(e.foundations[fi].unlocked, isTrue);
      expect(e.foundations[fi].wordCount, 0);
    });

    test('a word card is rejected until its category is unlocked', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final wordCard = e.stock.firstWhere((c) => !c.isCategory);
      final fi = e.foundationIndexForCategory(wordCard.categoryId);
      expect(e.canPlaceOnFoundation(wordCard, fi), isFalse);

      // Unlock that category by playing its category card from whichever
      // column top holds it.
      final col = List.generate(e.columnCount, (i) => i).firstWhere(
          (i) =>
              e.tableauTop(i)?.isCategory == true &&
              e.tableauTop(i)!.categoryId == wordCard.categoryId,
          orElse: () => -1);
      if (col >= 0) {
        e.playToFoundation(CardSource.tableau, col, fi);
        expect(e.canPlaceOnFoundation(wordCard, fi), isTrue);
      }
    });

    test('a card cannot go on a foundation of another category', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final top = e.tableauTop(0)!;
      final fi = e.foundationIndexForCategory(top.categoryId);
      final wrong = (fi + 1) % e.foundations.length;
      final result = e.playToFoundation(CardSource.tableau, 0, wrong);
      expect(result.outcome, PlaceOutcome.rejected);
      expect(e.mistakes, 1);
      expect(e.combo, 0);
    });
  });

  group('empty column rule', () {
    test('empty columns accept only category cards', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final catCard = GameCard.category(e.level.categories.first);
      final wordCard = GameCard.word(e.level.words.first);

      // A non-empty column never accepts a drop.
      expect(e.canPlaceOnColumn(catCard, 0), isFalse);

      // Simulate an empty column.
      e.columns[0].clear();
      expect(e.canPlaceOnColumn(catCard, 0), isTrue);
      expect(e.canPlaceOnColumn(wordCard, 0), isFalse);
    });
  });

  group('reveal', () {
    test('removing a column top flips the card beneath', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      // Depth-2 columns on early levels: top category card over a face-down.
      final col = List.generate(e.columnCount, (i) => i)
          .firstWhere((i) => e.columns[i].length >= 2, orElse: () => -1);
      if (col >= 0) {
        final top = e.tableauTop(col)!;
        final fi = e.foundationIndexForCategory(top.categoryId);
        e.playToFoundation(CardSource.tableau, col, fi);
        expect(e.columns[col].last.faceUp, isTrue);
      }
    });
  });

  group('solvability', () {
    test('every dealt level is greedily winnable (4, 5, 6 categories)', () {
      for (final cfg in [(4, 1), (4, 2), (5, 3), (5, 4), (6, 5), (6, 8)]) {
        for (var seed = 0; seed < 8; seed++) {
          final e = SolitaireEngine(
            _buildLevel(cfg.$1, number: cfg.$2),
            random: Random(seed),
          );
          expect(_greedyWin(e), isTrue,
              reason: 'unsolvable deal: cats=${cfg.$1} seed=$seed');
        }
      }
    });

    test('a clean solve earns 3 stars', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      expect(_greedyWin(e), isTrue);
      expect(e.mistakes, 0);
      expect(e.stars, 3);
      expect(e.streak, 4);
    });
  });

  group('scoring & undo', () {
    test('successful placements build a combo', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final m1 = e.suggestMove()!;
      e.playToFoundation(m1.source, m1.columnIndex, m1.foundationIndex);
      expect(e.combo, 1);
      final m2 = e.suggestMove()!;
      e.playToFoundation(m2.source, m2.columnIndex, m2.foundationIndex);
      expect(e.combo, 2);
      expect(e.bestCombo, 2);
    });

    test('undo reverts an unlock and re-locks the foundation', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final top = e.tableauTop(0)!;
      final fi = e.foundationIndexForCategory(top.categoryId);
      e.playToFoundation(CardSource.tableau, 0, fi);
      expect(e.foundations[fi].unlocked, isTrue);

      expect(e.undo(), isTrue);
      expect(e.foundations[fi].unlocked, isFalse);
      expect(e.tableauTop(0)!.id, top.id);
      expect(e.moves, 0);
    });

    test('undo returns false when there is nothing to undo', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      expect(e.undo(), isFalse);
    });
  });
}
