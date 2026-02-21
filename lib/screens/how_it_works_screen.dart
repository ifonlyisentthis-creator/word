import 'package:flutter/material.dart';

import '../widgets/ambient_background.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How It Works',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                    children: [
                      _StepCard(
                        number: '1',
                        title: 'Create Your Vault',
                        body:
                            'Write messages, record encrypted audio, or store your most important words. '
                            'Everything is encrypted on your device before upload. '
                            'Our servers only ever see ciphertext — never your plaintext.',
                        icon: Icons.enhanced_encryption,
                      ),
                      _StepCard(
                        number: '2',
                        title: 'Set Your Heartbeat Timer',
                        body:
                            'Choose a check-in cadence that fits your life — from 7 days to 10 years. '
                            'Free users have a 30-day timer. Pro unlocks 7–365 days, and Lifetime '
                            'extends up to 3,650 days (10 years).',
                        icon: Icons.timer_outlined,
                      ),
                      _StepCard(
                        number: '3',
                        title: 'Assign Recipients',
                        body:
                            'Each vault entry can be delivered to a different person. '
                            'Recipient emails are encrypted and sealed on your device — '
                            'no one (including Afterword admins) can swap or read them.',
                        icon: Icons.people_outline,
                      ),
                      _StepCard(
                        number: '4',
                        title: 'Check In to Keep Your Vault Locked',
                        body:
                            'Long-press the Soul Fire orb to reset your timer. '
                            'Your first press per session always resets. After that, '
                            'a 12-hour cooldown prevents unnecessary writes — you will '
                            'see "Vault Secure" instead of "Signal Verified" during cooldown. '
                            'Push notifications remind you at 66% and 33% remaining time. '
                            'Soul Fire only works manually — there is no auto check-in.',
                        icon: Icons.favorite_border,
                      ),
                      _StepCard(
                        number: '5',
                        title: 'Protocol Executes',
                        body:
                            'If your timer expires, Afterword delivers each entry to its designated recipient. '
                            'They receive a secure link and a unique key, then decrypt your '
                            'message entirely in their browser — no login required. '
                            'Delivered items auto-purge after 30 days.',
                        icon: Icons.send_outlined,
                      ),
                      _TipCard(
                        title: 'Check Your Inbox',
                        body:
                            'Afterword emails (timer warnings and vault deliveries) '
                            'may land in your Spam or Promotions folder the first time. '
                            'If this happens, open the email and tap "Not Spam" or move '
                            'it to your Inbox. This teaches your email provider that '
                            'Afterword messages are safe, so future emails arrive normally.',
                        icon: Icons.mark_email_read_outlined,
                      ),
                      _StepCard(
                        number: '6',
                        title: 'Protocol Zero',
                        body:
                            'Pro and Lifetime users can set any item to "Erase" mode. '
                            'When the timer expires, the data is permanently removed from our servers '
                            'instead of being delivered. No emails sent. Complete data erasure.',
                        icon: Icons.delete_forever_outlined,
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle('Security Architecture'),
                      _BulletPoint('Industry-standard encryption — keys generated on your device.'),
                      _BulletPoint('Integrity seals — prevent tampering with recipient addresses.'),
                      _BulletPoint('Data isolation — your data is fully separated at the database level.'),
                      _BulletPoint('Subscription features verified securely on the server.'),
                      _BulletPoint('Audio files encrypted before upload and stored in a private bucket.'),
                      _BulletPoint('Delivered vault entries auto-purge after 30 days.'),
                      const SizedBox(height: 24),
                      _SectionTitle('Plans'),
                      _BulletPoint('Free — 3 text items, 30-day timer, push notifications at 66% and 33%.'),
                      _BulletPoint('Pro — Unlimited text items, custom timer (7–365 days), '
                          'Protocol Zero (erase mode), email warning 24h before expiry.'),
                      _BulletPoint('Lifetime — Everything in Pro, plus encrypted audio vault '
                          '(10 minute bank), timer up to 10 years, all 6 themes and Soul Fire styles.'),
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

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String number;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$number. $title',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: Colors.amber),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
