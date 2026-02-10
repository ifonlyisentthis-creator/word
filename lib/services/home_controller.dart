import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



import '../models/profile.dart';

import 'account_service.dart';

import 'notification_service.dart';

import 'profile_service.dart';



class HomeController extends ChangeNotifier {

  HomeController({

    required ProfileService profileService,

    required NotificationService notificationService,

    required AccountService accountService,

  })  : _profileService = profileService,

        _notificationService = notificationService,

        _accountService = accountService;



  bool _isDisposed = false;



  final ProfileService _profileService;

  final NotificationService _notificationService;

  final AccountService _accountService;



  Profile? _profile;

  User? _user;

  bool _isLoading = false;

  String? _errorMessage;

  DateTime? _protocolExecutedAt;

  bool _protocolWasArchived = false;

  bool _protocolNoEntries = false;

  bool _notificationsReady = false;

  bool _hasVaultEntries = false;



  Profile? get profile => _profile;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  DateTime? get protocolExecutedAt => _protocolExecutedAt;

  bool get protocolWasArchived => _protocolWasArchived;

  bool get protocolNoEntries => _protocolNoEntries;

  bool get hasVaultEntries => _hasVaultEntries;



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

      if (ensured.status.toLowerCase() == 'active') {

        try {

          final updated = await _profileService.updateCheckIn(user.id);

          if (_isDisposed) return;

          _profile = updated.copyWith(senderName: ensured.senderName);

          _errorMessage = null;

        } catch (_) {

          _errorMessage = 'Unable to refresh your timer.';

        }

        await _scheduleReminders();

      } else {

        _profile = ensured;

        _errorMessage = null;

      }

      await _fetchVaultEntryStatus();

    } catch (error) {

      _errorMessage = 'Unable to load your timer. Please try again.';

    } finally {

      _setLoading(false);

    }

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

      _setProtocolState(profile);

      if (profile.status.toLowerCase() != 'active') {

        _profile = profile;

        _errorMessage = null;

        notifyListeners();

        return;

      }

      _profile = profile;

      try {

        _profile = await _profileService.updateCheckIn(_user!.id);

        if (_isDisposed) return;

        _errorMessage = null;

      } catch (_) {

        _errorMessage = 'Unable to refresh your timer.';

      }

      await _scheduleReminders();

      notifyListeners();

    } catch (_) {

      _errorMessage = 'Unable to refresh your timer.';

      notifyListeners();

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

      _profile = await _profileService.updateCheckIn(

        _user!.id,

        timerDays: timerDays,

      );

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

    _setLoading(true);

    try {

      final profile = await _profileService.fetchProfile(_user!.id);

      _profile = profile;

      _setProtocolState(profile);

      _errorMessage = null;

      await _scheduleReminders();

    } catch (_) {

      _errorMessage = 'Unable to refresh your profile.';

    } finally {

      _setLoading(false);

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

      await _scheduleReminders();

      return true;

    } catch (_) {

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

    if (!_notificationsReady) {

      await _ensureNotifications();

    }

    if (!_notificationsReady) return;

    try {

      await _notificationService.scheduleCheckInReminders(

        profile.lastCheckIn,

        profile.timerDays,

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
          .eq('status', 'active')
          .limit(1);
      _hasVaultEntries = (rows as List).isNotEmpty;
    } catch (_) {
      // Best-effort; leave current value.
    }
  }

  Future<void> refreshVaultStatus() async {
    await _fetchVaultEntryStatus();
    notifyListeners();
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

