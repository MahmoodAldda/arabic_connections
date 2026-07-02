import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium, modern palette for a polished mobile-game look.
abstract final class GameColors {
  // Surfaces
  static const background = Color(0xFFEFF6F1);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF17202A);

  // Brand
  static const green = Color(0xFF3FBF5A);
  static const greenDark = Color(0xFF2E9E47);
  static const greenLight = Color(0xFFD7FFB8);
  static const blue = Color(0xFF2CB6F6);
  static const blueDark = Color(0xFF1893D6);
  static const blueLight = Color(0xFFDDF4FF);
  static const orange = Color(0xFFFFA320);
  static const orangeDark = Color(0xFFE07E00);
  static const red = Color(0xFFFF5A5A);
  static const redDark = Color(0xFFEA2B2B);
  static const redLight = Color(0xFFFFDFE0);
  static const purple = Color(0xFFB775FF);
  static const purpleDark = Color(0xFF9B4DE8);
  static const gold = Color(0xFFFFC107);
  static const goldDark = Color(0xFFE6A100);

  // Text
  static const textPrimary = Color(0xFF1F2A37);
  static const textSecondary = Color(0xFF6B7785);

  // Lines / borders
  static const border = Color(0xFFE7ECF1);
  static const borderDark = Color(0xFFD3DBE3);
  static const shadow = Color(0x1A0B1B2B);
}

/// Reusable gradients used across surfaces, buttons and accents.
abstract final class GameGradients {
  static const appBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF4FBF6), Color(0xFFE4F2EA), Color(0xFFDCEDE6)],
    stops: [0.0, 0.55, 1.0],
  );

  static const felt = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF31B063), Color(0xFF1E8B4C), Color(0xFF116B39)],
    stops: [0.0, 0.5, 1.0],
  );

  static const gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE59A), Color(0xFFFFC107), Color(0xFFF5A623)],
  );

  static const green = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF57D06E), Color(0xFF2E9E47)],
  );

  static const blue = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4CC6FA), Color(0xFF1893D6)],
  );

  static const orange = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFC15A), Color(0xFFE07E00)],
  );

  static const purple = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC79BFF), Color(0xFF9B4DE8)],
  );

  /// Glossy top-sheen overlay for premium cards.
  static const cardSheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.6],
  );

  /// Builds a subtle two-stop gradient from a single brand color.
  static LinearGradient fromColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final light =
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    final dark =
        hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [light, dark],
    );
  }
}

/// Soft, layered shadow presets.
abstract final class GameShadows {
  static const soft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6)),
  ];

  static const card = [
    BoxShadow(color: Color(0x1A0B1B2B), blurRadius: 18, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const lifted = [
    BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 14)),
  ];

  static List<BoxShadow> glow(Color color, {double opacity = 0.45}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Corner radius scale.
abstract final class GameRadii {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 24.0;
  static const xl = 30.0;
  static const pill = 999.0;
}

abstract final class GameDecorations {
  /// Chunky 3D "candy" card with a colored bottom edge — used for buttons/tiles.
  static BoxDecoration card({
    required Color faceColor,
    required Color edgeColor,
    double radius = GameRadii.md,
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
      boxShadow: GameShadows.soft,
    );
  }

  /// Premium gradient card with soft shadow and hairline border.
  static BoxDecoration premiumCard({
    Gradient? gradient,
    Color? color,
    double radius = GameRadii.lg,
    List<BoxShadow>? shadows,
    Color borderColor = const Color(0x14FFFFFF),
  }) {
    return BoxDecoration(
      gradient: gradient,
      color: gradient == null ? (color ?? GameColors.surface) : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: shadows ?? GameShadows.card,
    );
  }

  /// Frosted-glass surface (pair with a [BackdropFilter] via GlassContainer).
  static BoxDecoration glass({
    double radius = GameRadii.lg,
    double tintOpacity = 0.16,
    Color tint = Colors.white,
  }) {
    return BoxDecoration(
      color: tint.withValues(alpha: tintOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
      boxShadow: GameShadows.soft,
    );
  }

  static BoxDecoration panel({Color? color, double radius = GameRadii.lg}) {
    return BoxDecoration(
      color: color ?? GameColors.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: GameShadows.card,
    );
  }
}

/// Cairo-based typography for a clean, modern Arabic + Latin look.
abstract final class GameTextStyles {
  static TextStyle get display => GoogleFonts.cairo(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: GameColors.textPrimary,
        height: 1.15,
      );

  static TextStyle get title => GoogleFonts.cairo(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: GameColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get subtitle => GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: GameColors.textSecondary,
      );

  static TextStyle get cardLabel => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: GameColors.textPrimary,
        height: 1.25,
      );

  static TextStyle get button => GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      );
}
