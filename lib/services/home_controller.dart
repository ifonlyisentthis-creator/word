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

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get protocolExecutedAt => _protocolExecutedAt;
  bool get protocolWasArchived => _protocolWasArchived;
  bool get protocolNoEntries => _protocolNoEntries;

  Future<void> initialize(User user) async {
    _user = user;
    _setLoading(true);
    try {
      await _ensureNotifications();
      final ensured = await _profileService.ensureProfile(user);
      _setProtocolState(ensured);
      if (ensured.status.toLowerCase() == 'active') {
        final updated = await _profileService.updateCheckIn(user.id);
        _profile = updated.copyWith(senderName: ensured.senderName);
        _errorMessage = null;
        await _scheduleReminders();
      } else {
        _profile = ensured;
        _errorMessage = null;
      }
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
    try {
      final profile = await _profileService.fetchProfile(_user!.id);
      _setProtocolState(profile);
      if (profile.status.toLowerCase() != 'active') {
        _profile = profile;
        _errorMessage = null;
        notifyListeners();
        return;
      }
      _profile = await _profileService.updateCheckIn(_user!.id);
      _errorMessage = null;
      await _scheduleReminders();
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Unable to refresh your timer.';
      notifyListeners();
    }
  }

  Future<void> updateSenderName(String senderName) async {
    if (_user == null) return;
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
    await _notificationService.initialize();
    _notificationsReady = true;
  }

  Future<void> _scheduleReminders() async {
    final profile = _profile;
    if (profile == null || profile.status.toLowerCase() != 'active') return;
    await _notificationService.scheduleCheckInReminders(
      profile.lastCheckIn,
      profile.timerDays,
    );
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
    _isLoading = value;
    notifyListeners();
  }
}
