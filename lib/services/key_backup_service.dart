import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_secret_service.dart';

class KeyBackupService {
  KeyBackupService({
    required SupabaseClient client,
    required DeviceSecretService deviceSecretService,
  })  : _client = client,
        _deviceSecretService = deviceSecretService;

  final SupabaseClient _client;
  final DeviceSecretService _deviceSecretService;

  static const int _pbkdf2Iterations = 100000;
  final _cipher = AesGcm.with256bits();

  /// Check if this user already has a recovery phrase stored locally.
  Future<String?> getStoredMnemonic(String userId) {
    return _deviceSecretService.readMnemonic(userId: userId);
  }

  /// Check if a backup exists on the server for this user.
  Future<bool> hasServerBackup(String userId) async {
    final response = await _client
        .from('profiles')
        .select('key_backup_encrypted')
        .eq('id', userId)
        .maybeSingle();
    return response != null && response['key_backup_encrypted'] != null;
  }

  /// Create an encrypted backup of the user's local keys and upload it.
  /// Returns the 12-word recovery phrase.
  Future<String> createBackup(String userId) async {
    final mnemonic = bip39.generateMnemonic();

    // Read current local keys
    final hmacKey = await _deviceSecretService.loadOrCreateHmacKey(userId: userId);
    final deviceKey = await _deviceSecretService.loadOrCreateDeviceWrappingKey(userId: userId);
    final hmacBytes = await hmacKey.extractBytes();
    final deviceBytes = await deviceKey.extractBytes();

    // Concatenate both keys (32 + 32 = 64 bytes)
    final payload = Uint8List(64);
    payload.setRange(0, 32, hmacBytes);
    payload.setRange(32, 64, deviceBytes);

    // Random salt for PBKDF2
    final saltKey = SecretKeyData.random(length: 16);
    final salt = Uint8List.fromList(await saltKey.extractBytes());

    // Derive AES-256 key from the mnemonic
    final aesKey = await _deriveKey(mnemonic, salt);

    // Encrypt both keys
    final secretBox = await _cipher.encrypt(payload, secretKey: aesKey);

    // Encode as JSON blob
    final backup = jsonEncode({
      'v': 1,
      'salt': base64.encode(salt),
      'nonce': base64.encode(secretBox.nonce),
      'ct': base64.encode(secretBox.cipherText),
      'mac': base64.encode(secretBox.mac.bytes),
    });

    // Upload to server
    await _client
        .from('profiles')
        .update({'key_backup_encrypted': backup})
        .eq('id', userId);

    // Store mnemonic locally so user can re-reveal it
    await _deviceSecretService.storeMnemonic(userId: userId, mnemonic: mnemonic);

    return mnemonic;
  }

  /// Restore local keys from the encrypted server backup using the mnemonic.
  Future<void> restoreBackup(String userId, String mnemonic) async {
    final trimmed = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(trimmed)) {
      throw const KeyBackupFailure('Invalid recovery phrase.');
    }

    // Download backup from server
    final response = await _client
        .from('profiles')
        .select('key_backup_encrypted')
        .eq('id', userId)
        .maybeSingle();

    final backupStr = response?['key_backup_encrypted'] as String?;
    if (backupStr == null || backupStr.isEmpty) {
      throw const KeyBackupFailure('No backup found for this account.');
    }

    // Parse
    final backup = jsonDecode(backupStr) as Map<String, dynamic>;
    final salt = base64.decode(backup['salt'] as String);
    final nonce = base64.decode(backup['nonce'] as String);
    final ct = base64.decode(backup['ct'] as String);
    final mac = base64.decode(backup['mac'] as String);

    // Derive AES key from mnemonic
    final aesKey = await _deriveKey(trimmed, Uint8List.fromList(salt));

    // Decrypt
    final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    final List<int> payload;
    try {
      payload = await _cipher.decrypt(secretBox, secretKey: aesKey);
    } catch (_) {
      throw const KeyBackupFailure('Incorrect recovery phrase.');
    }

    if (payload.length != 64) {
      throw const KeyBackupFailure('Corrupted backup data.');
    }

    // Split into two 32-byte keys
    final hmacBytes = payload.sublist(0, 32);
    final deviceBytes = payload.sublist(32, 64);

    // Overwrite local keys for this account
    await _deviceSecretService.storeHmacKey(userId: userId, bytes: hmacBytes);
    await _deviceSecretService.storeDeviceWrappingKey(userId: userId, bytes: deviceBytes);

    // Store mnemonic locally for re-reveal
    await _deviceSecretService.storeMnemonic(userId: userId, mnemonic: trimmed);
  }

  Future<SecretKey> _deriveKey(String mnemonic, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(mnemonic)),
      nonce: salt,
    );
  }
}

class KeyBackupFailure implements Exception {
  const KeyBackupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
