import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';



import '../services/home_controller.dart';
import '../services/revenuecat_controller.dart';
import '../services/theme_provider.dart';

import '../widgets/ambient_background.dart';



enum _PlanKind { monthly, yearly, lifetime, unknown }

class SubscriptionDebugScreen extends StatelessWidget {

  const SubscriptionDebugScreen({super.key});

  static final Uri _playSubscriptionsUrl =
      Uri.parse('https://play.google.com/store/account/subscriptions');

  String _normalizeProductId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return trimmed;
    final idx = trimmed.indexOf(':');
    if (idx <= 0) return trimmed;
    return trimmed.substring(0, idx);
  }

  bool _isLifetimeProductId(String id) {
    return id.toLowerCase().contains('lifetime');
  }

  _PlanKind _planKindForPackage(Package package) {
    final id = package.storeProduct.identifier;
    if (_isLifetimeProductId(id)) return _PlanKind.lifetime;

    final typeName = package.packageType.name.toLowerCase();
    if (typeName.contains('annual') || typeName.contains('year')) {
      return _PlanKind.yearly;
    }
    if (typeName.contains('month')) return _PlanKind.monthly;

    final normalized = _normalizeProductId(id).toLowerCase();
    if (normalized.contains('year') || normalized.contains('annual')) {
      return _PlanKind.yearly;
    }
    if (normalized.contains('month')) return _PlanKind.monthly;

    return _PlanKind.unknown;
  }

  Future<void> _showLifetimeCancelDialog(BuildContext context) async {
    if (!context.mounted) return;
    debugPrint('[PAYWALL] Showing manual-cancel dialog (lifetime + active sub)');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Lifetime unlocked!'),
          content: const Text(
            "Please note: you must manually cancel your old subscription in Google Play to avoid future charges.",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                debugPrint('[PAYWALL] User tapped open subscriptions link');
                await launchUrl(
                  _playSubscriptionsUrl,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('Open Google Play Subscriptions'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }



  @override

  Widget build(BuildContext context) {

    return Consumer<RevenueCatController>(

      builder: (context, controller, child) {

        final offerings = controller.offerings;

        final currentOffering = offerings?.current;

        final packages = currentOffering?.availablePackages ?? <Package>[];

        final isLifetime = controller.isLifetime;
        final isPro = controller.isPro;
        final activeProductId = controller.activeProductId;

        final activeSubscriptionsRaw =
            controller.customerInfo?.activeSubscriptions ?? <String>[];

        final activeSubscriptionIds = <String>{
          for (final id in activeSubscriptionsRaw) _normalizeProductId(id),
          if (activeProductId != null && activeProductId.isNotEmpty)
            _normalizeProductId(activeProductId),
        };

        Package? currentPackage;
        for (final package in packages) {
          if (activeSubscriptionIds
              .contains(_normalizeProductId(package.storeProduct.identifier))) {
            currentPackage = package;
            break;
          }
        }
        final currentKind =
            currentPackage != null ? _planKindForPackage(currentPackage) : null;

        return Scaffold(

          appBar: AppBar(

            title: const Text('Afterword Pro'),

            backgroundColor: const Color(0xFF0E0E0E),

            surfaceTintColor: Colors.transparent,

            actions: [

              IconButton(

                onPressed: controller.isLoading ? null : controller.refresh,

                icon: const Icon(Icons.refresh),

                tooltip: 'Refresh',

              ),

            ],

          ),

          body: Stack(

            children: [

              const RepaintBoundary(child: AmbientBackground()),

              SafeArea(

                top: false,

                child: ListView(

                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),

                children: [

                  _StatusCard(

                    isPro: isPro,

                    isLifetime: isLifetime,

                    isLoading: controller.isLoading,

                    lastFailure: controller.lastFailure,

                  ),

                  const SizedBox(height: 20),

                  if (isLifetime) ...[
                    _InfoBanner(
                      icon: Icons.workspace_premium,
                      message: 'You have Lifetime access. All features are permanently unlocked.',
                      color: const Color(0xFF5BC0B4),
                    ),
                  ] else ...[

                  // ── Feature comparison (above plans) ──
                  _FeatureComparisonCard(),

                  const SizedBox(height: 24),

                  Text(

                    'Available plans',

                    style: Theme.of(context).textTheme.titleMedium,

                  ),

                  const SizedBox(height: 12),

                  if (packages.isEmpty)

                    const Text(

                      'No offerings available. Check RevenueCat dashboard configuration.',

                    ),

                  for (final package in packages) ...[

                    Builder(
                      builder: (context) {
                        final kind = _planKindForPackage(package);
                        final normalizedId =
                            _normalizeProductId(package.storeProduct.identifier);

                        final isCurrent =
                            isPro && activeSubscriptionIds.contains(normalizedId);

                        final isDowngradeBlocked = isPro &&
                            currentKind == _PlanKind.yearly &&
                            kind == _PlanKind.monthly;

                        final buttonLabel = isCurrent
                            ? 'Current Plan'
                            : isDowngradeBlocked
                                ? 'Unavailable'
                                : controller.isLoading
                                    ? 'Processing'
                                    : 'Subscribe';

                        final isDisabled =
                            controller.isLoading || isCurrent || isDowngradeBlocked;

                        return _PackageTile(
                          package: package,
                          isLoading: controller.isLoading,
                          isCurrentPackage: isCurrent,
                          isDisabled: isDisabled,
                          buttonLabel: buttonLabel,
                          onPurchase: () async {
                            final beforeActiveSubs =
                                controller.customerInfo?.activeSubscriptions ??
                                    <String>[];

                            String? oldProductId;
                            if (defaultTargetPlatform ==
                                    TargetPlatform.android &&
                                isPro &&
                                currentKind != null &&
                                kind != _PlanKind.lifetime &&
                                kind != _PlanKind.unknown &&
                                currentKind != _PlanKind.unknown &&
                                currentKind != kind &&
                                beforeActiveSubs.isNotEmpty) {
                              // Pick the exact old product id from activeSubscriptions that matches the current package.
                              // This must be the Google Play base plan id string as returned by RevenueCat.
                              final currentNormalized = currentPackage == null
                                  ? null
                                  : _normalizeProductId(
                                      currentPackage.storeProduct.identifier,
                                    );
                              oldProductId = beforeActiveSubs.firstWhere(
                                (id) => currentNormalized != null &&
                                    _normalizeProductId(id) == currentNormalized,
                                orElse: () => beforeActiveSubs.first,
                              );
                            }

                            // Pre-purchase warning: buying lifetime while a
                            // subscription is active will NOT auto-cancel it.
                            if (kind == _PlanKind.lifetime &&
                                isPro &&
                                beforeActiveSubs.isNotEmpty &&
                                context.mounted) {
                              final proceed = await showDialog<bool>(
                                context: context,
                                builder: (dlg) => AlertDialog(
                                  title: const Text('Upgrade to Lifetime?'),
                                  content: const Text(
                                    'You have an active subscription. Google Play '
                                    'does not automatically cancel subscriptions '
                                    'when you buy a one-time product.\n\n'
                                    'After purchasing Lifetime, you will need to '
                                    'manually cancel your current subscription in '
                                    'Google Play to avoid being charged twice.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dlg, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(dlg, true),
                                      child: const Text('Continue'),
                                    ),
                                  ],
                                ),
                              );
                              if (proceed != true) return;
                              if (!context.mounted) return;
                            }

                            debugPrint(
                              '[PAYWALL] Purchase attempt: id=${package.storeProduct.identifier} kind=$kind oldProductId=${oldProductId ?? "(none)"}',
                            );

                            await controller.purchasePackage(
                              package,
                              oldProductId: oldProductId,
                            );

                            debugPrint(
                              '[PAYWALL] Purchase finished: isPro=${controller.isPro} isLifetime=${controller.isLifetime} activeSubs=${controller.customerInfo?.activeSubscriptions}',
                            );

                            if (context.mounted) {
                              final newStatus = controller.isLifetime
                                  ? 'lifetime'
                                  : controller.isPro
                                      ? 'pro'
                                      : 'free';
                              context
                                  .read<ThemeProvider>()
                                  .enforceSubscriptionLimits(newStatus);
                              // Re-fetch profile so all screens see updated subscription.
                              // Pass RC status so stale DB reads can't re-lock themes.
                              try {
                                await context
                                    .read<HomeController>()
                                    .refreshAfterPurchase(
                                      knownSubscriptionStatus: newStatus,
                                    );
                              } catch (_) {}

                              // Edge case: Android does not auto-cancel subscriptions when a one-time lifetime
                              // product is bought. If we just bought lifetime while a subscription was active,
                              // force a mandatory dialog to prevent double-billing.
                              final afterActiveSubs = controller
                                      .customerInfo?.activeSubscriptions ??
                                  <String>[];
                              if (kind == _PlanKind.lifetime &&
                                  controller.isLifetime &&
                                  beforeActiveSubs.isNotEmpty &&
                                  afterActiveSubs.isNotEmpty) {
                                if (context.mounted) {
                                  await _showLifetimeCancelDialog(context);
                                }
                              }
                            }
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                  ],
                  ],

                  const SizedBox(height: 20),

                  // ── Actions ──
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller.isLoading
                              ? null
                              : () async {
                                  await controller.restore();
                                  if (!context.mounted) return;
                                  final last = controller.lastFailure;
                                  if (last?.code ==
                                      PurchasesErrorCode.receiptAlreadyInUseError) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'This purchase is linked to another account.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Restore Purchases'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: controller.isLoading
                              ? null
                              : () async => controller.presentCustomerCenter(),
                          icon: const Icon(Icons.support_agent, size: 18),
                          label: const Text('Manage Subscription'),
                        ),
                      ),
                    ],
                  ),

                  // ── Cancellation / store policy ──
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subscription Info',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white54,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Subscriptions auto-renew unless cancelled at least '
                          '24 hours before the end of the current billing period. '
                          'You can cancel anytime from your device\'s app store settings. '
                          'No refund is provided for unused portions of a billing cycle. '
                          'Payment is charged to your app store account at confirmation of purchase.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                            height: 1.5,
                            fontSize: 11,
                          ),
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

      },

    );

  }

}



class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {

  const _StatusCard({

    required this.isPro,

    required this.isLifetime,

    required this.isLoading,

    required this.lastFailure,

  });



  final bool isPro;

  final bool isLifetime;

  final bool isLoading;

  final RevenueCatFailure? lastFailure;



  @override

  Widget build(BuildContext context) {

    final statusText = isLifetime ? 'Lifetime' : isPro ? 'Active' : 'Inactive';

    final statusColor = isLifetime
        ? const Color(0xFF5BC0B4)
        : isPro ? Theme.of(context).colorScheme.secondary : Colors.orangeAccent;



    final td = context.watch<ThemeProvider>().themeData;
    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [td.cardGradientStart, td.cardGradientEnd],

        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: td.dividerColor),

        boxShadow: [

          BoxShadow(

            color: td.accentGlow.withValues(alpha: 0.08),

            blurRadius: 24,

            spreadRadius: -4,

          ),

          BoxShadow(

            color: Colors.black.withValues(alpha: 0.35),

            blurRadius: 16,

            offset: const Offset(0, 10),

          ),

        ],

      ),

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              children: [

                Container(

                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(

                    color: statusColor.withValues(alpha: 0.18),

                    shape: BoxShape.circle,

                  ),

                  child: Icon(

                    isPro ? Icons.verified : Icons.lock_outline,

                    color: statusColor,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(

                        'Afterword Pro',

                        style: Theme.of(context).textTheme.titleMedium,

                      ),

                      const SizedBox(height: 4),

                      Text(

                        'Status: $statusText',

                        style: Theme.of(context)

                            .textTheme

                            .bodySmall

                            ?.copyWith(color: Colors.white60),

                      ),

                    ],

                  ),

                ),

                Container(

                  padding:

                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

                  decoration: BoxDecoration(

                    color: statusColor.withValues(alpha: 0.2),

                    borderRadius: BorderRadius.circular(999),

                  ),

                  child: Text(

                    statusText,

                    style: Theme.of(context)

                        .textTheme

                        .labelSmall

                        ?.copyWith(color: statusColor),

                  ),

                ),

              ],

            ),

            if (isLoading) ...[

              const SizedBox(height: 12),

              const LinearProgressIndicator(),

            ],

            if (lastFailure != null) ...[

              const SizedBox(height: 12),

              Text(

                lastFailure!.message,

                style: Theme.of(context).textTheme.bodyMedium?.copyWith(

                      color: Theme.of(context).colorScheme.error,

                    ),

              ),

            ],

          ],

        ),

      ),

    );

  }

}



class _PackageTile extends StatelessWidget {

  const _PackageTile({

    required this.package,

    required this.isLoading,

    required this.isCurrentPackage,

    required this.isDisabled,

    required this.buttonLabel,

    required this.onPurchase,

  });



  final Package package;

  final bool isLoading;

  final bool isCurrentPackage;

  final bool isDisabled;

  final String buttonLabel;

  final Future<void> Function() onPurchase;



  @override

  Widget build(BuildContext context) {

    final product = package.storeProduct;

    // Google Play appends " (App Name)" to product titles — strip it.
    var title = product.title.isNotEmpty ? product.title : product.identifier;
    final parenIdx = title.lastIndexOf('(');
    if (parenIdx > 0 && title.endsWith(')')) {
      title = title.substring(0, parenIdx).trimRight();
    }

    final description = product.description;

    final price = product.priceString;

    final typeLabel = _formatPackageType(package.packageType);



    final td = context.watch<ThemeProvider>().themeData;
    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [td.cardGradientStart, td.cardGradientEnd],

        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: td.dividerColor),

      ),

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Text(

              title,

              style: Theme.of(context).textTheme.titleMedium,

            ),

            const SizedBox(height: 4),

            Text(

              typeLabel,

              style: Theme.of(context)

                  .textTheme

                  .bodySmall

                  ?.copyWith(color: Colors.white60),

            ),

            if (description.isNotEmpty) ...[

              const SizedBox(height: 8),

              Text(

                description,

                style: Theme.of(context)

                    .textTheme

                    .bodySmall

                    ?.copyWith(color: Colors.white70),

              ),

            ],

            const SizedBox(height: 12),

            Row(

              children: [

                Text(

                  price,

                  style: Theme.of(context).textTheme.titleLarge,

                ),

                const Spacer(),

                FilledButton.icon(

                  onPressed: isDisabled

                      ? null

                      : () async {

                          await onPurchase();

                        },

                  icon: Icon(isCurrentPackage
                      ? Icons.check_circle_outline
                      : Icons.shopping_bag_outlined),

                  label: Text(buttonLabel),

                ),

              ],

            ),

          ],

        ),

      ),

    );

  }

}



class _FeatureComparisonCard extends StatelessWidget {
  const _FeatureComparisonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const check = Icon(Icons.check_circle, size: 16, color: Color(0xFF5BC0B4));
    const dash = Icon(Icons.remove_circle_outline, size: 16, color: Colors.white24);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: Colors.white70, fontSize: 12);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: Colors.white54, fontWeight: FontWeight.w700, letterSpacing: 1,
    );

    Widget row(String label, bool free, bool pro, bool lifetime) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(flex: 5, child: Text(label, style: labelStyle)),
            Expanded(flex: 2, child: Center(child: free ? check : dash)),
            Expanded(flex: 2, child: Center(child: pro ? check : dash)),
            Expanded(flex: 2, child: Center(child: lifetime ? check : dash)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Feature Comparison', style: theme.textTheme.titleSmall),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(flex: 5, child: Text('', style: headerStyle)),
              Expanded(flex: 2, child: Center(child: Text('FREE', style: headerStyle))),
              Expanded(flex: 2, child: Center(child: Text('PRO', style: headerStyle))),
              Expanded(flex: 2, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text('LIFETIME', style: headerStyle)))),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
          row('Text entries', true, true, true),
          row('Push notifications', true, true, true),
          row('Recovery phrase backup', true, true, true),
          row('3 themes & 3 soul fires', true, true, true),
          row('Unlimited entries', false, true, true),
          row('Custom timer (7–365 days)', false, true, true),
          row('Inactivity failsafe (erase mode)', false, true, true),
          row('Email expiry warning', false, true, true),
          row('7 themes & 7 soul fires', false, true, true),
          row('Audio vault (1 min)', false, true, true),
          row('All 10 themes & soul fires', false, false, true),
          row('Audio vault (10 min)', false, false, true),
          row('Extended timer (up to 10 yrs)', false, false, true),
        ],
      ),
    );
  }
}


String _formatPackageType(PackageType type) {

  final raw = type.name;

  final withSpaces = raw.replaceAllMapped(

    RegExp(r'([a-z])([A-Z])'),

    (match) => '${match[1]} ${match[2]}',

  );

  if (withSpaces.isEmpty) {

    return withSpaces;

  }

  return withSpaces[0].toUpperCase() + withSpaces.substring(1);

}

