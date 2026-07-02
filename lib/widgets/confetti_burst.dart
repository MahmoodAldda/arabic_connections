import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight confetti burst overlay for success moments.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rng = math.Random();

  static const _colors = [
    Color(0xFF58CC02),
    Color(0xFF1CB0F6),
    Color(0xFFFF9600),
    Color(0xFFCE82FF),
    Color(0xFFFF4B4B),
    Color(0xFFFFD900),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _particles = List.generate(36, (_) => _Particle.random(_rng));
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
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              progress: Curves.easeOutCubic.transform(_controller.value),
              particles: _particles,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
  });

  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;

  factory _Particle.random(math.Random rng) {
    return _Particle(
      angle: rng.nextDouble() * math.pi * 2,
      speed: 80 + rng.nextDouble() * 160,
      size: 5 + rng.nextDouble() * 7,
      color: _ConfettiBurstState._colors[rng.nextInt(_ConfettiBurstState._colors.length)],
      spin: rng.nextDouble() * math.pi * 2,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.35);
    final paint = Paint();

    for (final p in particles) {
      final dist = p.speed * progress;
      final x = origin.dx + math.cos(p.angle) * dist;
      final y = origin.dy + math.sin(p.angle) * dist + progress * progress * 120;
      paint.color = p.color.withValues(alpha: 1 - progress);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * progress * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
