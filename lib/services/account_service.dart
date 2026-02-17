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
    await _vaultService.deleteAllEntries(userId);
    await _client.from('vault_entry_tombstones').delete().eq('user_id', userId);
    await _client.from('profiles').delete().eq('id', userId);
    await _deviceSecretService.clearHmacKey();
    await _deviceSecretService.clearDeviceWrappingKey();
  }
}
