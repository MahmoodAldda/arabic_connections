import 'package:flutter/material.dart';

/// Duolingo-inspired playful palette and shared decorations.
abstract final class GameColors {
  static const background = Color(0xFFF5F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const green = Color(0xFF58CC02);
  static const greenDark = Color(0xFF46A302);
  static const greenLight = Color(0xFFD7FFB8);
  static const blue = Color(0xFF1CB0F6);
  static const blueDark = Color(0xFF1899D6);
  static const blueLight = Color(0xFFDDF4FF);
  static const orange = Color(0xFFFF9600);
  static const orangeDark = Color(0xFFE08600);
  static const red = Color(0xFFFF4B4B);
  static const redDark = Color(0xFFEA2B2B);
  static const redLight = Color(0xFFFFDFE0);
  static const purple = Color(0xFFCE82FF);
  static const textPrimary = Color(0xFF3C3C3C);
  static const textSecondary = Color(0xFF777777);
  static const border = Color(0xFFE5E5E5);
  static const borderDark = Color(0xFFD0D0D0);
  static const shadow = Color(0x1A000000);
}

abstract final class GameDecorations {
  static BoxDecoration card({
    required Color faceColor,
    required Color edgeColor,
    double radius = 18,
  }) {
    return BoxDecoration(
      color: faceColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        bottom: BorderSide(color: edgeColor, width: 4),
        left: BorderSide(color: edgeColor.withValues(alpha: 0.35), width: 1.5),
        right: BorderSide(color: edgeColor.withValues(alpha: 0.35), width: 1.5),
        top: BorderSide(color: edgeColor.withValues(alpha: 0.2), width: 1.5),
      ),
      boxShadow: const [
        BoxShadow(
          color: GameColors.shadow,
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    );
  }

  static BoxDecoration panel({Color? color}) {
    return BoxDecoration(
      color: color ?? GameColors.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: GameColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
}

abstract final class GameTextStyles {
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: GameColors.textPrimary,
    height: 1.2,
  );

  static const subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: GameColors.textSecondary,
  );

  static const cardLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: GameColors.textPrimary,
    height: 1.25,
  );

  static const button = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
  );
}
