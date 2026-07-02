import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme/game_theme.dart';

/// Animated 3D word tile with tap bounce and selection states.
class WordCard extends StatefulWidget {
  const WordCard({
    super.key,
    required this.word,
    required this.isSelected,
    this.isHighlighted = false,
    required this.showError,
    required this.entranceDelay,
    required this.onTap,
  });

  final WordItem word;
  final bool isSelected;
  final bool isHighlighted;
  final bool showError;
  final Duration entranceDelay;
  final VoidCallback onTap;

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pressController;
  late AnimationController _wiggleController;
  late Animation<double> _entranceScale;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0,
      upperBound: 1,
    );
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _entranceScale = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );
    _pressScale = Tween<double>(begin: 1, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );

    Future<void>.delayed(widget.entranceDelay, () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void didUpdateWidget(WordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showError && widget.showError) {
      _wiggleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pressController.dispose();
    _wiggleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _pressController.forward();

  void _onTapUp(TapUpDetails _) {
    _pressController.reverse();
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  void _onTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    late Color face;
    late Color edge;
    late Color textColor;

    if (widget.showError) {
      face = GameColors.redLight;
      edge = GameColors.redDark;
      textColor = GameColors.redDark;
    } else if (widget.isSelected) {
      face = GameColors.blueLight;
      edge = GameColors.blueDark;
      textColor = GameColors.blueDark;
    } else if (widget.isHighlighted) {
      face = const Color(0xFFFFF3E0);
      edge = GameColors.orangeDark;
      textColor = GameColors.orangeDark;
    } else {
      face = GameColors.surface;
      edge = GameColors.borderDark;
      textColor = GameColors.textPrimary;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entranceScale,
        _pressScale,
        _wiggleController,
      ]),
      builder: (context, child) {
        final wiggle = math.sin(_wiggleController.value * math.pi * 4) *
            6 *
            _wiggleController.value;
        return Transform.translate(
          offset: Offset(wiggle, 0),
          child: Transform.scale(
            scale: _entranceScale.value * _pressScale.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: GameDecorations.card(
            faceColor: face,
            edgeColor: edge,
            radius: 16,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            widget.word.text,
            textAlign: TextAlign.center,
            style: GameTextStyles.cardLabel.copyWith(
              color: textColor,
              fontSize: widget.isSelected ? 16 : 15,
            ),
          ),
        ),
      ),
    );
  }
}
