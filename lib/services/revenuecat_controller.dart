import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatController extends ChangeNotifier {
  RevenueCatController({required this.entitlementId});

  final String entitlementId;

  CustomerInfo? _customerInfo;
  Offerings? _offerings;
  RevenueCatFailure? _lastFailure;
  bool _isConfigured = false;
  bool _isLoading = false;

  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;
  RevenueCatFailure? get lastFailure => _lastFailure;
  bool get isConfigured => _isConfigured;
  bool get isLoading => _isLoading;

  bool get isPro =>
      _customerInfo?.entitlements.active.containsKey(entitlementId) ?? false;

  bool get isLifetime =>
      _customerInfo?.allPurchasedProductIdentifiers.contains('lifetime') ??
      false;

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
      final customerInfo = await Purchases.purchasePackage(package);
      _customerInfo = customerInfo;
      _lastFailure = null;
      return customerInfo;
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
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  RevenueCatFailure _mapFailure(PlatformException exception) {
    final code = PurchasesErrorHelper.getErrorCode(exception);
    final message = exception.message ??
        'RevenueCat error${code != null ? ' (${code.name})' : ''}.';
    return RevenueCatFailure(message, code: code);
  }
}

class RevenueCatFailure {
  const RevenueCatFailure(this.message, {this.code});

  final String message;
  final PurchasesErrorCode? code;
}
