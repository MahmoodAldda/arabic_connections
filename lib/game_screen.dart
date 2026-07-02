import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'models.dart';
import 'services/hint_service.dart';
import 'services/player_service.dart';
import 'theme/game_theme.dart';
import 'widgets/confetti_burst.dart';
import 'widgets/pressable_button.dart';
import 'widgets/word_card.dart';

/// Main gameplay screen for Arabic Connections.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.session,
    required this.playerService,
  });

  final GameSession session;
  final PlayerService playerService;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const int _wordsPerGroup = 4;
  static const int _totalGroups = 4;

  late int _levelIndex;
  late List<WordItem> _remainingWords;
  int _gridGeneration = 0;
  final Set<String> _selectedIds = {};
  final List<_SolvedGroup> _solvedGroups = [];
  final Set<String> _revealedCategoryIds = {};
  final Set<String> _hintedWordIds = {};
  final HintService _hintService = HintService();
  String? _lastHintMessage;

  bool _showError = false;
  bool _isLevelComplete = false;
  bool _showConfetti = false;
  late AnimationController _shakeController;
  late AnimationController _successController;

  Level get _level => widget.session.activeLevel;
  Set<String> get _solvedCategoryIds =>
      _solvedGroups.map((g) => g.category.id).toSet();

  @override
  void initState() {
    super.initState();
    _levelIndex = widget.session.levelIndex
        .clamp(0, widget.session.levels.length - 1);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
    _successController.dispose();
    super.dispose();
  }

  void _initLevel() {
    setState(() {
      _remainingWords = _level.shuffledWords();
      _gridGeneration++;
      _selectedIds.clear();
      _solvedGroups.clear();
      _revealedCategoryIds.clear();
      _hintedWordIds.clear();
      _lastHintMessage = null;
      _showError = false;
      _isLevelComplete = false;
      _showConfetti = false;
    });
  }

  void _toggleWord(WordItem word) {
    if (_isLevelComplete) return;
    setState(() {
      if (_selectedIds.contains(word.id)) {
        _selectedIds.remove(word.id);
      } else if (_selectedIds.length < _wordsPerGroup) {
        _selectedIds.add(word.id);
      }
      _showError = false;
    });
  }

  GroupValidation _validateSelection() {
    if (_selectedIds.length != _wordsPerGroup) {
      return const GroupValidation(result: GroupCheckResult.wrongSelection);
    }

    final selected = _remainingWords
        .where((w) => _selectedIds.contains(w.id))
        .toList();

    final categoryIds = selected.map((w) => w.categoryId).toSet();
    if (categoryIds.length != 1) {
      return const GroupValidation(result: GroupCheckResult.wrongGroup);
    }

    final categoryId = categoryIds.first;
    if (_solvedGroups.any((g) => g.category.id == categoryId)) {
      return const GroupValidation(result: GroupCheckResult.wrongGroup);
    }

    return GroupValidation(
      result: GroupCheckResult.correct,
      matchedCategory: _level.categoryById(categoryId),
    );
  }

  Future<void> _checkGroup() async {
    final validation = _validateSelection();

    if (validation.result == GroupCheckResult.wrongSelection) {
      _showErrorFeedback('اختر ٤ كلمات أولاً');
      return;
    }

    if (!validation.isCorrect) {
      _showErrorFeedback('ليس صحيحاً — جرّب مرة أخرى!');
      return;
    }

    HapticFeedback.mediumImpact();
    await _successController.forward(from: 0);

    final category = validation.matchedCategory!;
    final solvedWords = _remainingWords
        .where((w) => _selectedIds.contains(w.id))
        .toList();

    setState(() {
      _solvedGroups.add(_SolvedGroup(category: category, words: solvedWords));
      _remainingWords.removeWhere((w) => _selectedIds.contains(w.id));
      _selectedIds.clear();
      _showError = false;
      _showConfetti = true;

      if (_solvedGroups.length == _totalGroups) {
        _isLevelComplete = true;
      }
    });

    if (_isLevelComplete) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      await _awardCompletion();
      if (!mounted) return;
      _showLevelCompleteSheet();
    }
  }

  Future<void> _awardCompletion() async {
    await widget.playerService.addCoins(widget.session.coinReward);
    if (widget.session.isDaily) {
      await widget.playerService.markDailyCompleted();
    }
  }

  Future<void> _showHintPicker() async {
    if (_isLevelComplete) return;

    final choice = await showModalBottomSheet<HintType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _HintPickerSheet(
        coins: widget.playerService.coins,
        categoryCost: GameEconomy.categoryHintCost,
        wordCost: GameEconomy.wordHintCost,
      ),
    );
    if (choice == null || !mounted) return;

    final cost = choice == HintType.category
        ? GameEconomy.categoryHintCost
        : GameEconomy.wordHintCost;

    if (widget.playerService.coins < cost) {
      _showErrorFeedback('لا تملك عملات كافية');
      return;
    }

    final HintResult? hint;
    if (choice == HintType.category) {
      hint = _hintService.categoryHint(_level, _solvedCategoryIds);
    } else {
      hint = _hintService.wordHint(
        _level,
        _solvedCategoryIds,
        _hintedWordIds,
        _remainingWords,
      );
    }

    if (hint == null) {
      _showErrorFeedback('لا توجد تلميحات متبقية');
      return;
    }

    final spent = await widget.playerService.spendCoins(cost);
    if (!spent || !mounted) return;

    setState(() {
      if (hint!.type == HintType.category) {
        _revealedCategoryIds.add(hint.categoryId);
        _lastHintMessage = 'الفئة: ${hint.categoryName}';
      } else {
        _hintedWordIds.add(hint.wordId!);
        _lastHintMessage = 'كلمة مميزة من فئة ${hint.categoryName}';
      }
    });

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_lastHintMessage!, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
          backgroundColor: GameColors.blue,
        ),
      );
  }

  void _showErrorFeedback(String message) {
    HapticFeedback.vibrate();
    setState(() => _showError = true);
    _shakeController.forward(from: 0);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showLevelCompleteSheet() {
    final isDaily = widget.session.isDaily;
    final isLastLevel = _levelIndex >= widget.session.levels.length - 1;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _LevelCompleteSheet(
        levelNumber: _level.number,
        coinsEarned: widget.session.coinReward,
        isDaily: isDaily,
        isLastLevel: isLastLevel,
        onContinue: () {
          Navigator.pop(context);
          if (isDaily) {
            Navigator.pop(context);
            return;
          }
          setState(() {
            if (isLastLevel) {
              _levelIndex = 0;
            } else {
              _levelIndex++;
            }
            _initLevel();
          });
        },
      ),
    );
  }

  void _restartLevel() {
    HapticFeedback.lightImpact();
    _initLevel();
  }

  void _goToLevel(int index) {
    if (widget.session.isDaily) return;
    if (index < 0 || index >= widget.session.levels.length) return;
    setState(() {
      _levelIndex = index;
      _initLevel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _GameBackground(),
          SafeArea(
            child: Column(
              children: [
                _GameHeader(
                  level: _level,
                  solvedCount: _solvedGroups.length,
                  total: _totalGroups,
                  coins: widget.playerService.coins,
                  isDaily: widget.session.isDaily,
                  onRestart: _restartLevel,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      children: [
                        if (_solvedGroups.isNotEmpty) ...[
                          Flexible(
                            child: _SolvedGroupsPanel(groups: _solvedGroups),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          flex: _solvedGroups.isEmpty ? 1 : 2,
                          child: AnimatedBuilder(
                            animation: _shakeController,
                            builder: (context, child) {
                              final shake = math.sin(
                                    _shakeController.value * math.pi * 4,
                                  ) *
                                  10 *
                                  _shakeController.value;
                              return Transform.translate(
                                offset: Offset(shake, 0),
                                child: child,
                              );
                            },
                            child: _WordGrid(
                              key: ValueKey('grid-$_gridGeneration'),
                              words: _remainingWords,
                              selectedIds: _selectedIds,
                              highlightedWordIds: _hintedWordIds,
                              hintMessage: _lastHintMessage,
                              showError: _showError,
                              onWordTap: _toggleWord,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _BottomPanel(
                  selectedCount: _selectedIds.length,
                  canCheck: _selectedIds.isNotEmpty && !_isLevelComplete,
                  readyToCheck: _selectedIds.length == _wordsPerGroup,
                  onCheck: _checkGroup,
                  onHint: _showHintPicker,
                  showLevelPicker: !widget.session.isDaily,
                  levels: widget.session.levels,
                  currentIndex: _levelIndex,
                  onLevelSelected: _goToLevel,
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

class _SolvedGroup {
  const _SolvedGroup({required this.category, required this.words});

  final Category category;
  final List<WordItem> words;
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

class _GameBackground extends StatelessWidget {
  const _GameBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8F9E0), GameColors.background, GameColors.background],
          stops: [0.0, 0.35, 1.0],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _GameHeader extends StatelessWidget {
  const _GameHeader({
    required this.level,
    required this.solvedCount,
    required this.total,
    required this.coins,
    required this.isDaily,
    required this.onRestart,
  });

  final Level level;
  final int solvedCount;
  final int total;
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
              _IconCircleButton(
                icon: Icons.refresh_rounded,
                onTap: onRestart,
                color: GameColors.orange,
                edgeColor: GameColors.orangeDark,
              ),
              const Spacer(),
              Column(
                children: [
                  if (isDaily)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: GameColors.blue,
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
                    style: GameTextStyles.title,
                  ),
                  if (!isDaily)
                    Text(level.title, style: GameTextStyles.subtitle),
                ],
              ),
              const Spacer(),
              _CoinBadge(count: coins),
            ],
          ),
          const SizedBox(height: 14),
          _SegmentedProgress(solved: solvedCount, total: total),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatefulWidget {
  const _IconCircleButton({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.edgeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color edgeColor;

  @override
  State<_IconCircleButton> createState() => _IconCircleButtonState();
}

class _IconCircleButtonState extends State<_IconCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 44,
        height: 44,
        transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
        decoration: GameDecorations.card(
          faceColor: widget.color,
          edgeColor: widget.edgeColor,
          radius: 14,
        ),
        child: Icon(widget.icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _CoinBadge extends StatelessWidget {
  const _CoinBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: GameDecorations.card(
        faceColor: const Color(0xFFFFF8E1),
        edgeColor: const Color(0xFFFFC800),
        radius: 14,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFC800), size: 22),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFFE6A800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.solved, required this.total});

  final int solved;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i < solved;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              height: 14,
              decoration: BoxDecoration(
                color: filled ? GameColors.green : GameColors.border,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  bottom: BorderSide(
                    color: filled ? GameColors.greenDark : GameColors.borderDark,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Solved groups
// ---------------------------------------------------------------------------

class _SolvedGroupsPanel extends StatelessWidget {
  const _SolvedGroupsPanel({required this.groups});

  final List<_SolvedGroup> groups;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final group = groups[index];
        return TweenAnimationBuilder<double>(
          key: ValueKey(group.category.id),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
          child: _LockedGroupCard(group: group),
        );
      },
    );
  }
}

class _LockedGroupCard extends StatelessWidget {
  const _LockedGroupCard({required this.group});

  final _SolvedGroup group;

  Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final edge = _darken(group.category.color);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: GameDecorations.card(
        faceColor: group.category.color,
        edgeColor: edge,
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                group.category.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: group.words.map((w) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  w.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Word grid
// ---------------------------------------------------------------------------

class _WordGrid extends StatelessWidget {
  const _WordGrid({
    super.key,
    required this.words,
    required this.selectedIds,
    required this.highlightedWordIds,
    this.hintMessage,
    required this.showError,
    required this.onWordTap,
  });

  final List<WordItem> words;
  final Set<String> selectedIds;
  final Set<String> highlightedWordIds;
  final String? hintMessage;
  final bool showError;
  final ValueChanged<WordItem> onWordTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: GameDecorations.panel(),
      child: Column(
        children: [
          if (hintMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: GameColors.blueLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GameColors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_rounded, color: GameColors.blueDark, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hintMessage!,
                      style: const TextStyle(
                        color: GameColors.blueDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: words.length,
              itemBuilder: (context, index) {
                final word = words[index];
                return WordCard(
                  key: ValueKey(word.id),
                  word: word,
                  isSelected: selectedIds.contains(word.id),
                  isHighlighted: highlightedWordIds.contains(word.id),
                  showError: showError && selectedIds.contains(word.id),
                  entranceDelay: Duration(milliseconds: 40 * index),
                  onTap: () => onWordTap(word),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom panel
// ---------------------------------------------------------------------------

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.selectedCount,
    required this.canCheck,
    required this.readyToCheck,
    required this.onCheck,
    required this.onHint,
    required this.showLevelPicker,
    required this.levels,
    required this.currentIndex,
    required this.onLevelSelected,
  });

  final int selectedCount;
  final bool canCheck;
  final bool readyToCheck;
  final VoidCallback onCheck;
  final VoidCallback onHint;
  final bool showLevelPicker;
  final List<Level> levels;
  final int currentIndex;
  final ValueChanged<int> onLevelSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        color: GameColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: GameColors.shadow,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectionDots(count: selectedCount),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PressableButton(
                  label: 'تلميح',
                  icon: Icons.lightbulb_outline_rounded,
                  faceColor: GameColors.orange,
                  edgeColor: GameColors.orangeDark,
                  height: 50,
                  onPressed: onHint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PressableButton(
                  label: 'تحقق',
                  icon: Icons.bolt_rounded,
                  enabled: canCheck,
                  pulseWhenReady: readyToCheck,
                  height: 50,
                  onPressed: canCheck ? onCheck : null,
                ),
              ),
            ],
          ),
          if (showLevelPicker) ...[
            const SizedBox(height: 14),
            _LevelPath(
              levels: levels,
              currentIndex: currentIndex,
              onLevelSelected: onLevelSelected,
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionDots extends StatelessWidget {
  const _SelectionDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < count;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.elasticOut,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: filled ? 32 : 14,
          height: 14,
          decoration: BoxDecoration(
            color: filled ? GameColors.blue : GameColors.border,
            borderRadius: BorderRadius.circular(7),
            border: Border(
              bottom: BorderSide(
                color: filled ? GameColors.blueDark : GameColors.borderDark,
                width: 3,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _LevelPath extends StatelessWidget {
  const _LevelPath({
    required this.levels,
    required this.currentIndex,
    required this.onLevelSelected,
  });

  final List<Level> levels;
  final int currentIndex;
  final ValueChanged<int> onLevelSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(levels.length, (index) {
        final isActive = index == currentIndex;
        final isPast = index < currentIndex;
        final nodeColor = isActive
            ? GameColors.green
            : isPast
                ? GameColors.blue
                : GameColors.border;
        final edgeColor = isActive
            ? GameColors.greenDark
            : isPast
                ? GameColors.blueDark
                : GameColors.borderDark;

        return Row(
          children: [
            GestureDetector(
              onTap: () => onLevelSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isActive ? 42 : 36,
                height: isActive ? 42 : 36,
                decoration: GameDecorations.card(
                  faceColor: nodeColor,
                  edgeColor: edgeColor,
                  radius: 12,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${levels[index].number}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isActive ? 16 : 14,
                    color: isActive || isPast ? Colors.white : GameColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (index < levels.length - 1)
              Container(
                width: 24,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: index < currentIndex ? GameColors.blue : GameColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Level complete sheet
// ---------------------------------------------------------------------------

class _LevelCompleteSheet extends StatefulWidget {
  const _LevelCompleteSheet({
    required this.levelNumber,
    required this.coinsEarned,
    required this.isDaily,
    required this.isLastLevel,
    required this.onContinue,
  });

  final int levelNumber;
  final int coinsEarned;
  final bool isDaily;
  final bool isLastLevel;
  final VoidCallback onContinue;

  @override
  State<_LevelCompleteSheet> createState() => _LevelCompleteSheetState();
}

class _LevelCompleteSheetState extends State<_LevelCompleteSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bounce = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: GameDecorations.panel(color: GameColors.surface),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _bounce,
            child: Container(
              width: 88,
              height: 88,
              decoration: GameDecorations.card(
                faceColor: GameColors.green,
                edgeColor: GameColors.greenDark,
                radius: 44,
              ),
              child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.isDaily ? 'تحدي اليوم مكتمل!' : 'رائع!',
            style: GameTextStyles.title.copyWith(fontSize: 28, color: GameColors.green),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isDaily
                ? 'حصلت على ${widget.coinsEarned} عملة'
                : 'أكملت المستوى ${widget.levelNumber} (+${widget.coinsEarned} عملة)',
            style: GameTextStyles.subtitle.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PressableButton(
            label: widget.isDaily
                ? 'العودة للقائمة'
                : widget.isLastLevel
                    ? 'العب من جديد'
                    : 'المستوى التالي',
            icon: Icons.arrow_back_rounded,
            onPressed: widget.onContinue,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint picker
// ---------------------------------------------------------------------------

class _HintPickerSheet extends StatelessWidget {
  const _HintPickerSheet({
    required this.coins,
    required this.categoryCost,
    required this.wordCost,
  });

  final int coins;
  final int categoryCost;
  final int wordCost;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: GameDecorations.panel(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('اختر تلميحاً', style: GameTextStyles.title.copyWith(fontSize: 20)),
          const SizedBox(height: 6),
          Text('رصيدك: $coins عملة', style: GameTextStyles.subtitle),
          const SizedBox(height: 20),
          _HintOption(
            title: 'كشف الفئة',
            subtitle: 'يعرض اسم إحدى الفئات المتبقية',
            cost: categoryCost,
            icon: Icons.category_rounded,
            color: GameColors.purple,
            edgeColor: const Color(0xFF9B59B6),
            enabled: coins >= categoryCost,
            onTap: () => Navigator.pop(context, HintType.category),
          ),
          const SizedBox(height: 12),
          _HintOption(
            title: 'تمييز كلمة',
            subtitle: 'يُبرز كلمة من فئة غير محلولة',
            cost: wordCost,
            icon: Icons.highlight_rounded,
            color: GameColors.orange,
            edgeColor: GameColors.orangeDark,
            enabled: coins >= wordCost,
            onTap: () => Navigator.pop(context, HintType.word),
          ),
        ],
      ),
    );
  }
}

class _HintOption extends StatelessWidget {
  const _HintOption({
    required this.title,
    required this.subtitle,
    required this.cost,
    required this.icon,
    required this.color,
    required this.edgeColor,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int cost;
  final IconData icon;
  final Color color;
  final Color edgeColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: GameDecorations.card(
            faceColor: color.withValues(alpha: 0.12),
            edgeColor: enabled ? edgeColor : GameColors.borderDark,
            radius: 16,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: GameDecorations.card(
                  faceColor: color,
                  edgeColor: edgeColor,
                  radius: 12,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(subtitle, style: GameTextStyles.subtitle.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFC800), size: 18),
                  Text(' $cost', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
