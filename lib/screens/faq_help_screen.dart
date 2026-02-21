import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/ambient_background.dart';

class FaqHelpScreen extends StatelessWidget {
  const FaqHelpScreen({super.key});

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
                        'FAQ & Help',
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
                      _SectionTitle('Frequently Asked Questions'),
                      _FaqItem(
                        question: 'Can Afterword read my messages?',
                        answer:
                            'No. All encryption happens on your device using '
                            'industry-standard AES-256-GCM. Our servers only '
                            'ever store ciphertext — never your plaintext.',
                      ),
                      _FaqItem(
                        question: 'What happens if I forget to check in?',
                        answer:
                            'Your timer expires and Afterword delivers each vault '
                            'entry to its designated recipient (or permanently '
                            'erases it if set to Protocol Zero).',
                      ),
                      _FaqItem(
                        question: 'Can I change my timer after setting it?',
                        answer:
                            'Yes. Tap the timer card on the home screen to adjust '
                            'your check-in cadence at any time.',
                      ),
                      _FaqItem(
                        question: 'Will my recipient need an account?',
                        answer:
                            'No. They receive a secure link and a unique key via '
                            'email, then decrypt everything in their browser — '
                            'no login or app download required.',
                      ),
                      _FaqItem(
                        question: 'What does "Vault Secure" vs "Signal Verified" mean?',
                        answer:
                            '"Signal Verified" means your timer was actually reset '
                            'in the database. "Vault Secure" appears when no write '
                            'was needed — either your vault is empty (no timer '
                            'running) or you are within the 12-hour cooldown '
                            'between check-ins.',
                      ),
                      _FaqItem(
                        question: 'Is Soul Fire automatic or manual only?',
                        answer:
                            'Manual only. You must long-press the Soul Fire orb '
                            'yourself to reset the timer. There is no auto '
                            'check-in — this is by design for security.',
                      ),
                      _FaqItem(
                        question: 'Emails landing in spam?',
                        answer:
                            'Check your Spam or Promotions folder and tap "Not Spam" '
                            'or move the email to your Inbox. This trains your email '
                            'provider so future Afterword emails arrive normally.',
                      ),
                      _FaqItem(
                        question: 'What happens to my subscription if I delete my account?',
                        answer:
                            'Your Afterword profile, vault entries, and all stored '
                            'data are permanently deleted. Your subscription (including '
                            'Lifetime) is lost and cannot be restored. You would need '
                            'to re-purchase if you create a new account.',
                      ),
                      _FaqItem(
                        question: 'How long do recipients have to view delivered entries?',
                        answer:
                            'Recipients have 30 days from the delivery date to '
                            'access and decrypt their entry. After that, the data '
                            'is permanently purged from our servers.',
                      ),
                      const SizedBox(height: 28),
                      _SectionTitle('Contact & Support'),
                      const SizedBox(height: 4),
                      _ContactCard(
                        icon: Icons.mail_outline,
                        title: 'Email Support',
                        subtitle: 'afterword.app@gmail.com',
                        onTap: () {
                          final uri = Uri(
                            scheme: 'mailto',
                            path: 'afterword.app@gmail.com',
                            queryParameters: {
                              'subject': 'Afterword Support',
                              'body': 'Hi Afterword Team,\n\n',
                            },
                          );
                          launchUrl(uri);
                        },
                      ),
                      const SizedBox(height: 12),
                      _ContactCard(
                        icon: Icons.bug_report_outlined,
                        title: 'Report a Bug',
                        subtitle: 'Include steps to reproduce',
                        onTap: () {
                          final uri = Uri(
                            scheme: 'mailto',
                            path: 'afterword.app@gmail.com',
                            queryParameters: {
                              'subject': 'Afterword Bug Report',
                              'body':
                                  'Hi Afterword Team,\n\n'
                                  'Bug description:\n\n'
                                  'Steps to reproduce:\n1. \n2. \n3. \n\n'
                                  'Expected behavior:\n\n'
                                  'Actual behavior:\n\n',
                            },
                          );
                          launchUrl(uri);
                        },
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: _expanded ? 0.08 : 0.04),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _expanded
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    widget.answer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
