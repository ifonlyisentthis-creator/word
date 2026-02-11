import 'package:flutter/material.dart';

import 'package:provider/provider.dart';



import '../services/auth_controller.dart';

import '../widgets/ambient_background.dart';

import 'app_lock_gate.dart';

import 'home_screen.dart';




class AuthGate extends StatefulWidget {

  const AuthGate({super.key});



  @override

  State<AuthGate> createState() => _AuthGateState();

}



class _AuthGateState extends State<AuthGate> {

  @override

  Widget build(BuildContext context) {

    return Consumer<AuthController>(

      builder: (context, authController, child) {

        if (authController.isSigningOut) {

          return const Scaffold(

            body: Center(child: CircularProgressIndicator()),

          );

        }

        if (authController.isSignedIn) {

          return const AppLockGate(child: HomeScreen());

        }

        return _SignInScreen(authController: authController);

      },

    );

  }

}



class _SignInScreen extends StatelessWidget {

  const _SignInScreen({required this.authController});



  final AuthController authController;



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final cardDecoration = BoxDecoration(

      gradient: const LinearGradient(

        begin: Alignment.topLeft,

        end: Alignment.bottomRight,

        colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],

      ),

      borderRadius: BorderRadius.circular(24),

      border: Border.all(color: Colors.white12),

      boxShadow: [

        BoxShadow(

          color: Colors.black.withValues(alpha: 0.4),

          blurRadius: 18,

          offset: const Offset(0, 14),

        ),

      ],

    );

    return Scaffold(

      body: Stack(

        children: [

          const RepaintBoundary(child: AmbientBackground()),

          SafeArea(

            child: Center(

              child: ConstrainedBox(

                constraints: const BoxConstraints(maxWidth: 420),

                child: SingleChildScrollView(

                  padding: const EdgeInsets.all(28),

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.center,

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

                          size: 32,

                          color: theme.colorScheme.primary,

                        ),

                      ),

                      const SizedBox(height: 18),

                      Text(

                        'Afterword',

                        style: theme.textTheme.displaySmall?.copyWith(

                          fontWeight: FontWeight.w600,

                          letterSpacing: 1.1,

                        ),

                      ),

                      const SizedBox(height: 8),

                      Text(

                        'A secure vault for the words you may never say.',

                        textAlign: TextAlign.center,

                        style: theme.textTheme.bodyLarge?.copyWith(

                          color: Colors.white70,

                        ),

                      ),

                      const SizedBox(height: 24),

                      Container(

                        padding: const EdgeInsets.all(20),

                        decoration: cardDecoration,

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(

                              'Your vault includes',

                              style: theme.textTheme.titleSmall,

                            ),

                            const SizedBox(height: 12),

                            const _FeatureRow(

                              icon: Icons.enhanced_encryption,

                              text: 'End-to-end encryption on device',

                            ),

                            const SizedBox(height: 10),

                            const _FeatureRow(

                              icon: Icons.timer_outlined,

                              text: 'Timed protocol with check-in cadence',

                            ),

                            const SizedBox(height: 10),

                            const _FeatureRow(

                              icon: Icons.voice_over_off_outlined,

                              text: 'Audio vault and secure delivery',

                            ),

                            const SizedBox(height: 18),

                            SizedBox(

                              width: double.infinity,

                              child: FilledButton.icon(

                                onPressed: authController.isLoading

                                    ? null

                                    : () async {

                                        await authController.signInWithGoogle();

                                      },

                                icon: const Icon(Icons.login_rounded),

                                label: Text(

                                  authController.isLoading

                                      ? 'Connecting...'

                                      : 'Continue with Google',

                                ),

                              ),

                            ),

                            const SizedBox(height: 12),

                            Text(

                              'Google Sign-In only. Your data stays encrypted on this device.',

                              textAlign: TextAlign.center,

                              style: theme.textTheme.bodySmall?.copyWith(

                                color: Colors.white54,

                              ),

                            ),

                            if (authController.lastFailure != null) ...[

                              const SizedBox(height: 16),

                              Text(

                                authController.lastFailure!.message,

                                textAlign: TextAlign.center,

                                style: theme.textTheme.bodyMedium?.copyWith(

                                  color: theme.colorScheme.error,

                                ),

                              ),

                            ],

                          ],

                        ),

                      ),

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



class _FeatureRow extends StatelessWidget {

  const _FeatureRow({required this.icon, required this.text});



  final IconData icon;

  final String text;



  @override

  Widget build(BuildContext context) {

    return Row(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),

        const SizedBox(width: 10),

        Expanded(

          child: Text(

            text,

            style: Theme.of(context)

                .textTheme

                .bodySmall

                ?.copyWith(color: Colors.white70),

          ),

        ),

      ],

    );

  }

}

