import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arabic_connections/models.dart';
import 'package:arabic_connections/solitaire/solitaire_engine.dart';

Level _buildLevel() {
  final categories = List.generate(
    4,
    (c) => Category(id: 'c$c', name: 'Category $c', color: Colors.primaries[c]),
  );
  final words = <WordItem>[];
  for (var c = 0; c < 4; c++) {
    for (var w = 0; w < 4; w++) {
      words.add(WordItem(id: 'c${c}w$w', text: 'word-$c-$w', categoryId: 'c$c'));
    }
  }
  return Level(
    number: 1,
    title: 'Test',
    categories: categories,
    words: words,
  );
}

/// Plays greedily using [SolitaireEngine.suggestMove], drawing from the stock
/// whenever nothing is currently placeable. Returns when solved or stuck.
void _greedySolve(SolitaireEngine engine) {
  var guard = 0;
  while (!engine.isWon && guard++ < 300) {
    final move = engine.suggestMove();
    if (move != null) {
      if (move.source == CardSource.waste) {
        engine.playFromWaste(move.foundationIndex);
      } else {
        engine.playFromTableau(move.columnIndex, move.foundationIndex);
      }
    } else if (!engine.drawFromStock()) {
      break;
    }
  }
}

void main() {
  group('SolitaireEngine deal', () {
    test('deals a 1-2-3-4 staircase tableau with the rest in the stock', () {
      final engine = SolitaireEngine(_buildLevel());
      expect(engine.columns.length, kTableauColumns);
      expect(engine.columns.map((c) => c.length).toList(), [1, 2, 3, 4]);
      expect(engine.stockCount, kCardsTotal - 10); // 6 left in the stock
      expect(engine.waste, isEmpty);

      // Only the top card of each column is face-up.
      for (final column in engine.columns) {
        expect(column.last.faceUp, isTrue);
        for (var i = 0; i < column.length - 1; i++) {
          expect(column[i].faceUp, isFalse);
        }
      }

      final ids = <String>{
        ...engine.columns.expand((c) => c).map((t) => t.word.id),
        ...engine.stock.map((w) => w.id),
      };
      expect(ids.length, kCardsTotal);
      expect(engine.moves, 0);
      expect(engine.isWon, isFalse);
      expect(engine.completedCount, 0);
    });
  });

  group('SolitaireEngine stock & waste', () {
    test('drawing moves the stock top onto the waste', () {
      final engine = SolitaireEngine(_buildLevel());
      final expected = engine.stock.last;
      final before = engine.stockCount;

      expect(engine.drawFromStock(), isTrue);
      expect(engine.stockCount, before - 1);
      expect(engine.wasteTop!.id, expected.id);
    });

    test('drawing an empty stock recycles the waste', () {
      final engine = SolitaireEngine(_buildLevel());
      final total = engine.stockCount;
      for (var i = 0; i < total; i++) {
        engine.drawFromStock();
      }
      expect(engine.stockCount, 0);
      expect(engine.waste.length, total);

      expect(engine.drawFromStock(), isTrue); // recycle
      expect(engine.stockCount, total);
      expect(engine.waste, isEmpty);
    });
  });

  group('SolitaireEngine placement', () {
    test('placing a tableau top on an empty foundation claims its category', () {
      final engine = SolitaireEngine(_buildLevel());
      final word = engine.tableauTop(0)!;
      final result = engine.playFromTableau(0, 0);

      expect(result.outcome, PlaceOutcome.started);
      expect(engine.foundations[0].categoryId, word.categoryId);
      expect(engine.foundations[0].cards.single.id, word.id);
      expect(engine.moves, 1);
      expect(engine.columns[0], isEmpty); // column 0 had a single card
    });

    test('removing a tableau top flips the newly exposed card', () {
      final engine = SolitaireEngine(_buildLevel());
      // Column 3 has 4 cards: 3 face-down + 1 face-up on top.
      expect(engine.columns[3][2].faceUp, isFalse);
      final foundation = engine.tableauTop(3) == null
          ? -1
          : (engine.canPlaceTableau(3, 0) ? 0 : 1);
      engine.playFromTableau(3, foundation);
      expect(engine.columns[3].length, 3);
      expect(engine.columns[3].last.faceUp, isTrue); // flipped face-up
    });

    test('a face-down card cannot be placed', () {
      final engine = SolitaireEngine(_buildLevel());
      // Column 3 bottom card is face-down and not the top.
      expect(engine.canPlaceTableau(3, 0), isTrue); // the top can
      final buried = engine.columns[3].first;
      expect(buried.faceUp, isFalse);
    });

    test('greedy play reaches a win using every card', () {
      final engine = SolitaireEngine(_buildLevel());
      _greedySolve(engine);
      expect(engine.isWon, isTrue);
      expect(engine.completedCount, 4);
      expect(engine.suggestMove(), isNull);
    });
  });

  group('SolitaireEngine scoring', () {
    test('successful placements build a combo', () {
      final engine = SolitaireEngine(_buildLevel());
      expect(engine.combo, 0);
      final m1 = engine.suggestMove()!;
      engine.playFromTableau(m1.columnIndex, m1.foundationIndex);
      expect(engine.combo, 1);
      final m2 = engine.suggestMove()!;
      if (m2.source == CardSource.waste) {
        engine.playFromWaste(m2.foundationIndex);
      } else {
        engine.playFromTableau(m2.columnIndex, m2.foundationIndex);
      }
      expect(engine.combo, 2);
      expect(engine.bestCombo, 2);
    });

    test('an illegal placement counts a mistake and resets combo', () {
      final engine = SolitaireEngine(_buildLevel());
      final m1 = engine.suggestMove()!;
      engine.playFromTableau(m1.columnIndex, m1.foundationIndex);
      expect(engine.combo, 1);
      // Force an illegal placement: find a foundation the top cannot go to.
      final badFoundation = List.generate(4, (i) => i).firstWhere(
            (i) => !engine.canPlaceTableau(3, i),
            orElse: () => -1,
          );
      if (badFoundation >= 0) {
        engine.playFromTableau(3, badFoundation);
        expect(engine.mistakes, 1);
        expect(engine.combo, 0);
      }
    });

    test('a clean solve earns 3 stars', () {
      final engine = SolitaireEngine(_buildLevel());
      _greedySolve(engine);
      expect(engine.isWon, isTrue);
      expect(engine.mistakes, 0);
      expect(engine.stars, 3);
      expect(engine.streak, 4);
    });
  });

  group('SolitaireEngine undo', () {
    test('undo reverts the last tableau placement', () {
      final engine = SolitaireEngine(_buildLevel());
      final word = engine.tableauTop(0)!;
      engine.playFromTableau(0, 0);

      expect(engine.canUndo, isTrue);
      final undone = engine.undo();

      expect(undone, isTrue);
      expect(engine.moves, 0);
      expect(engine.foundations[0].isEmpty, isTrue);
      expect(engine.columns[0].last.word.id, word.id);
      expect(engine.columns[0].last.faceUp, isTrue);
      expect(engine.canUndo, isFalse);
    });

    test('undo re-hides a card revealed by the move', () {
      final engine = SolitaireEngine(_buildLevel());
      final foundation = engine.canPlaceTableau(3, 0) ? 0 : 1;
      engine.playFromTableau(3, foundation);
      expect(engine.columns[3].last.faceUp, isTrue);
      engine.undo();
      expect(engine.columns[3].length, 4);
      // The card that was revealed is face-down again (index 2).
      expect(engine.columns[3][2].faceUp, isFalse);
    });

    test('undo returns false when there is nothing to undo', () {
      final engine = SolitaireEngine(_buildLevel());
      expect(engine.undo(), isFalse);
    });
  });
}
