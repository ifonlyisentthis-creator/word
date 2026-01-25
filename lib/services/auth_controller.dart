import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'revenuecat_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required SupabaseClient supabaseClient,
    required RevenueCatController revenueCatController,
    required String redirectUrl,
  })  : _supabaseClient = supabaseClient,
        _revenueCatController = revenueCatController,
        _redirectUrl = redirectUrl;

  final SupabaseClient _supabaseClient;
  final RevenueCatController _revenueCatController;
  final String _redirectUrl;

  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  User? _user;
  AuthFailure? _lastFailure;
  bool _isLoading = false;

  Session? get session => _session;
  User? get user => _user;
  AuthFailure? get lastFailure => _lastFailure;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _session != null;

  Future<void> initialize() async {
    _session = _supabaseClient.auth.currentSession;
    _user = _session?.user;
    if (_user != null) {
      await _revenueCatController.logIn(_user!.id);
    }
    _authSubscription = _supabaseClient.auth.onAuthStateChange.listen(
      (data) async {
        await _handleAuthState(data);
      },
    );
  }

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      await _supabaseClient.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
      );
      _lastFailure = null;
    } on AuthException catch (exception) {
      _lastFailure = AuthFailure(exception.message);
    } catch (_) {
      _lastFailure = const AuthFailure('Unable to sign in. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _supabaseClient.auth.signOut();
      _lastFailure = null;
    } on AuthException catch (exception) {
      _lastFailure = AuthFailure(exception.message);
    } catch (_) {
      _lastFailure = const AuthFailure('Unable to sign out. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleAuthState(AuthState data) async {
    _session = data.session;
    _user = data.session?.user;
    if (_user != null) {
      await _revenueCatController.logIn(_user!.id);
    } else {
      await _revenueCatController.logOut();
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

class AuthFailure {
  const AuthFailure(this.message);

  final String message;
}
