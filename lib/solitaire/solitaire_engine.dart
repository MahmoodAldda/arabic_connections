import '../models.dart';

/// Number of tableau columns on the board.
const int kTableauColumns = 4;

/// Cards per completed category pile (also words-per-category).
const int kCardsPerCategory = 4;

/// Total playing cards in a level (4 categories x 4 words).
const int kCardsTotal = 16;

/// Classic staircase deal: column i receives (i + 1) cards. 1+2+3+4 = 10 cards
/// in the tableau; the remaining 6 form the face-down stock.
const List<int> _dealCounts = [1, 2, 3, 4];

/// A card sitting in a tableau column. Only the top card of a column is ever
/// [faceUp]; the ones beneath are face-down until revealed.
class TableauCard {
  TableauCard(this.word, {required this.faceUp});

  final WordItem word;
  bool faceUp;
}

/// Where a played card came from.
enum CardSource { tableau, waste }

/// A single category pile the player builds by moving matching words onto it.
class Foundation {
  Foundation();

  String? categoryId;
  final List<WordItem> cards = [];

  bool get isEmpty => categoryId == null;
  bool get isComplete => cards.length == kCardsPerCategory;

  void _reset() {
    categoryId = null;
    cards.clear();
  }
}

/// Outcome of attempting to place a card on a foundation.
enum PlaceOutcome { started, matched, completed, rejected }

/// Result returned by the play methods.
class PlaceResult {
  const PlaceResult(this.outcome, {this.foundationIndex, this.revealedWord});

  final PlaceOutcome outcome;
  final int? foundationIndex;

  /// The word that was flipped face-up as a result of this move, if any.
  final WordItem? revealedWord;

  bool get accepted => outcome != PlaceOutcome.rejected;
}

/// A suggested legal move used by the hint feature.
class HintMove {
  const HintMove({
    required this.source,
    required this.columnIndex,
    required this.word,
    required this.foundationIndex,
  });

  final CardSource source;

  /// Tableau column index (ignored when [source] is [CardSource.waste]).
  final int columnIndex;
  final WordItem word;
  final int foundationIndex;
}

/// Records one reversible action for [SolitaireEngine.undo].
class _Move {
  _Move.place({
    required this.source,
    required this.columnIndex,
    required this.foundationIndex,
    required this.word,
    required this.claimedCategory,
    required this.revealed,
  })  : type = _MoveType.place,
        count = 0;

  _Move.draw()
      : type = _MoveType.draw,
        source = null,
        columnIndex = -1,
        foundationIndex = -1,
        word = null,
        claimedCategory = false,
        revealed = false,
        count = 0;

  _Move.recycle(this.count)
      : type = _MoveType.recycle,
        source = null,
        columnIndex = -1,
        foundationIndex = -1,
        word = null,
        claimedCategory = false,
        revealed = false;

  final _MoveType type;
  final CardSource? source;
  final int columnIndex;
  final int foundationIndex;
  final WordItem? word;
  final bool claimedCategory;
  final bool revealed;
  final int count;
}

enum _MoveType { place, draw, recycle }

/// Pure Klondike-style game logic for the word-solitaire board. No Flutter
/// dependencies, so it can be unit-tested in isolation.
///
/// Structure: a face-down [stock] you draw from into the [waste]; four tableau
/// [columns] whose top card is face-up (rest face-down until revealed); and
/// four category [foundations]. The top of the waste and the face-up top of any
/// column can be moved onto a matching foundation.
class SolitaireEngine {
  SolitaireEngine(this.level) {
    deal();
  }

  final Level level;

  final List<List<TableauCard>> columns = [];
  final List<WordItem> stock = [];
  final List<WordItem> waste = [];
  final List<Foundation> foundations =
      List.generate(kTableauColumns, (_) => Foundation());
  final List<_Move> _history = [];

  int _moves = 0;
  int get moves => _moves;

  int _mistakes = 0;
  int get mistakes => _mistakes;

  int _combo = 0;
  int get combo => _combo;

  int _bestCombo = 0;
  int get bestCombo => _bestCombo;

  int _streak = 0;
  int get streak => _streak;

  int get stars {
    if (_mistakes == 0) return 3;
    if (_mistakes <= 2) return 2;
    return 1;
  }

  int get completedCount => foundations.where((f) => f.isComplete).length;

  bool get isWon => foundations.every((f) => f.isComplete);

  bool get canUndo => _history.isNotEmpty;

  WordItem? get wasteTop => waste.isEmpty ? null : waste.last;

  int get stockCount => stock.length;

  /// The face-up top card of [col], or null if the column is empty.
  WordItem? tableauTop(int col) {
    final column = columns[col];
    if (column.isEmpty) return null;
    final top = column.last;
    return top.faceUp ? top.word : null;
  }

  /// Deals the level into the staircase tableau + stock, resetting all state.
  void deal() {
    final words = level.shuffledWords();
    columns
      ..clear()
      ..addAll(List.generate(kTableauColumns, (_) => <TableauCard>[]));
    var idx = 0;
    for (var col = 0; col < kTableauColumns; col++) {
      final count = _dealCounts[col];
      for (var r = 0; r < count; r++) {
        columns[col].add(TableauCard(words[idx++], faceUp: r == count - 1));
      }
    }
    stock
      ..clear()
      ..addAll(words.sublist(idx));
    waste.clear();
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

  bool _canPlaceWord(WordItem word, int foundationIndex) {
    if (foundationIndex < 0 || foundationIndex >= foundations.length) {
      return false;
    }
    final foundation = foundations[foundationIndex];
    if (foundation.isComplete) return false;
    if (foundation.isEmpty) {
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

  /// Whether the face-up top of [col] can be placed on [foundationIndex].
  bool canPlaceTableau(int col, int foundationIndex) {
    final word = tableauTop(col);
    return word != null && _canPlaceWord(word, foundationIndex);
  }

  /// Whether the waste top can be placed on [foundationIndex].
  bool canPlaceWaste(int foundationIndex) {
    final word = wasteTop;
    return word != null && _canPlaceWord(word, foundationIndex);
  }

  /// Whether [word] (regardless of its source) could legally go on
  /// [foundationIndex]. Used by the UI to find a card's destination slot.
  bool canPlace(WordItem word, int foundationIndex) =>
      _canPlaceWord(word, foundationIndex);

  PlaceResult _applyPlacement(
    WordItem word,
    int foundationIndex, {
    required CardSource source,
    required int columnIndex,
    required bool revealed,
  }) {
    final foundation = foundations[foundationIndex];
    final claimed = foundation.isEmpty;
    if (claimed) foundation.categoryId = word.categoryId;
    foundation.cards.add(word);
    _history.add(_Move.place(
      source: source,
      columnIndex: columnIndex,
      foundationIndex: foundationIndex,
      word: word,
      claimedCategory: claimed,
      revealed: revealed,
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

  /// Moves the face-up top of [col] onto [foundationIndex], flipping the newly
  /// exposed card if there is one.
  PlaceResult playFromTableau(int col, int foundationIndex) {
    if (!canPlaceTableau(col, foundationIndex)) {
      _mistakes++;
      _combo = 0;
      return const PlaceResult(PlaceOutcome.rejected);
    }
    final card = columns[col].removeLast();
    var revealed = false;
    WordItem? revealedWord;
    if (columns[col].isNotEmpty && !columns[col].last.faceUp) {
      columns[col].last.faceUp = true;
      revealed = true;
      revealedWord = columns[col].last.word;
    }
    final result = _applyPlacement(
      card.word,
      foundationIndex,
      source: CardSource.tableau,
      columnIndex: col,
      revealed: revealed,
    );
    return PlaceResult(result.outcome,
        foundationIndex: result.foundationIndex, revealedWord: revealedWord);
  }

  /// Moves the waste top onto [foundationIndex].
  PlaceResult playFromWaste(int foundationIndex) {
    if (!canPlaceWaste(foundationIndex)) {
      _mistakes++;
      _combo = 0;
      return const PlaceResult(PlaceOutcome.rejected);
    }
    final word = waste.removeLast();
    return _applyPlacement(
      word,
      foundationIndex,
      source: CardSource.waste,
      columnIndex: -1,
      revealed: false,
    );
  }

  /// Flips the next stock card onto the waste. When the stock is empty, recycles
  /// the waste back into the stock. Returns false only if both are empty.
  bool drawFromStock() {
    if (stock.isNotEmpty) {
      waste.add(stock.removeLast());
      _history.add(_Move.draw());
      return true;
    }
    if (waste.isNotEmpty) {
      final count = waste.length;
      stock.addAll(waste.reversed);
      waste.clear();
      _history.add(_Move.recycle(count));
      return true;
    }
    return false;
  }

  /// Reverts the most recent action. Returns false if there is nothing to undo.
  bool undo() {
    if (_history.isEmpty) return false;
    final move = _history.removeLast();
    switch (move.type) {
      case _MoveType.place:
        final foundation = foundations[move.foundationIndex];
        foundation.cards.removeLast();
        if (move.claimedCategory) foundation.categoryId = null;
        if (move.source == CardSource.waste) {
          waste.add(move.word!);
        } else {
          if (move.revealed && columns[move.columnIndex].isNotEmpty) {
            columns[move.columnIndex].last.faceUp = false;
          }
          columns[move.columnIndex].add(TableauCard(move.word!, faceUp: true));
        }
        if (_moves > 0) _moves--;
      case _MoveType.draw:
        if (waste.isNotEmpty) stock.add(waste.removeLast());
      case _MoveType.recycle:
        final moved = stock.reversed.take(move.count).toList();
        stock.removeRange(stock.length - move.count, stock.length);
        waste.addAll(moved);
    }
    return true;
  }

  /// Suggests a legal move, preferring the waste top, then tableau tops that
  /// match an already-claimed foundation, then any legal placement. Returns
  /// null if nothing can currently be placed.
  HintMove? suggestMove() {
    HintMove? starting;

    for (var fi = 0; fi < foundations.length; fi++) {
      final w = wasteTop;
      if (w != null && canPlaceWaste(fi)) {
        if (!foundations[fi].isEmpty) {
          return HintMove(
              source: CardSource.waste,
              columnIndex: -1,
              word: w,
              foundationIndex: fi);
        }
        starting ??= HintMove(
            source: CardSource.waste,
            columnIndex: -1,
            word: w,
            foundationIndex: fi);
      }
    }

    for (var col = 0; col < columns.length; col++) {
      final w = tableauTop(col);
      if (w == null) continue;
      for (var fi = 0; fi < foundations.length; fi++) {
        if (!canPlaceTableau(col, fi)) continue;
        if (!foundations[fi].isEmpty) {
          return HintMove(
              source: CardSource.tableau,
              columnIndex: col,
              word: w,
              foundationIndex: fi);
        }
        starting ??= HintMove(
            source: CardSource.tableau,
            columnIndex: col,
            word: w,
            foundationIndex: fi);
      }
    }

    return starting;
  }
}
