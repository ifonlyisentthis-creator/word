import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RevenueCatController extends ChangeNotifier {
  RevenueCatController({required this.entitlementId});

  final String entitlementId;

  CustomerInfo? _customerInfo;
  Offerings? _offerings;
  RevenueCatFailure? _lastFailure;
  bool _isConfigured = false;
  bool _isLoading = false;
  bool _isSyncing = false;
  DateTime? _lastSyncAttempt;

  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;
  RevenueCatFailure? get lastFailure => _lastFailure;
  bool get isConfigured => _isConfigured;
  bool get isLoading => _isLoading;

  bool get isPro =>
      _customerInfo?.entitlements.active.containsKey(entitlementId) ?? false;

  bool get isLifetime {
    final active = _customerInfo?.entitlements.active;
    if (active == null || active.isEmpty) return false;
    return active.values
        .any((ent) => ent.productIdentifier.toLowerCase().contains('lifetime'));
  }

  Future<void> configure({required String apiKey}) async {
    if (_isConfigured) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _lastFailure = const RevenueCatFailure(
        'RevenueCat is only supported on iOS/Android builds.',
      );
      notifyListeners();
      return;
    }
    if (kDebugMode) {
      Purchases.setLogLevel(LogLevel.debug);
    }
    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      Purchases.addCustomerInfoUpdateListener(_handleCustomerInfoUpdate);
      _isConfigured = true;
      notifyListeners();
      await refresh();
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!_isConfigured) return;
    _setLoading(true);
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _offerings = await Purchases.getOfferings();
      _lastFailure = null;
      await _syncSubscriptionStatus();
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logIn(String userId) async {
    if (!_isConfigured) return;
    _setLoading(true);
    try {
      final result = await Purchases.logIn(userId);
      _customerInfo = result.customerInfo;
      _lastFailure = null;
      await _syncSubscriptionStatus(force: true);
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logOut() async {
    if (!_isConfigured) return;
    _setLoading(true);
    try {
      await Purchases.logOut();
      _customerInfo = await Purchases.getCustomerInfo();
      _lastFailure = null;
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
    } finally {
      _setLoading(false);
    }
  }

  Future<CustomerInfo?> purchasePackage(Package package) async {
    if (!_isConfigured) return null;
    _setLoading(true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      _lastFailure = null;
      await _syncSubscriptionStatus(force: true);
      return _customerInfo;
    } on PlatformException catch (exception) {
      final errorCode = PurchasesErrorHelper.getErrorCode(exception);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return null;
      }
      _lastFailure = _mapFailure(exception);
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<CustomerInfo?> restore() async {
    if (!_isConfigured) return null;
    _setLoading(true);
    try {
      final customerInfo = await Purchases.restorePurchases();
      _customerInfo = customerInfo;
      _lastFailure = null;
      await _syncSubscriptionStatus(force: true);
      return customerInfo;
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<PaywallResult?> presentPaywall() async {
    if (!_isConfigured) return null;
    try {
      final result = await RevenueCatUI.presentPaywall();
      await refresh();
      return result;
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
      notifyListeners();
      return null;
    }
  }

  Future<PaywallResult?> presentPaywallIfNeeded() async {
    if (!_isConfigured) return null;
    try {
      final result = await RevenueCatUI.presentPaywallIfNeeded(entitlementId);
      await refresh();
      return result;
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
      notifyListeners();
      return null;
    }
  }

  Future<void> presentCustomerCenter() async {
    if (!_isConfigured) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
      await refresh();
    } on PlatformException catch (exception) {
      _lastFailure = _mapFailure(exception);
      notifyListeners();
    }
  }

  void _handleCustomerInfoUpdate(CustomerInfo info) {
    _customerInfo = info;
    _lastFailure = null;
    // Only sync here if no explicit method (purchase, restore, etc.) is
    // already in progress — those methods call _syncSubscriptionStatus
    // themselves, so we'd duplicate the RPC otherwise.
    if (!_isLoading && !_isSyncing) {
      _syncSubscriptionStatus();
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> _syncSubscriptionStatus({bool force = false}) async {
    // Debounce: skip if already syncing or if last attempt was < 30s ago.
    // force=true bypasses debounce (used after purchase/restore/logIn).
    if (_isSyncing) return;
    if (!force) {
      final now = DateTime.now();
      if (_lastSyncAttempt != null &&
          now.difference(_lastSyncAttempt!).inSeconds < 30) {
        if (kDebugMode) debugPrint('[RC-SYNC] Debounced (< 30s since last attempt)');
        return;
      }
    }
    _isSyncing = true;
    _lastSyncAttempt = DateTime.now();
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (kDebugMode) debugPrint('[RC-SYNC] No Supabase user, skipping sync');
        return;
      }
      if (kDebugMode) debugPrint('[RC-SYNC] Verifying subscription server-side for ${user.id}');

      // Ensure the JWT is fresh before calling the Edge Function.
      try {
        await client.auth.refreshSession();
      } catch (_) {}

      final res = await client.functions.invoke('verify-subscription');
      if (kDebugMode) debugPrint('[RC-SYNC] Server verified: ${res.data}');
    } catch (e) {
      if (kDebugMode) debugPrint('[RC-SYNC] Error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  RevenueCatFailure _mapFailure(PlatformException exception) {
    final code = PurchasesErrorHelper.getErrorCode(exception);
    final message = exception.message ?? 'RevenueCat error (${code.name}).';
    return RevenueCatFailure(message, code: code);
  }
}

class RevenueCatFailure {
  const RevenueCatFailure(this.message, {this.code});

  final String message;
  final PurchasesErrorCode? code;
}
