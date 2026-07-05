import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arabic_connections/models.dart';
import 'package:arabic_connections/solitaire/difficulty.dart';
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
      number: number, title: 'Test', categories: categories, words: words);
}

RoundResult _result({
  int timeSec = 60,
  int mistakes = 0,
  int hintsUsed = 0,
  int bestCombo = 4,
  int categoryCount = 4,
  bool won = true,
}) =>
    RoundResult(
      timeSec: timeSec,
      mistakes: mistakes,
      hintsUsed: hintsUsed,
      bestCombo: bestCombo,
      categoryCount: categoryCount,
      won: won,
    );

void main() {
  const director = DifficultyDirector();

  group('RoundSpec.forLevelNumber (backward compatible tiers)', () {
    test('levels 1-2 are shallow with accessible category cards', () {
      for (final n in [1, 2]) {
        final s = RoundSpec.forLevelNumber(n);
        expect(s.columnDepth, 2);
        expect(s.buryCategoryCards, isFalse);
        expect(s.freeHints, 2);
      }
    });

    test('levels 3+ deepen and bury category cards', () {
      for (final n in [3, 5, 8]) {
        final s = RoundSpec.forLevelNumber(n);
        expect(s.columnDepth, 3);
        expect(s.buryCategoryCards, isTrue);
      }
      expect(RoundSpec.forLevelNumber(6).difficulty,
          greaterThan(RoundSpec.forLevelNumber(1).difficulty));
    });
  });

  group('specFor scales with skill', () {
    test('a beginner gets an easy, generous board', () {
      final s = director.specFor(0, categoryCount: 4);
      expect(s.columnDepth, 2);
      expect(s.buryCategoryCards, isFalse);
      expect(s.freeHints, 2);
      expect(s.difficulty, lessThan(0.2));
    });

    test('a mid player gets deeper, buried boards with fewer free hints', () {
      final s = director.specFor(50, categoryCount: 4);
      expect(s.columnDepth, 3);
      expect(s.buryCategoryCards, isTrue);
      expect(s.freeHints, 1);
    });

    test('an expert gets the deepest boards and no free hints', () {
      final s = director.specFor(90, categoryCount: 4);
      expect(s.columnDepth, 4);
      expect(s.buryCategoryCards, isTrue);
      expect(s.freeHints, 0);
      expect(s.difficulty, greaterThan(0.6));
    });

    test('difficulty is monotonic in skill', () {
      final low = director.specFor(10, categoryCount: 4).difficulty;
      final mid = director.specFor(50, categoryCount: 4).difficulty;
      final high = director.specFor(95, categoryCount: 4).difficulty;
      expect(low, lessThan(mid));
      expect(mid, lessThan(high));
    });
  });

  group('estimateParTime', () {
    test('tightens as difficulty rises and grows with categories', () {
      expect(estimateParTime(4, 0.9), lessThan(estimateParTime(4, 0.1)));
      expect(estimateParTime(6, 0.5), greaterThan(estimateParTime(4, 0.5)));
    });
  });

  group('roundScore', () {
    test('a fast, clean, unaided round scores high', () {
      final spec = director.specFor(50, categoryCount: 4);
      final score = director.roundScore(
        _result(timeSec: 30, mistakes: 0, hintsUsed: 0, bestCombo: 4),
        spec,
      );
      expect(score, greaterThan(0.8));
    });

    test('a slow, messy, hint-reliant round scores low', () {
      final spec = director.specFor(50, categoryCount: 4);
      final score = director.roundScore(
        _result(timeSec: 600, mistakes: 6, hintsUsed: 6, bestCombo: 0),
        spec,
      );
      expect(score, lessThan(0.4));
    });
  });

  group('updatedSkill', () {
    test('a strong win raises skill', () {
      final spec = director.specFor(30, categoryCount: 4);
      final next = director.updatedSkill(
          30, _result(timeSec: 25, mistakes: 0, hintsUsed: 0), spec);
      expect(next, greaterThan(30));
    });

    test('a lost/abandoned round eases difficulty gently', () {
      final spec = director.specFor(40, categoryCount: 4);
      final next = director.updatedSkill(40, _result(won: false), spec);
      expect(next, closeTo(37, 0.001));
    });

    test('stays within [0, 100]', () {
      final spec = director.specFor(100, categoryCount: 4);
      final high = director.updatedSkill(
          100, _result(timeSec: 5, mistakes: 0, hintsUsed: 0), spec);
      expect(high, lessThanOrEqualTo(100));
      final low = director.updatedSkill(0, _result(won: false), spec);
      expect(low, greaterThanOrEqualTo(0));
    });

    test('repeated strong wins ramp a beginner up over time', () {
      var skill = DifficultyDirector.startingSkill;
      for (var i = 0; i < 12; i++) {
        final spec = director.specFor(skill, categoryCount: 4);
        skill = director.updatedSkill(
            skill, _result(timeSec: 20, mistakes: 0, hintsUsed: 0), spec);
      }
      expect(skill, greaterThan(50));
    });
  });

  group('engine honours the spec', () {
    test('shallow spec keeps columns short and stock stocked', () {
      const spec = RoundSpec(
        columnDepth: 2,
        buryCategoryCards: false,
        freeHints: 2,
        parTimeSec: 100,
        difficulty: 0.1,
      );
      final e = SolitaireEngine(_buildLevel(4), random: Random(1), spec: spec);
      for (final col in e.columns) {
        expect(col.length, lessThanOrEqualTo(2));
      }
      expect(e.stockCount, greaterThanOrEqualTo(e.categoryCount));
      expect(e.spec.columnDepth, 2);
    });

    test('deep spec still deals a solvable board', () {
      const spec = RoundSpec(
        columnDepth: 4,
        buryCategoryCards: true,
        freeHints: 0,
        parTimeSec: 80,
        difficulty: 0.9,
      );
      final e = SolitaireEngine(_buildLevel(4), random: Random(7), spec: spec);
      // Greedy hint/draw loop must be able to finish it.
      var guard = 0;
      while (!e.isWon && guard++ < 1000) {
        final m = e.suggestMove();
        if (m != null) {
          e.playToFoundation(m.source, m.columnIndex, m.foundationIndex);
        } else if (!e.drawFromStock()) {
          break;
        }
      }
      expect(e.isWon, isTrue);
    });
  });
}
