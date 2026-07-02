import '../models.dart';

/// Number of tableau columns dealt on the board.
const int kSolitaireColumns = 4;

/// Cards per column (4 columns x 4 = 16 words per level).
const int kSolitaireCardsPerColumn = 4;

/// A single category pile the player builds by dropping matching words.
///
/// A foundation starts empty (no [categoryId]). The first word dropped on it
/// "claims" the category and reveals its name in the UI. It is [isComplete]
/// once all four words of that category are stacked on it.
class Foundation {
  Foundation();

  String? categoryId;
  final List<WordItem> cards = [];

  bool get isEmpty => categoryId == null;

  bool get isComplete => cards.length == kSolitaireCardsPerColumn;

  void _reset() {
    categoryId = null;
    cards.clear();
  }
}

/// Outcome of attempting to place a card on a foundation.
enum PlaceOutcome {
  /// The card claimed an empty foundation and revealed a new category.
  started,

  /// The card matched an already-claimed foundation.
  matched,

  /// The card matched and finished the group (4th card).
  completed,

  /// The move was illegal; board state is unchanged.
  rejected,
}

/// Result returned by [SolitaireEngine.tryPlace].
class PlaceResult {
  const PlaceResult(this.outcome, {this.foundationIndex});

  final PlaceOutcome outcome;
  final int? foundationIndex;

  bool get accepted => outcome != PlaceOutcome.rejected;
}

/// A suggested legal move used by the hint feature.
class HintPlacement {
  const HintPlacement({required this.word, required this.foundationIndex});

  final WordItem word;
  final int foundationIndex;
}

/// Records one applied placement so it can be reverted by [SolitaireEngine.undo].
class _Move {
  _Move({
    required this.columnIndex,
    required this.foundationIndex,
    required this.word,
    required this.claimedCategory,
  });

  final int columnIndex;
  final int foundationIndex;
  final WordItem word;

  /// Whether this move claimed a previously-empty foundation (so undo un-claims it).
  final bool claimedCategory;
}

/// Pure game logic for the word-solitaire board. No Flutter dependencies, so it
/// can be unit-tested in isolation.
class SolitaireEngine {
  SolitaireEngine(this.level) {
    deal();
  }

  final Level level;

  final List<List<WordItem>> columns = [];
  final List<Foundation> foundations =
      List.generate(kSolitaireColumns, (_) => Foundation());
  final List<_Move> _history = [];

  int _moves = 0;
  int get moves => _moves;

  int _mistakes = 0;
  int get mistakes => _mistakes;

  int _combo = 0;

  /// Current run of consecutive correct placements (resets on a mistake).
  int get combo => _combo;

  int _bestCombo = 0;
  int get bestCombo => _bestCombo;

  int _streak = 0;

  /// Consecutive completed categories (resets on a mistake).
  int get streak => _streak;

  /// Star rating (1..3) based on how cleanly the level was solved.
  int get stars {
    if (_mistakes == 0) return 3;
    if (_mistakes <= 2) return 2;
    return 1;
  }

  /// Number of fully-completed category piles (0..4).
  int get completedCount => foundations.where((f) => f.isComplete).length;

  bool get isWon =>
      foundations.every((f) => f.isComplete) &&
      columns.every((c) => c.isEmpty);

  bool get canUndo => _history.isNotEmpty;

  /// Deals the level's 16 words into [kSolitaireColumns] columns, resetting state.
  void deal() {
    final words = level.shuffledWords();
    columns
      ..clear()
      ..addAll(List.generate(kSolitaireColumns, (_) => <WordItem>[]));
    for (var i = 0; i < words.length; i++) {
      columns[i % kSolitaireColumns].add(words[i]);
    }
    for (final f in foundations) {
      f._reset();
    }
    _history.clear();
    _moves = 0;
    _mistakes = 0;
    _combo = 0;
    _bestCombo = 0;
    _streak = 0;
  }

  /// The playable card at the front of each column (null for empty columns),
  /// indexed by column.
  List<WordItem?> get frontCards =>
      columns.map((c) => c.isEmpty ? null : c.last).toList();

  /// Index of the column whose front card is [word], or -1 if it is not a front card.
  int columnIndexOfFront(WordItem word) {
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      if (c.isNotEmpty && c.last.id == word.id) return i;
    }
    return -1;
  }

  /// Whether [word] (a front card) may legally be placed on [foundationIndex].
  bool canPlace(WordItem word, int foundationIndex) {
    if (foundationIndex < 0 || foundationIndex >= foundations.length) {
      return false;
    }
    if (columnIndexOfFront(word) == -1) return false;
    final foundation = foundations[foundationIndex];
    if (foundation.isComplete) return false;
    if (foundation.isEmpty) {
      // Cannot start a new group for a category already claimed elsewhere.
      return !_categoryClaimedElsewhere(word.categoryId, foundationIndex);
    }
    return foundation.categoryId == word.categoryId;
  }

  bool _categoryClaimedElsewhere(String categoryId, int exceptIndex) {
    for (var i = 0; i < foundations.length; i++) {
      if (i == exceptIndex) continue;
      if (foundations[i].categoryId == categoryId) return true;
    }
    return false;
  }

  /// Attempts to move the front card [word] onto foundation [foundationIndex].
  /// Returns [PlaceOutcome.rejected] without mutating state if the move is illegal.
  PlaceResult tryPlace(WordItem word, int foundationIndex) {
    if (!canPlace(word, foundationIndex)) {
      _mistakes++;
      _combo = 0;
      return const PlaceResult(PlaceOutcome.rejected);
    }

    final columnIndex = columnIndexOfFront(word);
    final foundation = foundations[foundationIndex];
    final claimed = foundation.isEmpty;

    if (claimed) foundation.categoryId = word.categoryId;
    foundation.cards.add(word);
    columns[columnIndex].removeLast();
    _history.add(_Move(
      columnIndex: columnIndex,
      foundationIndex: foundationIndex,
      word: word,
      claimedCategory: claimed,
    ));
    _moves++;
    _combo++;
    if (_combo > _bestCombo) _bestCombo = _combo;

    final outcome = foundation.isComplete
        ? PlaceOutcome.completed
        : (claimed ? PlaceOutcome.started : PlaceOutcome.matched);
    if (outcome == PlaceOutcome.completed) _streak++;
    return PlaceResult(outcome, foundationIndex: foundationIndex);
  }

  /// Reverts the most recent placement. Returns false if there is nothing to undo.
  bool undo() {
    if (_history.isEmpty) return false;
    final move = _history.removeLast();
    final foundation = foundations[move.foundationIndex];
    foundation.cards.removeLast();
    if (move.claimedCategory) foundation.categoryId = null;
    columns[move.columnIndex].add(move.word);
    if (_moves > 0) _moves--;
    return true;
  }

  /// Returns a legal move to suggest as a hint, preferring a card that matches an
  /// already-claimed foundation before one that would start a new group. Returns
  /// null if no legal move exists (e.g. the board is solved).
  HintPlacement? suggestMove() {
    HintPlacement? startingMove;
    for (final word in frontCards) {
      if (word == null) continue;
      for (var i = 0; i < foundations.length; i++) {
        if (!canPlace(word, i)) continue;
        if (!foundations[i].isEmpty) {
          return HintPlacement(word: word, foundationIndex: i);
        }
        startingMove ??= HintPlacement(word: word, foundationIndex: i);
      }
    }
    return startingMove;
  }
}
