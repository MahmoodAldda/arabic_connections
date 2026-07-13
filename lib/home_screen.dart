import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'models.dart';
import 'services/ad_service.dart';
import 'services/daily_challenge_service.dart';
import 'services/level_api_service.dart';
import 'services/player_service.dart';
import 'services/sound_service.dart';
import 'solitaire/difficulty.dart';
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

  void _openClassic() {
    if (_levels.isEmpty) return;
    SoundService.instance.play(SoundFx.button);
    Navigator.of(context).push(
      premiumRoute<void>(
        SolitaireGameScreen(
          session: GameSession(
            mode: GameMode.classic,
            levels: _levels,
          ),
          playerService: widget.playerService,
        ),
      ),
    ).then((_) => setState(() {}));
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
                        const SizedBox(height: 22),
                        _ProgressCard(
                          skill: widget.playerService.skill,
                          round: widget.playerService.round,
                          streak: widget.playerService.cleanStreak,
                        ),
                        const SizedBox(height: 16),
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
                          onPressed: _levels.isEmpty ? null : _openClassic,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'لعبة واحدة متواصلة تزداد صعوبةً كلما تقدّمت',
                          textAlign: TextAlign.center,
                          style: GameTextStyles.subtitle.copyWith(fontSize: 13),
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

/// Surfaces the player's progression: current rank + progress toward the next,
/// the continuous game's round, and the active clean-win streak. This is the
/// "sense of advancement" that replaces classic level tiers.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.skill,
    required this.round,
    required this.streak,
  });

  final double skill;
  final int round;
  final int streak;

  static const _rankIcons = [
    Icons.spa_rounded,
    Icons.eco_rounded,
    Icons.workspace_premium_rounded,
    Icons.military_tech_rounded,
    Icons.emoji_events_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final rank = PlayerRank.fromSkill(skill);
    final progress = rank.progressAt(skill);
    final isMax = rank.index >= PlayerRank.count - 1;
    final nextName = isMax ? null : PlayerRank.ranks[rank.index + 1].name;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: GameDecorations.premiumCard(
        color: GameColors.surface,
        radius: GameRadii.xl,
        borderColor: GameColors.border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: GameGradients.gold,
                  borderRadius: BorderRadius.circular(GameRadii.md),
                  boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.4),
                ),
                child: Icon(
                  _rankIcons[rank.index.clamp(0, _rankIcons.length - 1)],
                  color: const Color(0xFF6E4A00),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رتبتك: ${rank.name}',
                        style: GameTextStyles.title.copyWith(fontSize: 18)),
                    Text(
                      isMax ? 'أعلى رتبة!' : 'التالي: $nextName',
                      style: GameTextStyles.subtitle.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (streak > 0) _chip(Icons.local_fire_department_rounded,
                  '$streak', GameColors.orange),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(GameRadii.pill),
            child: LinearProgressIndicator(
              value: isMax ? 1.0 : progress,
              minHeight: 10,
              backgroundColor: GameColors.background,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(GameColors.gold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _chip(Icons.flag_rounded, 'الجولة $round', GameColors.green),
              const SizedBox(width: 8),
              _chip(Icons.trending_up_rounded,
                  'المهارة ${skill.round()}', GameColors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(GameRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GameTextStyles.subtitle
                .copyWith(fontSize: 12.5, color: color, fontWeight: FontWeight.w700),
          ),
        ],
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
