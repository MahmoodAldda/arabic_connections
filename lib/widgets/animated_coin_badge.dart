import 'package:flutter/material.dart';

import '../theme/game_theme.dart';

/// A gold coin pill that counts up smoothly when the balance changes and gives
/// a little celebratory bounce + glow when coins are gained.
class AnimatedCoinBadge extends StatefulWidget {
  const AnimatedCoinBadge({
    super.key,
    required this.count,
    this.compact = false,
    this.onTap,
  });

  final int count;
  final bool compact;
  final VoidCallback? onTap;

  @override
  State<AnimatedCoinBadge> createState() => _AnimatedCoinBadgeState();
}

class _AnimatedCoinBadgeState extends State<AnimatedCoinBadge>
    with SingleTickerProviderStateMixin {
  late int _displayFrom;
  late int _displayTo;
  late AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _displayFrom = widget.count;
    _displayTo = widget.count;
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void didUpdateWidget(AnimatedCoinBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) {
      _displayFrom = oldWidget.count;
      _displayTo = widget.count;
      if (widget.count > oldWidget.count) {
        _bounce.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vPad = widget.compact ? 6.0 : 8.0;
    final hPad = widget.compact ? 10.0 : 14.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (context, child) {
          final t = _bounce.value;
          final pulse = 1 + (t < 0.5 ? t : 1 - t) * 0.16;
          return Transform.scale(scale: pulse, child: child);
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            gradient: GameGradients.gold,
            borderRadius: BorderRadius.circular(GameRadii.pill),
            boxShadow: GameShadows.glow(GameColors.gold, opacity: 0.4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.compact ? 20 : 24,
                height: widget.compact ? 20 : 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF3C4), Color(0xFFF5A623)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x55B37400),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '\$',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: widget.compact ? 12 : 14,
                    color: const Color(0xFF9A6A00),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(
                    begin: _displayFrom.toDouble(), end: _displayTo.toDouble()),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    value.round().toString(),
                    style: GameTextStyles.button.copyWith(
                      color: const Color(0xFF7A5200),
                      fontSize: widget.compact ? 14 : 16,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
