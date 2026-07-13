import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arabic_connections/models.dart';

/// Guards the bundled level content: valid JSON, unique numbering, and each
/// category holding exactly four words with unique ids.
void main() {
  test('assets/levels.json is well-formed and internally consistent', () {
    final body = File('assets/levels.json').readAsStringSync();
    final levels = LevelParser.parseLevelsResponse(body);

    expect(levels, isNotEmpty);

    final numbers = <int>{};
    for (final level in levels) {
      // Unique, sensible category count.
      expect(level.categories.length, inInclusiveRange(2, 6),
          reason: 'level ${level.number} category count');
      final catIds = level.categories.map((c) => c.id).toSet();
      expect(catIds.length, level.categories.length,
          reason: 'level ${level.number} has duplicate category ids');

      // Exactly four words per category.
      expect(level.words.length, level.categories.length * 4,
          reason: 'level ${level.number} word count');
      for (final cat in level.categories) {
        final count = level.words.where((w) => w.categoryId == cat.id).length;
        expect(count, 4,
            reason: 'level ${level.number} category ${cat.id} word count');
      }

      // Word ids unique within a level; every word maps to a real category.
      final wordIds = level.words.map((w) => w.id).toSet();
      expect(wordIds.length, level.words.length,
          reason: 'level ${level.number} has duplicate word ids');
      for (final w in level.words) {
        expect(catIds.contains(w.categoryId), isTrue,
            reason: 'level ${level.number} word ${w.id} has unknown category');
      }

      expect(numbers.add(level.number), isTrue,
          reason: 'duplicate level number ${level.number}');
    }
  });
}
