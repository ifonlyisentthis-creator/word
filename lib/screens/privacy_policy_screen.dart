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
      backgroundColor: Colors.transparent,
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
                        '• Vault entries (stored as encrypted ciphertext — never plaintext)\n'
                        '• Recipient email addresses (encrypted and sealed on your device)\n'
                        '• Subscription status\n'
                        '• Push notification token (for timer reminders)\n\n'
                        'We do not collect analytics, location data, contacts, browsing history, or any telemetry.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Time-Locked Encryption', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'All vault content — text messages, recipient addresses, and audio recordings — '
                        'is encrypted on your device before upload. Content encryption keys '
                        'are generated locally on your device.\n\n'
                        'When your check-in timer expires, our secure server retrieves the delivery '
                        'key and sends it to your designated recipient. The recipient then decrypts '
                        'the content entirely in their own browser — the key is never sent back to '
                        'our servers after delivery.\n\n'
                        'Integrity seals protect against tampering. '
                        'Audio files are encrypted before storage in a private, '
                        'access-controlled bucket.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. How We Use Your Information', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• Authenticate your identity via secure sign-in\n'
                        '• Store and deliver your encrypted vault entries when your timer expires\n'
                        '• Send push notifications for timer reminders\n'
                        '• Send email warnings to subscribed users before expiry\n'
                        '• Verify subscription entitlements securely\n\n'
                        'We do not sell, share, rent, or use your data for advertising or profiling.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('4. Third-Party Services', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword uses trusted third-party services for authentication, '
                        'secure data storage, subscription management, and push notifications. '
                        'Each service operates under their respective privacy policies.\n\n'
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
