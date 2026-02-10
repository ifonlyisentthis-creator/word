import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_controller.dart';
import '../services/home_controller.dart';
import '../services/revenuecat_controller.dart';
import 'account_settings_screen.dart';
import 'how_it_works_screen.dart';
import 'my_vault_page.dart';
import 'privacy_policy_screen.dart';
import 'subscription_debug_screen.dart';
import 'terms_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authController = context.read<AuthController>();
    final revenueCat = context.watch<RevenueCatController>();
    final homeController = context.watch<HomeController>();
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    // Use sender name from profile (updated in account settings) with auth metadata fallback
    final profileName = homeController.profile?.senderName;
    final authName = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;
    final displayName = (profileName != null && profileName != 'Afterword')
        ? profileName
        : authName ?? email.split('@').first;

    final isPro = revenueCat.isPro || revenueCat.isLifetime;

    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Column(
          children: [
            // Profile header with avatar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                          theme.colorScheme.secondary.withValues(alpha: 0.15),
                        ],
                      ),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Plan badge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isPro
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPro
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.white12,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  revenueCat.isLifetime
                      ? 'LIFETIME'
                      : isPro
                          ? 'PRO'
                          : 'FREE PLAN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isPro ? theme.colorScheme.primary : Colors.white54,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            // Navigation items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerItem(
                    icon: Icons.note_outlined,
                    label: 'My Vault',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyVaultPage(userId: userId),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.help_outline,
                    label: 'How It Works',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HowItWorksScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.white12, indent: 20, endIndent: 20),
                  _DrawerItem(
                    icon: Icons.card_membership_outlined,
                    label: 'Subscription',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionDebugScreen(),
                        ),
                      );
                    },
                  ),
                  if (isPro) ...[
                    _DrawerItem(
                      icon: Icons.support_agent_outlined,
                      label: 'Manage Subscription',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionDebugScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                  const Divider(color: Colors.white12, indent: 20, endIndent: 20),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: 'Account Settings',
                    onTap: () {
                      final homeController = context.read<HomeController>();
                      final authController = context.read<AuthController>();
                      final rcController = context.read<RevenueCatController>();
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountSettingsScreen(
                            homeController: homeController,
                            authController: authController,
                            revenueCatController: rcController,
                          ),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.description_outlined,
                    label: 'Terms & Conditions',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _DrawerItem(
              icon: Icons.logout,
              label: 'Sign Out',
              onTap: () {
                final rc = context.read<RevenueCatController>();
                Navigator.pop(context);
                authController.prepareSignOut();
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await rc.logOut();
                  await authController.signOut();
                });
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Afterword v1.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white24,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22, color: Colors.white70),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
      ),
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
