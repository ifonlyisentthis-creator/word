import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceSecretService {
  DeviceSecretService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _hmacKeyStorageKey = 'afterword_hmac_key';

  final FlutterSecureStorage _storage;

  Future<SecretKey> loadOrCreateHmacKey() async {
    final stored = await _storage.read(key: _hmacKeyStorageKey);
    if (stored != null && stored.isNotEmpty) {
      return SecretKey(base64.decode(stored));
    }

    final key = SecretKey.randomBytes(32);
    final bytes = await key.extractBytes();
    await _storage.write(key: _hmacKeyStorageKey, value: base64.encode(bytes));
    return key;
  }

  Future<void> clearHmacKey() async {
    await _storage.delete(key: _hmacKeyStorageKey);
  }
}
