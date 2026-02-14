import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_theme.dart';
import '../services/home_controller.dart';
import '../services/profile_service.dart';
import '../services/revenuecat_controller.dart';
import '../services/theme_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final td = themeProvider.themeData;
    final rc = context.watch<RevenueCatController>();
    final sub = rc.isLifetime
        ? 'lifetime'
        : rc.isPro
            ? 'pro'
            : 'free';

    return Scaffold(
      backgroundColor: td.scaffoldColor,
      appBar: AppBar(
        backgroundColor: td.surfaceColor,
        surfaceTintColor: Colors.transparent,
        title: Text('Customization', style: TextStyle(color: td.textPrimary)),
        iconTheme: IconThemeData(color: td.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _SectionHeader(label: 'Themes', color: td.textSecondary),
          const SizedBox(height: 12),
          ...AppThemeId.values.map((id) => _ThemeTile(
                themeId: id,
                isSelected: themeProvider.themeId == id,
                isUnlocked: id.isUnlocked(sub),
                onTap: () => _selectTheme(context, id),
              )),
          const SizedBox(height: 28),
          _SectionHeader(label: 'Soul Fire', color: td.textSecondary),
          const SizedBox(height: 12),
          ...SoulFireStyleId.values.map((id) => _SoulFireTile(
                styleId: id,
                isSelected: themeProvider.soulFireId == id,
                isUnlocked: id.isUnlocked(sub),
                onTap: () => _selectSoulFire(context, id),
              )),
        ],
      ),
    );
  }

  Future<void> _selectTheme(BuildContext context, AppThemeId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectTheme(id)) return;
    await _persistPreferences(context, selectedTheme: id.key);
  }

  Future<void> _selectSoulFire(
      BuildContext context, SoulFireStyleId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectSoulFire(id)) return;
    await _persistPreferences(context, selectedSoulFire: id.key);
  }

  Future<void> _persistPreferences(
    BuildContext context, {
    String? selectedTheme,
    String? selectedSoulFire,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final profileService =
        ProfileService(Supabase.instance.client);
    try {
      final updated = await profileService.updatePreferences(
        userId,
        selectedTheme: selectedTheme,
        selectedSoulFire: selectedSoulFire,
      );
      if (!context.mounted) return;
      context.read<HomeController>().updateProfileFromPreferences(updated);
    } catch (e) {
      debugPrint('Failed to save preferences: $e');
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.themeId,
    required this.isSelected,
    required this.isUnlocked,
    required this.onTap,
  });

  final AppThemeId themeId;
  final bool isSelected;
  final bool isUnlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = AppThemeData.fromId(themeId);
    final tierLabel = themeId.requiredTier == 'free'
        ? null
        : themeId.requiredTier.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: isUnlocked ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [data.cardGradientStart, data.cardGradientEnd],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? data.primaryColor.withValues(alpha: 0.7)
                  : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Color preview circles
              _ColorDot(color: data.primaryColor),
              const SizedBox(width: 6),
              _ColorDot(color: data.secondaryColor),
              const SizedBox(width: 6),
              _ColorDot(color: data.scaffoldColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      themeId.label,
                      style: TextStyle(
                        color: isUnlocked ? data.textPrimary : Colors.white38,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (tierLabel != null)
                      Text(
                        tierLabel,
                        style: TextStyle(
                          color: isUnlocked
                              ? data.primaryColor.withValues(alpha: 0.7)
                              : Colors.white24,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isUnlocked)
                const Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else if (isSelected)
                Icon(Icons.check_circle, size: 20, color: data.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoulFireTile extends StatelessWidget {
  const _SoulFireTile({
    required this.styleId,
    required this.isSelected,
    required this.isUnlocked,
    required this.onTap,
  });

  final SoulFireStyleId styleId;
  final bool isSelected;
  final bool isUnlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tierLabel = styleId.requiredTier == 'free'
        ? null
        : styleId.requiredTier.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: isUnlocked ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? styleId.primaryColor.withValues(alpha: 0.7)
                  : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Soul fire color preview
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      styleId.primaryColor.withValues(alpha: isUnlocked ? 0.8 : 0.3),
                      styleId.secondaryColor.withValues(alpha: isUnlocked ? 0.3 : 0.1),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(
                    color: styleId.primaryColor.withValues(alpha: isUnlocked ? 0.4 : 0.15),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      styleId.label,
                      style: TextStyle(
                        color: isUnlocked ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (tierLabel != null)
                      Text(
                        tierLabel,
                        style: TextStyle(
                          color: isUnlocked
                              ? styleId.primaryColor.withValues(alpha: 0.7)
                              : Colors.white24,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isUnlocked)
                const Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else if (isSelected)
                Icon(Icons.check_circle,
                    size: 20, color: styleId.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white12),
      ),
    );
  }
}
