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
                        'If you do not agree, please do not use the App.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('2. Description of Service', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is a secure, time-locked digital vault. It allows you to '
                        'create, encrypt, and store text messages and audio recordings on your device '
                        'before uploading them to secure servers. Entries can be configured to:\n\n'
                        '• Deliver to a designated recipient when your check-in timer expires\n'
                        '• Permanently erase when your timer expires (Protocol Zero)\n\n'
                        'Recipients access delivered items via a secure browser viewer using a private key.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('3. Accounts', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You must sign in with a Google account to use Afterword. '
                        'You are responsible for maintaining the security of your account '
                        'and any devices used to access the App.\n\n'
                        'You may permanently delete your account and all associated data '
                        'at any time from Account Settings. This action is irreversible.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('4. Subscriptions & Payments', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword offers tiered access:\n\n'
                        '• Free — Up to 3 text entries, 30-day fixed timer, push notifications\n'
                        '• Pro Monthly — Unlimited text entries, custom timer (7–365 days), '
                        'Protocol Zero (erase mode), email warning before expiry\n'
                        '• Pro Annual — Same as Pro Monthly, billed annually at a discount\n'
                        '• Lifetime — All Pro features plus encrypted audio vault, '
                        'extended timer duration, all themes and styles\n\n'
                        'Subscriptions are processed through your device\'s app store. '
                        'Monthly and annual plans auto-renew unless cancelled at least 24 hours '
                        'before the end of the current billing period. '
                        'Manage or cancel subscriptions in your app store settings.\n\n'
                        'If a subscription is refunded, all premium features are revoked immediately '
                        'and the account reverts to the free tier. Existing vault entries are preserved '
                        'but premium features (custom timer, erase mode, themes) are removed. '
                        'Audio vault entries from Lifetime plans are deleted upon refund.\n\n'
                        'If a subscription expires or is not renewed, the same reversion applies '
                        'at the end of the billing period.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('5. User Content & Encryption', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You retain full ownership of all content you create. '
                        'Vault entries are encrypted on your device — '
                        'Afterword cannot read, access, or recover your plaintext content.\n\n'
                        'You are solely responsible for the content of your vault entries, '
                        'the accuracy of recipient email addresses, and keeping your security keys safe.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('6. Prohibited Use', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'You agree not to:\n\n'
                        '• Use the App for any unlawful, abusive, or harmful purpose\n'
                        '• Store content that constitutes threats, harassment, or intimidation\n'
                        '• Use the App to facilitate fraud, extortion, or any criminal activity\n'
                        '• Attempt to gain unauthorized access to the service or other accounts\n'
                        '• Reverse engineer, decompile, or modify the App\n'
                        '• Circumvent subscription, payment, or security mechanisms\n\n'
                        'You are solely responsible for all content stored in your vault. '
                        'Afterword does not monitor or review vault contents due to encryption, '
                        'but reserves the right to terminate accounts reported for misuse. '
                        'By using Afterword, you confirm that your use is lawful, ethical, and '
                        'intended for legitimate personal purposes only.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('7. Delivery & Reliability', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'While we engineer for reliable delivery, Afterword operates on a '
                        'best-effort basis and does not guarantee delivery of emails, '
                        'push notifications, or vault content.\n\n'
                        'Do not rely on Afterword as your sole means of critical communication. '
                        'Sent items remain accessible for 30 days, then auto-purge permanently.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('8. Limitation of Liability', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Afterword is provided "as is" without warranties of any kind, '
                        'express or implied. To the maximum extent permitted by law, '
                        'we shall not be liable for any indirect, incidental, special, or '
                        'consequential damages arising from your use of the App, including '
                        'but not limited to failed delivery, data loss, or service interruption.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('9. Termination', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We reserve the right to suspend or terminate accounts that '
                        'violate these Terms or engage in abusive behavior. '
                        'You may terminate your account at any time via Account Settings.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('10. Changes to Terms', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'We may update these Terms from time to time. '
                        'The "Last updated" date will reflect changes. '
                        'Continued use of the App after updates constitutes acceptance.',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      Text('11. Contact', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Questions about these Terms? Contact us:\n\n'
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
