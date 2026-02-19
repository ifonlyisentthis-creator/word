import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afterword/services/device_secret_service.dart';
import 'package:afterword/services/key_backup_service.dart';

void main() {
  group('normalizeRecoveryPhrase', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(
        normalizeRecoveryPhrase('  Abandon   ABANDON\nabout   '),
        'abandon abandon about',
      );
    });
  });

  group('KeyBackupService', () {
    const userId = 'user-1';
    const validMnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    test('hasServerBackup treats null/blank as missing', () async {
      final remote = FakeRemoteStore();
      final keyStore = FakeKeyMaterialStore();
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: keyStore,
      );

      expect(await service.hasServerBackup(userId), isFalse);

      remote.setBackup(userId, '    ');
      expect(await service.hasServerBackup(userId), isFalse);

      remote.setBackup(userId, '{"v":1}');
      expect(await service.hasServerBackup(userId), isTrue);
    });

    test('createBackup stores mnemonic and encrypted blob', () async {
      final hmac = List<int>.generate(32, (i) => 255 - i);
      final wrapping = List<int>.generate(32, (i) => i + 1);
      final remote = FakeRemoteStore();
      final keyStore = FakeKeyMaterialStore(
        initialHmac: {userId: hmac},
        initialDeviceWrapping: {userId: wrapping},
      );
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: keyStore,
      );

      final mnemonic = await service.createBackup(userId);

      expect(bip39.validateMnemonic(mnemonic), isTrue);
      expect(mnemonic, normalizeRecoveryPhrase(mnemonic));
      expect(await keyStore.readMnemonic(userId: userId), mnemonic);

      final backupStr = remote.backupFor(userId);
      expect(backupStr, isNotNull);

      final decoded = jsonDecode(backupStr!) as Map<String, dynamic>;
      expect(decoded['v'], 1);
      expect(decoded['salt'], isA<String>());
      expect(decoded['nonce'], isA<String>());
      expect(decoded['ct'], isA<String>());
      expect(decoded['mac'], isA<String>());
    });

    test('restoreBackup rejects invalid phrase', () async {
      final service = KeyBackupService(
        remoteStore: FakeRemoteStore(),
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, 'not a valid phrase'),
        _throwsKeyBackupFailure('Invalid recovery phrase.'),
      );
    });

    test('restoreBackup fails when server backup is missing', () async {
      final service = KeyBackupService(
        remoteStore: FakeRemoteStore(),
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, validMnemonic),
        _throwsKeyBackupFailure('No backup found for this account.'),
      );
    });

    test('restoreBackup fails on malformed backup json', () async {
      final remote = FakeRemoteStore(
        initial: {userId: 'not-json'},
      );
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, validMnemonic),
        _throwsKeyBackupFailure('Corrupted backup data.'),
      );
    });

    test('restoreBackup fails on unsupported backup version', () async {
      final remote = FakeRemoteStore(
        initial: {
          userId: jsonEncode({'v': 2}),
        },
      );
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, validMnemonic),
        _throwsKeyBackupFailure('Unsupported backup format.'),
      );
    });

    test('restoreBackup fails on corrupted base64 fields', () async {
      final remote = FakeRemoteStore(
        initial: {
          userId: jsonEncode({
            'v': 1,
            'salt': '%%%invalid%%%',
            'nonce': 'AQ==',
            'ct': 'AQ==',
            'mac': 'AQ==',
          }),
        },
      );
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, validMnemonic),
        _throwsKeyBackupFailure('Corrupted backup data.'),
      );
    });

    test('restoreBackup fails when decrypted payload length is invalid', () async {
      final backup = await buildBackupBlob(
        mnemonic: validMnemonic,
        payload: List<int>.filled(10, 7),
      );
      final remote = FakeRemoteStore(
        initial: {userId: backup},
      );
      final service = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        service.restoreBackup(userId, validMnemonic),
        _throwsKeyBackupFailure('Corrupted backup data.'),
      );
    });

    test('restoreBackup fails with incorrect phrase for existing backup', () async {
      final remote = FakeRemoteStore();
      final creatorStore = FakeKeyMaterialStore();
      final creator = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: creatorStore,
      );

      final phrase = await creator.createBackup(userId);
      final wrongPhrase = differentValidMnemonic(phrase);

      final restorer = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: FakeKeyMaterialStore(),
      );

      await expectLater(
        restorer.restoreBackup(userId, wrongPhrase),
        _throwsKeyBackupFailure('Incorrect recovery phrase.'),
      );
    });

    test('restoreBackup restores keys and stores normalized mnemonic', () async {
      final sourceHmac = List<int>.generate(32, (i) => i);
      final sourceWrapping = List<int>.generate(32, (i) => i + 32);

      final remote = FakeRemoteStore();
      final sourceStore = FakeKeyMaterialStore(
        initialHmac: {userId: sourceHmac},
        initialDeviceWrapping: {userId: sourceWrapping},
      );
      final creator = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: sourceStore,
      );

      final phrase = await creator.createBackup(userId);

      final targetStore = FakeKeyMaterialStore(
        initialHmac: {userId: List<int>.filled(32, 9)},
        initialDeviceWrapping: {userId: List<int>.filled(32, 4)},
      );
      final restorer = KeyBackupService(
        remoteStore: remote,
        deviceSecretService: targetStore,
      );

      final noisyInput = '  ${phrase.toUpperCase().split(' ').join('   \n')}  ';
      await restorer.restoreBackup(userId, noisyInput);

      expect(targetStore.hmacBytesFor(userId), sourceHmac);
      expect(targetStore.deviceWrappingBytesFor(userId), sourceWrapping);
      expect(
        await targetStore.readMnemonic(userId: userId),
        normalizeRecoveryPhrase(noisyInput),
      );
    });
  });
}

Matcher _throwsKeyBackupFailure(String message) {
  return throwsA(
    isA<KeyBackupFailure>().having((error) => error.message, 'message', message),
  );
}

String differentValidMnemonic(String avoid) {
  var candidate = normalizeRecoveryPhrase(
    'legal winner thank year wave sausage worth useful legal winner thank yellow',
  );

  while (candidate == normalizeRecoveryPhrase(avoid)) {
    candidate = normalizeRecoveryPhrase(bip39.generateMnemonic());
  }

  return candidate;
}

Future<String> buildBackupBlob({
  required String mnemonic,
  required List<int> payload,
}) async {
  final normalized = normalizeRecoveryPhrase(mnemonic);
  final salt = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(normalized)),
    nonce: salt,
  );

  final cipher = AesGcm.with256bits();
  final encrypted = await cipher.encrypt(payload, secretKey: key);

  return jsonEncode({
    'v': 1,
    'salt': base64.encode(salt),
    'nonce': base64.encode(encrypted.nonce),
    'ct': base64.encode(encrypted.cipherText),
    'mac': base64.encode(encrypted.mac.bytes),
  });
}

class FakeRemoteStore implements KeyBackupRemoteStore {
  FakeRemoteStore({Map<String, String?>? initial}) : _backups = {...?initial};

  final Map<String, String?> _backups;

  @override
  Future<String?> fetchEncryptedBackup(String userId) async {
    return _backups[userId];
  }

  @override
  Future<void> saveEncryptedBackup(String userId, String encryptedBackup) async {
    _backups[userId] = encryptedBackup;
  }

  void setBackup(String userId, String? value) {
    _backups[userId] = value;
  }

  String? backupFor(String userId) => _backups[userId];
}

class FakeKeyMaterialStore implements KeyMaterialStore {
  FakeKeyMaterialStore({
    Map<String, List<int>>? initialHmac,
    Map<String, List<int>>? initialDeviceWrapping,
    Map<String, String>? initialMnemonic,
  })  : _hmac = {
          for (final entry in (initialHmac ?? {}).entries)
            entry.key: List<int>.from(entry.value),
        },
        _deviceWrapping = {
          for (final entry in (initialDeviceWrapping ?? {}).entries)
            entry.key: List<int>.from(entry.value),
        },
        _mnemonics = {...?initialMnemonic};

  final Map<String, List<int>> _hmac;
  final Map<String, List<int>> _deviceWrapping;
  final Map<String, String> _mnemonics;

  @override
  Future<SecretKey> loadOrCreateHmacKey({required String userId}) async {
    final bytes = _hmac.putIfAbsent(
      userId,
      () => List<int>.generate(32, (i) => i),
    );
    return SecretKey(List<int>.from(bytes));
  }

  @override
  Future<void> storeHmacKey({
    required String userId,
    required List<int> bytes,
  }) async {
    _hmac[userId] = List<int>.from(bytes);
  }

  @override
  Future<SecretKey> loadOrCreateDeviceWrappingKey({required String userId}) async {
    final bytes = _deviceWrapping.putIfAbsent(
      userId,
      () => List<int>.generate(32, (i) => i + 32),
    );
    return SecretKey(List<int>.from(bytes));
  }

  @override
  Future<void> storeDeviceWrappingKey({
    required String userId,
    required List<int> bytes,
  }) async {
    _deviceWrapping[userId] = List<int>.from(bytes);
  }

  @override
  Future<String?> readMnemonic({required String userId}) async {
    return _mnemonics[userId];
  }

  @override
  Future<void> storeMnemonic({
    required String userId,
    required String mnemonic,
  }) async {
    _mnemonics[userId] = mnemonic;
  }

  List<int> hmacBytesFor(String userId) {
    return List<int>.from(_hmac[userId] ?? const <int>[]);
  }

  List<int> deviceWrappingBytesFor(String userId) {
    return List<int>.from(_deviceWrapping[userId] ?? const <int>[]);
  }
}
