import 'package:flutter/material.dart';

import '../widgets/ambient_background.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

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
                      Text('Terms & Conditions',
                          style: theme.textTheme.titleLarge),
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
                      Text('1. Acceptance of Terms', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'By downloading, installing, or using Afterword ("the App"), '
                        'you agree to be bound by these Terms & Conditions. '
                        'If you do not agree, do not use the App.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Description of Service', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is a secure digital vault that allows you to create, '
                        'encrypt, and store messages and audio recordings. These entries '
                        'can be configured to be delivered to a recipient via email '
                        'if you do not check in within a user-defined time period.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. Accounts', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You must sign in with a Google account to use Afterword. '
                        'You are responsible for maintaining the security of your account. '
                        'You may delete your account at any time from Account Settings, '
                        'which permanently removes all your data.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('4. Subscriptions & Payments', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword offers free and paid subscription tiers:\n\n'
                        '• Free — Up to 3 text vault entries, 30-day timer\n'
                        '• Pro Monthly — Unlimited entries, custom timer (7-365 days), Protocol Zero\n'
                        '• Pro Annual — Same as Pro Monthly, billed annually\n'
                        '• Lifetime — All Pro features plus Audio Vault, custom timer up to 10 years\n\n'
                        'Subscriptions are billed through Google Play. '
                        'Monthly and annual subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. '
                        'You can manage or cancel subscriptions in your Google Play settings.\n\n'
                        'Refunds are handled by Google Play according to their refund policy.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('5. User Content', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You retain ownership of all content you create in the App. '
                        'Your vault entries are encrypted on your device — we cannot read them.\n\n'
                        'You are solely responsible for the content of your vault entries '
                        'and the email addresses you designate as recipients.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('6. Prohibited Use', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You agree not to:\n\n'
                        '• Use the App for any unlawful purpose\n'
                        '• Attempt to gain unauthorized access to the service\n'
                        '• Reverse engineer, decompile, or modify the App\n'
                        '• Use the App to harass, threaten, or harm others\n'
                        '• Circumvent subscription or payment mechanisms',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('7. Delivery & Reliability', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'While we strive for reliable delivery of vault entries, '
                        'Afterword does not guarantee delivery of emails or notifications. '
                        'The service is provided on a best-effort basis. '
                        'Do not rely on Afterword as a sole means of critical communication.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('8. Limitation of Liability', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is provided "as is" without warranties of any kind. '
                        'To the maximum extent permitted by law, we shall not be liable '
                        'for any indirect, incidental, or consequential damages arising '
                        'from your use of the App.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('9. Termination', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We reserve the right to suspend or terminate accounts that '
                        'violate these terms. You may terminate your account at any time '
                        'by deleting it from Account Settings.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('10. Changes to Terms', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We may update these Terms from time to time. '
                        'Continued use of the App after changes constitutes acceptance '
                        'of the updated terms.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('11. Contact', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'For questions about these Terms, contact us at:\n\n'
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
