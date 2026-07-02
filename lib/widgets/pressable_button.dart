import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/game_theme.dart';

/// Chunky 3D button inspired by Duolingo's primary CTA.
class PressableButton extends StatefulWidget {
  const PressableButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.faceColor = GameColors.green,
    this.edgeColor = GameColors.greenDark,
    this.gradient,
    this.textColor = Colors.white,
    this.icon,
    this.height = 54,
    this.pulseWhenReady = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color faceColor;
  final Color edgeColor;

  /// Optional gradient face for a premium look. Falls back to [faceColor].
  final Gradient? gradient;
  final Color textColor;
  final IconData? icon;
  final double height;
  final bool pulseWhenReady;

  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulseWhenReady) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PressableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseWhenReady && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.pulseWhenReady && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
  }

  void _handleTapUp(TapUpDetails _) => setState(() => _pressed = false);

  void _handleTapCancel() => setState(() => _pressed = false);

  void _handleTap() {
    if (!widget.enabled || widget.onPressed == null) return;
    HapticFeedback.lightImpact();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled;
    final face = disabled ? GameColors.border : widget.faceColor;
    final edge = disabled ? GameColors.borderDark : widget.edgeColor;
    final useGradient = widget.gradient != null && !disabled;
    final pressOffset = _pressed ? 3.0 : 0.0;
    final decoration = useGradient
        ? BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(GameRadii.md),
            border: Border(
              bottom: BorderSide(color: edge, width: 4),
            ),
            boxShadow: GameShadows.glow(widget.edgeColor, opacity: 0.35),
          )
        : GameDecorations.card(faceColor: face, edgeColor: edge, radius: GameRadii.md);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = widget.pulseWhenReady && widget.enabled
            ? 1.0 + (_pulseController.value * 0.02)
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          height: widget.height,
          transform: Matrix4.translationValues(0, pressOffset, 0),
          decoration: decoration,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: disabled ? GameColors.textSecondary : widget.textColor, size: 22),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: GameTextStyles.button.copyWith(
                    color: disabled ? GameColors.textSecondary : widget.textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
