import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/game_theme.dart';

/// A frosted-glass surface: blurs whatever is behind it and overlays a
/// translucent tint with a hairline border. Great for headers, chips and cards
/// layered over gradients.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = GameRadii.lg,
    this.blur = 14,
    this.tintOpacity = 0.18,
    this.tint = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.shadows,
  });

  final Widget child;
  final double radius;
  final double blur;
  final double tintOpacity;
  final Color tint;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows ?? GameShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: tintOpacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
