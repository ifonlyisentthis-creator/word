import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/profile.dart';
import '../services/account_service.dart';
import '../services/auth_controller.dart';
import '../services/crypto_service.dart';
import '../services/device_secret_service.dart';
import '../services/home_controller.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/revenuecat_controller.dart';
import '../services/vault_service.dart';
import '../widgets/ambient_background.dart';
import 'vault_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final user = authController.user;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final config = context.read<AppConfig>();

    return ChangeNotifierProvider(
      key: ValueKey(user.id),
      create: (_) => HomeController(
        profileService: ProfileService(Supabase.instance.client),
        notificationService: NotificationService(),
        accountService: AccountService(
          client: Supabase.instance.client,
          vaultService: VaultService(
            client: Supabase.instance.client,
            cryptoService: CryptoService(serverSecret: config.serverSecret),
            deviceSecretService: DeviceSecretService(),
          ),
          deviceSecretService: DeviceSecretService(),
        ),
      )..initialize(user),
      child: _HomeView(
        userId: user.id,
        serverSecret: config.serverSecret,
      ),
    );
  }
}

class _AccountDeletionCard extends StatelessWidget {
  const _AccountDeletionCard({
    required this.isLoading,
    required this.onDelete,
  });

  final bool isLoading;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return _SurfaceCard(
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
                    color: errorColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_forever, color: errorColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Danger Zone',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: errorColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Permanently delete your account and every vault entry.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
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
                onPressed: isLoading ? null : () async => onDelete(),
                child: const Text('Delete Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolBanner extends StatelessWidget {
  const _ProtocolBanner({
    required this.dateLabel,
    required this.isArchived,
    required this.isNoEntries,
  });

  final String dateLabel;
  final bool isArchived;
  final bool isNoEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = isArchived
        ? theme.colorScheme.error
        : isNoEntries
            ? theme.colorScheme.secondary
            : theme.colorScheme.primary;
    final title = isNoEntries
        ? 'Protocol Executed · Vault Empty'
        : isArchived
            ? 'Protocol Executed'
            : 'Protocol Executed · Messages Sent';
    final message = isNoEntries
        ? 'Protocol executed on $dateLabel. Your vault was empty, so nothing was sent.'
        : isArchived
            ? 'Protocol executed on $dateLabel. Data was permanently erased.'
            : 'Protocol executed on $dateLabel. Sent items are read-only for 7 days.';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.16),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hold the Pulse to reset your timer and continue.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
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

class _HomeView extends StatefulWidget {
  const _HomeView({
    required this.userId,
    required this.serverSecret,
  });

  final String userId;
  final String serverSecret;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> with WidgetsBindingObserver {
  final TextEditingController _senderController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  int _timerDays = 30;
  String? _seededProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _senderController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<HomeController>().autoCheckIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final revenueCat = context.watch<RevenueCatController>();
    final authController = context.read<AuthController>();
    final profile = controller.profile;
    final protocolExecutedAt = controller.protocolExecutedAt;
    final protocolWasArchived = controller.protocolWasArchived;
    final protocolNoEntries = controller.protocolNoEntries;
    final isLifetime = revenueCat.isLifetime;
    final isPro = revenueCat.isPro || isLifetime;

    _seedProfile(profile);

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                _HeaderRow(
                  isPro: isPro,
                  isLifetime: isLifetime,
                  onSignOut: authController.signOut,
                ),
                if (controller.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _StatusBanner(message: controller.errorMessage!),
                ],
                if (protocolExecutedAt != null) ...[
                  const SizedBox(height: 16),
                  _ProtocolBanner(
                    dateLabel: _dateFormat.format(
                      protocolExecutedAt.toLocal(),
                    ),
                    isArchived: protocolWasArchived,
                    isNoEntries: protocolNoEntries,
                  ),
                ],
                const SizedBox(height: 16),
                _TimerCard(profile: profile, dateFormat: _dateFormat),
                const SizedBox(height: 24),
                Center(
                  child: PulseRing(
                    enabled: !controller.isLoading && profile != null,
                    onConfirmed: () async {
                      final success = await controller.manualCheckIn();
                      if (!mounted) return;
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signal verified.')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Hold to verify your signal',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white60, letterSpacing: 1.1),
                  ),
                ),
                const SizedBox(height: 28),
                _TimerSettingsCard(
                  isPro: isPro,
                  timerDays: _timerDays,
                  isLoading: controller.isLoading,
                  onChanged: (value) {
                    setState(() {
                      _timerDays = value;
                    });
                  },
                  onSave: () async {
                    await controller.updateTimerDays(_timerDays);
                  },
                  onUpgrade: () async {
                    await revenueCat.presentPaywall();
                  },
                ),
                const SizedBox(height: 20),
                _SenderNameCard(
                  controller: _senderController,
                  isLoading: controller.isLoading,
                  onSave: () async {
                    await controller.updateSenderName(_senderController.text);
                  },
                ),
                const SizedBox(height: 20),
                VaultSection(
                  userId: widget.userId,
                  serverSecret: widget.serverSecret,
                  isPro: isPro,
                  isLifetime: isLifetime,
                ),
                const SizedBox(height: 20),
                _SubscriptionActions(
                  isPro: isPro,
                  isLoading: revenueCat.isLoading,
                  onCustomerCenter: revenueCat.presentCustomerCenter,
                ),
                const SizedBox(height: 20),
                _AccountDeletionCard(
                  isLoading: controller.isLoading,
                  onDelete: () async {
                    final confirmed = await _confirmDeleteAccount(context);
                    if (!confirmed) return;
                    final success = await controller.deleteAccount();
                    if (!mounted) return;
                    if (success) {
                      await authController.signOut();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account deleted.')),
                      );
                    } else {
                      final message = controller.errorMessage ??
                          'Unable to delete your account.';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _seedProfile(Profile? profile) {
    if (profile == null) return;
    if (_seededProfileId != profile.id) {
      _seededProfileId = profile.id;
      _senderController.text = profile.senderName;
      _timerDays = profile.timerDays;
      return;
    }
    if (_senderController.text.isEmpty) {
      _senderController.text = profile.senderName;
    }
    if (_timerDays == 30 && profile.timerDays != 30) {
      _timerDays = profile.timerDays;
    }
  }

  Future<bool> _confirmDeleteAccount(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isMatch = controller.text.trim().toUpperCase() == 'DELETE';
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
                  controller: controller,
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
    controller.dispose();
    return result ?? false;
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.isPro,
    required this.isLifetime,
    required this.onSignOut,
  });

  final bool isPro;
  final bool isLifetime;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Afterword',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Signal-secure vault',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
        ),
        const Spacer(),
        _PlanChip(isPro: isPro, isLifetime: isLifetime),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: IconButton(
            onPressed: () async {
              await onSignOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ),
      ],
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({
    required this.isPro,
    required this.isLifetime,
  });

  final bool isPro;
  final bool isLifetime;

  @override
  Widget build(BuildContext context) {
    final label = isLifetime
        ? 'Lifetime'
        : isPro
            ? 'Pro Active'
            : 'Free Tier';
    final icon = isLifetime
        ? Icons.workspace_premium
        : isPro
            ? Icons.stars
            : Icons.lock_outline;
    final gradient = isLifetime
        ? const LinearGradient(
            colors: [Color(0xFF5BC0B4), Color(0xFF7ED9CE)],
          )
        : isPro
            ? const LinearGradient(
                colors: [Color(0xFFFFB85C), Color(0xFFFFD18A)],
              )
            : null;
    final textColor = (isPro || isLifetime) ? const Color(0xFF1B1410) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white10 : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: gradient == null ? Colors.white24 : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: textColor ?? Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: textColor ?? Colors.white70, letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.profile,
    required this.dateFormat,
  });

  final Profile? profile;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const _SurfaceCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Syncing your timer...'),
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final remaining = profile.timeRemaining;
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final statusMessage = profile.status.toLowerCase() == 'active'
        ? 'Protocol secure'
        : 'Protocol executed';
    final statusColor = profile.status.toLowerCase() == 'active'
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;
    final totalSeconds = profile.timerDays * 24 * 60 * 60;
    final remainingSeconds =
        remaining.inSeconds.clamp(0, totalSeconds.toInt());
    final progress = totalSeconds == 0
        ? 0.0
        : remainingSeconds / totalSeconds.toDouble();

    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusMessage.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Cycle ${profile.timerDays} days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              remaining.isNegative ? 'Expired' : '$days days',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              remaining.isNegative
                  ? 'Check in immediately'
                  : '$hours hours remaining',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                backgroundColor: Colors.white12,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Deadline: ${dateFormat.format(profile.deadline)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            Text(
              'Last check-in: ${dateFormat.format(profile.lastCheckIn.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerSettingsCard extends StatelessWidget {
  const _TimerSettingsCard({
    required this.isPro,
    required this.timerDays,
    required this.isLoading,
    required this.onChanged,
    required this.onSave,
    required this.onUpgrade,
  });

  final bool isPro;
  final int timerDays;
  final bool isLoading;
  final ValueChanged<int> onChanged;
  final Future<void> Function() onSave;
  final Future<void> Function() onUpgrade;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
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
                  child: const Icon(Icons.timer_outlined, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Timer Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isPro)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '$timerDays days',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isPro
                  ? 'Custom cadence (7–365 days)'
                  : 'Locked on the free plan (30 days)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            if (isPro) ...[
              Slider(
                value: timerDays.toDouble(),
                min: 7,
                max: 365,
                divisions: 358,
                label: '$timerDays',
                onChanged: isLoading
                    ? null
                    : (value) {
                        onChanged(value.round());
                      },
                onChangeEnd: isLoading
                    ? null
                    : (value) async {
                        await onSave();
                      },
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upgrade to unlock custom timers and Protocol Zero.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () async => onUpgrade(),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock Pro'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SenderNameCard extends StatelessWidget {
  const _SenderNameCard({
    required this.controller,
    required this.isLoading,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool isLoading;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
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
                  child: const Icon(Icons.mark_email_read_outlined, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Sender Name',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This name appears in email subjects sent to your beneficiaries.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
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
                onPressed: isLoading
                    ? null
                    : () async {
                        await onSave();
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Sender Name'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionActions extends StatelessWidget {
  const _SubscriptionActions({
    required this.isPro,
    required this.isLoading,
    required this.onCustomerCenter,
  });

  final bool isPro;
  final bool isLoading;
  final Future<void> Function() onCustomerCenter;

  @override
  Widget build(BuildContext context) {
    if (!isPro) {
      return const SizedBox.shrink();
    }
    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage Plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Update billing or cancel anytime via RevenueCat Customer Center.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        await onCustomerCenter();
                      },
                icon: const Icon(Icons.support_agent),
                label: const Text('Open Customer Center'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      decoration: BoxDecoration(
        color: errorColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: errorColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: errorColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: errorColor,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

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
            color: Colors.black.withOpacity(0.35),
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

class PulseRing extends StatefulWidget {
  const PulseRing({
    super.key,
    required this.enabled,
    required this.onConfirmed,
  });

  final bool enabled;
  final Future<void> Function() onConfirmed;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _holdController;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..addStatusListener(_handleHoldStatus);
  }

  @override
  void dispose() {
    _breathController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _handleHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
      widget.onConfirmed();
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _holdController.reverse(from: 1);
        }
      });
    }
  }

  void _startHold(LongPressStartDetails details) {
    if (!widget.enabled) return;
    _triggered = false;
    _holdController.forward(from: 0);
  }

  void _endHold(LongPressEndDetails details) {
    if (!widget.enabled) return;
    if (!_holdController.isCompleted) {
      _holdController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.enabled
        ? Theme.of(context).colorScheme.primary
        : Colors.white24;

    return GestureDetector(
      onLongPressStart: widget.enabled ? _startHold : null,
      onLongPressEnd: widget.enabled ? _endHold : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _breathController,
          _holdController,
        ]),
        builder: (context, child) {
          return CustomPaint(
            size: const Size(180, 180),
            painter: _PulsePainter(
              glowValue: _breathController.value,
              progress: _holdController.value,
              color: baseColor,
            ),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.glowValue,
    required this.progress,
    required this.color,
  });

  final double glowValue;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.4;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.18 + glowValue * 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);

    final ringPaint = Paint()
      ..color = color.withOpacity(0.4 + glowValue * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius + 10, glowPaint);
    canvas.drawCircle(center, radius, ringPaint);

    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -pi / 2,
        progress * 2 * pi,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return glowValue != oldDelegate.glowValue ||
        progress != oldDelegate.progress ||
        color != oldDelegate.color;
  }
}
