import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A premium decorative backdrop: a base gradient with a few softly-glowing,
/// slowly-drifting blobs and an optional felt vignette + diamond motif. Purely
/// decorative and cheap (radial gradients, no per-frame blur).
class DecorBackground extends StatefulWidget {
  const DecorBackground({
    super.key,
    required this.gradient,
    required this.blobs,
    this.felt = false,
    this.child,
  });

  final Gradient gradient;
  final List<Color> blobs;
  final bool felt;
  final Widget? child;

  @override
  State<DecorBackground> createState() => _DecorBackgroundState();
}

class _DecorBackgroundState extends State<DecorBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: widget.gradient)),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _DecorPainter(
                t: _controller.value,
                blobs: widget.blobs,
                felt: widget.felt,
              ),
            );
          },
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _DecorPainter extends CustomPainter {
  _DecorPainter({required this.t, required this.blobs, required this.felt});

  final double t;
  final List<Color> blobs;
  final bool felt;

  @override
  void paint(Canvas canvas, Size size) {
    const tau = math.pi * 2;

    for (var i = 0; i < blobs.length; i++) {
      final phase = i / blobs.length;
      final driftX = math.sin((t + phase) * tau) * 22;
      final driftY = math.cos((t + phase * 1.3) * tau) * 26;
      final cx = size.width * (0.18 + 0.64 * ((i * 0.37) % 1.0)) + driftX;
      final cy = size.height * (0.12 + 0.7 * ((i * 0.53) % 1.0)) + driftY;
      final radius = size.width * (0.34 + 0.12 * ((i * 0.29) % 1.0));

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            blobs[i].withValues(alpha: felt ? 0.32 : 0.5),
            blobs[i].withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }

    if (felt) {
      _paintDiamonds(canvas, size);
      _paintSpotlight(canvas, size);
      _paintTopSheen(canvas, size);
      _paintVignette(canvas, size);
    }
  }

  /// Warm stage light glowing from just above the board center.
  void _paintSpotlight(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final radius = size.width * 0.85;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  /// Cool highlight along the very top edge for depth.
  void _paintTopSheen(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.34);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintDiamonds(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const step = 46.0;
    const half = 5.0;
    for (double y = 0; y < size.height + step; y += step) {
      for (double x = 0; x < size.width + step; x += step) {
        final path = Path()
          ..moveTo(x, y - half)
          ..lineTo(x + half, y)
          ..lineTo(x, y + half)
          ..lineTo(x - half, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 0.95,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.12),
          Colors.black.withValues(alpha: 0.34),
        ],
        stops: const [0.5, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_DecorPainter oldDelegate) => oldDelegate.t != t;
}
