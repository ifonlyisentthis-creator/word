import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_theme.dart';
import '../services/profile_service.dart';
import '../services/theme_provider.dart';
import '../widgets/ambient_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final sub = tp.subscriptionStatus;
    final td = tp.themeData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customization'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              physics: const ClampingScrollPhysics(),
              children: [
                // ── Section: Themes ──
                _SectionLabel(
                  label: 'THEMES',
                  accent: td.primaryColor,
                ),
                const SizedBox(height: 12),
                ...AppThemeId.values.map((id) => _ThemeCard(
                      themeId: id,
                      isSelected: tp.themeId == id,
                      isUnlocked: id.isUnlocked(sub),
                      onTap: () => _selectTheme(context, id),
                    )),

                const SizedBox(height: 28),

                // ── Section: Soul Fire ──
                _SectionLabel(
                  label: 'SOUL FIRE',
                  accent: tp.soulFireId.primaryColor,
                ),
                const SizedBox(height: 12),
                ...SoulFireStyleId.values.map((id) => _SoulFireCard(
                      styleId: id,
                      isSelected: tp.soulFireId == id,
                      isUnlocked: id.isUnlocked(sub),
                      onTap: () => _selectSoulFire(context, id),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectTheme(BuildContext context, AppThemeId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectTheme(id)) return;
    await _persist(context, selectedTheme: id.key);
  }

  void _selectSoulFire(BuildContext context, SoulFireStyleId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectSoulFire(id)) return;
    await _persist(context, selectedSoulFire: id.key);
  }

  Future<void> _persist(BuildContext context,
      {String? selectedTheme, String? selectedSoulFire}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await ProfileService(Supabase.instance.client).updatePreferences(
        userId,
        selectedTheme: selectedTheme,
        selectedSoulFire: selectedSoulFire,
      );
    } catch (e) {
      debugPrint('Failed to save preferences: $e');
    }
  }
}

// ─── Section label ───
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ─── Theme selection card ───
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
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
    final tier = themeId.requiredTier;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: isUnlocked ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                data.cardGradientStart,
                data.cardGradientEnd,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? data.primaryColor.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: data.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Color swatch strip
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      data.primaryColor,
                      data.secondaryColor,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: data.scaffoldColor,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
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
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (tier != 'free')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: data.primaryColor
                                  .withValues(alpha: isUnlocked ? 0.15 : 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tier.toUpperCase(),
                              style: TextStyle(
                                color: isUnlocked
                                    ? data.primaryColor
                                    : Colors.white24,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        if (tier == 'free')
                          Text(
                            'INCLUDED',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isUnlocked)
                Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.primaryColor.withValues(alpha: 0.2),
                    border: Border.all(color: data.primaryColor, width: 1.5),
                  ),
                  child: Icon(Icons.check, size: 14, color: data.primaryColor),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Soul Fire selection card ───
class _SoulFireCard extends StatelessWidget {
  const _SoulFireCard({
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
    final tier = styleId.requiredTier;
    final pc = styleId.primaryColor;
    final sc = styleId.secondaryColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: isUnlocked ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? pc.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: pc.withValues(alpha: 0.12),
                      blurRadius: 20,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Orb preview
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isUnlocked ? pc : pc.withValues(alpha: 0.3)),
                      (isUnlocked ? sc : sc.withValues(alpha: 0.1))
                          .withValues(alpha: 0.4),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(
                    color: pc.withValues(alpha: isUnlocked ? 0.3 : 0.10),
                  ),
                  boxShadow: isUnlocked
                      ? [
                          BoxShadow(
                            color: pc.withValues(alpha: 0.25),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: isUnlocked
                    ? Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.7),
                            boxShadow: [
                              BoxShadow(
                                color: pc.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      )
                    : null,
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
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (tier != 'free')
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              pc.withValues(alpha: isUnlocked ? 0.15 : 0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tier.toUpperCase(),
                          style: TextStyle(
                            color: isUnlocked ? pc : Colors.white24,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      )
                    else
                      Text(
                        'INCLUDED',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isUnlocked)
                Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pc.withValues(alpha: 0.2),
                    border: Border.all(color: pc, width: 1.5),
                  ),
                  child: Icon(Icons.check, size: 14, color: pc),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
