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

  })  : _profileService = profileService,

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

  bool _protocolWasArchived = false;

  bool _protocolNoEntries = false;

  bool _notificationsReady = false;

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

  bool get protocolWasArchived => _protocolWasArchived;

  bool get protocolNoEntries => _protocolNoEntries;

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



  Future<void> initialize(User user, {String subscriptionStatus = 'free'}) async {

    _user = user;

    _setLoading(true);

    try {

      await _ensureNotifications();

      if (_isDisposed) return;

      final ensured = await _profileService.ensureProfile(user);

      if (_isDisposed) return;

      // Sync subscription status now that the profile row exists.
      // RevenueCat's earlier sync may have fired before the row was created.
      if (kDebugMode) debugPrint('[HC-SYNC] ensured=${ensured.subscriptionStatus}, expected=$subscriptionStatus');
      if (ensured.subscriptionStatus != subscriptionStatus) {
        try {
          await Supabase.instance.client.functions.invoke('verify-subscription');
          if (kDebugMode) debugPrint('[HC-SYNC] Server-verified subscription');
        } catch (e) {
          if (kDebugMode) debugPrint('[HC-SYNC] Error: $e');
        }
      }

      _setProtocolState(ensured);

      _profile = ensured;

      // Sync theme/soul fire from profile ONCE on load (not on every build)
      _themeProvider.syncFromProfile(ensured);

      _errorMessage = null;

      if (ensured.status.toLowerCase() == 'active') {

        await _scheduleReminders();

      }

      await _fetchVaultEntryStatus();

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
      final changed = _profile == null ||
          profile.lastCheckIn != _profile!.lastCheckIn ||
          profile.timerDays != _profile!.timerDays ||
          profile.status != _profile!.status ||
          profile.subscriptionStatus != _profile!.subscriptionStatus;

      _setProtocolState(profile);

      _profile = profile;

      _errorMessage = null;

      if (changed) notifyListeners();

    } catch (_) {

      // Silent background refresh — no error shown

    }

  }



  Future<void> updateSenderName(String senderName) async {

    if (_user == null) return;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return;

    _setLoading(true);

    try {

      _profile = await _profileService.updateSenderName(

        _user!.id,

        senderName,

      );

      _errorMessage = null;

    } catch (_) {

      _errorMessage = 'Unable to update sender name.';

    } finally {

      _setLoading(false);

    }

  }



  Future<void> updateTimerDays(int timerDays) async {

    if (_user == null) return;

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

    if (_user == null) return false;

    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != _user!.id) return false;

    _setLoading(true);

    try {

      _profile = await _profileService.updateCheckIn(_user!.id);

      _errorMessage = null;

      _protocolExecutedAt = null;

      _protocolWasArchived = false;

      _protocolNoEntries = false;

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

    if (profile == null || profile.status.toLowerCase() != 'active') return;

    // No notifications if vault is empty — timer has no effect
    if (!_hasVaultEntries) {
      if (_notificationsReady) {
        try { await _notificationService.cancelAll(); } catch (_) {}
      }
      return;
    }

    if (!_notificationsReady) {

      await _ensureNotifications();

    }

    if (!_notificationsReady) return;

    try {

      await _notificationService.scheduleCheckInReminders(

        profile.lastCheckIn,

        profile.timerDays,

        push66SentAt: profile.push66SentAt,

        push33SentAt: profile.push33SentAt,

      );

    } catch (_) {

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

    if (status != 'active') {

      _protocolExecutedAt = profile.deadline;

      _protocolWasArchived = status == 'archived';

      _protocolNoEntries = status == 'inactive';

    } else {

      _protocolExecutedAt = null;

      _protocolWasArchived = false;

      _protocolNoEntries = false;

    }

  }



  void _setLoading(bool value) {

    if (_isDisposed) return;

    _isLoading = value;

    notifyListeners();

  }

}

