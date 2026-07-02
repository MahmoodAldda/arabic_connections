import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models.dart';
import '../services/player_service.dart';
import '../services/sound_service.dart';
import '../theme/game_theme.dart';
import '../widgets/animated_coin_badge.dart';
import '../widgets/confetti_burst.dart';
import '../widgets/decor_background.dart';
import '../widgets/fireworks.dart';
import '../widgets/glass_container.dart';
import '../widgets/pressable_button.dart';
import 'solitaire_engine.dart';

/// Premium green-felt word-solitaire board with juicy animations.
/// (Game logic + scoring live in [SolitaireEngine].)
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
  final SoundService _sound = SoundService.instance;

  late int _levelIndex;
  late SolitaireEngine _engine;

  String? _hintedWordId;
  int? _flashFoundationIndex;
  String? _flyingWordId;
  bool _showConfetti = false;
  bool _showFireworks = false;
  bool _isComplete = false;

  String? _comboText;
  int _comboSeq = 0;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  late AnimationController _shakeController;
  late AnimationController _dealController;
  int _boardGeneration = 0;

  final List<GlobalKey> _foundationKeys =
      List.generate(kSolitaireColumns, (_) => GlobalKey());
  final Map<String, GlobalKey> _cardKeys = {};

  Level get _level => widget.session.activeLevel;

  GlobalKey _cardKey(String id) =>
      _cardKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _levelIndex =
        widget.session.levelIndex.clamp(0, widget.session.levels.length - 1);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _dealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
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
    _dealController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _initLevel() {
    _cardKeys.clear();
    setState(() {
      _engine = SolitaireEngine(_level);
      _hintedWordId = null;
      _flashFoundationIndex = null;
      _flyingWordId = null;
      _showConfetti = false;
      _showFireworks = false;
      _isComplete = false;
      _comboText = null;
      _elapsed = Duration.zero;
      _boardGeneration++;
    });
    _dealController.forward(from: 0);
    _startTimer();
  }

  void _startTimer() {
    _stopwatch
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_isComplete) {
        setState(() => _elapsed = _stopwatch.elapsed);
      }
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
    _elapsed = _stopwatch.elapsed;
  }

  void _haptic(void Function() fn) {
    if (_sound.hapticsEnabled) fn();
  }

  // --- Placement ------------------------------------------------------------

  int _findTarget(WordItem word) {
    for (var i = 0; i < _engine.foundations.length; i++) {
      if (!_engine.foundations[i].isEmpty && _engine.canPlace(word, i)) return i;
    }
    for (var i = 0; i < _engine.foundations.length; i++) {
      if (_engine.canPlace(word, i)) return i;
    }
    return -1;
  }

  /// Tap-to-place: the card flies (and flips) to its foundation.
  void _tapPlace(WordItem word) {
    if (_isComplete || _flyingWordId != null) return;
    final target = _findTarget(word);
    if (target == -1) {
      _sound.play(SoundFx.wrong);
      _rejectFeedback();
      return;
    }
    final src = _rectFor(_cardKey(word.id));
    final dst = _rectFor(_foundationKeys[target]);
    if (src == null || dst == null) {
      _commitPlace(word, target);
      return;
    }
    _sound.play(SoundFx.cardTap);
    setState(() => _flyingWordId = word.id);
    _spawnFlyingCard(word, src, dst, () {
      if (!mounted) return;
      setState(() => _flyingWordId = null);
      _commitPlace(word, target);
    });
  }

  void _onDragAccept(WordItem word, int foundationIndex) {
    if (_isComplete) return;
    _commitPlace(word, foundationIndex);
  }

  void _commitPlace(WordItem word, int foundationIndex) {
    final result = _engine.tryPlace(word, foundationIndex);
    if (!result.accepted) {
      _sound.play(SoundFx.wrong);
      _rejectFeedback();
      setState(() {});
      return;
    }
    _sound.play(SoundFx.cardMove);
    _haptic(HapticFeedback.selectionClick);
    final combo = _engine.combo;
    setState(() => _hintedWordId = null);

    if (result.outcome == PlaceOutcome.completed) {
      _sound.play(SoundFx.correct);
      _haptic(HapticFeedback.mediumImpact);
      setState(() => _showConfetti = true);
      if (combo >= 2) _flashCombo(combo);
    } else if (combo >= 3) {
      _flashCombo(combo);
    }

    if (_engine.isWon) _handleWin();
  }

  void _flashCombo(int combo) {
    _comboSeq++;
    setState(() => _comboText = 'كومبو ×$combo');
    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _comboText = null);
    });
  }

  Rect? _rectFor(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _spawnFlyingCard(
      WordItem word, Rect src, Rect dst, VoidCallback onArrive) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyingCard(
        word: word,
        src: src,
        dst: dst,
        onDone: () {
          entry.remove();
          onArrive();
        },
      ),
    );
    overlay.insert(entry);
  }

  void _rejectFeedback() {
    _haptic(HapticFeedback.vibrate);
    _shakeController.forward(from: 0);
  }

  void _undo() {
    if (_isComplete) return;
    if (_engine.undo()) {
      _sound.play(SoundFx.button);
      _haptic(HapticFeedback.lightImpact);
      setState(() => _hintedWordId = null);
    }
  }

  void _shuffle() {
    if (_isComplete) return;
    _sound.play(SoundFx.shuffle);
    _haptic(HapticFeedback.lightImpact);
    _initLevel();
  }

  Future<void> _hint() async {
    if (_isComplete) return;
    _sound.play(SoundFx.button);
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
    _haptic(HapticFeedback.mediumImpact);
    setState(() {
      _hintedWordId = move.word.id;
      _flashFoundationIndex = move.foundationIndex;
    });
    _showSnack('جرّب هذه البطاقة');
  }

  Future<void> _handleWin() async {
    _stopTimer();
    setState(() {
      _isComplete = true;
      _showConfetti = true;
      _showFireworks = true;
    });
    _sound.play(SoundFx.victory);
    await widget.playerService.addCoins(widget.session.coinReward);
    _sound.play(SoundFx.coins);
    if (widget.session.isDaily) {
      await widget.playerService.markDailyCompleted();
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _haptic(HapticFeedback.heavyImpact);
    _showVictory();
  }

  void _showVictory() {
    final isDaily = widget.session.isDaily;
    final isLastLevel = _levelIndex >= widget.session.levels.length - 1;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => VictorySheet(
        stars: _engine.stars,
        levelNumber: _level.number,
        coinsEarned: widget.session.coinReward,
        moves: _engine.moves,
        mistakes: _engine.mistakes,
        bestCombo: _engine.bestCombo,
        elapsed: _elapsed,
        isDaily: isDaily,
        showNext: !isDaily && !isLastLevel,
        onReplay: () {
          Navigator.pop(context);
          _initLevel();
        },
        onNext: () {
          Navigator.pop(context);
          setState(() => _levelIndex = isLastLevel ? 0 : _levelIndex + 1);
          _initLevel();
        },
        onHome: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.center)),
      );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF116B39),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecorBackground(
              gradient: GameGradients.felt,
              blobs: [Color(0xFF4CDB7E), Color(0xFF0C7A3D), Color(0xFF7BF0A8)],
              felt: true,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _SolitaireHeader(
                  level: _level,
                  moves: _engine.moves,
                  mistakes: _engine.mistakes,
                  bestCombo: _engine.bestCombo,
                  elapsed: _elapsed,
                  completed: _engine.completedCount,
                  total: kSolitaireColumns,
                  coins: widget.playerService.coins,
                  isDaily: widget.session.isDaily,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        _FoundationsRow(
                          foundations: _engine.foundations,
                          level: _level,
                          flashIndex: _flashFoundationIndex,
                          slotKeys: _foundationKeys,
                          canAccept: (word, i) => _engine.canPlace(word, i),
                          onAccept: _onDragAccept,
                        ),
                        const SizedBox(height: 16),
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
                              flyingWordId: _flyingWordId,
                              dealAnimation: _dealController,
                              cardKeyFor: _cardKey,
                              onTapFront: _tapPlace,
                              onDragStarted: () => _sound.play(SoundFx.cardTap),
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
                ),
              ],
            ),
          ),
          if (_comboText != null)
            _ComboPopup(key: ValueKey(_comboSeq), text: _comboText!),
          if (_showConfetti)
            ConfettiBurst(
              onComplete: () {
                if (mounted) setState(() => _showConfetti = false);
              },
            ),
          if (_showFireworks)
            Fireworks(
              onComplete: () {
                if (mounted) setState(() => _showFireworks = false);
              },
            ),
        ],
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
    required this.mistakes,
    required this.bestCombo,
    required this.elapsed,
    required this.completed,
    required this.total,
    required this.coins,
    required this.isDaily,
  });

  final Level level;
  final int moves;
  final int mistakes;
  final int bestCombo;
  final Duration elapsed;
  final int completed;
  final int total;
  final int coins;
  final bool isDaily;

  String get _time {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: GlassContainer(
        radius: GameRadii.xl,
        blur: 16,
        tintOpacity: 0.16,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isDaily)
                        Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(GameRadii.pill),
                          ),
                          child: const Text(
                            'تحدي اليوم',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      Text(
                        isDaily ? level.title : 'المستوى ${level.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GameTextStyles.title.copyWith(
                          color: Colors.white,
                          fontSize: 19,
                          shadows: const [
                            Shadow(
                                color: Color(0x66000000),
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedCoinBadge(count: coins),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MiniStat(icon: Icons.timer_outlined, label: _time),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.swipe_rounded, label: '$moves'),
                const SizedBox(width: 8),
                _MiniStat(
                  icon: Icons.bolt_rounded,
                  label: '×$bestCombo',
                  tint: GameColors.gold,
                ),
                const SizedBox(width: 8),
                _MiniStat(
                  icon: Icons.close_rounded,
                  label: '$mistakes',
                  tint: mistakes > 0 ? GameColors.red : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _LevelProgressBar(value: total == 0 ? 0 : completed / total),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(GameRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tint ?? Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: tint ?? Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelProgressBar extends StatelessWidget {
  const _LevelProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 12,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(GameRadii.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * value.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  gradient: GameGradients.gold,
                  borderRadius: BorderRadius.circular(GameRadii.pill),
                  boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Combo popup
// ---------------------------------------------------------------------------

class _ComboPopup extends StatelessWidget {
  const _ComboPopup({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.34,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, t, child) {
              final scale = 0.6 + Curves.elasticOut.transform(t.clamp(0, 1)) * 0.4;
              final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -30 * t),
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                gradient: GameGradients.gold,
                borderRadius: BorderRadius.circular(GameRadii.pill),
                boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.6),
              ),
              child: Text(
                text,
                style: GameTextStyles.title.copyWith(
                  color: const Color(0xFF7A5200),
                  fontSize: 22,
                ),
              ),
            ),
          ),
        ),
      ),
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
    required this.slotKeys,
    required this.canAccept,
    required this.onAccept,
  });

  final List<Foundation> foundations;
  final Level level;
  final int? flashIndex;
  final List<GlobalKey> slotKeys;
  final bool Function(WordItem word, int index) canAccept;
  final void Function(WordItem word, int index) onAccept;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(foundations.length, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
            child: DragTarget<WordItem>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) => onAccept(details.data, i),
              builder: (context, candidate, rejected) {
                final hasCandidate = candidate.isNotEmpty;
                final valid = hasCandidate && canAccept(candidate.first!, i);
                return _FoundationSlot(
                  key: slotKeys[i],
                  foundation: foundations[i],
                  level: level,
                  highlighted: valid || flashIndex == i,
                  invalidHover: hasCandidate && !valid,
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

class _FoundationSlot extends StatefulWidget {
  const _FoundationSlot({
    super.key,
    required this.foundation,
    required this.level,
    required this.highlighted,
    required this.invalidHover,
  });

  final Foundation foundation;
  final Level level;
  final bool highlighted;
  final bool invalidHover;

  @override
  State<_FoundationSlot> createState() => _FoundationSlotState();
}

class _FoundationSlotState extends State<_FoundationSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didUpdateWidget(_FoundationSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.foundation.cards.length > oldWidget.foundation.cards.length) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, child) {
        final pop = 1 + math.sin(_bounce.value * math.pi) * 0.12;
        return Transform.scale(scale: pop, child: child);
      },
      child: _buildSlot(),
    );
  }

  Widget _buildSlot() {
    final foundation = widget.foundation;
    final category = foundation.isEmpty
        ? null
        : widget.level.categoryById(foundation.categoryId!);

    if (category == null) {
      final borderColor = widget.invalidHover
          ? GameColors.red
          : Colors.white.withValues(alpha: widget.highlighted ? 0.9 : 0.4);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: widget.highlighted ? 0.32 : 0.14),
          borderRadius: BorderRadius.circular(GameRadii.md),
          border: Border.all(
            color: borderColor,
            width: widget.highlighted || widget.invalidHover ? 2.5 : 1.5,
          ),
          boxShadow: widget.highlighted
              ? GameShadows.glow(Colors.white, opacity: 0.35)
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.workspace_premium_rounded,
            color: Colors.white.withValues(alpha: 0.7),
            size: 28,
          ),
        ),
      );
    }

    final gradient = GameGradients.fromColor(category.color);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: widget.invalidHover
              ? GameColors.red
              : (widget.highlighted
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4)),
          width: widget.highlighted || widget.invalidHover ? 2.5 : 1,
        ),
        boxShadow: foundation.isComplete
            ? GameShadows.glow(category.color, opacity: 0.6)
            : GameShadows.card,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            category.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              height: 1.1,
              shadows: [
                Shadow(
                    color: Color(0x55000000),
                    blurRadius: 3,
                    offset: Offset(0, 1)),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(GameRadii.pill),
            ),
            child: Text(
              foundation.isComplete
                  ? '✓ مكتمل'
                  : '${foundation.cards.length}/$kSolitaireCardsPerColumn',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
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
    required this.flyingWordId,
    required this.dealAnimation,
    required this.cardKeyFor,
    required this.onTapFront,
    required this.onDragStarted,
    required this.enabled,
  });

  final List<List<WordItem>> columns;
  final String? hintedWordId;
  final String? flyingWordId;
  final Animation<double> dealAnimation;
  final GlobalKey Function(String id) cardKeyFor;
  final ValueChanged<WordItem> onTapFront;
  final VoidCallback onDragStarted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns.length - 1)) / columns.length;
        final cardHeight = math.min(cardWidth * 1.36, 108.0);
        final peek = cardHeight * 0.36;
        final columnHeight =
            cardHeight + peek * (kSolitaireCardsPerColumn - 1);

        var globalIndex = 0;
        return Align(
          alignment: Alignment.topCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(columns.length, (i) {
              final baseIndex = globalIndex;
              globalIndex += columns[i].length;
              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child: SizedBox(
                  width: cardWidth,
                  height: columnHeight,
                  child: columns[i].isEmpty
                      ? _EmptyColumnSlot(height: cardHeight)
                      : Stack(
                          children:
                              List.generate(columns[i].length, (index) {
                            final card = columns[i][index];
                            final isFront = index == columns[i].length - 1;
                            return Positioned(
                              top: index * peek,
                              left: 0,
                              right: 0,
                              child: _CardTile(
                                word: card,
                                boxKey: isFront ? cardKeyFor(card.id) : null,
                                width: cardWidth,
                                height: cardHeight,
                                isFront: isFront,
                                isHinted: card.id == hintedWordId,
                                isFlying: card.id == flyingWordId,
                                entranceIndex: baseIndex + index,
                                dealAnimation: dealAnimation,
                                onTapFront: onTapFront,
                                onDragStarted: onDragStarted,
                                enabled: enabled,
                              ),
                            );
                          }),
                        ),
                ),
              );
            }),
          ),
        );
      },
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
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Center(
        child: Icon(
          Icons.check_circle_outline_rounded,
          color: Colors.white.withValues(alpha: 0.35),
          size: 24,
        ),
      ),
    );
  }
}

class _CardTile extends StatefulWidget {
  const _CardTile({
    required this.word,
    required this.boxKey,
    required this.width,
    required this.height,
    required this.isFront,
    required this.isHinted,
    required this.isFlying,
    required this.entranceIndex,
    required this.dealAnimation,
    required this.onTapFront,
    required this.onDragStarted,
    required this.enabled,
  });

  final WordItem word;
  final GlobalKey? boxKey;
  final double width;
  final double height;
  final bool isFront;
  final bool isHinted;
  final bool isFlying;
  final int entranceIndex;
  final Animation<double> dealAnimation;
  final ValueChanged<WordItem> onTapFront;
  final VoidCallback onDragStarted;
  final bool enabled;

  @override
  State<_CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<_CardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sized = SizedBox(
      width: widget.width,
      height: widget.height,
      child: _CardFace(
        word: widget.word,
        isFront: widget.isFront,
        isHinted: widget.isHinted,
      ),
    );

    if (widget.isFlying) {
      return Opacity(opacity: 0, child: sized);
    }

    Widget content;
    if (!widget.isFront || !widget.enabled) {
      content = sized;
    } else {
      content = Draggable<WordItem>(
        data: widget.word,
        dragAnchorStrategy: childDragAnchorStrategy,
        onDragStarted: widget.onDragStarted,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: _CardFace(
              word: widget.word,
              isFront: true,
              isHinted: widget.isHinted,
              elevated: true,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: sized),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTapFront(widget.word);
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: KeyedSubtree(key: widget.boxKey, child: sized),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.dealAnimation,
      builder: (context, child) {
        final start = (widget.entranceIndex / 26).clamp(0.0, 0.6);
        final v = widget.dealAnimation.value;
        final local =
            ((v - start) / 0.4).clamp(0.0, 1.0);
        final scale = 0.7 + Curves.easeOutBack.transform(local) * 0.3;
        final opacity = Curves.easeOut.transform(local.clamp(0.0, 1.0));
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: content,
      ),
    );
  }
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
    Gradient gradient;
    Color borderColor;
    Color textColor;

    if (isHinted) {
      gradient = GameGradients.orange;
      borderColor = Colors.white.withValues(alpha: 0.6);
      textColor = Colors.white;
    } else if (isFront) {
      gradient = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFEEF2F7)],
      );
      borderColor = const Color(0xFFE2E8F0);
      textColor = GameColors.textPrimary;
    } else {
      gradient = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F9FB), Color(0xFFE7ECF2)],
      );
      borderColor = const Color(0xFFDCE3EB);
      textColor = GameColors.textSecondary;
    }

    final shadows = elevated
        ? GameShadows.lifted
        : (isFront ? GameShadows.card : GameShadows.soft);

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isHinted
            ? GameShadows.glow(GameColors.orange, opacity: 0.5)
            : shadows,
      ),
      child: Stack(
        children: [
          // Glossy top sheen.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 22,
              decoration: const BoxDecoration(
                gradient: GameGradients.cardSheen,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(GameRadii.md)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                word.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GameTextStyles.cardLabel.copyWith(
                  color: textColor,
                  fontSize: 14.5,
                  letterSpacing: 0.2,
                  fontWeight: isFront ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flying card overlay (tap-to-place)
// ---------------------------------------------------------------------------

class _FlyingCard extends StatefulWidget {
  const _FlyingCard({
    required this.word,
    required this.src,
    required this.dst,
    required this.onDone,
  });

  final WordItem word;
  final Rect src;
  final Rect dst;
  final VoidCallback onDone;

  @override
  State<_FlyingCard> createState() => _FlyingCardState();
}

class _FlyingCardState extends State<_FlyingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        final rect = Rect.lerp(widget.src, widget.dst, t)!;
        final arc = -math.sin(t * math.pi) * 46; // gentle hop
        final flip = t * math.pi * 2; // one full flip, lands face-up
        return Positioned(
          left: rect.left,
          top: rect.top + arc,
          width: rect.width,
          height: rect.height,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(flip),
            child: _CardFace(
              word: widget.word,
              isFront: true,
              isHinted: false,
              elevated: true,
            ),
          ),
        );
      },
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
  });

  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onShuffle;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        color: GameColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(GameRadii.xl)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: PressableButton(
                label: 'تلميح',
                icon: Icons.lightbulb_rounded,
                gradient: GameGradients.orange,
                faceColor: GameColors.orange,
                edgeColor: GameColors.orangeDark,
                height: 54,
                onPressed: onHint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PressableButton(
                label: 'تراجع',
                icon: Icons.undo_rounded,
                gradient: canUndo ? GameGradients.blue : null,
                faceColor: GameColors.blue,
                edgeColor: GameColors.blueDark,
                height: 54,
                enabled: canUndo,
                onPressed: canUndo ? onUndo : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PressableButton(
                label: 'خلط',
                icon: Icons.shuffle_rounded,
                gradient: GameGradients.green,
                faceColor: GameColors.green,
                edgeColor: GameColors.greenDark,
                height: 54,
                onPressed: onShuffle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Victory sheet
// ---------------------------------------------------------------------------

/// Premium end-of-level screen: animated 3-star rating, coin reward, stats,
/// and replay / next / home actions.
class VictorySheet extends StatefulWidget {
  const VictorySheet({
    super.key,
    required this.stars,
    required this.levelNumber,
    required this.coinsEarned,
    required this.moves,
    required this.mistakes,
    required this.bestCombo,
    required this.elapsed,
    required this.isDaily,
    required this.showNext,
    required this.onReplay,
    required this.onNext,
    required this.onHome,
  });

  final int stars;
  final int levelNumber;
  final int coinsEarned;
  final int moves;
  final int mistakes;
  final int bestCombo;
  final Duration elapsed;
  final bool isDaily;
  final bool showNext;
  final VoidCallback onReplay;
  final VoidCallback onNext;
  final VoidCallback onHome;

  @override
  State<VictorySheet> createState() => _VictorySheetState();
}

class _VictorySheetState extends State<VictorySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _time {
    final m = widget.elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = widget.elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF1F6FA)],
        ),
        borderRadius: BorderRadius.circular(GameRadii.xl),
        boxShadow: GameShadows.lifted,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.isDaily ? 'تحدي اليوم مكتمل!' : 'رائع!',
            style: GameTextStyles.display
                .copyWith(fontSize: 30, color: GameColors.green),
          ),
          const SizedBox(height: 18),
          _StarsRow(stars: widget.stars, controller: _controller),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: GameGradients.gold,
              borderRadius: BorderRadius.circular(GameRadii.pill),
              boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text(
                  '+${widget.coinsEarned}',
                  style: GameTextStyles.title
                      .copyWith(color: Colors.white, fontSize: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(icon: Icons.timer_outlined, label: _time),
              _StatChip(icon: Icons.swipe_rounded, label: '${widget.moves}'),
              _StatChip(
                  icon: Icons.bolt_rounded, label: '×${widget.bestCombo}'),
              _StatChip(
                  icon: Icons.close_rounded, label: '${widget.mistakes}'),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.showNext)
            PressableButton(
              label: 'المستوى التالي',
              icon: Icons.arrow_back_rounded,
              gradient: GameGradients.green,
              height: 56,
              onPressed: widget.onNext,
            )
          else
            PressableButton(
              label: widget.isDaily ? 'رائع!' : 'العب من جديد',
              icon: Icons.check_rounded,
              gradient: GameGradients.green,
              height: 56,
              onPressed: widget.isDaily ? widget.onHome : widget.onNext,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PressableButton(
                  label: 'إعادة',
                  icon: Icons.replay_rounded,
                  gradient: GameGradients.blue,
                  faceColor: GameColors.blue,
                  edgeColor: GameColors.blueDark,
                  height: 50,
                  onPressed: widget.onReplay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PressableButton(
                  label: 'القائمة',
                  icon: Icons.home_rounded,
                  faceColor: GameColors.surface,
                  edgeColor: GameColors.borderDark,
                  textColor: GameColors.textPrimary,
                  height: 50,
                  onPressed: widget.onHome,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.stars, required this.controller});

  final int stars;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final earned = i < stars;
        final start = 0.15 + i * 0.22;
        final anim = CurvedAnimation(
          parent: controller,
          curve: Interval(start, (start + 0.35).clamp(0.0, 1.0),
              curve: Curves.elasticOut),
        );
        final isMiddle = i == 1;
        return ScaleTransition(
          scale: anim,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMiddle ? 4 : 10),
            child: Transform.translate(
              offset: Offset(0, isMiddle ? -12 : 0),
              child: Icon(
                earned ? Icons.star_rounded : Icons.star_outline_rounded,
                size: isMiddle ? 68 : 56,
                color: earned ? GameColors.gold : GameColors.border,
                shadows: earned
                    ? [
                        const Shadow(
                            color: Color(0x66E6A100),
                            blurRadius: 12,
                            offset: Offset(0, 4)),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: GameColors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: GameColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
