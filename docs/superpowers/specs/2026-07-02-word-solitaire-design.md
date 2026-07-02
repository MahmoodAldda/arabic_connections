# Word-Solitaire (وصلة سوليتير) — Design Spec

**Date:** 2026-07-02
**Status:** Approved design, pending implementation plan
**Author:** Pairing session (Cursor agent + user)

## 1. Summary

Convert the existing Arabic word-grouping puzzle (NYT-Connections style) into a
**word-solitaire game**: the same level content (16 words across 4 categories) is
dealt onto a solitaire-style board where the player drags word cards into
category "foundation" slots. This keeps the game's unique Arabic word-grouping
concept while giving it the tactile, relaxing feel of a solitaire game (like the
reference the user provided).

The level data model and all services are reused unchanged. Only a new game board
(engine + screen) is built, and the Home screen is re-pointed to it.

## 2. Decisions (locked)

| Topic | Decision |
|-------|----------|
| Core mechanic | Grouping concept on a solitaire board |
| Interaction | Drag the front card of a column onto a category foundation |
| Board layout | 4 columns × 4 cards, **all face-up**; only the front card of each column is draggable |
| Foundations | Blank at start; **reveal category name + color when the first word is placed** (reveal-on-first) |
| Difficulty | Ship the **relaxing** base version first (every front card always has a legal home). Optional **Challenge Mode** (hidden category names) deferred to a later iteration. |
| Code approach | **A** — replace gameplay with solitaire board, reuse data/services/theme. Old `game_screen.dart` kept in repo (unused) for easy rollback. |
| Visual style | **Green-felt** solitaire/casino look, reusing existing color tokens where sensible. |
| Features kept | Undo, Moves counter, Hint, Shuffle/re-deal, Coins, Daily challenge, Classic levels + progression |

## 3. Gameplay rules

1. The active level's 16 words are dealt into **4 columns of 4 cards**, all face-up.
   Only the **front (bottom) card of each column** is draggable; removing it reveals
   the next card behind it.
2. The player drags a front card onto one of **4 foundation slots**:
   - **Empty foundation** → starts a new group with that card; the foundation
     reveals the card's **category name + color** (reveal-on-first).
   - **Claimed foundation** → the card sticks only if its `categoryId` matches the
     foundation's category; otherwise it **bounces back** (shake + haptic, **no coin
     penalty**).
3. A foundation **completes** when it holds all 4 words of its category. It locks
   with a small celebration and fills one progress segment in the header.
4. **Win** = all 4 foundations complete (all 16 cards placed). Triggers the existing
   level-complete sheet, coin award, confetti, and next-level progression.
5. There is **no lose state** in the base (relaxing) version.

### Feature behavior

- **Undo**: reverts the most recent placement, returning the card to the front of
  its original column. (Move counter behavior: an undo does not reduce the recorded
  move count; it counts as continuing play. Final decision documented in the plan.)
- **Moves counter**: increments on each successful placement. Bounced (invalid)
  attempts do not count as moves. Shown in the header/bottom bar.
- **Hint**: uses `HintService` + coins to highlight a valid front-card → foundation
  move (a new "next best placement" helper is added to `HintService`).
- **Shuffle / re-deal**: re-deals the current level (fresh shuffle), resets moves and
  foundations.
- **Coins / Daily / Levels**: reuse existing `PlayerService`, `DailyChallengeService`,
  `LevelApiService`, and `GameSession` exactly as the current game does.

## 4. Architecture

New, isolated units:

- `lib/solitaire/solitaire_engine.dart` — **pure Dart**, no Flutter imports.
  - State: `List<List<WordItem>> columns`, `List<Foundation> foundations`,
    move history for undo, `int moves`.
  - API: `deal(Level)`, `List<WordItem> get frontCards`, `PlaceResult tryPlace(WordItem, int foundationIndex)`, `bool undo()`, `bool get isWon`, `int get moves`.
  - `Foundation`: `{ String? categoryId; List<WordItem> cards; bool get isComplete; }`
  - `PlaceResult`: enum `{ started, matched, completed, rejected }` (+ affected data).
  - Fully unit-testable without a widget tree.
- `lib/solitaire/solitaire_game_screen.dart` — the UI.
  - Green-felt background; foundations row; tableau columns using
    `Draggable`/`DragTarget`; bottom bar (hint / undo / shuffle) + moves.
  - Reuses `_GameHeader`-style header (coins, level title, segmented progress),
    `ConfettiBurst`, `PressableButton`, level-complete sheet, `GameColors`/`GameDecorations`.

Edits to existing files:

- `lib/home_screen.dart` — route `_openClassic` and `_openDaily` to
  `SolitaireGameScreen` instead of `GameScreen`.
- `lib/services/hint_service.dart` — add a helper that, given the engine state,
  returns a valid front-card → foundation placement to highlight.

Reused unchanged:

- `lib/models.dart` (`Level`, `WordItem`, `Category`, `GameSession`, `GameMode`)
- `lib/services/player_service.dart`, `daily_challenge_service.dart`,
  `level_api_service.dart`, `ad_service.dart`
- `lib/theme/game_theme.dart`, `lib/widgets/confetti_burst.dart`,
  `lib/widgets/pressable_button.dart`
- `lib/game_screen.dart` — retained but no longer routed to (rollback safety).

## 5. Testing

- `test/solitaire_engine_test.dart`:
  - `deal` produces 4 columns of 4 cards using all 16 level words.
  - Placing a front card on an empty foundation claims the category.
  - Placing a matching card on a claimed foundation succeeds; a non-matching card is
    rejected without mutating state.
  - Completing all 4 categories sets `isWon`.
  - `undo` restores the previous state and the card returns to its column front.
- Manual: `flutter analyze` clean, `flutter test` green, run on device/web to verify
  drag-and-drop, reveal-on-first, win flow, undo, shuffle, hint, coins.

## 6. Out of scope (this iteration)

- Challenge Mode (hidden category names) — deferred.
- Face-down cards / stock-and-waste pile — not used.
- Free cells / holding tray — not needed in the base version.
- Keeping the old grouping game as a selectable mode (approach B) — not chosen.

## 7. Open items for the plan

- Exact green-felt palette tokens (new colors vs. reusing existing).
- Column overlap spacing and card sizing for portrait on small/large phones.
- Precise Undo ↔ Moves-counter interaction (see §3).
