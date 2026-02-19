import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_secret_service.dart';
import '../services/home_controller.dart';
import '../services/key_backup_service.dart';
import '../services/theme_provider.dart';
import '../widgets/ambient_background.dart';

class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({super.key, required this.homeController});

  final HomeController homeController;

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  bool _busy = false;
  String? _localError;

  KeyBackupService get _keyBackupService => KeyBackupService(
        client: Supabase.instance.client,
        deviceSecretService: DeviceSecretService(),
      );

  HomeController get _controller => widget.homeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Recovery Phrase',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child:
                                  const Icon(Icons.key_outlined, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Text('Backup Your Keys',
                                style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Back up your encryption keys as a 12-word phrase. '
                          'Use it to restore access to your vault on a new device.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white60),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _busy ? null : () => _handleRevealOrCreate(context),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Reveal Recovery Phrase'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _busy ? null : () => _handleRestore(context),
                            icon: const Icon(Icons.restore),
                            label: const Text('Restore from Phrase'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_localError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: theme.colorScheme.error
                              .withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _localError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reveal / Create ──────────────────────────────────────────────────

  Future<void> _handleRevealOrCreate(BuildContext context) async {
    final userId = _controller.profile?.id;
    if (userId == null) return;

    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      var mnemonic = await _keyBackupService.getStoredMnemonic(userId);

      if (mnemonic != null && mnemonic.isNotEmpty) {
        if (!context.mounted) return;
        _showRecoveryPhrase(context, mnemonic);
        return;
      }

      final hasExisting = await _keyBackupService.hasServerBackup(userId);
      if (hasExisting && context.mounted) {
        final action = await _showBackupExistsDialog(context);
        if (!context.mounted) return;
        if (action == _BackupAction.restore) {
          await _handleRestore(context);
          return;
        }
        if (action != _BackupAction.createNew) return;
      }

      mnemonic = await _keyBackupService.createBackup(userId);

      if (!context.mounted) return;
      _showRecoveryPhrase(context, mnemonic);
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _localError = 'Failed to create backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_BackupAction?> _showBackupExistsDialog(BuildContext context) {
    return showDialog<_BackupAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup already exists'),
        content: const Text(
          'A recovery phrase backup already exists for this account. '
          'If you lost your 12 words, use "Restore" to recover your old keys first.\n\n'
          'Creating a new backup will permanently invalidate your previous recovery phrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _BackupAction.restore),
            child: const Text('Restore Instead'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _BackupAction.createNew),
            child: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  void _showRecoveryPhrase(BuildContext context, String mnemonic) {
    final normalizedMnemonic = normalizeRecoveryPhrase(mnemonic);
    final words = normalizedMnemonic.split(' ');
    final theme = Theme.of(context);
    final td = context.read<ThemeProvider>().themeData;
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: td.cardGradientStart,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 20, 24,
          MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.key, size: 32, color: Colors.amberAccent),
            const SizedBox(height: 12),
            Text('Your Recovery Phrase',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Write these words down in order and store them safely. '
              'This is the only way to access your vault on a new device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (i) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${i + 1}. ${words[i]}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: normalizedMnemonic));
                  messenger.showSnackBar(
                    const SnackBar(
                        content:
                            Text('Recovery phrase copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy to Clipboard'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Restore ──────────────────────────────────────────────────────────

  Future<void> _handleRestore(BuildContext context) async {
    final userId = _controller.profile?.id;
    if (userId == null) return;

    final tc = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final wordCount = tc.text
                .trim()
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .length;
            final isValid = wordCount == 12;
            return AlertDialog(
              title: const Text('Restore Recovery Phrase'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This will replace the encryption keys on this device. '
                              'Only use this to recover YOUR OWN keys from another device. '
                              'Do not restore a different account\'s phrase.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Enter your 12-word recovery phrase:'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tc,
                      maxLines: 3,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'word1 word2 word3 ...',
                        filled: true,
                        helperText: '$wordCount / 12 words',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      isValid ? () => Navigator.pop(context, true) : null,
                  child: const Text('Restore'),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed != true) return;

      final phrase = tc.text.trim().toLowerCase();
      setState(() {
        _busy = true;
        _localError = null;
      });
      try {
        await _keyBackupService.restoreBackup(userId, phrase);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keys restored successfully.')),
        );
      } on KeyBackupFailure catch (e) {
        if (!context.mounted) return;
        setState(() => _localError = e.message);
      } catch (e) {
        if (!context.mounted) return;
        setState(() => _localError = 'Restore failed: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      tc.dispose();
    }
  }
}

enum _BackupAction { restore, createNew }

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final td = context.watch<ThemeProvider>().themeData;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [td.cardGradientStart, td.cardGradientEnd],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: td.dividerColor),
        boxShadow: [
          BoxShadow(
            color: td.accentGlow.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }
}
