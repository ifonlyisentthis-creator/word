import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_theme.dart';
import '../models/profile.dart';

/// Manages the selected theme and soul fire style.
/// Caches preferences locally so the correct theme is applied before
/// the network profile fetch completes (prevents theme flicker).
class ThemeProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _keyTheme = 'cached_theme';
  static const _keySoulFire = 'cached_soul_fire';
  static const _keySub = 'cached_sub_status';

  AppThemeId _themeId = AppThemeId.oledVoid;
  SoulFireStyleId _soulFireId = SoulFireStyleId.etherealOrb;
  String _subscriptionStatus = 'free';

  AppThemeId get themeId => _themeId;
  SoulFireStyleId get soulFireId => _soulFireId;
  String get subscriptionStatus => _subscriptionStatus;

  AppThemeData get themeData => AppThemeData.fromId(_themeId);
  ThemeData get flutterTheme => themeData.toFlutterTheme();

  /// Load cached preferences from local storage (call during splash).
  /// This is synchronous-safe: if cache is empty, defaults are kept.
  Future<void> loadCached() async {
    try {
      final cachedTheme = await _storage.read(key: _keyTheme);
      final cachedSf = await _storage.read(key: _keySoulFire);
      final cachedSub = await _storage.read(key: _keySub) ?? 'free';
      _subscriptionStatus = cachedSub;
      if (cachedTheme != null) {
        try {
          final parsed = AppThemeId.values.firstWhere((e) => e.key == cachedTheme);
          if (parsed.isUnlocked(cachedSub)) _themeId = parsed;
        } catch (_) {}
      }
      if (cachedSf != null) {
        try {
          final parsed = SoulFireStyleId.values.firstWhere((e) => e.key == cachedSf);
          if (parsed.isUnlocked(cachedSub)) _soulFireId = parsed;
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {
      // Cache read failed — keep defaults, no flicker is worse than wrong theme
    }
  }

  /// Persist current selections to local cache.
  Future<void> _saveToCache() async {
    try {
      await Future.wait([
        _storage.write(key: _keyTheme, value: _themeId.key),
        _storage.write(key: _keySoulFire, value: _soulFireId.key),
        _storage.write(key: _keySub, value: _subscriptionStatus),
      ]);
    } catch (_) {}
  }

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
      _saveToCache();
    }
  }

  /// Called when user selects a new theme. Returns true if changed.
  bool selectTheme(AppThemeId id) {
    if (!id.isUnlocked(_subscriptionStatus)) return false;
    if (_themeId == id) return false;
    _themeId = id;
    notifyListeners();
    _saveToCache();
    return true;
  }

  /// Called when user selects a new soul fire style. Returns true if changed.
  bool selectSoulFire(SoulFireStyleId id) {
    if (!id.isUnlocked(_subscriptionStatus)) return false;
    if (_soulFireId == id) return false;
    _soulFireId = id;
    notifyListeners();
    _saveToCache();
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

  /// Reset to free defaults. Call on sign-out so the next user
  /// doesn't inherit the previous user's premium theme.
  void reset() {
    _themeId = AppThemeId.oledVoid;
    _soulFireId = SoulFireStyleId.etherealOrb;
    _subscriptionStatus = 'free';
    notifyListeners();
    _saveToCache();
  }
}
