import 'package:flutter/material.dart';

/// All available app themes. Free users get only [oledVoid].
/// Pro users unlock [obsidianSteel], [midnightEmber], [deepOcean].
/// Lifetime users additionally unlock [auroraNight], [cosmicDusk].
enum AppThemeId {
  oledVoid,       // Free: pure OLED black + warm amber/gold accents
  obsidianSteel,  // Pro: dark charcoal + cool silver/steel blue accents
  midnightEmber,  // Pro: deep navy + ember orange/red accents
  deepOcean,      // Pro: dark teal/ocean + aqua highlights
  auroraNight,    // Lifetime: near-black + shifting aurora green/purple
  cosmicDusk,     // Lifetime: dark plum/indigo + rose gold accents
}

/// All available Soul Fire button styles.
enum SoulFireStyleId {
  etherealOrb,    // Free: purple/cyan energy sphere (current)
  voidPortal,     // Pro: dark void portal with cyan/purple swirling smoke
  plasmaBurst,    // Pro: intense cyan electric plasma burst
  plasmaCell,     // Pro: solid blue plasma ball with cell texture
  toxicCore,      // Lifetime: toxic green molten energy sphere
  crystalAscend,  // Lifetime: crystal blue ethereal orb with ascending wisps
}

extension AppThemeIdX on AppThemeId {
  String get key => name;

  String get label {
    switch (this) {
      case AppThemeId.oledVoid:
        return 'Void Black';
      case AppThemeId.obsidianSteel:
        return 'Obsidian Steel';
      case AppThemeId.midnightEmber:
        return 'Midnight Ember';
      case AppThemeId.deepOcean:
        return 'Deep Ocean';
      case AppThemeId.auroraNight:
        return 'Aurora Night';
      case AppThemeId.cosmicDusk:
        return 'Cosmic Dusk';
    }
  }

  /// Minimum subscription tier required.
  /// 'free', 'pro', or 'lifetime'
  String get requiredTier {
    switch (this) {
      case AppThemeId.oledVoid:
        return 'free';
      case AppThemeId.obsidianSteel:
      case AppThemeId.midnightEmber:
      case AppThemeId.deepOcean:
        return 'pro';
      case AppThemeId.auroraNight:
      case AppThemeId.cosmicDusk:
        return 'lifetime';
    }
  }

  bool isUnlocked(String subscriptionStatus) {
    switch (requiredTier) {
      case 'free':
        return true;
      case 'pro':
        return subscriptionStatus == 'pro' || subscriptionStatus == 'lifetime';
      case 'lifetime':
        return subscriptionStatus == 'lifetime';
      default:
        return false;
    }
  }
}

extension SoulFireStyleIdX on SoulFireStyleId {
  String get key => name;

  String get label {
    switch (this) {
      case SoulFireStyleId.etherealOrb:
        return 'Ethereal Orb';
      case SoulFireStyleId.voidPortal:
        return 'Void Portal';
      case SoulFireStyleId.plasmaBurst:
        return 'Plasma Burst';
      case SoulFireStyleId.plasmaCell:
        return 'Plasma Cell';
      case SoulFireStyleId.toxicCore:
        return 'Toxic Core';
      case SoulFireStyleId.crystalAscend:
        return 'Crystal Ascend';
    }
  }

  String get requiredTier {
    switch (this) {
      case SoulFireStyleId.etherealOrb:
        return 'free';
      case SoulFireStyleId.voidPortal:
      case SoulFireStyleId.plasmaBurst:
      case SoulFireStyleId.plasmaCell:
        return 'pro';
      case SoulFireStyleId.toxicCore:
      case SoulFireStyleId.crystalAscend:
        return 'lifetime';
    }
  }

  bool isUnlocked(String subscriptionStatus) {
    switch (requiredTier) {
      case 'free':
        return true;
      case 'pro':
        return subscriptionStatus == 'pro' || subscriptionStatus == 'lifetime';
      case 'lifetime':
        return subscriptionStatus == 'lifetime';
      default:
        return false;
    }
  }

  /// Primary color used for each Soul Fire style.
  Color get primaryColor {
    switch (this) {
      case SoulFireStyleId.etherealOrb:
        return const Color(0xFF00E5FF); // Cyan
      case SoulFireStyleId.voidPortal:
        return const Color(0xFF7B68EE); // Purple-blue
      case SoulFireStyleId.plasmaBurst:
        return const Color(0xFF00BFFF); // Deep sky blue
      case SoulFireStyleId.plasmaCell:
        return const Color(0xFF1E90FF); // Dodger blue
      case SoulFireStyleId.toxicCore:
        return const Color(0xFF39FF14); // Neon green
      case SoulFireStyleId.crystalAscend:
        return const Color(0xFF87CEEB); // Light sky blue
    }
  }

  /// Secondary/accent color.
  Color get secondaryColor {
    switch (this) {
      case SoulFireStyleId.etherealOrb:
        return const Color(0xFFAA00FF); // Purple
      case SoulFireStyleId.voidPortal:
        return const Color(0xFF00E5FF); // Cyan
      case SoulFireStyleId.plasmaBurst:
        return const Color(0xFFCDFCFF); // Ice white
      case SoulFireStyleId.plasmaCell:
        return const Color(0xFF0077BE); // Ocean blue
      case SoulFireStyleId.toxicCore:
        return const Color(0xFF00FF7F); // Spring green
      case SoulFireStyleId.crystalAscend:
        return const Color(0xFFE0F0FF); // Ice white-blue
    }
  }
}

/// Theme data definition for each AppThemeId.
class AppThemeData {
  const AppThemeData({
    required this.id,
    required this.scaffoldColor,
    required this.surfaceColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.dividerColor,
    required this.cardGradientStart,
    required this.cardGradientEnd,
  });

  final AppThemeId id;
  final Color scaffoldColor;
  final Color surfaceColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentGlow;
  final Color textPrimary;
  final Color textSecondary;
  final Color dividerColor;
  final Color cardGradientStart;
  final Color cardGradientEnd;

  static AppThemeData fromId(AppThemeId id) {
    switch (id) {
      case AppThemeId.oledVoid:
        return const AppThemeData(
          id: AppThemeId.oledVoid,
          scaffoldColor: Color(0xFF000000),
          surfaceColor: Color(0xFF0E0E0E),
          primaryColor: Color(0xFFD4A84B),
          secondaryColor: Color(0xFFE8C36A),
          accentGlow: Color(0x33D4A84B),
          textPrimary: Color(0xFFFFFFFF),
          textSecondary: Color(0xB3FFFFFF),
          dividerColor: Color(0x1FFFFFFF),
          cardGradientStart: Color(0xFF1A1A1A),
          cardGradientEnd: Color(0xFF0E0E0E),
        );
      case AppThemeId.obsidianSteel:
        return const AppThemeData(
          id: AppThemeId.obsidianSteel,
          scaffoldColor: Color(0xFF08090C),
          surfaceColor: Color(0xFF12141A),
          primaryColor: Color(0xFF8EACCD),
          secondaryColor: Color(0xFFB0C4DE),
          accentGlow: Color(0x338EACCD),
          textPrimary: Color(0xFFE8ECF1),
          textSecondary: Color(0xB3C8CED6),
          dividerColor: Color(0x1FC8CED6),
          cardGradientStart: Color(0xFF181C24),
          cardGradientEnd: Color(0xFF0E1016),
        );
      case AppThemeId.midnightEmber:
        return const AppThemeData(
          id: AppThemeId.midnightEmber,
          scaffoldColor: Color(0xFF060810),
          surfaceColor: Color(0xFF0E1018),
          primaryColor: Color(0xFFE8734A),
          secondaryColor: Color(0xFFFF9B6B),
          accentGlow: Color(0x33E8734A),
          textPrimary: Color(0xFFF0E8E4),
          textSecondary: Color(0xB3D4C8C0),
          dividerColor: Color(0x1FD4C8C0),
          cardGradientStart: Color(0xFF1A1420),
          cardGradientEnd: Color(0xFF0C0A12),
        );
      case AppThemeId.deepOcean:
        return const AppThemeData(
          id: AppThemeId.deepOcean,
          scaffoldColor: Color(0xFF040A0E),
          surfaceColor: Color(0xFF0A1218),
          primaryColor: Color(0xFF4ECDC4),
          secondaryColor: Color(0xFF7EEEE6),
          accentGlow: Color(0x334ECDC4),
          textPrimary: Color(0xFFE4F0EE),
          textSecondary: Color(0xB3BCD4D0),
          dividerColor: Color(0x1FBCD4D0),
          cardGradientStart: Color(0xFF121E24),
          cardGradientEnd: Color(0xFF081014),
        );
      case AppThemeId.auroraNight:
        return const AppThemeData(
          id: AppThemeId.auroraNight,
          scaffoldColor: Color(0xFF020408),
          surfaceColor: Color(0xFF0A0E14),
          primaryColor: Color(0xFF66FFB2),
          secondaryColor: Color(0xFFB388FF),
          accentGlow: Color(0x3366FFB2),
          textPrimary: Color(0xFFE8F5F0),
          textSecondary: Color(0xB3C0D8D0),
          dividerColor: Color(0x1FC0D8D0),
          cardGradientStart: Color(0xFF101820),
          cardGradientEnd: Color(0xFF060C12),
        );
      case AppThemeId.cosmicDusk:
        return const AppThemeData(
          id: AppThemeId.cosmicDusk,
          scaffoldColor: Color(0xFF080410),
          surfaceColor: Color(0xFF100C18),
          primaryColor: Color(0xFFE8A0BF),
          secondaryColor: Color(0xFFD4A574),
          accentGlow: Color(0x33E8A0BF),
          textPrimary: Color(0xFFF0E8F0),
          textSecondary: Color(0xB3D4C8D4),
          dividerColor: Color(0x1FD4C8D4),
          cardGradientStart: Color(0xFF1C1424),
          cardGradientEnd: Color(0xFF0E0A14),
        );
    }
  }

  ThemeData toFlutterTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldColor,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: const Color(0xFFCF6679),
      ),
      dividerColor: dividerColor,
      cardColor: surfaceColor,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: textPrimary),
        titleSmall: TextStyle(color: textPrimary),
        labelSmall: TextStyle(color: textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: scaffoldColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceColor,
        contentTextStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
