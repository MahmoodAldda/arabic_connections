import 'dart:math';

import '../models.dart';

/// Provides category and word hints for the active level.
class HintService {
  final _random = Random();

  /// Reveals an unsolved category name.
  HintResult? categoryHint(Level level, Set<String> solvedCategoryIds) {
    final unsolved = level.categories
        .where((c) => !solvedCategoryIds.contains(c.id))
        .toList();
    if (unsolved.isEmpty) return null;
    final category = unsolved[_random.nextInt(unsolved.length)];
    return HintResult(
      type: HintType.category,
      categoryId: category.id,
      categoryName: category.name,
    );
  }

  /// Highlights one word from an unsolved category.
  HintResult? wordHint(
    Level level,
    Set<String> solvedCategoryIds,
    Set<String> alreadyHintedWordIds,
    List<WordItem> remainingWords,
  ) {
    final unsolvedCategoryIds = level.categories
        .map((c) => c.id)
        .where((id) => !solvedCategoryIds.contains(id))
        .toSet();

    final candidates = remainingWords.where(
      (w) =>
          unsolvedCategoryIds.contains(w.categoryId) &&
          !alreadyHintedWordIds.contains(w.id),
    ).toList();

    if (candidates.isEmpty) return null;

    final word = candidates[_random.nextInt(candidates.length)];
    final category = level.categoryById(word.categoryId);
    return HintResult(
      type: HintType.word,
      categoryId: word.categoryId,
      wordId: word.id,
      wordText: word.text,
      categoryName: category.name,
    );
  }
}
