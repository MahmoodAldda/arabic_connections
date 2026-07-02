import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'game_screen.dart';
import 'models.dart';
import 'services/ad_service.dart';
import 'services/daily_challenge_service.dart';
import 'services/level_api_service.dart';
import 'services/player_service.dart';
import 'theme/game_theme.dart';
import 'widgets/pressable_button.dart';

/// Main menu — daily challenge, classic play, coins, and rewarded ads.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.playerService,
    required this.levelApiService,
    required this.adService,
    required this.dailyChallengeService,
  });

  final PlayerService playerService;
  final LevelApiService levelApiService;
  final AdService adService;
  final DailyChallengeService dailyChallengeService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Level> _levels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLevels();
    widget.playerService.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    widget.playerService.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() => setState(() {});

  Future<void> _loadLevels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final levels = await widget.levelApiService.fetchLevels();
      if (!mounted) return;
      setState(() {
        _levels = levels;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المستويات';
        _loading = false;
      });
    }
  }

  void _openClassic({int levelIndex = 0}) {
    if (_levels.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          session: GameSession(
            mode: GameMode.classic,
            levels: _levels,
            levelIndex: levelIndex,
          ),
          playerService: widget.playerService,
        ),
      ),
    );
  }

  void _openDaily() {
    if (_levels.isEmpty) return;
    if (widget.playerService.isDailyCompletedToday()) {
      _showSnack('أكملت تحدي اليوم بالفعل! عد غداً');
      return;
    }
    final today = DateTime.now();
    final dailyLevel =
        widget.dailyChallengeService.dailyLevelForDate(_levels, today);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          session: GameSession(
            mode: GameMode.daily,
            levels: _levels,
            dailyLevel: dailyLevel,
          ),
          playerService: widget.playerService,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Future<void> _watchRewardedAd() async {
    HapticFeedback.lightImpact();
    final rewarded = await widget.adService.showRewardedAd();
    if (!mounted) return;
    if (rewarded) {
      await widget.playerService.addCoins(GameEconomy.rewardedAdCoins);
      _showSnack('+${GameEconomy.rewardedAdCoins} عملة!');
    } else {
      _showSnack('الإعلان غير متاح حالياً');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final dailyDone = widget.playerService.isDailyCompletedToday();
    final today = DateTime.now();
    final dailyLevel = _levels.isEmpty
        ? null
        : widget.dailyChallengeService.dailyLevelForDate(_levels, today);

    return Scaffold(
      body: Stack(
        children: [
          const _MenuBackground(),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: GameColors.green))
                : RefreshIndicator(
                    onRefresh: _loadLevels,
                    color: GameColors.green,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        _TopBar(coins: widget.playerService.coins),
                        const SizedBox(height: 24),
                        Text(
                          'Arabic\nConnections',
                          textAlign: TextAlign.center,
                          style: GameTextStyles.title.copyWith(
                            fontSize: 34,
                            height: 1.15,
                            color: GameColors.greenDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'جمّع الكلمات في مجموعات',
                          textAlign: TextAlign.center,
                          style: GameTextStyles.subtitle.copyWith(fontSize: 16),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: GameColors.red)),
                        ],
                        const SizedBox(height: 28),
                        _DailyChallengeCard(
                          completed: dailyDone,
                          dateLabel: widget.dailyChallengeService.formattedDate(today),
                          levelTitle: dailyLevel?.title ?? '—',
                          reward: GameEconomy.dailyChallengeReward,
                          onPlay: _levels.isEmpty ? null : _openDaily,
                        ),
                        const SizedBox(height: 16),
                        PressableButton(
                          label: 'العب الكلاسيكي',
                          icon: Icons.play_arrow_rounded,
                          enabled: _levels.isNotEmpty,
                          onPressed: _levels.isEmpty ? null : () => _openClassic(),
                        ),
                        const SizedBox(height: 16),
                        _LevelGrid(
                          levels: _levels,
                          onLevelTap: (i) => _openClassic(levelIndex: i),
                        ),
                        const SizedBox(height: 20),
                        _RewardedAdCard(
                          coins: GameEconomy.rewardedAdCoins,
                          ready: widget.adService.isRewardedAdReady,
                          onWatch: _watchRewardedAd,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MenuBackground extends StatelessWidget {
  const _MenuBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8F9E0), GameColors.background],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: GameDecorations.card(
            faceColor: const Color(0xFFFFF8E1),
            edgeColor: const Color(0xFFFFC800),
            radius: 14,
          ),
          child: Row(
            children: [
              const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFC800), size: 22),
              const SizedBox(width: 6),
              Text(
                '$coins',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFFE6A800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyChallengeCard extends StatelessWidget {
  const _DailyChallengeCard({
    required this.completed,
    required this.dateLabel,
    required this.levelTitle,
    required this.reward,
    this.onPlay,
  });

  final bool completed;
  final String dateLabel;
  final String levelTitle;
  final int reward;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: completed ? null : onPlay,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: GameDecorations.card(
          faceColor: completed ? GameColors.border : GameColors.blue,
          edgeColor: completed ? GameColors.borderDark : GameColors.blueDark,
          radius: 22,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  completed ? Icons.check_circle_rounded : Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تحدي اليوم',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '+$reward',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              completed ? 'عد غداً لتحدي جديد!' : levelTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            if (!completed) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'ابدأ التحدي',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: GameColors.blueDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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

class _LevelGrid extends StatelessWidget {
  const _LevelGrid({required this.levels, required this.onLevelTap});

  final List<Level> levels;
  final ValueChanged<int> onLevelTap;

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('المستويات (${levels.length})', style: GameTextStyles.subtitle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(levels.length, (i) {
            return GestureDetector(
              onTap: () => onLevelTap(i),
              child: Container(
                width: 56,
                height: 56,
                decoration: GameDecorations.card(
                  faceColor: GameColors.surface,
                  edgeColor: GameColors.borderDark,
                  radius: 14,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${levels[i].number}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: GameColors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _RewardedAdCard extends StatelessWidget {
  const _RewardedAdCard({
    required this.coins,
    required this.ready,
    required this.onWatch,
  });

  final int coins;
  final bool ready;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: GameDecorations.panel(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: GameDecorations.card(
              faceColor: GameColors.orange,
              edgeColor: GameColors.orangeDark,
              radius: 12,
            ),
            child: const Icon(Icons.play_circle_outline_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'شاهد إعلاناً',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                Text(
                  ready ? '+$coins عملة مجاناً' : 'جاري التحميل…',
                  style: GameTextStyles.subtitle,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: ready ? onWatch : null,
            child: const Text('شاهد', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
