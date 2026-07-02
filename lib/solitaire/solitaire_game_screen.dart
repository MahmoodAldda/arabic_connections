import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models.dart';
import '../services/player_service.dart';
import '../theme/game_theme.dart';
import '../widgets/confetti_burst.dart';
import '../widgets/pressable_button.dart';
import 'solitaire_engine.dart';

/// Green-felt word-solitaire board. Reuses the same level content and services
/// as the classic grouping game.
class SolitaireGameScreen extends StatefulWidget {
  const SolitaireGameScreen({
    super.key,
    required this.session,
    required this.playerService,
  });

  final GameSession session;
  final PlayerService playerService;

  @override
  State<SolitaireGameScreen> createState() => _SolitaireGameScreenState();
}

class _SolitaireGameScreenState extends State<SolitaireGameScreen>
    with TickerProviderStateMixin {
  late int _levelIndex;
  late SolitaireEngine _engine;

  String? _hintedWordId;
  int? _flashFoundationIndex;
  bool _showConfetti = false;
  bool _isComplete = false;

  late AnimationController _shakeController;
  int _boardGeneration = 0;

  Level get _level => widget.session.activeLevel;

  @override
  void initState() {
    super.initState();
    _levelIndex =
        widget.session.levelIndex.clamp(0, widget.session.levels.length - 1);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _initLevel();
    widget.playerService.addListener(_onPlayerUpdate);
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.playerService.removeListener(_onPlayerUpdate);
    _shakeController.dispose();
    super.dispose();
  }

  void _initLevel() {
    setState(() {
      _engine = SolitaireEngine(_level);
      _hintedWordId = null;
      _flashFoundationIndex = null;
      _showConfetti = false;
      _isComplete = false;
      _boardGeneration++;
    });
  }

  // --- Actions --------------------------------------------------------------

  void _placeOnFoundation(WordItem word, int foundationIndex) {
    if (_isComplete) return;
    final result = _engine.tryPlace(word, foundationIndex);
    if (!result.accepted) {
      _rejectFeedback();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _hintedWordId = null);
    if (result.outcome == PlaceOutcome.completed) {
      HapticFeedback.mediumImpact();
    }
    if (_engine.isWon) {
      _handleWin();
    }
  }

  /// Tap a front card to send it to its matching (or a new) foundation.
  void _autoPlace(WordItem word) {
    if (_isComplete) return;
    for (var i = 0; i < _engine.foundations.length; i++) {
      if (!_engine.foundations[i].isEmpty && _engine.canPlace(word, i)) {
        _placeOnFoundation(word, i);
        return;
      }
    }
    for (var i = 0; i < _engine.foundations.length; i++) {
      if (_engine.canPlace(word, i)) {
        _placeOnFoundation(word, i);
        return;
      }
    }
    _rejectFeedback();
  }

  void _rejectFeedback() {
    HapticFeedback.vibrate();
    _shakeController.forward(from: 0);
  }

  void _undo() {
    if (_isComplete) return;
    if (_engine.undo()) {
      HapticFeedback.lightImpact();
      setState(() => _hintedWordId = null);
    }
  }

  void _shuffle() {
    HapticFeedback.lightImpact();
    _initLevel();
  }

  Future<void> _hint() async {
    if (_isComplete) return;
    const cost = GameEconomy.wordHintCost;
    if (widget.playerService.coins < cost) {
      _showSnack('لا تملك عملات كافية');
      return;
    }
    final move = _engine.suggestMove();
    if (move == null) {
      _showSnack('لا توجد حركات متاحة');
      return;
    }
    final spent = await widget.playerService.spendCoins(cost);
    if (!spent || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _hintedWordId = move.word.id;
      _flashFoundationIndex = move.foundationIndex;
    });
    _showSnack('جرّب هذه البطاقة');
  }

  Future<void> _handleWin() async {
    setState(() {
      _isComplete = true;
      _showConfetti = true;
    });
    await widget.playerService.addCoins(widget.session.coinReward);
    if (widget.session.isDaily) {
      await widget.playerService.markDailyCompleted();
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _showWinSheet();
  }

  void _showWinSheet() {
    final isDaily = widget.session.isDaily;
    final isLastLevel = _levelIndex >= widget.session.levels.length - 1;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _WinSheet(
        levelNumber: _level.number,
        coinsEarned: widget.session.coinReward,
        moves: _engine.moves,
        isDaily: isDaily,
        isLastLevel: isLastLevel,
        onContinue: () {
          Navigator.pop(context);
          if (isDaily) {
            Navigator.pop(context);
            return;
          }
          setState(() {
            _levelIndex = isLastLevel ? 0 : _levelIndex + 1;
          });
          _initLevel();
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _FeltColors.line,
        ),
      );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _FeltBackground(),
          SafeArea(
            child: Column(
              children: [
                _SolitaireHeader(
                  level: _level,
                  moves: _engine.moves,
                  completed: _engine.completedCount,
                  coins: widget.playerService.coins,
                  isDaily: widget.session.isDaily,
                  onRestart: _shuffle,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        _FoundationsRow(
                          foundations: _engine.foundations,
                          level: _level,
                          flashIndex: _flashFoundationIndex,
                          canAccept: (word, i) => _engine.canPlace(word, i),
                          onAccept: _placeOnFoundation,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _shakeController,
                            builder: (context, child) {
                              final dx = math.sin(
                                    _shakeController.value * math.pi * 4,
                                  ) *
                                  9 *
                                  _shakeController.value;
                              return Transform.translate(
                                offset: Offset(dx, 0),
                                child: child,
                              );
                            },
                            child: _Tableau(
                              key: ValueKey('board-$_boardGeneration'),
                              columns: _engine.columns,
                              hintedWordId: _hintedWordId,
                              onTapFront: _autoPlace,
                              enabled: !_isComplete,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SolitaireBottomBar(
                  onHint: _hint,
                  onUndo: _undo,
                  onShuffle: _shuffle,
                  canUndo: _engine.canUndo && !_isComplete,
                  hintCost: GameEconomy.wordHintCost,
                ),
              ],
            ),
          ),
          if (_showConfetti)
            ConfettiBurst(
              onComplete: () {
                if (mounted) setState(() => _showConfetti = false);
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Felt palette
// ---------------------------------------------------------------------------

abstract final class _FeltColors {
  static const top = Color(0xFF2FA35C);
  static const bottom = Color(0xFF15723C);
  static const slot = Color(0x33FFFFFF);
  static const slotBorder = Color(0x66FFFFFF);
  static const line = Color(0xFF0E5C30);
}

class _FeltBackground extends StatelessWidget {
  const _FeltBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_FeltColors.top, _FeltColors.bottom],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _SolitaireHeader extends StatelessWidget {
  const _SolitaireHeader({
    required this.level,
    required this.moves,
    required this.completed,
    required this.coins,
    required this.isDaily,
    required this.onRestart,
  });

  final Level level;
  final int moves;
  final int completed;
  final int coins;
  final bool isDaily;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_rounded,
                        color: _FeltColors.bottom, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '$moves',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _FeltColors.line,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                children: [
                  if (isDaily)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'تحدي اليوم',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Text(
                    isDaily ? level.title : 'المستوى ${level.number}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _HeaderChip(
                faceColor: const Color(0xFFFFF8E1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on_rounded,
                        color: Color(0xFFFFC800), size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '$coins',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE6A800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(kSolitaireColumns, (i) {
              final filled = i < completed;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.elasticOut,
                    height: 10,
                    decoration: BoxDecoration(
                      color: filled
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.child, this.faceColor = Colors.white});

  final Widget child;
  final Color faceColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: faceColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Foundations
// ---------------------------------------------------------------------------

class _FoundationsRow extends StatelessWidget {
  const _FoundationsRow({
    required this.foundations,
    required this.level,
    required this.flashIndex,
    required this.canAccept,
    required this.onAccept,
  });

  final List<Foundation> foundations;
  final Level level;
  final int? flashIndex;
  final bool Function(WordItem word, int index) canAccept;
  final void Function(WordItem word, int index) onAccept;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(foundations.length, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
            child: DragTarget<WordItem>(
              onWillAcceptWithDetails: (details) =>
                  canAccept(details.data, i),
              onAcceptWithDetails: (details) => onAccept(details.data, i),
              builder: (context, candidate, rejected) {
                final highlighted = candidate.isNotEmpty || flashIndex == i;
                return _FoundationSlot(
                  foundation: foundations[i],
                  level: level,
                  highlighted: highlighted,
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

class _FoundationSlot extends StatelessWidget {
  const _FoundationSlot({
    required this.foundation,
    required this.level,
    required this.highlighted,
  });

  final Foundation foundation;
  final Level level;
  final bool highlighted;

  Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final category =
        foundation.isEmpty ? null : level.categoryById(foundation.categoryId!);

    if (category == null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 78,
        decoration: BoxDecoration(
          color: highlighted ? const Color(0x55FFFFFF) : _FeltColors.slot,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted ? Colors.white : _FeltColors.slotBorder,
            width: 2,
          ),
        ),
        child: const Center(
          child: Icon(Icons.workspace_premium_rounded,
              color: Color(0x88FFFFFF), size: 26),
        ),
      );
    }

    final edge = _darken(category.color);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: GameDecorations.card(
        faceColor: category.color,
        edgeColor: edge,
        radius: 14,
      ).copyWith(
        border: highlighted
            ? Border.all(color: Colors.white, width: 2.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              foundation.isComplete
                  ? '✓'
                  : '${foundation.cards.length}/$kSolitaireCardsPerColumn',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tableau (columns of cards)
// ---------------------------------------------------------------------------

class _Tableau extends StatelessWidget {
  const _Tableau({
    super.key,
    required this.columns,
    required this.hintedWordId,
    required this.onTapFront,
    required this.enabled,
  });

  final List<List<WordItem>> columns;
  final String? hintedWordId;
  final ValueChanged<WordItem> onTapFront;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns.length - 1)) / columns.length;
        final cardHeight = math.min(cardWidth * 1.28, 96.0);
        final peek = cardHeight * 0.34;
        final columnHeight =
            cardHeight + peek * (kSolitaireCardsPerColumn - 1);

        return Align(
          alignment: Alignment.topCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(columns.length, (i) {
              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child: _Column(
                  cards: columns[i],
                  width: cardWidth,
                  cardHeight: cardHeight,
                  peek: peek,
                  columnHeight: columnHeight,
                  hintedWordId: hintedWordId,
                  onTapFront: onTapFront,
                  enabled: enabled,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.cards,
    required this.width,
    required this.cardHeight,
    required this.peek,
    required this.columnHeight,
    required this.hintedWordId,
    required this.onTapFront,
    required this.enabled,
  });

  final List<WordItem> cards;
  final double width;
  final double cardHeight;
  final double peek;
  final double columnHeight;
  final String? hintedWordId;
  final ValueChanged<WordItem> onTapFront;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: columnHeight,
      child: cards.isEmpty
          ? _EmptyColumnSlot(height: cardHeight)
          : Stack(
              children: List.generate(cards.length, (index) {
                final card = cards[index];
                final isFront = index == cards.length - 1;
                return Positioned(
                  top: index * peek,
                  left: 0,
                  right: 0,
                  child: _CardTile(
                    word: card,
                    width: width,
                    height: cardHeight,
                    isFront: isFront,
                    isHinted: card.id == hintedWordId,
                    onTapFront: onTapFront,
                    enabled: enabled,
                  ),
                );
              }),
            ),
    );
  }
}

class _EmptyColumnSlot extends StatelessWidget {
  const _EmptyColumnSlot({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x44FFFFFF), width: 1.5),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.word,
    required this.width,
    required this.height,
    required this.isFront,
    required this.isHinted,
    required this.onTapFront,
    required this.enabled,
  });

  final WordItem word;
  final double width;
  final double height;
  final bool isFront;
  final bool isHinted;
  final ValueChanged<WordItem> onTapFront;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final face = _face();

    if (!isFront || !enabled) return face;

    return Draggable<WordItem>(
      data: word,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          height: height,
          child: _CardFace(
            word: word,
            isFront: true,
            isHinted: isHinted,
            elevated: true,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: face),
      child: GestureDetector(
        onTap: () => onTapFront(word),
        child: face,
      ),
    );
  }

  Widget _face() => SizedBox(
        width: width,
        height: height,
        child: _CardFace(word: word, isFront: isFront, isHinted: isHinted),
      );
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.word,
    required this.isFront,
    required this.isHinted,
    this.elevated = false,
  });

  final WordItem word;
  final bool isFront;
  final bool isHinted;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    Color face = GameColors.surface;
    Color edge = GameColors.borderDark;
    Color textColor = GameColors.textPrimary;
    if (isHinted) {
      face = const Color(0xFFFFF3E0);
      edge = GameColors.orangeDark;
      textColor = GameColors.orangeDark;
    } else if (!isFront) {
      face = const Color(0xFFF3F4F6);
    }

    return Container(
      decoration: GameDecorations.card(
        faceColor: face,
        edgeColor: edge,
        radius: 14,
      ).copyWith(
        boxShadow: elevated
            ? const [
                BoxShadow(
                    color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 6)),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      alignment: Alignment.topCenter,
      child: Text(
        word.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: GameTextStyles.cardLabel.copyWith(
          color: textColor,
          fontSize: 14,
          fontWeight: isFront ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class _SolitaireBottomBar extends StatelessWidget {
  const _SolitaireBottomBar({
    required this.onHint,
    required this.onUndo,
    required this.onShuffle,
    required this.canUndo,
    required this.hintCost,
  });

  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onShuffle;
  final bool canUndo;
  final int hintCost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: GameColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: GameColors.shadow, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: PressableButton(
              label: 'تلميح',
              icon: Icons.lightbulb_outline_rounded,
              faceColor: GameColors.orange,
              edgeColor: GameColors.orangeDark,
              height: 52,
              onPressed: onHint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressableButton(
              label: 'تراجع',
              icon: Icons.undo_rounded,
              faceColor: GameColors.blue,
              edgeColor: GameColors.blueDark,
              height: 52,
              enabled: canUndo,
              onPressed: canUndo ? onUndo : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressableButton(
              label: 'خلط',
              icon: Icons.shuffle_rounded,
              faceColor: GameColors.green,
              edgeColor: GameColors.greenDark,
              height: 52,
              onPressed: onShuffle,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Win sheet
// ---------------------------------------------------------------------------

class _WinSheet extends StatelessWidget {
  const _WinSheet({
    required this.levelNumber,
    required this.coinsEarned,
    required this.moves,
    required this.isDaily,
    required this.isLastLevel,
    required this.onContinue,
  });

  final int levelNumber;
  final int coinsEarned;
  final int moves;
  final bool isDaily;
  final bool isLastLevel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: GameDecorations.panel(color: GameColors.surface),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: GameDecorations.card(
              faceColor: GameColors.green,
              edgeColor: GameColors.greenDark,
              radius: 44,
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          Text(
            isDaily ? 'تحدي اليوم مكتمل!' : 'رائع!',
            style:
                GameTextStyles.title.copyWith(fontSize: 28, color: GameColors.green),
          ),
          const SizedBox(height: 8),
          Text(
            isDaily
                ? 'حصلت على $coinsEarned عملة  ·  $moves حركة'
                : 'أكملت المستوى $levelNumber (+$coinsEarned عملة)  ·  $moves حركة',
            style: GameTextStyles.subtitle.copyWith(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PressableButton(
            label: isDaily
                ? 'العودة للقائمة'
                : isLastLevel
                    ? 'العب من جديد'
                    : 'المستوى التالي',
            icon: Icons.arrow_back_rounded,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
