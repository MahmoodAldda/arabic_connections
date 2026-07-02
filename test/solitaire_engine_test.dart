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

/// Plays greedily: place each front card on its matching claimed foundation,
/// otherwise on an empty foundation. Returns when solved or stuck.
void _greedySolve(SolitaireEngine engine) {
  var guard = 0;
  while (!engine.isWon && guard++ < 100) {
    final move = engine.suggestMove();
    if (move == null) break;
    engine.tryPlace(move.word, move.foundationIndex);
  }
}

void main() {
  group('SolitaireEngine deal', () {
    test('deals 4 columns of 4 using all 16 words', () {
      final engine = SolitaireEngine(_buildLevel());
      expect(engine.columns.length, kSolitaireColumns);
      for (final column in engine.columns) {
        expect(column.length, kSolitaireCardsPerColumn);
      }
      final ids = engine.columns.expand((c) => c).map((w) => w.id).toSet();
      expect(ids.length, 16);
      expect(engine.moves, 0);
      expect(engine.isWon, isFalse);
      expect(engine.completedCount, 0);
    });
  });

  group('SolitaireEngine placement', () {
    test('placing a front card on an empty foundation claims its category', () {
      final engine = SolitaireEngine(_buildLevel());
      final word = engine.frontCards[0]!;
      final result = engine.tryPlace(word, 0);

      expect(result.outcome, PlaceOutcome.started);
      expect(engine.foundations[0].categoryId, word.categoryId);
      expect(engine.foundations[0].cards.single.id, word.id);
      expect(engine.moves, 1);
      expect(engine.columns[0].length, kSolitaireCardsPerColumn - 1);
    });

    test('a non-front card cannot be placed', () {
      final engine = SolitaireEngine(_buildLevel());
      final buriedCard = engine.columns[0].first; // behind the front card
      expect(engine.canPlace(buriedCard, 0), isFalse);
      final result = engine.tryPlace(buriedCard, 0);
      expect(result.outcome, PlaceOutcome.rejected);
      expect(engine.moves, 0);
    });

    test('cannot claim a category already claimed by another foundation', () {
      final engine = SolitaireEngine(_buildLevel());
      final word = engine.frontCards[0]!;
      // Simulate the category being claimed on foundation 0.
      engine.foundations[0].categoryId = word.categoryId;
      expect(engine.canPlace(word, 1), isFalse); // claimed elsewhere
      expect(engine.canPlace(word, 0), isTrue); // matches its own foundation
    });

    test('greedy play reaches a win in exactly 16 moves', () {
      final engine = SolitaireEngine(_buildLevel());
      _greedySolve(engine);
      expect(engine.isWon, isTrue);
      expect(engine.completedCount, 4);
      expect(engine.moves, 16);
      expect(engine.suggestMove(), isNull);
    });
  });

  group('SolitaireEngine undo', () {
    test('undo reverts the last placement', () {
      final engine = SolitaireEngine(_buildLevel());
      final word = engine.frontCards[0]!;
      engine.tryPlace(word, 0);

      expect(engine.canUndo, isTrue);
      final undone = engine.undo();

      expect(undone, isTrue);
      expect(engine.moves, 0);
      expect(engine.foundations[0].isEmpty, isTrue);
      expect(engine.columns[0].last.id, word.id);
      expect(engine.canUndo, isFalse);
    });

    test('undo returns false when there is nothing to undo', () {
      final engine = SolitaireEngine(_buildLevel());
      expect(engine.undo(), isFalse);
    });
  });
}
