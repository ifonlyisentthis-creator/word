import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_secret_service.dart';

String normalizeRecoveryPhrase(String phrase) {
  return phrase
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}

abstract class KeyBackupRemoteStore {
  Future<String?> fetchEncryptedBackup(String userId);
  Future<void> saveEncryptedBackup(String userId, String encryptedBackup);
}

class SupabaseKeyBackupRemoteStore implements KeyBackupRemoteStore {
  SupabaseKeyBackupRemoteStore(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> fetchEncryptedBackup(String userId) async {
    final response = await _client
        .from('profiles')
        .select('key_backup_encrypted')
        .eq('id', userId)
        .maybeSingle();
    return response?['key_backup_encrypted'] as String?;
  }

  @override
  Future<void> saveEncryptedBackup(String userId, String encryptedBackup) async {
    await _client
        .from('profiles')
        .update({'key_backup_encrypted': encryptedBackup})
        .eq('id', userId);
  }
}

class KeyBackupService {
  KeyBackupService({
    SupabaseClient? client,
    KeyBackupRemoteStore? remoteStore,
    required KeyMaterialStore deviceSecretService,
  })  : assert(client != null || remoteStore != null),
        _remoteStore = remoteStore ?? SupabaseKeyBackupRemoteStore(client!),
        _deviceSecretService = deviceSecretService;

  final KeyBackupRemoteStore _remoteStore;
  final KeyMaterialStore _deviceSecretService;

  static const int _pbkdf2Iterations = 100000;
  final _cipher = AesGcm.with256bits();

  /// Check if this user already has a recovery phrase stored locally.
  Future<String?> getStoredMnemonic(String userId) {
    return _deviceSecretService.readMnemonic(userId: userId);
  }

  /// Check if a backup exists on the server for this user.
  Future<bool> hasServerBackup(String userId) async {
    final backup = await _remoteStore.fetchEncryptedBackup(userId);
    return backup != null && backup.trim().isNotEmpty;
  }

  /// Create an encrypted backup of the user's local keys and upload it.
  /// Returns the 12-word recovery phrase.
  Future<String> createBackup(String userId) async {
    final mnemonic = normalizeRecoveryPhrase(bip39.generateMnemonic());

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
    await _remoteStore.saveEncryptedBackup(userId, backup);

    // Store mnemonic locally so user can re-reveal it
    await _deviceSecretService.storeMnemonic(userId: userId, mnemonic: mnemonic);

    return mnemonic;
  }

  /// Restore local keys from the encrypted server backup using the mnemonic.
  Future<void> restoreBackup(String userId, String mnemonic) async {
    final normalized = normalizeRecoveryPhrase(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const KeyBackupFailure('Invalid recovery phrase.');
    }

    // Download backup from server
    final backupStr = await _remoteStore.fetchEncryptedBackup(userId);
    if (backupStr == null || backupStr.isEmpty) {
      throw const KeyBackupFailure('No backup found for this account.');
    }

    final backup = _parseBackupBlob(backupStr);

    // Derive AES key from mnemonic
    final aesKey = await _deriveKey(normalized, backup.salt);

    // Decrypt
    final secretBox = SecretBox(
      backup.cipherText,
      nonce: backup.nonce,
      mac: Mac(backup.mac),
    );
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
    await _deviceSecretService.storeMnemonic(userId: userId, mnemonic: normalized);
  }

  _EncryptedBackupBlob _parseBackupBlob(String backupStr) {
    try {
      final decoded = jsonDecode(backupStr);
      if (decoded is! Map<String, dynamic>) {
        throw const KeyBackupFailure('Corrupted backup data.');
      }

      final version = decoded['v'];
      final parsedVersion = version is num
          ? version.toInt()
          : int.tryParse(version?.toString() ?? '1');
      if (parsedVersion != 1) {
        throw const KeyBackupFailure('Unsupported backup format.');
      }

      final salt = _decodeBase64Field(decoded, 'salt');
      final nonce = _decodeBase64Field(decoded, 'nonce');
      final cipherText = _decodeBase64Field(decoded, 'ct');
      final mac = _decodeBase64Field(decoded, 'mac');

      if (salt.length < 8 || nonce.isEmpty || cipherText.isEmpty || mac.isEmpty) {
        throw const KeyBackupFailure('Corrupted backup data.');
      }

      return _EncryptedBackupBlob(
        salt: Uint8List.fromList(salt),
        nonce: nonce,
        cipherText: cipherText,
        mac: mac,
      );
    } on KeyBackupFailure {
      rethrow;
    } catch (_) {
      throw const KeyBackupFailure('Corrupted backup data.');
    }
  }

  List<int> _decodeBase64Field(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is! String || value.isEmpty) {
      throw const KeyBackupFailure('Corrupted backup data.');
    }
    try {
      return base64.decode(value);
    } catch (_) {
      throw const KeyBackupFailure('Corrupted backup data.');
    }
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

class _EncryptedBackupBlob {
  const _EncryptedBackupBlob({
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final Uint8List salt;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;
}
