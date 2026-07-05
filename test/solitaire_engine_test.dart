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

/// A word card for the first word of category [c] in [e]'s level.
GameCard _wordOf(SolitaireEngine e, String categoryId) =>
    GameCard.word(e.level.words.firstWhere((w) => w.categoryId == categoryId));

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
    test('foundations start empty, generic and unlabeled; all cards dealt', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      expect(e.foundations.length, 4);
      for (final f in e.foundations) {
        expect(f.unlocked, isFalse);
        expect(f.categoryId, isNull);
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
    test('a category card locks an empty foundation to its category', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      // Early levels place a category card on a column top.
      final top = e.tableauTop(0)!;
      expect(top.isCategory, isTrue);
      // Any empty foundation accepts any (unclaimed) category card.
      expect(e.canPlaceOnFoundation(top, 0), isTrue);

      final result = e.playToFoundation(CardSource.tableau, 0, 0);
      expect(result.outcome, PlaceOutcome.unlocked);
      expect(e.foundations[0].unlocked, isTrue);
      expect(e.foundations[0].categoryId, top.categoryId);
      expect(e.foundations[0].wordCount, 0);
    });

    test('the same category cannot be claimed by two foundations', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final top = e.tableauTop(0)!;
      e.playToFoundation(CardSource.tableau, 0, 0);
      // A second (hypothetical) card of the same category is refused on any
      // other empty foundation.
      final dupe = GameCard.category(
          e.level.categories.firstWhere((c) => c.id == top.categoryId));
      expect(e.canPlaceOnFoundation(dupe, 1), isFalse);
    });

    test('a word card is rejected until its category is unlocked', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final top = e.tableauTop(0)!; // a category card
      final word = _wordOf(e, top.categoryId);

      // Foundation 0 is empty: it only accepts a category card.
      expect(e.canPlaceOnFoundation(word, 0), isFalse);

      e.playToFoundation(CardSource.tableau, 0, 0); // unlock foundation 0
      expect(e.canPlaceOnFoundation(word, 0), isTrue);
    });

    test('an unlocked foundation rejects a different category word', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final top = e.tableauTop(0)!;
      e.playToFoundation(CardSource.tableau, 0, 0); // locks foundation 0

      final otherCat =
          e.level.categories.firstWhere((c) => c.id != top.categoryId).id;
      final wrongWord = _wordOf(e, otherCat);
      final matchWord = _wordOf(e, top.categoryId);
      expect(e.canPlaceOnFoundation(wrongWord, 0), isFalse);
      expect(e.canPlaceOnFoundation(matchWord, 0), isTrue);
    });
  });

  group('tableau rules', () {
    test('empty columns accept only category cards', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final catCard = GameCard.category(e.level.categories.first);
      final wordCard = GameCard.word(e.level.words.first);

      e.columns[0].clear();
      expect(e.canPlaceOnColumn(catCard, 0), isTrue);
      expect(e.canPlaceOnColumn(wordCard, 0), isFalse);
    });

    test('word cards stack only on a same-category top', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final catA = e.level.categories[0].id;
      final catB = e.level.categories[1].id;
      final sameA = e.level.words.where((w) => w.categoryId == catA).toList();
      final wA1 = GameCard.word(sameA[0]);
      final wA2 = GameCard.word(sameA[1]);
      final wB = _wordOf(e, catB);
      final catCard = GameCard.category(e.level.categories[0]);

      // Column 1 tops with a face-up word of category A.
      e.columns[1]
        ..clear()
        ..add(TableauCard(wA1, faceUp: true));

      expect(e.canPlaceOnColumn(wA2, 1), isTrue, reason: 'same category');
      expect(e.canPlaceOnColumn(wB, 1), isFalse, reason: 'different category');
      expect(e.canPlaceOnColumn(catCard, 1), isFalse,
          reason: 'category cards never stack on a non-empty column');
    });

    test('a face-down top blocks stacking', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final catA = e.level.categories[0].id;
      final w = _wordOf(e, catA);
      e.columns[2]
        ..clear()
        ..add(TableauCard(GameCard.word(e.level.words.last), faceUp: false));
      expect(e.canPlaceOnColumn(w, 2), isFalse);
    });

    test('moveToColumn rejects dropping a column onto itself', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final result = e.moveToColumn(CardSource.tableau, 0, 0);
      expect(result.outcome, PlaceOutcome.rejected);
    });
  });

  group('reveal', () {
    test('removing a column top flips the card beneath', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      final col = List.generate(e.columnCount, (i) => i)
          .firstWhere((i) => e.columns[i].length >= 2, orElse: () => -1);
      if (col >= 0) {
        e.playToFoundation(CardSource.tableau, col, 0);
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
      e.playToFoundation(CardSource.tableau, 0, 0);
      expect(e.foundations[0].unlocked, isTrue);

      expect(e.undo(), isTrue);
      expect(e.foundations[0].unlocked, isFalse);
      expect(e.foundations[0].categoryId, isNull);
      expect(e.tableauTop(0)!.id, top.id);
      expect(e.moves, 0);
    });

    test('undo returns false when there is nothing to undo', () {
      final e = SolitaireEngine(_buildLevel(4), random: Random(1));
      expect(e.undo(), isFalse);
    });
  });
}
