import 'package:flutter/material.dart';

import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:provider/provider.dart';



import '../services/home_controller.dart';
import '../services/revenuecat_controller.dart';
import '../services/theme_provider.dart';

import '../widgets/ambient_background.dart';



class SubscriptionDebugScreen extends StatelessWidget {

  const SubscriptionDebugScreen({super.key});



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

        return Scaffold(
          backgroundColor: Colors.transparent,

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

                    _PackageTile(

                      package: package,

                      isLoading: controller.isLoading,

                      isCurrentPackage: isPro && package.storeProduct.identifier == activeProductId,

                      onPurchase: () async {

                        await controller.purchasePackage(package);
                        if (context.mounted) {
                          final newStatus = controller.isLifetime
                              ? 'lifetime'
                              : controller.isPro
                                  ? 'pro'
                                  : 'free';
                          context.read<ThemeProvider>().enforceSubscriptionLimits(newStatus);
                          // Re-fetch profile so all screens see updated subscription
                          try {
                            context.read<HomeController>().refreshAfterPurchase();
                          } catch (_) {}
                        }

                      },

                    ),

                    const SizedBox(height: 12),

                  ],
                  ],

                  const SizedBox(height: 20),

                  Text(

                    'Actions',

                    style: Theme.of(context).textTheme.titleMedium,

                  ),

                  const SizedBox(height: 12),

                  Wrap(

                    spacing: 12,

                    runSpacing: 12,

                    children: [

                      _ActionButton(

                        label: 'Show Paywall',

                        icon: Icons.auto_awesome,

                        onPressed: controller.isLoading

                            ? null

                            : () async {

                                await controller.presentPaywall();

                              },

                      ),

                      _ActionButton(

                        label: 'Paywall if Needed',

                        icon: Icons.lock_clock,

                        onPressed: controller.isLoading

                            ? null

                            : () async {

                                await controller.presentPaywallIfNeeded();

                              },

                      ),

                      _ActionButton(

                        label: 'Restore Purchases',

                        icon: Icons.restore,

                        onPressed: controller.isLoading

                            ? null

                            : () async {

                                await controller.restore();

                              },

                      ),

                      _ActionButton(

                        label: 'Customer Center',

                        icon: Icons.support_agent,

                        onPressed: controller.isLoading

                            ? null

                            : () async {

                                await controller.presentCustomerCenter();

                              },

                      ),

                    ],

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



    return Container(

      decoration: BoxDecoration(

        gradient: const LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],

        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.white12),

        boxShadow: [

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

    required this.onPurchase,

  });



  final Package package;

  final bool isLoading;

  final bool isCurrentPackage;

  final Future<void> Function() onPurchase;



  @override

  Widget build(BuildContext context) {

    final product = package.storeProduct;

    final title = product.title.isNotEmpty ? product.title : product.identifier;

    final description = product.description;

    final price = product.priceString;

    final typeLabel = _formatPackageType(package.packageType);



    return Container(

      decoration: BoxDecoration(

        gradient: const LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],

        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.white12),

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

                  onPressed: (isLoading || isCurrentPackage)

                      ? null

                      : () async {

                          await onPurchase();

                        },

                  icon: Icon(isCurrentPackage
                      ? Icons.check_circle_outline
                      : Icons.shopping_bag_outlined),

                  label: Text(isCurrentPackage
                      ? 'Current Plan'
                      : isLoading ? 'Processing' : 'Subscribe'),

                ),

              ],

            ),

          ],

        ),

      ),

    );

  }

}



class _ActionButton extends StatelessWidget {

  const _ActionButton({

    required this.label,

    required this.icon,

    required this.onPressed,

  });



  final String label;

  final IconData icon;

  final Future<void> Function()? onPressed;



  @override

  Widget build(BuildContext context) {

    return OutlinedButton.icon(

      onPressed: onPressed == null

          ? null

          : () async {

              await onPressed!();

            },

      icon: Icon(icon, size: 18),

      label: Text(label),

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

