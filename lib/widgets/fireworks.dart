import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A celebratory multi-burst fireworks overlay for finishing a level. Several
/// bursts pop at staggered times and random positions, then it calls
/// [onComplete]. Cheap CustomPaint — runs smoothly at 60 FPS.
class Fireworks extends StatefulWidget {
  const Fireworks({super.key, required this.onComplete, this.burstCount = 6});

  final VoidCallback onComplete;
  final int burstCount;

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<Fireworks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Burst> _bursts;
  final _rng = math.Random();

  static const _palette = [
    Color(0xFFFFC107),
    Color(0xFF3FBF5A),
    Color(0xFF2CB6F6),
    Color(0xFFB775FF),
    Color(0xFFFF5A5A),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _bursts = List.generate(widget.burstCount, (i) {
      return _Burst(
        start: (i / widget.burstCount) * 0.6 + _rng.nextDouble() * 0.1,
        center: Offset(0.15 + _rng.nextDouble() * 0.7, 0.2 + _rng.nextDouble() * 0.45),
        color: _palette[_rng.nextInt(_palette.length)],
        particles: List.generate(24, (_) {
          final angle = _rng.nextDouble() * math.pi * 2;
          final speed = 0.5 + _rng.nextDouble() * 0.5;
          return _FParticle(angle: angle, speed: speed);
        }),
      );
    });
    _controller.forward().then((_) => widget.onComplete());
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
        builder: (context, _) => CustomPaint(
          painter: _FireworksPainter(t: _controller.value, bursts: _bursts),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Burst {
  _Burst({
    required this.start,
    required this.center,
    required this.color,
    required this.particles,
  });

  final double start;
  final Offset center; // fractional (0..1) of size
  final Color color;
  final List<_FParticle> particles;
}

class _FParticle {
  _FParticle({required this.angle, required this.speed});
  final double angle;
  final double speed;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter({required this.t, required this.bursts});

  final double t;
  final List<_Burst> bursts;

  @override
  void paint(Canvas canvas, Size size) {
    const burstDur = 0.4;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final burst in bursts) {
      final local = ((t - burst.start) / burstDur);
      if (local < 0 || local > 1) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final origin =
          Offset(burst.center.dx * size.width, burst.center.dy * size.height);
      final maxRadius = size.width * 0.32;

      for (final p in burst.particles) {
        final dist = eased * maxRadius * p.speed;
        final x = origin.dx + math.cos(p.angle) * dist;
        final y = origin.dy + math.sin(p.angle) * dist + eased * eased * 40;
        paint.color = burst.color.withValues(alpha: (1 - local).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), 3.0 * (1 - local) + 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) => oldDelegate.t != t;
}
