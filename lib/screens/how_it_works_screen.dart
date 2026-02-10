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
                            'Write messages, record audio, or store secrets. '
                            'Each item is encrypted on your device before it ever '
                            'leaves your phone. Not even we can read it.',
                        icon: Icons.enhanced_encryption,
                      ),
                      _StepCard(
                        number: '2',
                        title: 'Set Your Timer',
                        body:
                            'Choose how often you want to check in — from 7 days '
                            'to 10 years. If you stop opening the app, the countdown '
                            'begins. Free users have a fixed 30-day timer.',
                        icon: Icons.timer_outlined,
                      ),
                      _StepCard(
                        number: '3',
                        title: 'Assign Beneficiaries',
                        body:
                            'For each vault item, enter the email of the person '
                            'you want to receive it. Different items can go to '
                            'different people.',
                        icon: Icons.people_outline,
                      ),
                      _StepCard(
                        number: '4',
                        title: 'Check In to Stay Safe',
                        body:
                            'Simply open the app to reset your timer. You can also '
                            'long-press the Soul Fire ring for a satisfying confirmation. '
                            'Every time you open Afterword, your vault stays locked.',
                        icon: Icons.favorite_border,
                      ),
                      _StepCard(
                        number: '5',
                        title: 'If You Disappear…',
                        body:
                            'When your timer expires, Afterword sends each beneficiary '
                            'a secure link and a unique key. They open a website, enter '
                            'the key, and read your message — decrypted in their browser. '
                            'No one else can access it.',
                        icon: Icons.send_outlined,
                      ),
                      _StepCard(
                        number: '6',
                        title: 'Or Destroy Everything',
                        body:
                            'Pro and Lifetime users can set items to "Destroy" instead '
                            'of "Send." If the timer expires, the data is permanently '
                            'deleted. No emails. No trace. Gone forever.',
                        icon: Icons.delete_forever_outlined,
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Security'),
                      _BulletPoint('All data is encrypted with AES-256 on your device.'),
                      _BulletPoint('Encryption keys are wrapped with a server secret '
                          'stored only in secure infrastructure.'),
                      _BulletPoint('HMAC signatures prevent anyone — including admins — '
                          'from swapping beneficiary emails.'),
                      _BulletPoint('Row-Level Security ensures only you can access your data.'),
                      _BulletPoint('Sent items auto-delete after 30 days.'),
                      const SizedBox(height: 20),
                      _SectionTitle('Plans'),
                      _BulletPoint('Free: 3 text items, 30-day timer, push notifications.'),
                      _BulletPoint('Pro: Unlimited text, custom timer (7–365 days), '
                          'destroy mode, email warning failsafe.'),
                      _BulletPoint('Lifetime: Everything in Pro + audio vault (10 min), '
                          'timer up to 10 years.'),
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
