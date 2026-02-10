import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_service.dart';
import 'revenuecat_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required SupabaseClient supabaseClient,
    required RevenueCatController revenueCatController,
    required String redirectUrl,
    required PushService pushService,
  })  : _supabaseClient = supabaseClient,
        _revenueCatController = revenueCatController,
        _pushService = pushService;

  final SupabaseClient _supabaseClient;
  final RevenueCatController _revenueCatController;
  final PushService _pushService;

  GoogleSignIn _buildGoogleSignIn() {
    const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    return GoogleSignIn(
      serverClientId: webClientId.isEmpty ? null : webClientId,
      scopes: const ['email'],
    );
  }

  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  User? _user;
  AuthFailure? _lastFailure;
  bool _isLoading = false;
  bool _signingOut = false;

  Session? get session => _session;
  User? get user => _user;
  AuthFailure? get lastFailure => _lastFailure;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _session != null;
  bool get isSigningOut => _signingOut;

  Future<void> initialize() async {
    _session = _supabaseClient.auth.currentSession;
    _user = _session?.user;
    if (_user != null) {
      await _pushService.onSignIn(_user!.id);
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
      final signIn = _buildGoogleSignIn();

      await signIn.disconnect().catchError((_) { return null; });
      await signIn.signOut().catchError((_) { return null; });
      final account = await signIn.signIn();
      if (account == null) {
        _lastFailure = null;
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null || idToken.isEmpty) {
        _lastFailure = const AuthFailure(
          'Google sign-in failed. Please try again.',
        );
        return;
      }

      await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
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

  /// Call before signOut to remove HomeScreen from the widget tree
  /// before the actual auth state change. This prevents the
  /// _dependents.isEmpty assertion in InheritedElement.unmount().
  void prepareSignOut() {
    _signingOut = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _pushService.onSignOut();

      final googleSignIn = _buildGoogleSignIn();
      await googleSignIn.signOut().catchError((_) { return null; });
      await googleSignIn.disconnect().catchError((_) { return null; });

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
    final hadUser = _user != null;
    _session = data.session;
    _user = data.session?.user;
    if (_user != null) {
      _signingOut = false;
      await _pushService.onSignIn(_user!.id);
      await _revenueCatController.logIn(_user!.id);
    } else if (hadUser) {
      // Only log out if we previously had a signed-in user.
      // Avoids "Called logOut but the current user is anonymous" on startup.
      await _pushService.onSignOut();
      await _revenueCatController.logOut();
      _signingOut = false;
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
