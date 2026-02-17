import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_controller.dart';
import '../services/device_secret_service.dart';
import '../services/home_controller.dart';
import '../services/key_backup_service.dart';
import '../services/revenuecat_controller.dart';
import '../services/theme_provider.dart';
import '../widgets/ambient_background.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.homeController,
    required this.authController,
    required this.revenueCatController,
  });

  final HomeController homeController;
  final AuthController authController;
  final RevenueCatController revenueCatController;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final TextEditingController _senderController;
  bool _senderDirty = false;
  bool _isLoading = false;
  bool _backupBusy = false;
  String? _localError;

  KeyBackupService get _keyBackupService => KeyBackupService(
        client: Supabase.instance.client,
        deviceSecretService: DeviceSecretService(),
      );

  HomeController get _controller => widget.homeController;
  AuthController get _authController => widget.authController;

  @override
  void initState() {
    super.initState();
    _senderController =
        TextEditingController(text: _controller.profile?.senderName ?? '');
    _senderController.addListener(() {
      final isDirty =
          _senderController.text != (_controller.profile?.senderName ?? '');
      if (isDirty != _senderDirty) {
        setState(() => _senderDirty = isDirty);
      }
    });
  }

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final authController = _authController;
    final errorColor = theme.colorScheme.error;

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
                      'Account Settings',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (controller.isInGracePeriod) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, size: 18,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Account settings are disabled during the grace period.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Sender Name + Danger Zone — all disabled during grace
                IgnorePointer(
                ignoring: controller.isInGracePeriod,
                child: AnimatedOpacity(
                opacity: controller.isInGracePeriod ? 0.32 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    // Sender Name
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
                                  child: const Icon(
                                      Icons.mark_email_read_outlined,
                                      size: 18),
                                ),
                                const SizedBox(width: 12),
                                Text('Sender Name',
                                    style: theme.textTheme.titleMedium),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This name appears in email subjects sent to your beneficiaries.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white60),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _senderController,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Sender name',
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isLoading || !_senderDirty
                                    ? null
                                    : () async {
                                        setState(() {
                                          _isLoading = true;
                                          _localError = null;
                                        });
                                        await controller.updateSenderName(
                                          _senderController.text,
                                        );
                                        if (!context.mounted) return;
                                        final message = controller.errorMessage;
                                        if (message == null) {
                                          setState(() => _senderDirty = false);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Sender name updated.')));
                                        } else {
                                          _localError = message;
                                        }
                                        setState(() => _isLoading = false);
                                      },
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save Sender Name'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Danger Zone
                    _Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: errorColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.delete_forever,
                                      color: errorColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Danger Zone',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(color: errorColor),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Permanently delete your account and every vault entry.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: Colors.white60),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: errorColor,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () async {
                                        final confirmed =
                                            await _confirmDeleteAccount(context);
                                        if (!confirmed) return;
                                        setState(() {
                                          _isLoading = true;
                                          _localError = null;
                                        });
                                        final success =
                                            await controller.deleteAccount();
                                        if (!context.mounted) return;
                                        if (success) {
                                          final auth = authController;
                                          final rc = widget.revenueCatController;
                                          if (context.mounted) {
                                            Navigator.of(context).pop();
                                          }
                                          if (context.mounted) {
                                            context.read<ThemeProvider>().reset();
                                          }
                                          auth.prepareSignOut();
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) async {
                                            await rc.logOut();
                                            await auth.signOut();
                                          });
                                          return;
                                        }
                                        final msg = controller.errorMessage ??
                                            'Unable to delete your account.';
                                        if (!context.mounted) return;
                                        setState(() {
                                          _localError = msg;
                                          _isLoading = false;
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(msg)));
                                      },
                                child: const Text('Delete Account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ),
                ),

                const SizedBox(height: 24),

                // Recovery Phrase — always accessible
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
                              child: const Icon(Icons.key_outlined, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Text('Recovery Phrase',
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
                            onPressed: _backupBusy
                                ? null
                                : () => _handleRevealOrCreate(context),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Reveal Recovery Phrase'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _backupBusy
                                ? null
                                : () => _handleRestore(context),
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
                      color: errorColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: errorColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: errorColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _localError!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: errorColor),
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

  Future<bool> _confirmDeleteAccount(BuildContext context) async {
    final tc = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isMatch = tc.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            title: const Text('Delete account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your profile and all vault data, including audio. This cannot be undone.',
                ),
                const SizedBox(height: 12),
                const Text('Type DELETE to confirm.'),
                const SizedBox(height: 8),
                TextField(
                  controller: tc,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'DELETE',
                    filled: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isMatch ? () => Navigator.pop(context, true) : null,
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _handleRevealOrCreate(BuildContext context) async {
    final userId = _controller.profile?.id;
    if (userId == null) return;

    setState(() => _backupBusy = true);
    try {
      // Check if mnemonic already exists locally
      var mnemonic = await _keyBackupService.getStoredMnemonic(userId);

      if (mnemonic == null || mnemonic.isEmpty) {
        // No local mnemonic — create a new backup
        mnemonic = await _keyBackupService.createBackup(userId);
      }

      if (!context.mounted) return;
      _showRecoveryPhrase(context, mnemonic);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _showRecoveryPhrase(BuildContext context, String mnemonic) {
    final words = mnemonic.split(' ');
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
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
                  Clipboard.setData(ClipboardData(text: mnemonic));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Recovery phrase copied to clipboard')),
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

  Future<void> _handleRestore(BuildContext context) async {
    final userId = _controller.profile?.id;
    if (userId == null) return;

    final tc = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final wordCount =
              tc.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          final isValid = wordCount == 12;
          return AlertDialog(
            title: const Text('Restore Recovery Phrase'),
            content: Column(
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
                          'This will replace your current encryption keys. '
                          'Any vault entries created on this device will become '
                          'permanently unreadable.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isValid ? () => Navigator.pop(context, true) : null,
                child: const Text('Restore'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final phrase = tc.text.trim().toLowerCase();
    setState(() => _backupBusy = true);
    try {
      await _keyBackupService.restoreBackup(userId, phrase);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keys restored successfully.')),
      );
    } on KeyBackupFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181818), Color(0xFF0E0E0E)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
        boxShadow: [
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
