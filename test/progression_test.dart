import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arabic_connections/solitaire/progression.dart';

void main() {
  group('pickRoundLevelIndex', () {
    test('returns 0 for an empty pool', () {
      expect(
        pickRoundLevelIndex(categoryCounts: const [], skill: 0, round: 1),
        0,
      );
    });

    test('low skill favours the smallest (3-category) boards', () {
      final counts = [3, 4, 5, 6];
      final idx = pickRoundLevelIndex(
        categoryCounts: counts,
        skill: 0,
        round: 1,
        rng: Random(0),
      );
      expect(counts[idx], 3);
    });

    test('high skill favours the largest (6-category) boards', () {
      final counts = [3, 4, 5, 6];
      final idx = pickRoundLevelIndex(
        categoryCounts: counts,
        skill: 100,
        round: 1,
        rng: Random(0),
      );
      expect(counts[idx], 6);
    });

    test('picks the nearest available count when the target is missing', () {
      // Target at skill 0 is 3, but only 5- and 6-category boards exist.
      final counts = [5, 6];
      final idx = pickRoundLevelIndex(
        categoryCounts: counts,
        skill: 0,
        round: 1,
        rng: Random(0),
      );
      expect(counts[idx], 5);
    });

    test('mid skill targets a middle size', () {
      final counts = [3, 4, 5, 6];
      // skill 50 -> target = 3 + 2 = 5.
      final idx = pickRoundLevelIndex(
        categoryCounts: counts,
        skill: 50,
        round: 7,
        rng: Random(0),
      );
      expect(counts[idx], 5);
    });

    test('always returns a valid index', () {
      final counts = [3, 3, 4, 4, 5];
      for (var round = 1; round <= 20; round++) {
        final idx = pickRoundLevelIndex(
          categoryCounts: counts,
          skill: round * 5.0,
          round: round,
        );
        expect(idx, inInclusiveRange(0, counts.length - 1));
      }
    });
  });
}
