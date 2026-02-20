import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterword/services/crypto_service.dart';

/// Comprehensive security tests for the Afterword encryption pipeline.
///
/// These tests verify:
/// 1. AES-256-GCM encrypt/decrypt roundtrips (text and bytes)
/// 2. Key wrapping (data key encrypted with device wrapping key)
/// 3. HMAC integrity seals (tamper detection)
/// 4. Tampered ciphertext, nonce, and MAC all fail decryption
/// 5. Wrong key fails decryption
/// 6. SecretBox format consistency (nonce.ciphertext.mac)
/// 7. Each encryption produces unique ciphertext (random nonce)
/// 8. Empty and large plaintext handling
void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('AES-256-GCM text encryption', () {
    test('encrypt then decrypt roundtrip', () async {
      final key = await crypto.generateDataKey();
      const plaintext = 'Hello, beneficiary! This is my vault message.';

      final encrypted = await crypto.encryptText(plaintext, key);
      final decrypted = await crypto.decryptText(encrypted, key);

      expect(decrypted, plaintext);
    });

    test('empty string roundtrip', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('', key);
      final decrypted = await crypto.decryptText(encrypted, key);
      expect(decrypted, '');
    });

    test('unicode and emoji roundtrip', () async {
      final key = await crypto.generateDataKey();
      const plaintext = 'こんにちは世界 🔐🛡️ Ñoño';

      final encrypted = await crypto.encryptText(plaintext, key);
      final decrypted = await crypto.decryptText(encrypted, key);

      expect(decrypted, plaintext);
    });

    test('large plaintext (50KB) roundtrip', () async {
      final key = await crypto.generateDataKey();
      final plaintext = 'A' * 50000;

      final encrypted = await crypto.encryptText(plaintext, key);
      final decrypted = await crypto.decryptText(encrypted, key);

      expect(decrypted, plaintext);
    });

    test('each encryption produces unique ciphertext (random nonce)', () async {
      final key = await crypto.generateDataKey();
      const plaintext = 'Same message encrypted twice';

      final encrypted1 = await crypto.encryptText(plaintext, key);
      final encrypted2 = await crypto.encryptText(plaintext, key);

      // Both decrypt to the same plaintext
      expect(await crypto.decryptText(encrypted1, key), plaintext);
      expect(await crypto.decryptText(encrypted2, key), plaintext);

      // But ciphertext is different (unique nonce)
      expect(encrypted1, isNot(encrypted2));
    });

    test('SecretBox format is nonce.ciphertext.mac (3 dot-separated parts)', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('test', key);

      final parts = encrypted.split('.');
      expect(parts.length, 3, reason: 'Expected nonce.ciphertext.mac format');

      // Each part is valid base64
      for (final part in parts) {
        expect(() => base64.decode(part), returnsNormally);
      }

      // Nonce should be 12 bytes (96 bits for AES-GCM)
      expect(base64.decode(parts[0]).length, 12);

      // MAC should be 16 bytes (128 bits for AES-GCM)
      expect(base64.decode(parts[2]).length, 16);
    });
  });

  group('AES-256-GCM bytes encryption', () {
    test('encrypt then decrypt bytes roundtrip', () async {
      final key = await crypto.generateDataKey();
      final bytes = List.generate(256, (i) => i % 256);

      final encrypted = await crypto.encryptBytes(bytes, key);
      final decrypted = await crypto.decryptBytes(encrypted, key);

      expect(decrypted, bytes);
    });

    test('audio-sized payload (1MB) roundtrip', () async {
      final key = await crypto.generateDataKey();
      final bytes = List.generate(1024 * 1024, (i) => i % 256);

      final encrypted = await crypto.encryptBytes(bytes, key);
      final decrypted = await crypto.decryptBytes(encrypted, key);

      expect(decrypted.length, bytes.length);
      expect(decrypted, bytes);
    });
  });

  group('Key wrapping', () {
    test('data key wrapped and unwrapped with device wrapping key', () async {
      final dataKey = await crypto.generateDataKey();
      final wrappingKey = await crypto.generateDataKey();

      final wrapped = await crypto.encryptKey(dataKey, wrappingKey);
      final unwrapped = await crypto.decryptKey(wrapped, wrappingKey);

      final originalBytes = await dataKey.extractBytes();
      final recoveredBytes = await unwrapped.extractBytes();

      expect(recoveredBytes, originalBytes);
    });

    test('wrong wrapping key fails to unwrap', () async {
      final dataKey = await crypto.generateDataKey();
      final wrappingKey1 = await crypto.generateDataKey();
      final wrappingKey2 = await crypto.generateDataKey();

      final wrapped = await crypto.encryptKey(dataKey, wrappingKey1);

      expect(
        () => crypto.decryptKey(wrapped, wrappingKey2),
        throwsA(anything),
        reason: 'Wrong wrapping key must fail decryption',
      );
    });

    test('each wrap produces unique ciphertext', () async {
      final dataKey = await crypto.generateDataKey();
      final wrappingKey = await crypto.generateDataKey();

      final wrapped1 = await crypto.encryptKey(dataKey, wrappingKey);
      final wrapped2 = await crypto.encryptKey(dataKey, wrappingKey);

      expect(wrapped1, isNot(wrapped2));
    });
  });

  group('Tamper detection (AES-GCM authentication)', () {
    test('tampered ciphertext fails decryption', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('Secret message', key);

      final parts = encrypted.split('.');
      // Flip a byte in the ciphertext
      final ctBytes = base64.decode(parts[1]);
      ctBytes[0] ^= 0xFF;
      final tampered = '${parts[0]}.${base64.encode(ctBytes)}.${parts[2]}';

      expect(
        () => crypto.decryptText(tampered, key),
        throwsA(anything),
        reason: 'Tampered ciphertext must fail authentication',
      );
    });

    test('tampered MAC fails decryption', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('Secret message', key);

      final parts = encrypted.split('.');
      // Flip a byte in the MAC
      final macBytes = base64.decode(parts[2]);
      macBytes[0] ^= 0xFF;
      final tampered = '${parts[0]}.${parts[1]}.${base64.encode(macBytes)}';

      expect(
        () => crypto.decryptText(tampered, key),
        throwsA(anything),
        reason: 'Tampered MAC must fail authentication',
      );
    });

    test('tampered nonce fails decryption', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('Secret message', key);

      final parts = encrypted.split('.');
      // Flip a byte in the nonce
      final nonceBytes = base64.decode(parts[0]);
      nonceBytes[0] ^= 0xFF;
      final tampered = '${base64.encode(nonceBytes)}.${parts[1]}.${parts[2]}';

      expect(
        () => crypto.decryptText(tampered, key),
        throwsA(anything),
        reason: 'Tampered nonce must fail authentication',
      );
    });

    test('wrong key fails decryption', () async {
      final key1 = await crypto.generateDataKey();
      final key2 = await crypto.generateDataKey();

      final encrypted = await crypto.encryptText('Secret message', key1);

      expect(
        () => crypto.decryptText(encrypted, key2),
        throwsA(anything),
        reason: 'Wrong key must fail decryption',
      );
    });

    test('truncated payload fails', () async {
      final key = await crypto.generateDataKey();
      final encrypted = await crypto.encryptText('Secret', key);

      // Only two parts instead of three
      final parts = encrypted.split('.');
      final truncated = '${parts[0]}.${parts[1]}';

      expect(
        () => crypto.decryptText(truncated, key),
        throwsA(isA<FormatException>()),
        reason: 'Truncated payload must throw FormatException',
      );
    });

    test('empty string payload fails', () async {
      final key = await crypto.generateDataKey();
      expect(
        () => crypto.decryptText('', key),
        throwsA(isA<FormatException>()),
      );
    });

    test('garbage input fails', () async {
      final key = await crypto.generateDataKey();
      expect(
        () => crypto.decryptText('not.valid.base64!!!', key),
        throwsA(anything),
      );
    });
  });

  group('HMAC integrity seals', () {
    test('HMAC is deterministic for same message and key', () async {
      final key = await crypto.generateHmacKey();
      const message = 'payload_encrypted|recipient_encrypted';

      final sig1 = await crypto.computeHmac(message, key);
      final sig2 = await crypto.computeHmac(message, key);

      expect(sig1, sig2);
    });

    test('HMAC changes with different message', () async {
      final key = await crypto.generateHmacKey();

      final sig1 = await crypto.computeHmac('message1', key);
      final sig2 = await crypto.computeHmac('message2', key);

      expect(sig1, isNot(sig2));
    });

    test('HMAC changes with different key', () async {
      final key1 = await crypto.generateHmacKey();
      final key2 = await crypto.generateHmacKey();
      const message = 'same message';

      final sig1 = await crypto.computeHmac(message, key1);
      final sig2 = await crypto.computeHmac(message, key2);

      expect(sig1, isNot(sig2));
    });

    test('HMAC output is valid base64', () async {
      final key = await crypto.generateHmacKey();
      final sig = await crypto.computeHmac('test', key);

      expect(() => base64.decode(sig), returnsNormally);

      // HMAC-SHA256 produces 32 bytes
      expect(base64.decode(sig).length, 32);
    });

    test('tamper detection: modified payload changes HMAC', () async {
      final key = await crypto.generateHmacKey();
      const payload = 'encrypted_payload_data';
      const recipient = 'encrypted_recipient';

      final original = await crypto.computeHmac('$payload|$recipient', key);
      final tampered = await crypto.computeHmac('$payload|modified_recipient', key);

      expect(original, isNot(tampered),
          reason: 'Heartbeat would reject this entry due to HMAC mismatch');
    });

    test('empty recipient in signature message', () async {
      final key = await crypto.generateHmacKey();

      // This matches the _buildSignatureMessage format when recipient is null
      final sig = await crypto.computeHmac('encrypted_payload|', key);
      expect(sig, isNotEmpty);
    });
  });

  group('Key generation', () {
    test('data keys are 256 bits (32 bytes)', () async {
      final key = await crypto.generateDataKey();
      final bytes = await key.extractBytes();
      expect(bytes.length, 32);
    });

    test('HMAC keys are 256 bits (32 bytes)', () async {
      final key = await crypto.generateHmacKey();
      final bytes = await key.extractBytes();
      expect(bytes.length, 32);
    });

    test('generated keys are unique', () async {
      final key1 = await crypto.generateDataKey();
      final key2 = await crypto.generateDataKey();

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, isNot(bytes2));
    });
  });

  group('Dual envelope metadata encryption (structural)', () {
    // These verify the JSON envelope format used by VaultService for
    // metadata encryption (recipient email, data key).
    // The actual server-side encryption is mocked, but the structure
    // must be consistent.

    test('envelope JSON format has v, server, device fields', () {
      // Mirrors _encryptMetadataText in vault_service.dart
      final envelope = jsonEncode({
        'v': 1,
        'server': 'server_ciphertext_here',
        'device': 'device_ciphertext_here',
      });

      final decoded = jsonDecode(envelope) as Map<String, dynamic>;
      expect(decoded['v'], 1);
      expect(decoded['server'], isA<String>());
      expect(decoded['device'], isA<String>());
    });

    test('extract_server_ciphertext from envelope', () {
      // Mirrors extract_server_ciphertext in heartbeat.py
      final envelope = jsonEncode({
        'v': 1,
        'server': 'the_server_cipher',
        'device': 'the_device_cipher',
      });

      final decoded = jsonDecode(envelope) as Map<String, dynamic>;
      final serverCipher = decoded['server'] as String;
      expect(serverCipher, 'the_server_cipher');
    });

    test('legacy non-envelope format returns raw value', () {
      // Mirrors heartbeat.py extract_server_ciphertext fallback
      const legacy = 'raw_ciphertext_no_json';

      Map<String, dynamic>? tryDecodeEnvelope(String value) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map<String, dynamic>) return decoded;
        } catch (_) {
          return null;
        }
        return null;
      }

      final envelope = tryDecodeEnvelope(legacy);
      expect(envelope, isNull);
      // Fallback: use raw value directly
      expect(legacy, 'raw_ciphertext_no_json');
    });
  });

  group('Profile timer calculations', () {
    test('deadline = lastCheckIn + timerDays', () {
      final lastCheckIn = DateTime(2026, 2, 1, 12, 0);
      const timerDays = 30;
      final deadline = lastCheckIn.add(Duration(days: timerDays));

      expect(deadline, DateTime(2026, 3, 3, 12, 0));
    });

    test('timeRemaining is positive when before deadline', () {
      final lastCheckIn = DateTime(2026, 2, 1, 12, 0);
      const timerDays = 30;
      final deadline = lastCheckIn.add(Duration(days: timerDays));
      final now = DateTime(2026, 2, 15, 12, 0);

      final remaining = deadline.difference(now);
      expect(remaining.isNegative, false);
      expect(remaining.inDays, 16);
    });

    test('timeRemaining is negative when past deadline', () {
      final lastCheckIn = DateTime(2026, 1, 1, 12, 0);
      const timerDays = 30;
      final deadline = lastCheckIn.add(Duration(days: timerDays));
      final now = DateTime(2026, 2, 15, 12, 0);

      final remaining = deadline.difference(now);
      expect(remaining.isNegative, true);
    });

    test('progress fraction decreases over time', () {
      final lastCheckIn = DateTime(2026, 2, 1, 0, 0);
      const timerDays = 30;
      final totalSeconds = timerDays * 86400;
      final deadline = lastCheckIn.add(Duration(days: timerDays));

      // At 50% of timer
      final halfwayNow = lastCheckIn.add(const Duration(days: 15));
      final halfRemaining = deadline.difference(halfwayNow).inSeconds;
      final halfFraction = halfRemaining / totalSeconds;
      expect(halfFraction, closeTo(0.5, 0.01));

      // At 90% elapsed
      final lateNow = lastCheckIn.add(const Duration(days: 27));
      final lateRemaining = deadline.difference(lateNow).inSeconds;
      final lateFraction = lateRemaining / totalSeconds;
      expect(lateFraction, closeTo(0.1, 0.01));
    });

    test('timer reset to 100% after successful check-in', () {
      const timerDays = 30;
      final totalSeconds = timerDays * 86400;

      // Simulate: user checks in at now
      final newLastCheckIn = DateTime(2026, 2, 21, 12, 0);
      final newDeadline = newLastCheckIn.add(Duration(days: timerDays));
      final remaining = newDeadline.difference(newLastCheckIn).inSeconds;
      final fraction = remaining / totalSeconds;

      expect(fraction, closeTo(1.0, 0.001));
    });
  });
}
