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

/// Identifies a playable card and where it came from.
class _CardRef {
  const _CardRef(this.source, this.column, this.word);

  final CardSource source;
  final int column; // tableau column, or -1 for the waste
  final WordItem word;
}

/// Premium Klondike-style word-solitaire board: a face-down stock you draw into
/// a waste pile, staircase tableau columns with decorative card backs, and four
/// category foundations that cards fly into. Game logic lives in
/// [SolitaireEngine].
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
      List.generate(kTableauColumns, (_) => GlobalKey());
  final Map<String, GlobalKey> _cardKeys = {};
  final GlobalKey _coinKey = GlobalKey();
  final GlobalKey _wasteKey = GlobalKey();

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
      duration: const Duration(milliseconds: 1000),
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

  void _initLevel({bool showIntro = false}) {
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
    if (showIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLevelIntro());
    }
  }

  void _showLevelIntro() {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _LevelIntro(
        text: widget.session.isDaily ? _level.title : 'المستوى ${_level.number}',
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  void _flyCoinsToBadge() {
    final badgeCtx = _coinKey.currentContext;
    if (badgeCtx == null) return;
    final box = badgeCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final target = box.localToGlobal(box.size.center(Offset.zero));
    final screen = MediaQuery.of(context).size;
    final origin = Offset(screen.width / 2, screen.height * 0.5);
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoinFly(
        origin: origin,
        target: target,
        count: 12,
        onDone: () {
          entry.remove();
          _sound.play(SoundFx.coins);
        },
      ),
    );
    overlay.insert(entry);
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

  /// Tap-to-place: the card flies (and flips) from its source to a foundation.
  void _tapPlace(_CardRef ref) {
    if (_isComplete || _flyingWordId != null) return;
    final target = _findTarget(ref.word);
    if (target == -1) {
      _sound.play(SoundFx.wrong);
      _rejectFeedback();
      return;
    }
    final srcKey =
        ref.source == CardSource.waste ? _wasteKey : _cardKey(ref.word.id);
    final src = _rectFor(srcKey);
    final dst = _rectFor(_foundationKeys[target]);
    if (src == null || dst == null) {
      _commitPlace(ref, target);
      return;
    }
    _sound.play(SoundFx.cardTap);
    setState(() => _flyingWordId = ref.word.id);
    _spawnFlyingCard(ref.word, src, dst, () {
      if (!mounted) return;
      setState(() => _flyingWordId = null);
      _commitPlace(ref, target);
    });
  }

  void _onDragAccept(_CardRef ref, int foundationIndex) {
    if (_isComplete) return;
    _commitPlace(ref, foundationIndex);
  }

  void _commitPlace(_CardRef ref, int foundationIndex) {
    final result = ref.source == CardSource.waste
        ? _engine.playFromWaste(foundationIndex)
        : _engine.playFromTableau(ref.column, foundationIndex);
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

  void _drawStock() {
    if (_isComplete || _flyingWordId != null) return;
    if (_engine.drawFromStock()) {
      _sound.play(SoundFx.cardTap);
      _haptic(HapticFeedback.selectionClick);
      setState(() => _hintedWordId = null);
    }
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
      _showSnack('اسحب من مجموعة الأوراق');
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
          _flyCoinsToBadge();
        },
        onNext: () {
          Navigator.pop(context);
          setState(() => _levelIndex = isLastLevel ? 0 : _levelIndex + 1);
          _initLevel(showIntro: true);
          _flyCoinsToBadge();
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
                  total: kTableauColumns,
                  coins: widget.playerService.coins,
                  isDaily: widget.session.isDaily,
                  coinKey: _coinKey,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Column(
                      children: [
                        _FoundationsRow(
                          foundations: _engine.foundations,
                          level: _level,
                          flashIndex: _flashFoundationIndex,
                          slotKeys: _foundationKeys,
                          canAccept: (ref, i) => _engine.canPlace(ref.word, i),
                          onAccept: _onDragAccept,
                        ),
                        const SizedBox(height: 8),
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
                              onTapTop: _tapPlace,
                              onDragStarted: () => _sound.play(SoundFx.cardTap),
                              enabled: !_isComplete,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StockWasteBar(
                          stockCount: _engine.stockCount,
                          wasteTop: _engine.wasteTop,
                          wasteKey: _wasteKey,
                          flyingWordId: _flyingWordId,
                          hintedWordId: _hintedWordId,
                          canUndo: _engine.canUndo,
                          enabled: !_isComplete,
                          onDrawStock: _drawStock,
                          onTapWaste: _tapPlace,
                          onWasteDragStarted: () =>
                              _sound.play(SoundFx.cardTap),
                          onHint: _hint,
                          onUndo: _undo,
                          onShuffle: _shuffle,
                        ),
                      ],
                    ),
                  ),
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
    required this.onBack,
    required this.coinKey,
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
  final VoidCallback onBack;
  final GlobalKey coinKey;

  String get _time {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: GlassContainer(
        radius: GameRadii.xl,
        blur: 18,
        tintOpacity: 0.18,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (isDaily)
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(GameRadii.pill),
                          ),
                          child: const Text(
                            'تحدي اليوم',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
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
                          letterSpacing: 0.3,
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
                AnimatedCoinBadge(key: coinKey, count: coins),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MiniStat(icon: Icons.timer_outlined, label: _time),
                _MiniStat(icon: Icons.swipe_rounded, label: '$moves'),
                _MiniStat(
                  icon: Icons.bolt_rounded,
                  label: '×$bestCombo',
                  tint: GameColors.gold,
                ),
                _MiniStat(
                  icon: Icons.close_rounded,
                  label: '$mistakes',
                  tint: mistakes > 0 ? GameColors.red : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LevelProgressBar(value: total == 0 ? 0 : completed / total),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatefulWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 17),
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
          height: 11,
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
  final bool Function(_CardRef ref, int index) canAccept;
  final void Function(_CardRef ref, int index) onAccept;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(foundations.length, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
            child: DragTarget<_CardRef>(
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
    with TickerProviderStateMixin {
  late final AnimationController _bounce;
  late final AnimationController _shimmer;

  static const double _slotHeight = 82;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.foundation.isComplete) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(_FoundationSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.foundation.cards.length > oldWidget.foundation.cards.length) {
      _bounce.forward(from: 0);
    }
    if (widget.foundation.isComplete && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!widget.foundation.isComplete && _shimmer.isAnimating) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, child) {
        final pop = 1 + math.sin(_bounce.value * math.pi) * 0.14;
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

    if (category == null) return _emptySlot();
    if (foundation.isComplete) return _completedSlot(category);
    return _inProgressSlot(category, foundation);
  }

  Widget _emptySlot() {
    final borderColor = widget.invalidHover
        ? GameColors.red
        : Colors.white.withValues(alpha: widget.highlighted ? 0.95 : 0.45);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: _slotHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: widget.highlighted ? 0.30 : 0.13),
            Colors.white.withValues(alpha: widget.highlighted ? 0.16 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: borderColor,
          width: widget.highlighted || widget.invalidHover ? 2.5 : 1.5,
        ),
        boxShadow: widget.highlighted
            ? GameShadows.glow(Colors.white, opacity: 0.4)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded,
              color: Colors.white.withValues(alpha: 0.85), size: 22),
          const SizedBox(height: 2),
          Text(
            'ضع هنا',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inProgressSlot(Category category, Foundation foundation) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: _slotHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        gradient: GameGradients.fromColor(category.color),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: widget.invalidHover
              ? GameColors.red
              : (widget.highlighted
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4)),
          width: widget.highlighted || widget.invalidHover ? 2.5 : 1,
        ),
        boxShadow: GameShadows.card,
      ),
      child: _slotContent(
        name: category.name,
        badge: '${foundation.cards.length}/$kCardsPerCategory',
        gold: false,
      ),
    );
  }

  Widget _completedSlot(Category category) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final glow = 0.42 + math.sin(_shimmer.value * math.pi * 2) * 0.22;
        return Container(
          height: _slotHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            gradient: GameGradients.gold,
            borderRadius: BorderRadius.circular(GameRadii.md),
            border: Border.all(color: const Color(0xFFFFF1C2), width: 2),
            boxShadow: GameShadows.glow(GameColors.gold, opacity: glow),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(GameRadii.md - 2),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _ShimmerPainter(_shimmer.value)),
                ),
                Center(child: child),
              ],
            ),
          ),
        );
      },
      child: _slotContent(name: category.name, badge: 'مكتمل', gold: true),
    );
  }

  Widget _slotContent({
    required String name,
    required String badge,
    required bool gold,
  }) {
    final onColor = gold ? const Color(0xFF6E4A00) : Colors.white;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (gold) ...[
          Icon(Icons.emoji_events_rounded, color: onColor, size: 18),
          const SizedBox(height: 2),
        ],
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: onColor,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            height: 1.1,
            shadows: gold
                ? null
                : const [
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
            color: Colors.white.withValues(alpha: gold ? 0.55 : 0.3),
            borderRadius: BorderRadius.circular(GameRadii.pill),
          ),
          child: Text(
            gold ? 'مكتمل ✓' : badge,
            style: TextStyle(
              color: onColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// A diagonal light band that sweeps across completed (gold) foundations.
class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = (t * 1.8 - 0.4) * size.width;
    final bandWidth = size.width * 0.45;
    final rect = Rect.fromLTWH(
        dx - bandWidth / 2, -size.height, bandWidth, size.height * 3);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas
      ..save()
      ..translate(dx, 0)
      ..rotate(0.35)
      ..translate(-dx, 0)
      ..drawRect(rect, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) => oldDelegate.t != t;
}
// ---------------------------------------------------------------------------
// Tableau (staircase columns of overlapping cards)
// ---------------------------------------------------------------------------

class _Tableau extends StatelessWidget {
  const _Tableau({
    super.key,
    required this.columns,
    required this.hintedWordId,
    required this.flyingWordId,
    required this.dealAnimation,
    required this.cardKeyFor,
    required this.onTapTop,
    required this.onDragStarted,
    required this.enabled,
  });

  final List<List<TableauCard>> columns;
  final String? hintedWordId;
  final String? flyingWordId;
  final Animation<double> dealAnimation;
  final GlobalKey Function(String id) cardKeyFor;
  final ValueChanged<_CardRef> onTapTop;
  final VoidCallback onDragStarted;
  final bool enabled;

  static const int _maxStack = 4; // longest column in the 1-2-3-4 deal

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final maxH = constraints.maxHeight;
        final cardWidth =
            (constraints.maxWidth - gap * (columns.length - 1)) / columns.length;

        var cardHeight = cardWidth * 1.42;
        var peek = (maxH - cardHeight) / (_maxStack - 1);
        peek = peek.clamp(cardHeight * 0.22, cardHeight * 0.40);
        var columnHeight = cardHeight + peek * (_maxStack - 1);
        if (columnHeight > maxH) {
          final scale = maxH / columnHeight;
          cardHeight *= scale;
          peek *= scale;
          columnHeight = maxH;
        }

        var globalIndex = 0;
        return Align(
          alignment: Alignment.topCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(columns.length, (i) {
              final baseIndex = globalIndex;
              globalIndex += columns[i].length;
              final column = columns[i];
              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child: SizedBox(
                  width: cardWidth,
                  height: columnHeight,
                  child: column.isEmpty
                      ? _EmptyColumnSlot(height: cardHeight)
                      : Stack(
                          clipBehavior: Clip.none,
                          children: List.generate(column.length, (index) {
                            final card = column[index];
                            final isTop = index == column.length - 1;
                            return Positioned(
                              key: ValueKey(card.word.id),
                              top: index * peek,
                              left: 0,
                              right: 0,
                              child: _TableauCardWidget(
                                card: card,
                                faceUp: card.faceUp,
                                column: i,
                                isTop: isTop,
                                boxKey: isTop ? cardKeyFor(card.word.id) : null,
                                width: cardWidth,
                                height: cardHeight,
                                isHinted: card.word.id == hintedWordId,
                                isFlying: card.word.id == flyingWordId,
                                entranceIndex: baseIndex + index,
                                dealAnimation: dealAnimation,
                                onTapTop: onTapTop,
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
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.4,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.check_circle_outline_rounded,
          color: Colors.white.withValues(alpha: 0.3),
          size: 22,
        ),
      ),
    );
  }
}

class _TableauCardWidget extends StatefulWidget {
  const _TableauCardWidget({
    required this.card,
    required this.faceUp,
    required this.column,
    required this.isTop,
    required this.boxKey,
    required this.width,
    required this.height,
    required this.isHinted,
    required this.isFlying,
    required this.entranceIndex,
    required this.dealAnimation,
    required this.onTapTop,
    required this.onDragStarted,
    required this.enabled,
  });

  final TableauCard card;

  /// Captured by value so a reveal (false → true) can be detected in
  /// [State.didUpdateWidget] even though the underlying [TableauCard] is mutated
  /// in place by the engine.
  final bool faceUp;
  final int column;
  final bool isTop;
  final GlobalKey? boxKey;
  final double width;
  final double height;
  final bool isHinted;
  final bool isFlying;
  final int entranceIndex;
  final Animation<double> dealAnimation;
  final ValueChanged<_CardRef> onTapTop;
  final VoidCallback onDragStarted;
  final bool enabled;

  @override
  State<_TableauCardWidget> createState() => _TableauCardWidgetState();
}

class _TableauCardWidgetState extends State<_TableauCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1, // already resolved (no flip in progress)
    );
  }

  @override
  void didUpdateWidget(_TableauCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A previously hidden card was just revealed → play a flip.
    if (!oldWidget.faceUp && widget.faceUp) {
      _flip.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sized = SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) => _flipFace(),
      ),
    );

    if (widget.isFlying) {
      return Opacity(opacity: 0, child: sized);
    }

    final interactive = widget.isTop && widget.faceUp && widget.enabled;

    Widget content = sized;
    if (interactive) {
      final ref =
          _CardRef(CardSource.tableau, widget.column, widget.card.word);
      content = Draggable<_CardRef>(
        data: ref,
        dragAnchorStrategy: childDragAnchorStrategy,
        onDragStarted: widget.onDragStarted,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: _CardFace(
              word: widget.card.word,
              isFront: true,
              isHinted: widget.isHinted,
              elevated: true,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.28, child: sized),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTapTop(ref);
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: KeyedSubtree(key: widget.boxKey, child: sized),
        ),
      );
      content = AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: content,
      );
    }

    return AnimatedBuilder(
      animation: widget.dealAnimation,
      builder: (context, child) {
        final start = (widget.entranceIndex / 30).clamp(0.0, 0.6);
        final v = widget.dealAnimation.value;
        final local = ((v - start) / 0.4).clamp(0.0, 1.0);
        final scale = 0.72 + Curves.easeOutBack.transform(local) * 0.28;
        final opacity = Curves.easeOut.transform(local);
        final dy = (1 - local) * -26; // cards settle downward into place
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: content,
    );
  }

  Widget _flipFace() {
    final flipping = _flip.value < 1.0 && widget.faceUp;
    if (!flipping) {
      return widget.faceUp
          ? _CardFace(
              word: widget.card.word,
              isFront: true,
              isHinted: widget.isHinted,
            )
          : const _CardBack();
    }
    final t = _flip.value;
    final angle = (1 - t) * math.pi;
    final showBack = t < 0.5;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateY(angle),
      child: showBack
          ? const _CardBack()
          : _CardFace(
              word: widget.card.word,
              isFront: true,
              isHinted: widget.isHinted,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium green/gold card back
// ---------------------------------------------------------------------------

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GameRadii.md),
        boxShadow: const [
          BoxShadow(
              color: Color(0x330B1B2B),
              blurRadius: 8,
              offset: Offset(0, 4),
              spreadRadius: -2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GameRadii.md),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF12633A), Color(0xFF063D22)],
            ),
            border: Border.all(color: const Color(0xFFE9C25A), width: 1.6),
            borderRadius: BorderRadius.circular(GameRadii.md),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _CardBackPainter()),
              // Center emblem: a gold diamond with a small star.
              Center(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: GameGradients.gold,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: const Color(0xFFFFF1C2), width: 1.2),
                      boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.4),
                    ),
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: const Icon(Icons.star_rounded,
                          size: 15, color: Color(0xFF6E4A00)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a subtle gold diagonal lattice + inset frame on the card back.
class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x33E9C25A)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const step = 12.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    final frame = Paint()
      ..color = const Color(0x55E9C25A)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final inset = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      const Radius.circular(6),
    );
    canvas.drawRRect(inset, frame);
  }

  @override
  bool shouldRepaint(_CardBackPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Card face
// ---------------------------------------------------------------------------

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
      borderColor = Colors.white.withValues(alpha: 0.7);
      textColor = Colors.white;
    } else {
      gradient = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FA), Color(0xFFE7EDF4)],
        stops: [0.0, 0.55, 1.0],
      );
      borderColor = Colors.white;
      textColor = GameColors.textPrimary;
    }

    final List<BoxShadow> shadows;
    if (isHinted) {
      shadows = GameShadows.glow(GameColors.orange, opacity: 0.55);
    } else if (elevated) {
      shadows = const [
        BoxShadow(
            color: Color(0x4D0B1B2B),
            blurRadius: 28,
            offset: Offset(0, 18),
            spreadRadius: -2),
        BoxShadow(
            color: Color(0x1A0B1B2B), blurRadius: 6, offset: Offset(0, 2)),
      ];
    } else {
      shadows = const [
        BoxShadow(
            color: Color(0x2E0B1B2B),
            blurRadius: 14,
            offset: Offset(0, 8),
            spreadRadius: -3),
        BoxShadow(
            color: Color(0x140B1B2B), blurRadius: 3, offset: Offset(0, 1)),
      ];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GameRadii.md),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GameRadii.md),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(GameRadii.md),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.45],
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: GameGradients.cardSheen),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.06),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Center(
                  child: Text(
                    word.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GameTextStyles.cardLabel.copyWith(
                      color: textColor,
                      fontSize: 14,
                      height: 1.15,
                      letterSpacing: 0.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Stock + waste + actions (bottom zone)
// ---------------------------------------------------------------------------

class _StockWasteBar extends StatelessWidget {
  const _StockWasteBar({
    required this.stockCount,
    required this.wasteTop,
    required this.wasteKey,
    required this.flyingWordId,
    required this.hintedWordId,
    required this.canUndo,
    required this.enabled,
    required this.onDrawStock,
    required this.onTapWaste,
    required this.onWasteDragStarted,
    required this.onHint,
    required this.onUndo,
    required this.onShuffle,
  });

  final int stockCount;
  final WordItem? wasteTop;
  final GlobalKey wasteKey;
  final String? flyingWordId;
  final String? hintedWordId;
  final bool canUndo;
  final bool enabled;
  final VoidCallback onDrawStock;
  final ValueChanged<_CardRef> onTapWaste;
  final VoidCallback onWasteDragStarted;
  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardW = (constraints.maxWidth * 0.155).clamp(46.0, 64.0);
        final cardH = cardW * 1.4;
        return SizedBox(
          height: cardH + 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StockPile(
                count: stockCount,
                width: cardW,
                height: cardH,
                enabled: enabled,
                onTap: onDrawStock,
              ),
              const SizedBox(width: 10),
              _WastePile(
                key: ValueKey('waste-${wasteTop?.id ?? 'empty'}'),
                boxKey: wasteKey,
                word: wasteTop,
                width: cardW,
                height: cardH,
                isHinted: wasteTop != null && wasteTop!.id == hintedWordId,
                isFlying: wasteTop != null && wasteTop!.id == flyingWordId,
                enabled: enabled,
                onTap: onTapWaste,
                onDragStarted: onWasteDragStarted,
              ),
              const Spacer(),
              _RoundAction(
                icon: Icons.lightbulb_rounded,
                gradient: GameGradients.orange,
                enabled: enabled,
                onTap: onHint,
              ),
              const SizedBox(width: 8),
              _RoundAction(
                icon: Icons.undo_rounded,
                gradient: GameGradients.blue,
                enabled: enabled && canUndo,
                onTap: onUndo,
              ),
              const SizedBox(width: 8),
              _RoundAction(
                icon: Icons.shuffle_rounded,
                gradient: GameGradients.green,
                enabled: enabled,
                onTap: onShuffle,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockPile extends StatelessWidget {
  const _StockPile({
    required this.count,
    required this.width,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  final int count;
  final double width;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layers = count == 0 ? 1 : math.min(count, 3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width + 6,
        height: height + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (count == 0)
              Positioned(
                left: 3,
                top: 3,
                child: _StockEmpty(width: width, height: height),
              )
            else ...[
              for (var i = layers - 1; i >= 0; i--)
                Positioned(
                  left: 3.0 + i * 2.0,
                  top: 3.0 - i * 2.0,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: const _CardBack(),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF063D22),
                    borderRadius: BorderRadius.circular(GameRadii.pill),
                    border:
                        Border.all(color: const Color(0xFFE9C25A), width: 1),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Color(0xFFE9C25A),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockEmpty extends StatelessWidget {
  const _StockEmpty({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: const Color(0xFFE9C25A).withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
      child: Icon(
        Icons.refresh_rounded,
        color: const Color(0xFFE9C25A).withValues(alpha: 0.85),
        size: 24,
      ),
    );
  }
}

class _WastePile extends StatefulWidget {
  const _WastePile({
    super.key,
    required this.boxKey,
    required this.word,
    required this.width,
    required this.height,
    required this.isHinted,
    required this.isFlying,
    required this.enabled,
    required this.onTap,
    required this.onDragStarted,
  });

  final GlobalKey boxKey;
  final WordItem? word;
  final double width;
  final double height;
  final bool isHinted;
  final bool isFlying;
  final bool enabled;
  final ValueChanged<_CardRef> onTap;
  final VoidCallback onDragStarted;

  @override
  State<_WastePile> createState() => _WastePileState();
}

class _WastePileState extends State<_WastePile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.word != null) _in.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.word == null) {
      return _emptySlot();
    }
    final word = widget.word!;
    final face = SizedBox(
      width: widget.width,
      height: widget.height,
      child: _CardFace(word: word, isFront: true, isHinted: widget.isHinted),
    );

    if (widget.isFlying) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Opacity(opacity: 0, child: face),
      );
    }

    final ref = _CardRef(CardSource.waste, -1, word);
    Widget child = Draggable<_CardRef>(
      data: ref,
      dragAnchorStrategy: childDragAnchorStrategy,
      onDragStarted: widget.onDragStarted,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: _CardFace(
            word: word,
            isFront: true,
            isHinted: widget.isHinted,
            elevated: true,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: face),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          if (widget.enabled) widget.onTap(ref);
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: KeyedSubtree(key: widget.boxKey, child: face),
      ),
    );

    child = AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: child,
    );

    return AnimatedBuilder(
      animation: _in,
      builder: (context, inner) {
        final t = Curves.easeOutCubic.transform(_in.value);
        final angle = (1 - t) * math.pi; // flips in from the stock
        final showFace = t >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFace
              ? inner
              : SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: const _CardBack(),
                ),
        );
      },
      child: child,
    );
  }

  Widget _emptySlot() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GameRadii.md),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.4,
        ),
      ),
    );
  }
}

class _RoundAction extends StatefulWidget {
  const _RoundAction({
    required this.icon,
    required this.gradient,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Gradient gradient;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RoundAction> createState() => _RoundActionState();
}

class _RoundActionState extends State<_RoundAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: widget.gradient,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 22),
          ),
        ),
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
        final arc = -math.sin(t * math.pi) * 46;
        final flip = t * math.pi * 2;
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
              pulseWhenReady: true,
              onPressed: widget.onNext,
            )
          else
            PressableButton(
              label: widget.isDaily ? 'رائع!' : 'العب من جديد',
              icon: Icons.check_rounded,
              gradient: GameGradients.green,
              height: 56,
              pulseWhenReady: true,
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

// ---------------------------------------------------------------------------
// Coin-fly reward animation
// ---------------------------------------------------------------------------

class _CoinFly extends StatefulWidget {
  const _CoinFly({
    required this.origin,
    required this.target,
    required this.count,
    required this.onDone,
  });

  final Offset origin;
  final Offset target;
  final int count;
  final VoidCallback onDone;

  @override
  State<_CoinFly> createState() => _CoinFlyState();
}

class _CoinFlyState extends State<_CoinFly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Offset> _controls;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward().then((_) => widget.onDone());
    final mid = Offset(
      (widget.origin.dx + widget.target.dx) / 2,
      (widget.origin.dy + widget.target.dy) / 2,
    );
    _controls = List.generate(
      widget.count,
      (_) => mid +
          Offset((_rng.nextDouble() - 0.5) * 220,
              (_rng.nextDouble() - 0.5) * 150 - 40),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _bezier(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final children = <Widget>[];
          for (var i = 0; i < widget.count; i++) {
            final start = (i / widget.count) * 0.3;
            final local = ((_controller.value - start) / 0.7).clamp(0.0, 1.0);
            if (local >= 1) continue;
            final t = Curves.easeInOutCubic.transform(local);
            final pos = _bezier(widget.origin, _controls[i], widget.target, t);
            final scale = (local < 0.2 ? local / 0.2 : 1.0) * (1 - local * 0.25);
            final opacity = local >= 0.88 ? (1 - (local - 0.88) / 0.12) : 1.0;
            children.add(Positioned(
              left: pos.dx - 14,
              top: pos.dy - 14,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(scale: scale, child: _coin()),
              ),
            ));
          }
          return Stack(children: children);
        },
      ),
    );
  }

  Widget _coin() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: GameGradients.gold,
        shape: BoxShape.circle,
        boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.6),
      ),
      child: const Icon(Icons.monetization_on_rounded,
          color: Color(0xFF7A5200), size: 20),
    );
  }
}

// ---------------------------------------------------------------------------
// Level intro banner
// ---------------------------------------------------------------------------

class _LevelIntro extends StatefulWidget {
  const _LevelIntro({required this.text, required this.onDone});

  final String text;
  final VoidCallback onDone;

  @override
  State<_LevelIntro> createState() => _LevelIntroState();
}

class _LevelIntroState extends State<_LevelIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = _controller.value;
          double opacity;
          double dx;
          if (v < 0.2) {
            final t = Curves.easeOut.transform(v / 0.2);
            opacity = t;
            dx = (1 - t) * 70;
          } else if (v > 0.8) {
            final t = (v - 0.8) / 0.2;
            opacity = 1 - t;
            dx = -t * 50;
          } else {
            opacity = 1;
            dx = 0;
          }
          return Center(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: _banner(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
      decoration: BoxDecoration(
        gradient: GameGradients.gold,
        borderRadius: BorderRadius.circular(GameRadii.xl),
        boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.6),
      ),
      child: Text(
        widget.text,
        style: GameTextStyles.display
            .copyWith(color: const Color(0xFF6E4A00), fontSize: 30),
      ),
    );
  }
}




