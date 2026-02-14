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
                        'Afterword collects only the minimum data necessary to operate:\n\n'
                        '• Google account email (authentication only)\n'
                        '• Vault entries (stored as AES-256-GCM ciphertext — never plaintext)\n'
                        '• Recipient email addresses (encrypted and HMAC-sealed on your device)\n'
                        '• Subscription status (managed by RevenueCat)\n'
                        '• Push notification token (for timer reminders at 66% and 33%)\n\n'
                        'We do not collect analytics, location data, contacts, browsing history, or any telemetry.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Zero-Knowledge Encryption', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'All vault content — text messages, recipient addresses, and audio recordings — '
                        'is encrypted on your device with AES-256-GCM before upload. Encryption keys '
                        'are generated locally and never transmitted to or stored on our servers.\n\n'
                        'HMAC integrity seals protect against tampering — even Afterword admins '
                        'cannot read, modify, or swap your data.\n\n'
                        'Audio files are encrypted into noise before storage in a private, '
                        'access-controlled bucket.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. How We Use Your Information', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• Authenticate your identity via Google Sign-In\n'
                        '• Store and deliver your encrypted vault entries when your timer expires\n'
                        '• Send push notifications for timer reminders (66% and 33% remaining)\n'
                        '• Send email warnings to paid users 24 hours before expiry\n'
                        '• Verify subscription entitlements server-side via RevenueCat\n\n'
                        'We do not sell, share, rent, or use your data for advertising or profiling.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('4. Third-Party Services', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• Google Sign-In — authentication\n'
                        '• Supabase — secure data storage with Row-Level Security and encryption at rest\n'
                        '• RevenueCat — subscription management and entitlement verification\n'
                        '• Firebase Cloud Messaging — push notifications only\n\n'
                        'Each service operates under their respective privacy policies. '
                        'No third party has access to your decrypted vault content.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('5. Data Retention & Deletion', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Active data is retained as long as your account exists. '
                        'Sent vault entries are automatically purged 30 days after delivery.\n\n'
                        'You can permanently delete your account and all associated data '
                        'at any time from Account Settings. This action is immediate and irreversible — '
                        'all vault entries, encryption keys, and profile data are destroyed.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('6. Children\'s Privacy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is not intended for use by anyone under 13 years of age. '
                        'We do not knowingly collect personal information from children.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('7. Changes to This Policy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We may update this Privacy Policy from time to time. '
                        'Changes will be reflected by the "Last updated" date above. '
                        'Continued use of the app after changes constitutes acceptance of the updated policy.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('8. Contact', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Questions about this Privacy Policy? Contact us:\n\n'
                        'hello@afterword-app.com',
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
