import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_controller.dart';
import '../services/home_controller.dart';
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
  String? _localError;

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
                            'Settings are locked during the grace period. You can still delete your account below.',
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

                // Sender Name — disabled during grace
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
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        theme.colorScheme.primary.withValues(alpha: 0.15),
                                        theme.colorScheme.primary.withValues(alpha: 0.05),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.20),
                                    ),
                                  ),
                                  child: Icon(
                                      Icons.mark_email_read_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary),
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

                  ],
                ),
                ),
                ),

                    const SizedBox(height: 24),

                    // Danger Zone — always accessible, even during grace period.
                    // Deleting your account is a user right.
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
    final isPaidUser = widget.revenueCatController.isPro ||
        widget.revenueCatController.isLifetime;
    final isLifetime = widget.revenueCatController.isLifetime;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isMatch = tc.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            title: const Text('Delete account?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes your profile and all vault data, including audio. This cannot be undone.',
                  ),
                  if (isPaidUser) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
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
                              size: 16,
                              color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isLifetime
                                  ? 'Your Lifetime subscription will be permanently lost. You will need to re-purchase if you create a new account.'
                                  : 'Your Pro subscription will be lost. You will need to re-subscribe if you create a new account.',
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.error,
                                        height: 1.4,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

}


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
