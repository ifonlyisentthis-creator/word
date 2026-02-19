import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyMaterialStore {
  Future<SecretKey> loadOrCreateHmacKey({required String userId});
  Future<void> storeHmacKey({required String userId, required List<int> bytes});

  Future<SecretKey> loadOrCreateDeviceWrappingKey({required String userId});
  Future<void> storeDeviceWrappingKey({required String userId, required List<int> bytes});

  Future<String?> readMnemonic({required String userId});
  Future<void> storeMnemonic({required String userId, required String mnemonic});
}

class DeviceSecretService implements KeyMaterialStore {
  DeviceSecretService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Legacy single-slot keys (pre per-account migration)
  static const String _legacyHmacKey = 'afterword_hmac_key';
  static const String _legacyDeviceKey = 'afterword_device_wrap_v1';

  final FlutterSecureStorage _storage;

  String _hmacKeyFor(String userId) => 'afterword_hmac_key_$userId';
  String _deviceKeyFor(String userId) => 'afterword_device_wrap_v1_$userId';

  @override
  Future<SecretKey> loadOrCreateHmacKey({required String userId}) async {
    final perAccountKey = _hmacKeyFor(userId);

    // 1. Per-account key (preferred)
    final stored = await _storage.read(key: perAccountKey);
    if (stored != null && stored.isNotEmpty) {
      return SecretKey(base64.decode(stored));
    }

    // 2. Migrate from legacy single-slot key if it exists
    final legacy = await _storage.read(key: _legacyHmacKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _storage.write(key: perAccountKey, value: legacy);
      return SecretKey(base64.decode(legacy));
    }

    // 3. Generate new key
    final key = SecretKeyData.random(length: 32);
    final bytes = await key.extractBytes();
    await _storage.write(key: perAccountKey, value: base64.encode(bytes));
    return key;
  }

  @override
  Future<void> storeHmacKey({required String userId, required List<int> bytes}) async {
    await _storage.write(key: _hmacKeyFor(userId), value: base64.encode(bytes));
  }

  Future<void> clearHmacKey({required String userId}) async {
    await _storage.delete(key: _hmacKeyFor(userId));
  }

  @override
  Future<SecretKey> loadOrCreateDeviceWrappingKey({required String userId}) async {
    final perAccountKey = _deviceKeyFor(userId);

    final stored = await _storage.read(key: perAccountKey);
    if (stored != null && stored.isNotEmpty) {
      return SecretKey(base64.decode(stored));
    }

    final legacy = await _storage.read(key: _legacyDeviceKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _storage.write(key: perAccountKey, value: legacy);
      return SecretKey(base64.decode(legacy));
    }

    final key = SecretKeyData.random(length: 32);
    final bytes = await key.extractBytes();
    await _storage.write(key: perAccountKey, value: base64.encode(bytes));
    return key;
  }

  @override
  Future<void> storeDeviceWrappingKey({required String userId, required List<int> bytes}) async {
    await _storage.write(key: _deviceKeyFor(userId), value: base64.encode(bytes));
  }

  Future<void> clearDeviceWrappingKey({required String userId}) async {
    await _storage.delete(key: _deviceKeyFor(userId));
  }

  static const String _mnemonicPrefix = 'afterword_recovery_phrase';
  String _mnemonicKeyFor(String userId) => '${_mnemonicPrefix}_$userId';

  @override
  Future<String?> readMnemonic({required String userId}) async {
    return _storage.read(key: _mnemonicKeyFor(userId));
  }

  @override
  Future<void> storeMnemonic({required String userId, required String mnemonic}) async {
    await _storage.write(key: _mnemonicKeyFor(userId), value: mnemonic);
  }

  Future<void> clearMnemonic({required String userId}) async {
    await _storage.delete(key: _mnemonicKeyFor(userId));
  }
}
