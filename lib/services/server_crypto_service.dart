import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServerCryptoService {
  ServerCryptoService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<void> _refreshSession() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        await _client.auth.refreshSession();
        return;
      }
      final expiresAt = session.expiresAt;
      if (expiresAt == null) {
        await _client.auth.refreshSession();
        return;
      }
      final expiresTime =
          DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      if (expiresTime
          .isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
        await _client.auth.refreshSession();
      }
    } catch (_) {
      // Best-effort; the invoke call will surface any auth error.
    }
  }

  Map<String, String> get _authHeader {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  Future<FunctionResponse> _invoke(Map<String, dynamic> body) async {
    await _refreshSession();
    try {
      return await _client.functions.invoke(
        'metadata-crypto',
        body: body,
        headers: _authHeader,
      );
    } on FunctionException catch (error) {
      if (error.status == 401) {
        // Force-refresh and retry once with an explicit auth header.
        try {
          await _client.auth.refreshSession();
        } catch (_) {
          rethrow; // rethrow the original FunctionException
        }
        return _client.functions.invoke(
          'metadata-crypto',
          body: body,
          headers: _authHeader,
        );
      }
      rethrow;
    }
  }

  Future<String> encryptText(String plaintext) async {
    final response = await _invoke({
      'op': 'encrypt_text',
      'plaintext': plaintext,
    });

    final data = response.data;
    if (data is Map<String, dynamic> && data['ciphertext'] is String) {
      return data['ciphertext'] as String;
    }
    throw const ServerCryptoFailure('Unable to encrypt metadata.');
  }

  Future<String> decryptText(String ciphertext, {required String proofB64}) async {
    final response = await _invoke({
      'op': 'decrypt_text',
      'ciphertext': ciphertext,
      'proof_b64': proofB64,
    });

    final data = response.data;
    if (data is Map<String, dynamic> && data['plaintext'] is String) {
      return data['plaintext'] as String;
    }
    throw const ServerCryptoFailure('Unable to decrypt metadata.');
  }

  Future<String> encryptBytes(List<int> bytes) async {
    final response = await _invoke({
      'op': 'encrypt_bytes',
      'bytes_b64': base64.encode(bytes),
    });

    final data = response.data;
    if (data is Map<String, dynamic> && data['ciphertext'] is String) {
      return data['ciphertext'] as String;
    }
    throw const ServerCryptoFailure('Unable to encrypt metadata.');
  }

  Future<List<int>> decryptBytes(String ciphertext, {required String proofB64}) async {
    final response = await _invoke({
      'op': 'decrypt_bytes',
      'ciphertext': ciphertext,
      'proof_b64': proofB64,
    });

    final data = response.data;
    if (data is Map<String, dynamic> && data['bytes_b64'] is String) {
      return base64.decode(data['bytes_b64'] as String);
    }
    throw const ServerCryptoFailure('Unable to decrypt metadata.');
  }

  Future<String> encryptKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    return encryptBytes(bytes);
  }

  Future<SecretKey> decryptKey(String ciphertext, {required String proofB64}) async {
    final bytes = await decryptBytes(ciphertext, proofB64: proofB64);
    return SecretKey(bytes);
  }
}

class ServerCryptoFailure implements Exception {
  const ServerCryptoFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
