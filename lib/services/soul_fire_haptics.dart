import 'package:flutter/services.dart';

import '../models/app_theme.dart';

enum _H { light, medium, heavy, selection }

/// Unique haptic feedback patterns for each Soul Fire style.
///
/// Disabled by default. When enabled, replaces the generic light/heavy
/// haptics with style-matched rhythmic sequences during hold and
/// on completion.
class SoulFireHaptics {
  SoulFireHaptics._();

  // ── Hold-phase milestones ──
  // Each entry is (progress threshold 0..1, haptic type).
  // Fired once per hold cycle as the hold animation progresses.

  static const _etherealOrb = [
    (0.15, _H.selection), (0.35, _H.light), (0.55, _H.light),
    (0.75, _H.medium), (0.92, _H.medium),
  ];
  static const _goldenPulse = [
    (0.12, _H.selection), (0.18, _H.light),
    (0.30, _H.selection), (0.36, _H.light),
    (0.50, _H.medium), (0.56, _H.light),
    (0.70, _H.medium), (0.76, _H.light),
    (0.88, _H.heavy),
  ];
  static const _nebulaHeart = [
    (0.15, _H.light), (0.18, _H.light), (0.21, _H.selection),
    (0.45, _H.light), (0.48, _H.light), (0.51, _H.selection),
    (0.75, _H.medium), (0.78, _H.light),
  ];
  static const _voidPortal = [
    (0.25, _H.heavy), (0.50, _H.heavy), (0.75, _H.heavy),
  ];
  static const _plasmaBurst = [
    (0.12, _H.selection), (0.24, _H.selection), (0.36, _H.selection),
    (0.48, _H.selection), (0.60, _H.selection), (0.72, _H.selection),
    (0.84, _H.medium),
  ];
  static const _plasmaCell = [
    (0.22, _H.medium), (0.27, _H.medium),
    (0.52, _H.medium), (0.57, _H.medium),
    (0.82, _H.heavy),
  ];
  static const _infinityWell = [
    (0.20, _H.selection), (0.35, _H.light), (0.50, _H.medium),
    (0.65, _H.medium), (0.80, _H.heavy),
  ];
  static const _toxicCore = [
    (0.16, _H.medium), (0.32, _H.medium), (0.48, _H.medium),
    (0.64, _H.medium), (0.80, _H.heavy),
  ];
  static const _crystalAscend = [
    (0.15, _H.selection), (0.20, _H.light),
    (0.40, _H.selection), (0.45, _H.light),
    (0.65, _H.selection), (0.70, _H.medium),
    (0.88, _H.medium),
  ];
  static const _phantomPulse = [
    (0.25, _H.heavy), (0.50, _H.medium), (0.75, _H.light),
  ];

  static List<(double, _H)> _milestonesFor(SoulFireStyleId style) {
    return switch (style) {
      SoulFireStyleId.etherealOrb   => _etherealOrb,
      SoulFireStyleId.goldenPulse   => _goldenPulse,
      SoulFireStyleId.nebulaHeart   => _nebulaHeart,
      SoulFireStyleId.voidPortal    => _voidPortal,
      SoulFireStyleId.plasmaBurst   => _plasmaBurst,
      SoulFireStyleId.plasmaCell    => _plasmaCell,
      SoulFireStyleId.infinityWell  => _infinityWell,
      SoulFireStyleId.toxicCore     => _toxicCore,
      SoulFireStyleId.crystalAscend => _crystalAscend,
      SoulFireStyleId.phantomPulse  => _phantomPulse,
    };
  }

  static void _fire(_H type) {
    switch (type) {
      case _H.light:     HapticFeedback.lightImpact();
      case _H.medium:    HapticFeedback.mediumImpact();
      case _H.heavy:     HapticFeedback.heavyImpact();
      case _H.selection: HapticFeedback.selectionClick();
    }
  }

  /// Fire hold-start haptic. Each style gets a unique initial touch feel.
  static void onHoldStart(SoulFireStyleId style) {
    switch (style) {
      case SoulFireStyleId.etherealOrb:   HapticFeedback.selectionClick();
      case SoulFireStyleId.goldenPulse:   HapticFeedback.lightImpact();
      case SoulFireStyleId.nebulaHeart:   HapticFeedback.lightImpact();
      case SoulFireStyleId.voidPortal:    HapticFeedback.heavyImpact();
      case SoulFireStyleId.plasmaBurst:   HapticFeedback.selectionClick();
      case SoulFireStyleId.plasmaCell:    HapticFeedback.mediumImpact();
      case SoulFireStyleId.infinityWell:  HapticFeedback.lightImpact();
      case SoulFireStyleId.toxicCore:     HapticFeedback.mediumImpact();
      case SoulFireStyleId.crystalAscend: HapticFeedback.selectionClick();
      case SoulFireStyleId.phantomPulse:  HapticFeedback.heavyImpact();
    }
  }

  /// Check hold progress and fire milestone haptics as thresholds are crossed.
  /// [firedIndices] tracks which milestones already fired this hold cycle.
  static void onHoldProgress(
    SoulFireStyleId style,
    double progress,
    Set<int> firedIndices,
  ) {
    final milestones = _milestonesFor(style);
    for (int i = 0; i < milestones.length; i++) {
      if (!firedIndices.contains(i) && progress >= milestones[i].$1) {
        firedIndices.add(i);
        _fire(milestones[i].$2);
      }
    }
  }

  /// Fire unique completion burst. Each style has a distinct rhythm.
  /// Total duration is kept under ~400ms so it completes well before
  /// the 1400ms reset delay.
  static Future<void> onCompletion(SoulFireStyleId style) async {
    switch (style) {
      // Ethereal ripple outward
      case SoulFireStyleId.etherealOrb:
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 80));
        HapticFeedback.heavyImpact();

      // Celestial supernova — ascending crescendo then shockwave
      case SoulFireStyleId.goldenPulse:
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 50));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.lightImpact();

      // Magnetic spike storm
      case SoulFireStyleId.nebulaHeart:
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 25));
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 25));
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 50));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 80));
        HapticFeedback.heavyImpact();

      // Deep void collapse
      case SoulFireStyleId.voidPortal:
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        HapticFeedback.heavyImpact();

      // Electric discharge
      case SoulFireStyleId.plasmaBurst:
        for (int i = 0; i < 5; i++) {
          HapticFeedback.selectionClick();
          await Future.delayed(const Duration(milliseconds: 20));
        }
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.heavyImpact();

      // Binary fusion
      case SoulFireStyleId.plasmaCell:
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 50));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 80));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 50));
        HapticFeedback.mediumImpact();

      // Dimensional fold-unfold
      case SoulFireStyleId.infinityWell:
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 40));
        HapticFeedback.lightImpact();

      // Containment breach then re-seal
      case SoulFireStyleId.toxicCore:
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 35));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 35));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 60));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.selectionClick();

      // Crystal bloom ascending
      case SoulFireStyleId.crystalAscend:
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 30));
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 60));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 80));
        HapticFeedback.heavyImpact();

      // Ghost fadeout
      case SoulFireStyleId.phantomPulse:
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.selectionClick();
    }
  }
}
