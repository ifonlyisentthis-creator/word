import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_theme.dart';
import '../services/profile_service.dart';
import '../services/theme_provider.dart';
import '../widgets/ambient_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  bool _themesExpanded = true;
  bool _soulFireExpanded = true;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final sub = themeProvider.subscriptionStatus;
    final td = themeProvider.themeData;
    final currentTheme = AppThemeData.fromId(themeProvider.themeId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customization'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              // ── Current Selection Summary ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      currentTheme.cardGradientStart,
                      currentTheme.cardGradientEnd,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: currentTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    // Theme preview
                    _ColorDot(color: currentTheme.primaryColor, size: 28),
                    const SizedBox(width: 8),
                    _ColorDot(color: currentTheme.secondaryColor, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            themeProvider.themeId.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            themeProvider.soulFireId.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: themeProvider.soulFireId.primaryColor
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Soul fire mini preview
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            themeProvider.soulFireId.primaryColor
                                .withValues(alpha: 0.9),
                            themeProvider.soulFireId.secondaryColor
                                .withValues(alpha: 0.3),
                            Colors.black,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Themes Section ──
              _DropdownHeader(
                label: 'THEMES',
                expanded: _themesExpanded,
                onToggle: () =>
                    setState(() => _themesExpanded = !_themesExpanded),
                accentColor: td.primaryColor,
              ),
              AnimatedCrossFade(
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: AppThemeId.values
                        .map((id) => _ThemeTile(
                              themeId: id,
                              isSelected: themeProvider.themeId == id,
                              isUnlocked: id.isUnlocked(sub),
                              onTap: () => _selectTheme(id),
                            ))
                        .toList(),
                  ),
                ),
                secondChild: const SizedBox.shrink(),
                crossFadeState: _themesExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 250),
              ),

              const SizedBox(height: 20),

              // ── Soul Fire Section ──
              _DropdownHeader(
                label: 'SOUL FIRE',
                expanded: _soulFireExpanded,
                onToggle: () =>
                    setState(() => _soulFireExpanded = !_soulFireExpanded),
                accentColor: themeProvider.soulFireId.primaryColor,
              ),
              AnimatedCrossFade(
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: SoulFireStyleId.values
                        .map((id) => _SoulFireTile(
                              styleId: id,
                              isSelected: themeProvider.soulFireId == id,
                              isUnlocked: id.isUnlocked(sub),
                              onTap: () => _selectSoulFire(id),
                            ))
                        .toList(),
                  ),
                ),
                secondChild: const SizedBox.shrink(),
                crossFadeState: _soulFireExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 250),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectTheme(AppThemeId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectTheme(id)) return;
    await _persistPreferences(selectedTheme: id.key);
  }

  Future<void> _selectSoulFire(SoulFireStyleId id) async {
    final tp = context.read<ThemeProvider>();
    if (!tp.selectSoulFire(id)) return;
    await _persistPreferences(selectedSoulFire: id.key);
  }

  Future<void> _persistPreferences({
    String? selectedTheme,
    String? selectedSoulFire,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final profileService = ProfileService(Supabase.instance.client);
    try {
      await profileService.updatePreferences(
        userId,
        selectedTheme: selectedTheme,
        selectedSoulFire: selectedSoulFire,
      );
    } catch (e) {
      debugPrint('Failed to save preferences: $e');
    }
  }
}

class _DropdownHeader extends StatelessWidget {
  const _DropdownHeader({
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.accentColor,
  });
  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more, size: 20, color: Colors.white38),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [data.cardGradientStart, data.cardGradientEnd],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? data.primaryColor.withValues(alpha: 0.6)
                    : Colors.white10,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _ColorDot(color: data.primaryColor),
                const SizedBox(width: 5),
                _ColorDot(color: data.secondaryColor),
                const SizedBox(width: 5),
                _ColorDot(color: data.scaffoldColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        themeId.label,
                        style: TextStyle(
                          color:
                              isUnlocked ? data.textPrimary : Colors.white38,
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
                  const Icon(Icons.lock_outline,
                      size: 18, color: Colors.white24)
                else if (isSelected)
                  Icon(Icons.check_circle,
                      size: 20, color: data.primaryColor),
              ],
            ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? styleId.primaryColor.withValues(alpha: 0.6)
                    : Colors.white10,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        styleId.primaryColor
                            .withValues(alpha: isUnlocked ? 0.85 : 0.3),
                        styleId.secondaryColor
                            .withValues(alpha: isUnlocked ? 0.3 : 0.1),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    border: Border.all(
                      color: styleId.primaryColor
                          .withValues(alpha: isUnlocked ? 0.35 : 0.12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                                ? styleId.primaryColor
                                    .withValues(alpha: 0.7)
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
                  const Icon(Icons.lock_outline,
                      size: 18, color: Colors.white24)
                else if (isSelected)
                  Icon(Icons.check_circle,
                      size: 20, color: styleId.primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.size = 20});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white12),
      ),
    );
  }
}
