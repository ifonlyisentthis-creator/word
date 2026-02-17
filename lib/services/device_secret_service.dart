import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceSecretService {
  DeviceSecretService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Legacy single-slot keys (pre per-account migration)
  static const String _legacyHmacKey = 'afterword_hmac_key';
  static const String _legacyDeviceKey = 'afterword_device_wrap_v1';

  final FlutterSecureStorage _storage;

  String _hmacKeyFor(String userId) => 'afterword_hmac_key_$userId';
  String _deviceKeyFor(String userId) => 'afterword_device_wrap_v1_$userId';

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

  Future<void> clearHmacKey({required String userId}) async {
    await _storage.delete(key: _hmacKeyFor(userId));
  }

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

  Future<void> clearDeviceWrappingKey({required String userId}) async {
    await _storage.delete(key: _deviceKeyFor(userId));
  }
}
