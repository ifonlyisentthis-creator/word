import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:provider/provider.dart';

import '../services/revenuecat_controller.dart';
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
        final topPadding =
            MediaQuery.of(context).padding.top + kToolbarHeight + 12;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('Afterword Pro'),
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
              const AmbientBackground(),
              ListView(
                padding: EdgeInsets.fromLTRB(20, topPadding, 20, 32),
                children: [
                  _StatusCard(
                    isPro: controller.isPro,
                    isLoading: controller.isLoading,
                    lastFailure: controller.lastFailure,
                  ),
                  const SizedBox(height: 20),
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
                      onPurchase: () async {
                        await controller.purchasePackage(package);
                      },
                    ),
                    const SizedBox(height: 12),
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
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isPro,
    required this.isLoading,
    required this.lastFailure,
  });

  final bool isPro;
  final bool isLoading;
  final RevenueCatFailure? lastFailure;

  @override
  Widget build(BuildContext context) {
    final statusText = isPro ? 'Active' : 'Inactive';
    final statusColor =
        isPro ? Theme.of(context).colorScheme.secondary : Colors.orangeAccent;

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
            color: Colors.black.withOpacity(0.35),
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
                    color: statusColor.withOpacity(0.18),
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
                    color: statusColor.withOpacity(0.2),
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
    required this.onPurchase,
  });

  final Package package;
  final bool isLoading;
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
                  onPressed: isLoading
                      ? null
                      : () async {
                          await onPurchase();
                        },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(isLoading ? 'Processing' : 'Subscribe'),
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
