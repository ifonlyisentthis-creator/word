import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../models/profile.dart';

/// Manages the selected theme and soul fire style.
/// Reads from Profile on init, persists changes via ProfileService RPC.
class ThemeProvider extends ChangeNotifier {
  AppThemeId _themeId = AppThemeId.oledVoid;
  SoulFireStyleId _soulFireId = SoulFireStyleId.etherealOrb;
  String _subscriptionStatus = 'free';

  AppThemeId get themeId => _themeId;
  SoulFireStyleId get soulFireId => _soulFireId;
  String get subscriptionStatus => _subscriptionStatus;

  AppThemeData get themeData => AppThemeData.fromId(_themeId);
  ThemeData get flutterTheme => themeData.toFlutterTheme();

  /// Sync state from a fetched Profile.
  /// Only notifies listeners if something actually changed.
  void syncFromProfile(Profile profile) {
    final oldSub = _subscriptionStatus;
    final oldTheme = _themeId;
    final oldSf = _soulFireId;

    _subscriptionStatus = profile.subscriptionStatus;

    // Parse theme from profile, fallback to default if invalid or locked
    final savedTheme = profile.selectedTheme;
    if (savedTheme != null) {
      try {
        final parsed = AppThemeId.values.firstWhere((e) => e.key == savedTheme);
        if (parsed.isUnlocked(profile.subscriptionStatus)) {
          _themeId = parsed;
        } else {
          _themeId = AppThemeId.oledVoid;
        }
      } catch (_) {
        _themeId = AppThemeId.oledVoid;
      }
    }

    // Parse soul fire style from profile
    final savedSoulFire = profile.selectedSoulFire;
    if (savedSoulFire != null) {
      try {
        final parsed =
            SoulFireStyleId.values.firstWhere((e) => e.key == savedSoulFire);
        if (parsed.isUnlocked(profile.subscriptionStatus)) {
          _soulFireId = parsed;
        } else {
          _soulFireId = SoulFireStyleId.etherealOrb;
        }
      } catch (_) {
        _soulFireId = SoulFireStyleId.etherealOrb;
      }
    }

    if (_subscriptionStatus != oldSub ||
        _themeId != oldTheme ||
        _soulFireId != oldSf) {
      notifyListeners();
    }
  }

  /// Called when user selects a new theme. Returns true if changed.
  bool selectTheme(AppThemeId id) {
    if (!id.isUnlocked(_subscriptionStatus)) return false;
    if (_themeId == id) return false;
    _themeId = id;
    notifyListeners();
    return true;
  }

  /// Called when user selects a new soul fire style. Returns true if changed.
  bool selectSoulFire(SoulFireStyleId id) {
    if (!id.isUnlocked(_subscriptionStatus)) return false;
    if (_soulFireId == id) return false;
    _soulFireId = id;
    notifyListeners();
    return true;
  }

  /// If subscription downgrades, revert to free defaults.
  void enforceSubscriptionLimits(String newStatus) {
    _subscriptionStatus = newStatus;
    if (!_themeId.isUnlocked(newStatus)) {
      _themeId = AppThemeId.oledVoid;
    }
    if (!_soulFireId.isUnlocked(newStatus)) {
      _soulFireId = SoulFireStyleId.etherealOrb;
    }
    notifyListeners();
  }
}
