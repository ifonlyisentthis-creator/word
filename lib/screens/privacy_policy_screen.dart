import 'package:flutter/material.dart';

import '../widgets/ambient_background.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headingStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      height: 1.6,
    );

    return Scaffold(
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Text('Privacy Policy', style: theme.textTheme.titleLarge),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                    children: [
                      Text(
                        'Last updated: February 2026',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white38),
                      ),
                      const SizedBox(height: 20),
                      Text('1. Information We Collect', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword collects the minimum information necessary to provide the service:\n\n'
                        '• Google account email address (for authentication)\n'
                        '• Vault entries you create (stored encrypted)\n'
                        '• Subscription status (managed by RevenueCat)\n'
                        '• Push notification tokens (for timer notifications)\n\n'
                        'We do not collect analytics, location data, contacts, or browsing history.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Encryption & Data Security', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'All vault entries are encrypted on your device before being stored on our servers. '
                        'We use AES-256-GCM encryption with keys derived on your device. '
                        'Our servers never see your plaintext content.\n\n'
                        'Audio files are encrypted before upload and stored in a private bucket accessible only to you.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. How We Use Your Information', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• To authenticate you and manage your account\n'
                        '• To store and deliver your encrypted vault entries\n'
                        '• To send timer-related push notifications\n'
                        '• To process subscription purchases via Google Play\n\n'
                        'We do not sell, share, or use your data for advertising.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('4. Third-Party Services', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• Google Sign-In — for authentication\n'
                        '• Supabase — for secure data storage (encrypted at rest)\n'
                        '• RevenueCat — for subscription management\n'
                        '• Firebase Cloud Messaging — for push notifications\n\n'
                        'Each service processes data according to their own privacy policies.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('5. Data Retention & Deletion', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Your data is retained as long as your account is active. '
                        'Sent vault entries are automatically deleted after 30 days.\n\n'
                        'You can permanently delete your account and all associated data '
                        'at any time from Account Settings. This action is irreversible.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('6. Children\'s Privacy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is not intended for use by children under 13. '
                        'We do not knowingly collect personal information from children.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('7. Changes to This Policy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We may update this Privacy Policy from time to time. '
                        'Changes will be reflected by the "Last updated" date above. '
                        'Continued use of the app after changes constitutes acceptance.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('8. Contact', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'If you have questions about this Privacy Policy, please contact us at:\n\n'
                        'afterword.app@gmail.com',
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
