import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_secret_service.dart';
import 'vault_service.dart';

class AccountService {
  AccountService({
    required SupabaseClient client,
    required VaultService vaultService,
    required DeviceSecretService deviceSecretService,
  })  : _client = client,
        _vaultService = vaultService,
        _deviceSecretService = deviceSecretService;

  final SupabaseClient _client;
  final VaultService _vaultService;
  final DeviceSecretService _deviceSecretService;

  Future<void> deleteAccount(String userId) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AccountServiceFailure('Not authorized to delete this account.');
    }

    // Step 1: Delete audio files via Storage API (direct SQL on
    // storage.objects is forbidden by Supabase — error 42501).
    try {
      await _vaultService.deleteAllEntries(userId);
    } catch (_) {
      // Best-effort; the RPC cascade will remove DB rows regardless.
    }

    // Step 2: Call the RPC which deletes auth.users (cascades to
    // profiles, vault_entries, push_devices, tombstones, etc.)
    try {
      await _client.rpc('delete_my_account');
    } on PostgrestException catch (error) {
      // Backward-compatible fallback for databases that do not yet have
      // delete_my_account() migration applied.
      final message = error.message.toLowerCase();
      if (!message.contains('delete_my_account')) rethrow;

      await _client.from('vault_entry_tombstones').delete().eq('user_id', userId);
      await _client.from('push_devices').delete().eq('user_id', userId);
      await _client.from('profiles').delete().eq('id', userId);
    } finally {
      // Best-effort local cleanup — must never mask a successful server deletion.
      try { await _deviceSecretService.clearHmacKey(userId: userId); } catch (_) {}
      try { await _deviceSecretService.clearDeviceWrappingKey(userId: userId); } catch (_) {}
      try { await _deviceSecretService.clearMnemonic(userId: userId); } catch (_) {}
    }
  }
}

class AccountServiceFailure implements Exception {
  const AccountServiceFailure(this.message);

  final String message;
}
