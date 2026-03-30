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
                        'Last updated: March 2026',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white38),
                      ),
                      const SizedBox(height: 20),
                      Text('1. Information We Collect', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword collects only the minimum data necessary to operate:\n\n'
                        '• Google account email (for authentication)\n'
                        '• Vault entries (stored as encrypted ciphertext — never in plaintext)\n'
                        '• Recipient email addresses (encrypted on your device before upload)\n'
                        '• Subscription status (managed by your device\'s app store)\n'
                        '• Push notification token (for timer reminders in Guardian Vault mode only)\n'
                        '• Encrypted key backup (optional — only if you enable recovery phrase)\n'
                        '• App operating mode preference (Guardian Vault, Time Capsule, or Forever Letters)\n'
                        '• Scheduled delivery dates (stored as timestamps for Time Capsule entries)\n'
                        '• Recurring delivery dates (stored as month/day for Forever Letters entries)\n'
                        '• Last delivery year tracking (to prevent duplicate annual sends)\n\n'
                        'We do not collect analytics, advertising identifiers, location data, '
                        'contacts, browsing history, or any telemetry.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Time-Locked Encryption', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'All vault content — text messages, recipient addresses, and audio recordings — '
                        'is encrypted on your device before upload. Content encryption keys '
                        'are generated locally on your device.\n\n'
                        'Afterword offers three operating modes:\n\n'
                        '• Guardian Vault — A global check-in timer protects all entries. '
                        'When the timer expires, our secure server retrieves the delivery '
                        'key and sends it to your designated recipient.\n\n'
                        '• Time Capsule — Each entry is scheduled for a specific future date. '
                        'On that date, the entry is delivered automatically. No check-ins are needed.\n\n'
                        '• Forever Letters — A recurring message delivered to your recipient '
                        'every year on the same date. The encrypted content and key remain '
                        'unchanged across deliveries. Available on Pro and Lifetime plans.\n\n'
                        'In all modes, the recipient decrypts the content entirely in their own '
                        'browser — the key is never sent back to our servers after delivery.\n\n'
                        'Zero-knowledge mode is available per entry on Guardian Vault and Time '
                        'Capsule (all plans). When enabled, the encryption key is stored only '
                        'on your device — the server never receives or stores a copy. You must '
                        'share the key with your beneficiary manually. If the key is lost, the '
                        'entry is permanently unrecoverable. Zero-knowledge is not available on '
                        'Forever Letters.\n\n'
                        'Integrity seals (HMAC) protect against tampering. Tampering is detected '
                        'but never blocks delivery — this prevents denial-of-service attacks. '
                        'Audio files are encrypted before storage in a private, '
                        'access-controlled bucket.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. How We Use Your Information', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        '• Authenticate your identity via secure sign-in\n'
                        '• Store and deliver your encrypted vault entries when your timer expires, '
                        'on your scheduled delivery date, or on the yearly anniversary '
                        '(Forever Letters)\n'
                        '• Send push notifications for timer reminders (Guardian Vault mode only)\n'
                        '• Send email warnings to subscribed users before expiry (Guardian Vault mode only)\n'
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
                      Text('5. Recovery Phrase & Key Backup', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You may optionally generate a 12-word recovery phrase to back up '
                        'your encryption keys. This phrase is used to derive an encryption key '
                        'locally on your device; the resulting encrypted key bundle is stored '
                        'on our servers. The recovery phrase itself is never transmitted.\n\n'
                        'If you lose your recovery phrase, we cannot recover your keys. '
                        'Afterword has no ability to decrypt your key backup without the phrase.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('6. Data Retention & Deletion', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Active data is retained as long as your account exists. '
                        'Sent vault entries in Guardian Vault and Time Capsule modes are '
                        'automatically purged 30 days after delivery. '
                        'After the 30-day grace period, the entry data is permanently erased '
                        'and vault slots are recovered.\n\n'
                        'Forever Letters are never automatically purged or deleted. They '
                        'continue to deliver annually until you manually delete them or '
                        'delete your account.\n\n'
                        'Vault entry limits: Free — 3 entries, Pro — 20 entries, Lifetime — 30 entries.\n\n'
                        'You can permanently delete your account and all associated data '
                        'at any time from Account Settings. This action is immediate and irreversible — '
                        'all vault entries, encryption keys, key backups, and profile data are destroyed.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('7. Children\'s Privacy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is not intended for use by anyone under 13 years of age. '
                        'We do not knowingly collect personal information from children.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('8. Changes to This Policy', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We may update this Privacy Policy from time to time. '
                        'Changes will be reflected by the "Last updated" date above. '
                        'Continued use of the app after changes constitutes acceptance of the updated policy.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('9. Contact', style: headingStyle),
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
