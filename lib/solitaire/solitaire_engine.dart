import 'dart:math';

import '../models.dart';
import 'difficulty.dart';

/// Words that make up one category (also the number a foundation needs after
/// its category card is placed).
const int kWordsPerCategory = 4;

/// A single playing card: either a special **category card** (which unlocks a
/// foundation) or a normal **word card**.
class GameCard {
  GameCard.word(WordItem this.word)
      : isCategory = false,
        id = word.id,
        categoryId = word.categoryId,
        label = word.text;

  GameCard.category(Category category)
      : isCategory = true,
        word = null,
        id = 'cat_${category.id}',
        categoryId = category.id,
        label = category.name;

  final WordItem? word;
  final bool isCategory;
  final String id;
  final String categoryId;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GameCard && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// A card in a tableau column. Only the top card of a column is ever [faceUp].
class TableauCard {
  TableauCard(this.card, {required this.faceUp});

  final GameCard card;
  bool faceUp;
}

/// Where a played card came from.
enum CardSource { tableau, waste }

/// A generic foundation pile. Starts empty and unlabeled; the first card placed
/// must be a **category card**, which locks the pile to that category forever.
/// It then accepts only word cards of the same category.
class Foundation {
  /// The category card (index 0, once unlocked) followed by placed word cards.
  final List<GameCard> pile = [];

  /// Null until a category card is placed, then the locked category id.
  String? get categoryId => pile.isEmpty ? null : pile.first.categoryId;

  bool get unlocked => pile.isNotEmpty;
  int get wordCount => pile.isEmpty ? 0 : pile.length - 1;
  bool get isComplete => unlocked && wordCount == kWordsPerCategory;

  void _reset() => pile.clear();
}

/// Outcome of a foundation placement.
enum PlaceOutcome { unlocked, matched, completed, rejected }

class PlaceResult {
  const PlaceResult(this.outcome, {this.foundationIndex, this.revealedCard});

  final PlaceOutcome outcome;
  final int? foundationIndex;
  final GameCard? revealedCard;

  bool get accepted => outcome != PlaceOutcome.rejected;
}

/// A suggested legal move for the hint system.
class HintMove {
  const HintMove({
    required this.source,
    required this.columnIndex,
    required this.card,
    required this.foundationIndex,
  });

  final CardSource source;
  final int columnIndex; // tableau column, or -1 for the waste
  final GameCard card;
  final int foundationIndex;
}

enum _MoveType { toFoundation, toColumn, draw, recycle }

class _Move {
  _Move.toFoundation({
    required this.source,
    required this.fromColumn,
    required this.foundationIndex,
    required this.card,
    required this.revealed,
  })  : type = _MoveType.toFoundation,
        toColumn = -1,
        count = 0;

  _Move.toColumn({
    required this.source,
    required this.fromColumn,
    required this.toColumn,
    required this.card,
    required this.revealed,
  })  : type = _MoveType.toColumn,
        foundationIndex = -1,
        count = 0;

  _Move.draw()
      : type = _MoveType.draw,
        source = CardSource.tableau,
        fromColumn = -1,
        toColumn = -1,
        foundationIndex = -1,
        card = null,
        revealed = false,
        count = 0;

  _Move.recycle(this.count)
      : type = _MoveType.recycle,
        source = CardSource.tableau,
        fromColumn = -1,
        toColumn = -1,
        foundationIndex = -1,
        card = null,
        revealed = false;

  final _MoveType type;
  final CardSource source;
  final int fromColumn;
  final int toColumn;
  final int foundationIndex;
  final GameCard? card;
  final bool revealed;
  final int count;
}

/// Pure, Flutter-free game logic for the strategic word-solitaire board.
///
/// Rules:
/// * Each foundation is **pre-labeled** with a category and starts **locked**.
///   It only accepts its matching **category card** first (which unlocks it),
///   then word cards of that category — in any order.
/// * Only the **top** card of each column is face-up; removing it flips the one
///   beneath. A card can be moved from a column top or the waste top.
/// * A card can only go to a **matching foundation**. An **empty column**
///   accepts **only a category card** (a scarce relocation buffer).
/// * The **stock** draws to the **waste**; when empty it recycles.
///
/// Every dealt level is verified **greedily solvable** before use.
class SolitaireEngine {
  SolitaireEngine(this.level, {Random? random, RoundSpec? spec})
      : _rng = random ?? Random() {
    _spec = spec ??
        RoundSpec.forLevelNumber(level.number,
            categoryCount: level.categories.length);
    _needed = {
      for (final c in level.categories)
        c.id: level.words.where((w) => w.categoryId == c.id).length,
    };
    foundations = [for (final _ in level.categories) Foundation()];
    deal();
  }

  final Level level;
  final Random _rng;

  /// The difficulty parameters for the current deal.
  late final RoundSpec _spec;
  RoundSpec get spec => _spec;

  late final Map<String, int> _needed;
  late final List<Foundation> foundations;

  final List<List<TableauCard>> columns = [];
  final List<GameCard> stock = [];
  final List<GameCard> waste = [];
  final List<_Move> _history = [];

  int get categoryCount => level.categories.length;
  int get columnCount => columns.length;

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

  GameCard? get wasteTop => waste.isEmpty ? null : waste.last;

  int get stockCount => stock.length;

  GameCard? tableauTop(int col) {
    final column = columns[col];
    if (column.isEmpty) return null;
    return column.last.faceUp ? column.last.card : null;
  }

  /// Index of the foundation already locked to [categoryId], or -1.
  int foundationIndexForCategory(String categoryId) =>
      foundations.indexWhere((f) => f.categoryId == categoryId);

  // --- Dealing --------------------------------------------------------------

  List<GameCard> _buildDeck() {
    final deck = <GameCard>[];
    for (final c in level.categories) {
      deck.add(GameCard.category(c));
    }
    for (final w in level.words) {
      deck.add(GameCard.word(w));
    }
    return deck;
  }

  /// Deals a fresh, guaranteed-solvable layout and resets all state.
  ///
  /// The board shape is driven by [spec]: deeper columns and buried category
  /// cards make a round harder. Solvability is still verified before use.
  void deal() {
    final columnsCount = categoryCount; // one column per category
    // At least one card per category stays in the stock so drawing matters.
    final depth = _spec.columnDepth.clamp(2, kWordsPerCategory);

    for (var attempt = 0; attempt < 400; attempt++) {
      final deck = _buildDeck()..shuffle(_rng);
      if (!_spec.buryCategoryCards) {
        _biasCategoryCardsAccessible(deck, columnsCount, depth);
      }
      final layout = _arrange(deck, columnsCount, depth);
      if (_greedySolvable(layout.$1, layout.$2)) {
        _adopt(layout.$1, layout.$2);
        return;
      }
    }
    // Fallback: category cards on top of every column → trivially reachable.
    _adopt(_easyLayout(), <GameCard>[]);
  }

  /// Moves category cards toward positions that will end up face-up (column
  /// tops) to make early levels gentler.
  void _biasCategoryCardsAccessible(
      List<GameCard> deck, int columnsCount, int depth) {
    // The last card dealt to each column (the top) is face-up. In a
    // column-by-column deal, those are indices depth-1, 2*depth-1, ...
    final topIndices = <int>[
      for (var c = 0; c < columnsCount; c++)
        ((c + 1) * depth - 1).clamp(0, deck.length - 1),
    ];
    final catIndices = [
      for (var i = 0; i < deck.length; i++)
        if (deck[i].isCategory) i,
    ];
    for (var k = 0; k < catIndices.length && k < topIndices.length; k++) {
      final from = catIndices[k];
      final to = topIndices[k];
      final tmp = deck[to];
      deck[to] = deck[from];
      deck[from] = tmp;
    }
  }

  /// Splits [deck] into columns (top card face-up) and a face-down stock.
  (List<List<TableauCard>>, List<GameCard>) _arrange(
      List<GameCard> deck, int columnsCount, int depth) {
    final tableauTarget =
        (columnsCount * depth).clamp(0, deck.length);
    final cols =
        List.generate(columnsCount, (_) => <TableauCard>[]);
    var idx = 0;
    for (var c = 0; c < columnsCount && idx < tableauTarget; c++) {
      for (var r = 0; r < depth && idx < tableauTarget; r++) {
        cols[c].add(TableauCard(deck[idx], faceUp: false));
        idx++;
      }
      if (cols[c].isNotEmpty) cols[c].last.faceUp = true;
    }
    final stockCards = deck.sublist(idx);
    return (cols, stockCards);
  }

  List<List<TableauCard>> _easyLayout() {
    // Every category card sits face-up on its own column; words fill the stock.
    final cats = [for (final c in level.categories) GameCard.category(c)];
    final cols = [
      for (final c in cats) [TableauCard(c, faceUp: true)],
    ];
    stock
      ..clear()
      ..addAll(level.words.map(GameCard.word).toList()..shuffle(_rng));
    return cols;
  }

  void _adopt(List<List<TableauCard>> cols, List<GameCard> stockCards) {
    columns
      ..clear()
      ..addAll(cols);
    stock
      ..clear()
      ..addAll(stockCards);
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

  // --- Placement rules ------------------------------------------------------

  bool canPlaceOnFoundation(GameCard card, int foundationIndex) {
    if (foundationIndex < 0 || foundationIndex >= foundations.length) {
      return false;
    }
    final f = foundations[foundationIndex];
    if (!f.unlocked) {
      // Empty foundation: only a category card whose category isn't already
      // claimed by another foundation.
      return card.isCategory &&
          foundationIndexForCategory(card.categoryId) == -1;
    }
    return !card.isCategory &&
        card.categoryId == f.categoryId &&
        f.wordCount < kWordsPerCategory;
  }

  /// Empty columns accept only category cards; non-empty columns accept a word
  /// card whose category matches the (face-up) top card — a real tableau build.
  bool canPlaceOnColumn(GameCard card, int columnIndex) {
    if (columnIndex < 0 || columnIndex >= columns.length) return false;
    final column = columns[columnIndex];
    if (column.isEmpty) return card.isCategory;
    final top = column.last;
    if (!top.faceUp) return false;
    return !card.isCategory && card.categoryId == top.card.categoryId;
  }

  GameCard? _sourceTop(CardSource source, int col) =>
      source == CardSource.waste ? wasteTop : tableauTop(col);

  GameCard _removeSourceTop(CardSource source, int col,
      {required void Function(GameCard? revealed) onRevealed}) {
    if (source == CardSource.waste) {
      onRevealed(null);
      return waste.removeLast();
    }
    final card = columns[col].removeLast().card;
    GameCard? revealed;
    if (columns[col].isNotEmpty && !columns[col].last.faceUp) {
      columns[col].last.faceUp = true;
      revealed = columns[col].last.card;
    }
    onRevealed(revealed);
    return card;
  }

  /// Places the top card of [source]/[fromColumn] onto foundation [index].
  PlaceResult playToFoundation(
      CardSource source, int fromColumn, int foundationIndex) {
    final card = _sourceTop(source, fromColumn);
    if (card == null || !canPlaceOnFoundation(card, foundationIndex)) {
      _mistakes++;
      _combo = 0;
      return const PlaceResult(PlaceOutcome.rejected);
    }
    GameCard? revealed;
    _removeSourceTop(source, fromColumn, onRevealed: (r) => revealed = r);
    foundations[foundationIndex].pile.add(card);
    _history.add(_Move.toFoundation(
      source: source,
      fromColumn: fromColumn,
      foundationIndex: foundationIndex,
      card: card,
      revealed: revealed != null,
    ));
    _moves++;
    _combo++;
    if (_combo > _bestCombo) _bestCombo = _combo;
    final f = foundations[foundationIndex];
    final outcome = card.isCategory
        ? PlaceOutcome.unlocked
        : (f.isComplete ? PlaceOutcome.completed : PlaceOutcome.matched);
    if (outcome == PlaceOutcome.completed) _streak++;
    return PlaceResult(outcome,
        foundationIndex: foundationIndex, revealedCard: revealed);
  }

  /// Moves the top card of [source]/[fromColumn] onto column [toCol]: a category
  /// card onto an empty column, or a word onto a same-category top.
  PlaceResult moveToColumn(CardSource source, int fromColumn, int toCol) {
    if (source == CardSource.tableau && fromColumn == toCol) {
      return const PlaceResult(PlaceOutcome.rejected);
    }
    final card = _sourceTop(source, fromColumn);
    if (card == null || !canPlaceOnColumn(card, toCol)) {
      return const PlaceResult(PlaceOutcome.rejected);
    }
    GameCard? revealed;
    _removeSourceTop(source, fromColumn, onRevealed: (r) => revealed = r);
    columns[toCol].add(TableauCard(card, faceUp: true));
    _history.add(_Move.toColumn(
      source: source,
      fromColumn: fromColumn,
      toColumn: toCol,
      card: card,
      revealed: revealed != null,
    ));
    _moves++;
    return PlaceResult(PlaceOutcome.matched, revealedCard: revealed);
  }

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

  void _returnToSource(_Move move) {
    if (move.source == CardSource.waste) {
      waste.add(move.card!);
    } else {
      if (move.revealed && columns[move.fromColumn].isNotEmpty) {
        columns[move.fromColumn].last.faceUp = false;
      }
      columns[move.fromColumn].add(TableauCard(move.card!, faceUp: true));
    }
  }

  bool undo() {
    if (_history.isEmpty) return false;
    final move = _history.removeLast();
    switch (move.type) {
      case _MoveType.toFoundation:
        foundations[move.foundationIndex].pile.removeLast();
        _returnToSource(move);
        if (_moves > 0) _moves--;
      case _MoveType.toColumn:
        columns[move.toColumn].removeLast();
        _returnToSource(move);
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

  // --- Hints ----------------------------------------------------------------

  HintMove? suggestMove() {
    HintMove? best;
    void consider(CardSource source, int col, GameCard? card) {
      if (card == null) return;
      // Word cards target their locked foundation; category cards target the
      // first empty foundation.
      final fi = card.isCategory
          ? foundations.indexWhere((f) => !f.unlocked)
          : foundationIndexForCategory(card.categoryId);
      if (fi < 0 || !canPlaceOnFoundation(card, fi)) return;
      final move =
          HintMove(source: source, columnIndex: col, card: card, foundationIndex: fi);
      // Prefer word cards that complete/extend an unlocked foundation, then
      // category cards that unlock a new one.
      if (best == null) {
        best = move;
      } else if (!card.isCategory && best!.card.isCategory) {
        best = move;
      }
    }

    consider(CardSource.waste, -1, wasteTop);
    for (var c = 0; c < columns.length; c++) {
      consider(CardSource.tableau, c, tableauTop(c));
    }
    return best;
  }

  // --- Solvability (greedy is complete for this rule set) -------------------

  bool _canPlaceSim(GameCard card, Set<String> unlocked, Map<String, int> wc) {
    if (card.isCategory) return !unlocked.contains(card.categoryId);
    return unlocked.contains(card.categoryId) &&
        wc[card.categoryId]! < _needed[card.categoryId]!;
  }

  void _applySim(GameCard card, Set<String> unlocked, Map<String, int> wc) {
    if (card.isCategory) {
      unlocked.add(card.categoryId);
    } else {
      wc[card.categoryId] = wc[card.categoryId]! + 1;
    }
  }

  /// Because placing any exposed card is never harmful here, a greedy playout is
  /// a *complete* solvability test: it wins iff the deal is winnable.
  bool _greedySolvable(
      List<List<TableauCard>> cols0, List<GameCard> stock0) {
    final cols = [
      for (final col in cols0)
        [for (final t in col) TableauCard(t.card, faceUp: t.faceUp)],
    ];
    final stock = List<GameCard>.from(stock0);
    final waste = <GameCard>[];
    final unlocked = <String>{};
    final wc = {for (final id in _needed.keys) id: 0};
    final totalToPlace =
        _needed.values.fold<int>(0, (a, b) => a + b) + _needed.length;
    var placed = 0;
    var drawsSinceProgress = 0;

    while (placed < totalToPlace) {
      var progressed = false;
      for (final col in cols) {
        if (col.isEmpty || !col.last.faceUp) continue;
        if (_canPlaceSim(col.last.card, unlocked, wc)) {
          _applySim(col.last.card, unlocked, wc);
          col.removeLast();
          if (col.isNotEmpty && !col.last.faceUp) col.last.faceUp = true;
          placed++;
          progressed = true;
        }
      }
      if (waste.isNotEmpty && _canPlaceSim(waste.last, unlocked, wc)) {
        _applySim(waste.last, unlocked, wc);
        waste.removeLast();
        placed++;
        progressed = true;
      }
      if (placed >= totalToPlace) break;
      if (progressed) {
        drawsSinceProgress = 0;
        continue;
      }
      if (stock.isEmpty && waste.isEmpty) return false;
      if (stock.isEmpty) {
        stock.addAll(waste.reversed);
        waste.clear();
      }
      waste.add(stock.removeLast());
      drawsSinceProgress++;
      if (drawsSinceProgress > stock.length + waste.length + 1) return false;
    }
    return true;
  }
}
