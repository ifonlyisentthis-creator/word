import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../widgets/ambient_background.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isUnlocked = false;
  bool _isAuthenticating = false;
  String? _errorMessage;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticateIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth.stopAuthentication());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isSupportedPlatform) return;
    if (state == AppLifecycleState.resumed) {
      _lockAndAuthenticate();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _lock();
    }
  }

  void _lock() {
    if (!_isUnlocked) return;
    setState(() {
      _isUnlocked = false;
    });
  }

  void _lockAndAuthenticate() {
    setState(() {
      _isUnlocked = false;
    });
    _authenticate();
  }

  Future<void> _authenticateIfNeeded() async {
    if (!_isSupportedPlatform) {
      setState(() {
        _isUnlocked = true;
      });
      return;
    }
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        if (!mounted) return;
        setState(() {
          _isAuthenticating = false;
          _errorMessage =
              'Device security is required to unlock Afterword.';
        });
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Unlock Afterword with your device PIN.',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!mounted) return;
      setState(() {
        _isUnlocked = authenticated;
        _isAuthenticating = false;
        if (!authenticated) {
          _errorMessage = 'Authentication required to continue.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _errorMessage = 'Unable to authenticate. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnlocked || !_isSupportedPlatform) {
      return widget.child;
    }

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1B1B1B), Color(0xFF0E0E0E)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          size: 36,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Unlock Afterword',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Device security keeps your vault sealed.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white60),
                      ),
                      const SizedBox(height: 24),
                      if (_isAuthenticating)
                        const CircularProgressIndicator()
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _authenticate,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Unlock Vault'),
                          ),
                        ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
