import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



import '../models/profile.dart';

import '../services/account_service.dart';

import '../services/auth_controller.dart';

import '../services/crypto_service.dart';

import '../services/device_secret_service.dart';

import '../services/home_controller.dart';

import '../services/notification_service.dart';

import '../services/profile_service.dart';

import '../services/revenuecat_controller.dart';

import '../services/theme_provider.dart';

import '../services/server_crypto_service.dart';

import '../services/vault_service.dart';

import '../widgets/ambient_background.dart';

import '../widgets/soul_fire_button.dart';

import 'app_drawer.dart';

import 'my_vault_page.dart';

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



    final rc = context.read<RevenueCatController>();
    final subStatus = rc.isLifetime ? 'lifetime' : rc.isPro ? 'pro' : 'free';

    return ChangeNotifierProvider(

      key: ValueKey(user.id),

      create: (_) => HomeController(

        profileService: ProfileService(Supabase.instance.client),

        notificationService: NotificationService(),

        accountService: AccountService(

          client: Supabase.instance.client,

          vaultService: VaultService(

            client: Supabase.instance.client,

            cryptoService: CryptoService(),

            serverCryptoService:

                ServerCryptoService(client: Supabase.instance.client),

            deviceSecretService: DeviceSecretService(),

          ),

          deviceSecretService: DeviceSecretService(),

        ),

      )..initialize(user, subscriptionStatus: subStatus),

      child: _HomeView(

        userId: user.id,

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

            : 'Protocol executed on $dateLabel. Sent items are read-only for 30 days.';

    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(

          colors: [

            accentColor.withValues(alpha: 0.16),

            Colors.transparent,

          ],

        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: accentColor.withValues(alpha: 0.35)),

      ),

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Row(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Container(

              padding: const EdgeInsets.all(8),

              decoration: BoxDecoration(

                color: accentColor.withValues(alpha: 0.18),

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

  });



  final String userId;



  @override

  State<_HomeView> createState() => _HomeViewState();

}



class _HomeViewState extends State<_HomeView> with WidgetsBindingObserver {

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final ScrollController _scrollController = ScrollController();

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');




  @override

  void initState() {

    super.initState();

    WidgetsBinding.instance.addObserver(this);

  }



  @override

  void dispose() {

    WidgetsBinding.instance.removeObserver(this);

    _scrollController.dispose();

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

    final profile = controller.profile;

    // Sync theme provider from profile whenever profile updates
    if (profile != null) {
      final tp = context.read<ThemeProvider>();
      tp.syncFromProfile(profile);
    }

    final protocolExecutedAt = controller.protocolExecutedAt;

    final protocolWasArchived = controller.protocolWasArchived;

    final protocolNoEntries = controller.protocolNoEntries;

    final isLifetime = revenueCat.isLifetime;

    final isPro = revenueCat.isPro || isLifetime;



    return Scaffold(

      key: _scaffoldKey,

      drawer: AppDrawer(

        userId: widget.userId,

      ),

      body: Stack(

        children: [

          const RepaintBoundary(child: AmbientBackground()),

          SafeArea(

            child: RefreshIndicator(
              displacement: 60,
              strokeWidth: 2.5,
              onRefresh: () async {
                final hc = context.read<HomeController>();
                await hc.autoCheckIn();
                await hc.refreshVaultStatus();
              },
              color: Theme.of(context).colorScheme.primary,
              child: ListView(

              controller: _scrollController,

              physics: const AlwaysScrollableScrollPhysics(),

              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),

              children: [

                _HeaderRow(

                  isPro: isPro,

                  isLifetime: isLifetime,

                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),

                ),

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

                _TimerCard(

                  profile: profile,

                  dateFormat: _dateFormat,

                  isLoading: controller.isLoading,

                  errorMessage: controller.errorMessage,

                  isPro: isPro,

                  isLifetime: isLifetime,

                  hasVaultEntries: controller.hasVaultEntries,

                  onTimerChanged: (days) => controller.updateTimerDays(days),

                ),

                const SizedBox(height: 24),

                Center(

                  child: RepaintBoundary(child: SoulFireButton(

                    styleId: context.watch<ThemeProvider>().soulFireId,

                    enabled: !controller.isLoading && profile != null,

                    onConfirmed: () async {

                      final success = await controller.manualCheckIn();

                      if (!context.mounted) return;

                      if (success) {

                        ScaffoldMessenger.of(context).showSnackBar(

                          const SnackBar(content: Text('Signal verified.')),

                        );

                      }

                    },

                  )),

                ),

                const SizedBox(height: 8),

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

                _VaultSummaryCard(
                  entryCount: controller.vaultEntryCount,
                  isLoading: controller.isLoading,
                  onViewAll: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyVaultPage(userId: widget.userId),
                      ),
                    ).then((_) {
                      // Refresh vault count when returning from vault page
                      if (context.mounted) {
                        context.read<HomeController>().refreshVaultStatus();
                      }
                    });
                  },
                  onAdd: () async {
                    final created = await openVaultEntryEditor(
                      context,
                      userId: widget.userId,
                      isPro: isPro,
                      isLifetime: isLifetime,
                    );
                    if (created && context.mounted) {
                      context.read<HomeController>().refreshVaultStatus();
                    }
                  },
                ),

              ],

            ),
            ),
          ),
        ],
      ),
    );

  }




}



class _HeaderRow extends StatelessWidget {

  const _HeaderRow({

    required this.isPro,

    required this.isLifetime,

    required this.onMenu,

  });



  final bool isPro;

  final bool isLifetime;

  final VoidCallback onMenu;



  @override

  Widget build(BuildContext context) {

    return Row(

      crossAxisAlignment: CrossAxisAlignment.center,

      children: [

        Container(

          decoration: BoxDecoration(

            color: Colors.white10,

            borderRadius: BorderRadius.circular(12),

            border: Border.all(color: Colors.white12),

          ),

          child: IconButton(

            onPressed: onMenu,

            icon: const Icon(Icons.menu),

            tooltip: 'Menu',

          ),

        ),

        const SizedBox(width: 12),

        Flexible(

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(

                'Afterword',

                style: Theme.of(context).textTheme.headlineSmall?.copyWith(

                      fontWeight: FontWeight.w600,

                      letterSpacing: 1.3,

                    ),

                overflow: TextOverflow.ellipsis,

              ),

              const SizedBox(height: 2),

              Text(

                'Signal-secure vault',

                style: Theme.of(context)

                    .textTheme

                    .bodySmall

                    ?.copyWith(color: Colors.white60),

                overflow: TextOverflow.ellipsis,

              ),

            ],

          ),

        ),

        const SizedBox(width: 8),

        _PlanChip(isPro: isPro, isLifetime: isLifetime),

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



class _TimerCard extends StatefulWidget {

  const _TimerCard({

    required this.profile,

    required this.dateFormat,

    required this.isLoading,

    this.errorMessage,

    required this.isPro,

    required this.isLifetime,

    required this.hasVaultEntries,

    required this.onTimerChanged,

  });



  final Profile? profile;

  final DateFormat dateFormat;

  final bool isLoading;

  final String? errorMessage;

  final bool isPro;

  final bool isLifetime;

  final bool hasVaultEntries;

  final ValueChanged<int> onTimerChanged;



  @override

  State<_TimerCard> createState() => _TimerCardState();

}

class _TimerCardState extends State<_TimerCard> {

  bool _showLongTimerWarning = false;
  Timer? _warningTimer;

  int get _minDays => widget.isPro || widget.isLifetime ? 7 : 30;
  int get _maxDays => widget.isLifetime ? 3650 : widget.isPro ? 365 : 30;
  bool get _canAdjust => widget.isPro || widget.isLifetime;

  @override
  void dispose() {
    _warningTimer?.cancel();
    super.dispose();
  }

  void _openTimerPicker() {
    final profile = widget.profile;
    if (profile == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TimerPickerSheet(
        currentDays: profile.timerDays,
        minDays: _minDays,
        maxDays: _maxDays,
        isLifetime: widget.isLifetime,
        onConfirm: (days) {
          Navigator.pop(context);
          if (days != profile.timerDays) {
            widget.onTimerChanged(days);
            if (days >= 365) {
              _warningTimer?.cancel();
              setState(() => _showLongTimerWarning = true);
              _warningTimer = Timer(const Duration(seconds: 5), () {
                if (mounted) setState(() => _showLongTimerWarning = false);
              });
            } else {
              _warningTimer?.cancel();
              if (_showLongTimerWarning) {
                setState(() => _showLongTimerWarning = false);
              }
            }
          }
        },
      ),
    );
  }

  String _fmtDays(int d) {
    if (d >= 365) {
      final y = d ~/ 365;
      final r = d % 365;
      if (r == 0) return '$y ${y == 1 ? 'year' : 'years'}';
      return '$y${y == 1 ? 'yr' : 'yrs'}, $r days';
    }
    return '$d days';
  }

  @override

  Widget build(BuildContext context) {

    final resolvedProfile = widget.profile;

    if (resolvedProfile == null) {

      return _SurfaceCard(

        child: Padding(

          padding: const EdgeInsets.all(20),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(

                widget.isLoading

                    ? 'Syncing your timer...'

                    : widget.errorMessage != null

                        ? 'Unable to sync timer'

                        : 'Syncing your timer...',

                style: Theme.of(context).textTheme.bodyMedium,

              ),

              const SizedBox(height: 8),

              if (widget.errorMessage != null && !widget.isLoading)

                Text(

                  'Pull down to retry or restart the app.',

                  style: Theme.of(context)

                      .textTheme

                      .bodySmall

                      ?.copyWith(color: Colors.white54),

                )

              else

                const LinearProgressIndicator(),

            ],

          ),

        ),

      );

    }



    final theme = Theme.of(context);

    final remaining = resolvedProfile.timeRemaining;

    final days = remaining.inDays;

    final hours = remaining.inHours.remainder(24);

    final timerLabel = remaining.isNegative

        ? 'Expired'

        : days > 0

            ? '$days days'

            : '${hours}h remaining';

    final timerSub = remaining.isNegative

        ? 'Check in to reactivate'

        : days > 0 && hours > 0

            ? '+ ${hours}h'

            : null;

    final statusMessage = resolvedProfile.status.toLowerCase() == 'active'

        ? 'Protocol secure'

        : 'Protocol executed';

    final statusColor = resolvedProfile.status.toLowerCase() == 'active'

        ? theme.colorScheme.secondary

        : theme.colorScheme.error;

    final totalSeconds = resolvedProfile.timerDays * 24 * 60 * 60;

    final remainingSeconds =

        remaining.inSeconds.clamp(0, totalSeconds.toInt());

    final progress = totalSeconds == 0

        ? 0.0

        : remainingSeconds / totalSeconds.toDouble();

    final currentDays = resolvedProfile.timerDays;



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

                    color: statusColor.withValues(alpha: 0.18),

                    borderRadius: BorderRadius.circular(999),

                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),

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

                  'Cycle ${resolvedProfile.timerDays} days',

                  style: theme.textTheme.labelSmall?.copyWith(

                    color: Colors.white54,

                  ),

                ),

              ],

            ),

            const SizedBox(height: 14),

            Row(

              crossAxisAlignment: CrossAxisAlignment.baseline,

              textBaseline: TextBaseline.alphabetic,

              children: [

                Text(

                  timerLabel,

                  style: theme.textTheme.headlineSmall?.copyWith(

                    fontWeight: FontWeight.w600,

                  ),

                ),

                if (timerSub != null) ...[

                  const SizedBox(width: 8),

                  Text(

                    timerSub,

                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),

                  ),

                ],

              ],

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

              'Deadline: ${widget.dateFormat.format(resolvedProfile.deadline)}',

              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),

            ),

            const SizedBox(height: 4),

            Text(

              'Last check-in: ${widget.dateFormat.format(resolvedProfile.lastCheckIn.toLocal())}',

              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),

            ),

            // --- Timer settings section ---
            const SizedBox(height: 16),
            Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 14),

            if (!widget.hasVaultEntries) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: theme.colorScheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vault is empty — timer has no effect until you add an entry.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.secondary, fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_canAdjust) ...[
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Timer: ${_fmtDays(currentDays)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: widget.isLoading ? null : _openTimerPicker,
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Adjust'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      textStyle: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              if (_showLongTimerWarning) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Time Capsule mode — beneficiaries won\'t receive '
                          'anything until the full duration passes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error, fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fixed at 30 days · Upgrade to customize',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],

          ],

        ),

      ),

    );

  }

}



class _TimerPickerSheet extends StatefulWidget {
  const _TimerPickerSheet({
    required this.currentDays,
    required this.minDays,
    required this.maxDays,
    required this.isLifetime,
    required this.onConfirm,
  });

  final int currentDays;
  final int minDays;
  final int maxDays;
  final bool isLifetime;
  final ValueChanged<int> onConfirm;

  @override
  State<_TimerPickerSheet> createState() => _TimerPickerSheetState();
}

class _TimerPickerSheetState extends State<_TimerPickerSheet> {
  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.currentDays
        .toDouble()
        .clamp(widget.minDays.toDouble(), widget.maxDays.toDouble());
  }

  int get _selectedDays => _sliderValue.round();

  String _fmtDays(int d) {
    if (d >= 365) {
      final y = d ~/ 365;
      final r = d % 365;
      if (r == 0) return '$y ${y == 1 ? 'year' : 'years'}';
      return '$y${y == 1 ? 'yr' : 'yrs'}, $r days';
    }
    return '$d days';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = widget.maxDays - widget.minDays;
    final divisions = range > 500 ? (range ~/ 5) : range;

    return SafeArea(
      top: false,
      child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Adjust Timer',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Set how long before protocol executes',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              _fmtDays(_selectedDays),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                _fmtDays(widget.minDays),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white30, fontSize: 10),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 18),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.white,
                    overlayColor:
                        theme.colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    min: widget.minDays.toDouble(),
                    max: widget.maxDays.toDouble(),
                    divisions: divisions,
                    value: _sliderValue,
                    onChanged: (v) => setState(() => _sliderValue = v),
                  ),
                ),
              ),
              Text(
                _fmtDays(widget.maxDays),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white30, fontSize: 10),
              ),
            ],
          ),
          if (_selectedDays >= 365) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Beneficiaries won\'t receive anything until the '
                      'full ${_fmtDays(_selectedDays)} duration passes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onConfirm(_selectedDays),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Set to ${_fmtDays(_selectedDays)}'),
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



class _VaultSummaryCard extends StatelessWidget {
  const _VaultSummaryCard({
    required this.entryCount,
    required this.isLoading,
    required this.onViewAll,
    required this.onAdd,
  });

  final int entryCount;
  final bool isLoading;
  final VoidCallback onViewAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  child: const Icon(Icons.lock_outline, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Vault', style: theme.textTheme.titleMedium),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$entryCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: TextButton(
                    onPressed: onViewAll,
                    child: const Text('View All →'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entryCount == 0
                  ? 'Your vault is empty. Add a secure message.'
                  : '$entryCount encrypted ${entryCount == 1 ? 'entry' : 'entries'} stored.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
