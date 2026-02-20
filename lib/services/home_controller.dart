import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

import 'account_service.dart';

import 'notification_service.dart';

import 'profile_service.dart';

import 'theme_provider.dart';

/// Result of a manual Soul Fire check-in attempt.
enum CheckInResult {
  /// Real Supabase write occurred — timer fully reset.
  success,

  /// 12-hour cooldown active — DB write suppressed, timer unchanged.
  cooldown,

  /// Error (network, auth, etc.) — check-in failed.
  error,
}

class HomeController extends ChangeNotifier {
  HomeController({
    required ProfileService profileService,

    required NotificationService notificationService,

    required AccountService accountService,

    required ThemeProvider themeProvider,
  }) : _profileService = profileService,

       _notificationService = notificationService,

       _accountService = accountService,

       _themeProvider = themeProvider;

  bool _isDisposed = false;

  final ProfileService _profileService;

  final NotificationService _notificationService;

  final AccountService _accountService;

  final ThemeProvider _themeProvider;

  Profile? _profile;

  User? _user;

  bool _isLoading = false;

  String? _errorMessage;

  DateTime? _protocolExecutedAt;

  bool _isInGracePeriod = false;

  DateTime? _graceEndDate;

  bool _hasVaultEntries = false;
  int _vaultEntryCount = 0;

  Profile? get profile => _profile;

  void updateProfileFromPreferences(Profile updated) {
    _profile = updated;
    notifyListeners();
  }

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  DateTime? get protocolExecutedAt => _protocolExecutedAt;

  bool get isInGracePeriod => _isInGracePeriod;

  DateTime? get graceEndDate => _graceEndDate;

  Duration get graceTimeRemaining {
    if (_graceEndDate == null) return Duration.zero;
    final remaining = _graceEndDate!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get graceExpired =>
      _isInGracePeriod &&
      _graceEndDate != null &&
      DateTime.now().isAfter(_graceEndDate!);

  bool get hasVaultEntries => _hasVaultEntries;
  int get vaultEntryCount => _vaultEntryCount;

  @override
  void notifyListeners() {
    if (_isDisposed) return;

    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;

    super.dispose();
  }

  Future<void> initialize(
    User user, {
    String subscriptionStatus = 'free',
  }) async {
    _user = user;

    _setLoading(true);

    try {
      var ensured = await _profileService.ensureProfile(user);

      if (_isDisposed) return;

      // Sync subscription status now that the profile row exists.
      // RevenueCat's earlier sync may have fired before the row was created.
      if (kDebugMode) {
        debugPrint(
          '[HC-SYNC] ensured=${ensured.subscriptionStatus}, expected=$subscriptionStatus',
        );
      }
      if (ensured.subscriptionStatus != subscriptionStatus) {
        try {
          await Supabase.instance.client.functions.invoke(
            'verify-subscription',
          );
          if (kDebugMode) debugPrint('[HC-SYNC] Server-verified subscription');
          // Re-fetch profile so we have the updated subscription_status
          if (!_isDisposed) {
            ensured = await _profileService.fetchProfile(user.id);
            if (kDebugMode) {
              debugPrint(
                '[HC-SYNC] Re-fetched profile: sub=${ensured.subscriptionStatus}',
              );
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[HC-SYNC] Error: $e');
        }
      }

      _setProtocolState(ensured);

      _profile = ensured;

      // Sync theme/soul fire from profile ONCE on load (not on every build)
      _themeProvider.syncFromProfile(ensured);

      _errorMessage = null;

      await _fetchVaultEntryStatus();

      if (ensured.status.toLowerCase() == 'active') {
        unawaited(_scheduleReminders());
      }
    } catch (error) {
      _errorMessage = 'Unable to load your timer. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  /// Re-fetch profile + sync theme after a purchase so Pro/Lifetime
  /// features unlock instantly without restarting.
  Future<void> refreshAfterPurchase() async {
    if (_user == null) return;
    try {
      final profile = await _profileService.fetchProfile(_user!.id);
      if (_isDisposed) return;
      _profile = profile;
      _themeProvider.syncFromProfile(profile);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> deleteAccount() async {
    if (_user == null) return false;

    _setLoading(true);

    try {
      await _accountService.deleteAccount(_user!.id);

      try { await _notificationService.cancelAll(); } catch (_) {}

      _profile = null;

      _errorMessage = null;

      return true;
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      _errorMessage = 'Unable to delete your account.';

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> autoCheckIn() async {
    if (_user == null) return;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return;

    try {
      final profile = await _profileService.fetchProfile(_user!.id);

      if (_isDisposed) return;

      // Only notify if data actually changed — prevents UI flicker on resume
      final changed =
          _profile == null ||
          profile.lastCheckIn != _profile!.lastCheckIn ||
          profile.timerDays != _profile!.timerDays ||
          profile.status != _profile!.status ||
          profile.subscriptionStatus != _profile!.subscriptionStatus ||
          profile.protocolExecutedAt != _profile!.protocolExecutedAt;

      _setProtocolState(profile);

      _profile = profile;

      _errorMessage = null;

      if (changed) notifyListeners();
    } catch (_) {
      // Silent background refresh — no error shown
    }
  }

  Future<void> updateSenderName(String senderName) async {
    if (_user == null || _isInGracePeriod) return;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return;

    _setLoading(true);

    try {
      _profile = await _profileService.updateSenderName(_user!.id, senderName);

      _errorMessage = null;
    } catch (_) {
      _errorMessage = 'Unable to update sender name.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateTimerDays(int timerDays) async {
    if (_user == null || _isInGracePeriod) return;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return;

    _setLoading(true);

    try {
      _profile = await _profileService.updateTimerDays(timerDays);

      _errorMessage = null;

      await _scheduleReminders();
    } catch (_) {
      _errorMessage = 'Unable to update your timer.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshProfile() async {
    if (_user == null) return;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return;

    try {
      final profile = await _profileService.fetchProfile(_user!.id);

      if (_isDisposed) return;

      _profile = profile;

      _setProtocolState(profile);

      _errorMessage = null;

      notifyListeners();

      await _scheduleReminders();
    } catch (_) {
      // Silent refresh — no error shown
    }
  }

  // ── 12-hour write cooldown ──
  // The Soul Fire animation always plays. The actual Supabase UPDATE is
  // silently skipped when less than _checkInCooldown has elapsed since the
  // last server-confirmed check-in. This prevents thousands of unnecessary
  // DB writes from users spamming the orb.
  //
  // UI contract:
  //   CheckInResult.success  → "Signal Verified" snackbar, timer UI resets
  //   CheckInResult.cooldown → "Vault Secure"   snackbar, timer UI unchanged
  //   CheckInResult.error    → error snackbar
  //
  // Timer progress bar and text are driven by _profile.lastCheckIn. Since we
  // do NOT update _profile on cooldown, the timer UI stays truthful.
  //
  // The cooldown source of truth is _profile.lastCheckIn (loaded from the
  // server on login and refreshed after every successful write). An in-memory
  // _lastWriteAt acts as a second layer so even stale profile data can't
  // cause duplicate writes within a single session.
  //
  // The 12-hour restriction applies ONLY to Soul Fire manual presses.
  // Timer adjustments (updateTimerDays), subscription snapping, and account
  // deletion all bypass this cooldown entirely.
  static const _checkInCooldown = Duration(hours: 12);
  DateTime? _lastWriteAt;

  Future<CheckInResult> manualCheckIn() async {
    if (_user == null || _isInGracePeriod) return CheckInResult.error;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) {
      return CheckInResult.error;
    }

    // ── Cooldown gate ──
    final now = DateTime.now();
    final serverLastCheckIn = _profile?.lastCheckIn;

    // Layer 1: server-sourced timestamp
    final serverCooldownOk = serverLastCheckIn == null ||
        now.difference(serverLastCheckIn.toLocal()) >= _checkInCooldown;

    // Layer 2: in-memory session guard
    final sessionCooldownOk = _lastWriteAt == null ||
        now.difference(_lastWriteAt!) >= _checkInCooldown;

    final needsWrite = serverCooldownOk && sessionCooldownOk;

    if (!needsWrite) {
      // Cooldown active — skip DB write. Timer UI stays as-is because
      // _profile is not touched. Return cooldown so caller can show
      // "Vault Secure" instead of "Signal Verified".
      return CheckInResult.cooldown;
    }

    _setLoading(true);

    try {
      _profile = await _profileService.updateCheckIn(_user!.id);

      _lastWriteAt = DateTime.now();

      _errorMessage = null;

      _protocolExecutedAt = null;

      _isInGracePeriod = false;

      _graceEndDate = null;

      notifyListeners();

      await _scheduleReminders();

      return CheckInResult.success;
    } catch (e) {
      debugPrint('manualCheckIn error: $e');

      _errorMessage = 'Unable to check in. Please try again.';

      return CheckInResult.error;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _scheduleReminders() async {
    final profile = _profile;

    if (profile == null || profile.status.toLowerCase() != 'active') {
      if (kDebugMode) {
        debugPrint('[NOTIF] Skipped: profile null or not active');
      }
      return;
    }

    // No notifications if vault is empty — timer has no effect
    if (!_hasVaultEntries) {
      if (kDebugMode) {
        debugPrint('[NOTIF] Vault empty, cancelling notifications');
      }
      try {
        await _notificationService.cancelAll();
      } catch (_) {}
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint(
          '[NOTIF] Server-authoritative reminder flow active. '
          'Clearing any legacy local reminder notifications.',
        );
      }

      await _notificationService.initialize();

      await _notificationService.scheduleCheckInReminders(
        profile.lastCheckIn,

        profile.timerDays,

        push66SentAt: profile.push66SentAt,

        push33SentAt: profile.push33SentAt,
      );

      if (kDebugMode) debugPrint('[NOTIF] Reminders scheduled successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[NOTIF] Schedule failed: $e');
    }
  }

  Future<void> _fetchVaultEntryStatus() async {
    if (_user == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('vault_entries')
          .select('id')
          .eq('user_id', _user!.id)
          .eq('status', 'active');
      final list = rows as List;
      _hasVaultEntries = list.isNotEmpty;
      _vaultEntryCount = list.length;
      if (kDebugMode) {
        debugPrint(
          '[NOTIF] Vault entries: $_vaultEntryCount, hasEntries=$_hasVaultEntries',
        );
      }
    } catch (_) {
      // Best-effort; leave current value.
    }
  }

  Future<void> refreshVaultStatus() async {
    final hadEntries = _hasVaultEntries;
    await _fetchVaultEntryStatus();
    notifyListeners();
    // If vault status changed, reschedule (or cancel) notifications
    if (_hasVaultEntries != hadEntries) {
      await _scheduleReminders();
    }
  }

  void _setProtocolState(Profile profile) {
    final status = profile.status.toLowerCase();
    final executed = profile.protocolExecutedAt;

    // Grace period requires BOTH: protocol_executed_at timestamp set
    // AND status inactive/archived (entries were sent to beneficiaries).
    if (executed != null && (status == 'inactive' || status == 'archived')) {
      _protocolExecutedAt = executed;

      _isInGracePeriod = true;

      _graceEndDate = executed.add(const Duration(days: 30));
    } else {
      _protocolExecutedAt = null;

      _isInGracePeriod = false;

      _graceEndDate = null;
    }
  }

  void _setLoading(bool value) {
    if (_isDisposed) return;

    _isLoading = value;

    notifyListeners();
  }
}
