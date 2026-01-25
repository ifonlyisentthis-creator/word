import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  CryptoService({required this.serverSecret})
      : _cipher = AesGcm.with256bits(),
        _serverKey = SecretKey(
          sha256.convert(utf8.encode(serverSecret)).bytes,
        );

  final String serverSecret;
  final Cipher _cipher;
  final SecretKey _serverKey;

  Future<SecretKey> generateDataKey() => _cipher.newSecretKey();

  Future<SecretKey> generateHmacKey() => SecretKey.randomBytes(32);

  Future<String> encryptText(String plaintext, SecretKey key) async {
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return _encodeSecretBox(secretBox);
  }

  Future<String> encryptBytes(List<int> bytes, SecretKey key) async {
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      bytes,
      secretKey: key,
      nonce: nonce,
    );
    return _encodeSecretBox(secretBox);
  }

  Future<String> decryptText(String encoded, SecretKey key) async {
    final box = _decodeSecretBox(encoded);
    final clearBytes = await _cipher.decrypt(
      box,
      secretKey: key,
    );
    return utf8.decode(clearBytes);
  }

  Future<List<int>> decryptBytes(String encoded, SecretKey key) async {
    final box = _decodeSecretBox(encoded);
    return _cipher.decrypt(
      box,
      secretKey: key,
    );
  }

  Future<String> encryptWithServerSecret(String plaintext) {
    return encryptText(plaintext, _serverKey);
  }

  Future<String> decryptWithServerSecret(String encoded) {
    return decryptText(encoded, _serverKey);
  }

  Future<String> encryptKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      bytes,
      secretKey: _serverKey,
      nonce: nonce,
    );
    return _encodeSecretBox(secretBox);
  }

  Future<SecretKey> decryptKey(String encoded) async {
    final box = _decodeSecretBox(encoded);
    final clearBytes = await _cipher.decrypt(
      box,
      secretKey: _serverKey,
    );
    return SecretKey(clearBytes);
  }

  Future<String> computeHmac(String message, SecretKey key) async {
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode(message),
      secretKey: key,
    );
    return base64.encode(mac.bytes);
  }

  String _encodeSecretBox(SecretBox box) {
    final nonce = base64.encode(box.nonce);
    final cipherText = base64.encode(box.cipherText);
    final mac = base64.encode(box.mac.bytes);
    return '$nonce.$cipherText.$mac';
  }

  SecretBox _decodeSecretBox(String encoded) {
    final parts = encoded.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid encrypted payload.');
    }
    return SecretBox(
      base64.decode(parts[1]),
      nonce: base64.decode(parts[0]),
      mac: Mac(base64.decode(parts[2])),
    );
  }
}
