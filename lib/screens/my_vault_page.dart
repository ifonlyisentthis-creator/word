import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/revenuecat_controller.dart';
import '../widgets/ambient_background.dart';
import 'vault_section.dart';

class MyVaultPage extends StatelessWidget {
  const MyVaultPage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    final revenueCat = context.watch<RevenueCatController>();
    final isLifetime = revenueCat.isLifetime;
    final isPro = revenueCat.isPro || isLifetime;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vault'),
        backgroundColor: const Color(0xFF0E0E0E),
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              VaultSection(
                userId: userId,
                isPro: isPro,
                isLifetime: isLifetime,
                readOnly: false,
                allowCreate: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
