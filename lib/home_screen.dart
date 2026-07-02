import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'models.dart';
import 'services/ad_service.dart';
import 'services/daily_challenge_service.dart';
import 'services/level_api_service.dart';
import 'services/player_service.dart';
import 'services/sound_service.dart';
import 'solitaire/solitaire_game_screen.dart';
import 'theme/game_theme.dart';
import 'widgets/animated_coin_badge.dart';
import 'widgets/decor_background.dart';
import 'widgets/premium_route.dart';
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
    SoundService.instance.play(SoundFx.button);
    Navigator.of(context).push(
      premiumRoute<void>(
        SolitaireGameScreen(
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
    SoundService.instance.play(SoundFx.button);
    Navigator.of(context).push(
      premiumRoute<void>(
        SolitaireGameScreen(
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
        SnackBar(content: Text(message, textAlign: TextAlign.center)),
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
          const Positioned.fill(
            child: DecorBackground(
              gradient: GameGradients.appBackground,
              blobs: [Color(0xFF9BE7B4), Color(0xFF9AD8FF), Color(0xFFFFE0A3)],
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: GameColors.green))
                : RefreshIndicator(
                    onRefresh: _loadLevels,
                    color: GameColors.green,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedCoinBadge(count: widget.playerService.coins),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const _BrandTitle(),
                        const SizedBox(height: 6),
                        Text(
                          'رتّب الكلمات في مجموعاتها',
                          textAlign: TextAlign.center,
                          style: GameTextStyles.subtitle.copyWith(fontSize: 16),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: GameColors.red)),
                        ],
                        const SizedBox(height: 28),
                        _DailyChallengeCard(
                          completed: dailyDone,
                          dateLabel:
                              widget.dailyChallengeService.formattedDate(today),
                          levelTitle: dailyLevel?.title ?? '—',
                          reward: GameEconomy.dailyChallengeReward,
                          onPlay: _levels.isEmpty ? null : _openDaily,
                        ),
                        const SizedBox(height: 16),
                        PressableButton(
                          label: 'العب الآن',
                          icon: Icons.play_arrow_rounded,
                          gradient: GameGradients.green,
                          enabled: _levels.isNotEmpty,
                          height: 58,
                          onPressed: _levels.isEmpty ? null : () => _openClassic(),
                        ),
                        const SizedBox(height: 20),
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

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3FBF5A), Color(0xFF1E8B4C)],
      ).createShader(rect),
      child: Text(
        'Arabic\nConnections',
        textAlign: TextAlign.center,
        style: GameTextStyles.display.copyWith(
          fontSize: 38,
          height: 1.1,
          color: Colors.white,
          shadows: const [
            Shadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
      ),
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
        decoration: BoxDecoration(
          gradient: completed
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFB8C4CE), Color(0xFF97A6B2)],
                )
              : GameGradients.blue,
          borderRadius: BorderRadius.circular(GameRadii.xl),
          boxShadow: completed
              ? GameShadows.soft
              : GameShadows.glow(GameColors.blue, opacity: 0.4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(GameRadii.md),
                  ),
                  child: Icon(
                    completed
                        ? Icons.check_circle_rounded
                        : Icons.local_fire_department_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تحدي اليوم',
                        style: GameTextStyles.title.copyWith(
                          color: Colors.white,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(GameRadii.pill),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '+$reward',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800),
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
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(GameRadii.md),
                  boxShadow: GameShadows.soft,
                ),
                child: Text(
                  'ابدأ التحدي',
                  textAlign: TextAlign.center,
                  style: GameTextStyles.button.copyWith(
                    color: GameColors.blueDark,
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

  static const _tileGradients = [
    GameGradients.green,
    GameGradients.blue,
    GameGradients.orange,
    GameGradients.purple,
  ];

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 10),
          child: Text('المستويات (${levels.length})',
              style: GameTextStyles.title.copyWith(fontSize: 18)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(levels.length, (i) {
            final gradient = _tileGradients[i % _tileGradients.length];
            return GestureDetector(
              onTap: () => onLevelTap(i),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(GameRadii.md),
                  boxShadow: GameShadows.card,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${levels[i].number}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
                    ],
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(GameRadii.lg),
        boxShadow: GameShadows.soft,
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: GameGradients.orange,
              borderRadius: BorderRadius.circular(GameRadii.md),
              boxShadow: GameShadows.glow(GameColors.orange, opacity: 0.35),
            ),
            child: const Icon(Icons.play_circle_outline_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('شاهد إعلاناً',
                    style: GameTextStyles.title.copyWith(fontSize: 16)),
                Text(
                  ready ? '+$coins عملة مجاناً' : 'جاري التحميل…',
                  style: GameTextStyles.subtitle,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: ready ? onWatch : null,
            child: Text('شاهد',
                style: GameTextStyles.button
                    .copyWith(fontSize: 15, color: GameColors.orangeDark)),
          ),
        ],
      ),
    );
  }
}
