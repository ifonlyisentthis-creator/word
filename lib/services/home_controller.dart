import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

import 'account_service.dart';

import 'notification_service.dart';

import 'profile_service.dart';

import 'theme_provider.dart';

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

  bool _notificationsReady = false;
  String? _lastReminderFingerprint;

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
      await _ensureNotifications();

      if (_isDisposed) return;

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
      await _ensureNotifications();

      await _accountService.deleteAccount(_user!.id);

      await _notificationService.cancelAll();

      _profile = null;

      _errorMessage = null;

      return true;
    } catch (_) {
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

  Future<bool> manualCheckIn() async {
    if (_user == null || _isInGracePeriod) return false;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return false;

    _setLoading(true);

    try {
      _profile = await _profileService.updateCheckIn(_user!.id);

      _errorMessage = null;

      _protocolExecutedAt = null;

      _isInGracePeriod = false;

      _graceEndDate = null;

      notifyListeners();

      await _scheduleReminders();

      return true;
    } catch (e) {
      debugPrint('manualCheckIn error: $e');

      _errorMessage = 'Unable to check in. Please try again.';

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;

    try {
      await _notificationService.initialize();

      _notificationsReady = true;
    } catch (_) {
      _notificationsReady = false;
    }
  }

  Future<void> _scheduleReminders() async {
    final profile = _profile;

    if (profile == null || profile.status.toLowerCase() != 'active') {
      if (kDebugMode) debugPrint('[NOTIF] Skipped: profile null or not active');
      _lastReminderFingerprint = null;
      return;
    }

    final fingerprint =
        '${profile.lastCheckIn.toUtc().toIso8601String()}|'
        '${profile.timerDays}|'
        '${profile.push66SentAt?.toUtc().toIso8601String() ?? ''}|'
        '${profile.push33SentAt?.toUtc().toIso8601String() ?? ''}|'
        '${_hasVaultEntries ? 1 : 0}';
    if (_lastReminderFingerprint == fingerprint) {
      if (kDebugMode) debugPrint('[NOTIF] Skipped: schedule unchanged');
      return;
    }

    // No notifications if vault is empty — timer has no effect
    if (!_hasVaultEntries) {
      if (kDebugMode) {
        debugPrint('[NOTIF] Vault empty, cancelling notifications');
      }
      if (_notificationsReady) {
        try {
          await _notificationService.cancelAll();
        } catch (_) {}
      }
      _lastReminderFingerprint = fingerprint;
      return;
    }

    if (!_notificationsReady) {
      await _ensureNotifications();
    }

    if (!_notificationsReady) return;

    try {
      if (kDebugMode) {
        debugPrint(
          '[NOTIF] Scheduling: lastCheckIn=${profile.lastCheckIn}, '
          'timerDays=${profile.timerDays}, '
          'push66=${profile.push66SentAt}, push33=${profile.push33SentAt}',
        );
      }

      await _notificationService.scheduleCheckInReminders(
        profile.lastCheckIn,

        profile.timerDays,

        push66SentAt: profile.push66SentAt,

        push33SentAt: profile.push33SentAt,
      );

      _lastReminderFingerprint = fingerprint;

      if (kDebugMode) debugPrint('[NOTIF] Reminders scheduled successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('[NOTIF] Schedule failed: $e');

      _notificationsReady = false;
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
