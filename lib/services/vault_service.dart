import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_entry.dart';
import 'crypto_service.dart';
import 'device_secret_service.dart';
import 'server_crypto_service.dart';

class VaultService {
  VaultService({
    required SupabaseClient client,
    required CryptoService cryptoService,
    required ServerCryptoService serverCryptoService,
    required DeviceSecretService deviceSecretService,
    Uuid? uuid,
  })  : _client = client,
        _cryptoService = cryptoService,
        _serverCryptoService = serverCryptoService,
        _deviceSecretService = deviceSecretService,
        _uuid = uuid ?? const Uuid();

  static const String _audioBucket = 'vault-audio';

  final SupabaseClient _client;
  final CryptoService _cryptoService;
  final ServerCryptoService _serverCryptoService;
  final DeviceSecretService _deviceSecretService;
  final Uuid _uuid;

  /// Refresh the Supabase session if the JWT is expired or about to expire.
  Future<void> _refreshSession() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        await _client.auth.refreshSession();
        return;
      }
      // Refresh if token expired or within 5 minutes of expiry.
      final expiresAt = session.expiresAt;
      if (expiresAt == null) {
        await _client.auth.refreshSession();
        return;
      }
      final expiresTime =
          DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      if (expiresTime.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
        await _client.auth.refreshSession();
      }
    } catch (_) {
      // Best-effort; if refresh fails the operation will fail with 401
      // and the caller will show the error.
    }
  }

  Future<List<VaultEntry>> fetchEntries(String userId) async {
    await _refreshSession();
    final response = await _client
        .from('vault_entries')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return response
        .map<VaultEntry>((entry) => VaultEntry.fromMap(entry))
        .toList();
  }

  Future<VaultEntryPayload> decryptEntry(VaultEntry entry) async {
    final hmacKey = await _deviceSecretService.loadOrCreateHmacKey();
    final deviceWrappingKey =
        await _deviceSecretService.loadOrCreateDeviceWrappingKey();

    final dataKey = await _decryptMetadataKey(
      entry.dataKeyEncrypted,
      hmacKey: hmacKey,
      deviceWrappingKey: deviceWrappingKey,
    );
    final plaintext =
        await _cryptoService.decryptText(entry.payloadEncrypted, dataKey);
    final recipient = entry.recipientEncrypted == null
        ? null
        : await _decryptMetadataText(
            entry.recipientEncrypted!,
            hmacKey: hmacKey,
            deviceWrappingKey: deviceWrappingKey,
          );
    return VaultEntryPayload(
      plaintext: plaintext,
      recipientEmail: recipient,
      audioFilePath: entry.audioFilePath,
      audioDurationSeconds: entry.audioDurationSeconds,
    );
  }

  Future<VaultEntry> createEntry(String userId, VaultEntryDraft draft) async {
    await _refreshSession();
    final normalizedTitle = draft.title.trim().isEmpty
        ? 'Untitled'
        : draft.title.trim();
    final recipient = _normalizeRecipient(draft);
    if (draft.actionType == VaultActionType.send && recipient == null) {
      throw const VaultFailure('Recipient email is required.');
    }

    final isAudio = draft.dataType == VaultDataType.audio;
    final entryId = _uuid.v4();
    final audioFilePath =
        isAudio ? _buildAudioPath(userId: userId, entryId: entryId) : null;
    final audioDurationSeconds =
        isAudio ? draft.audioDurationSeconds : null;
    if (isAudio && (draft.audioFilePath == null || audioDurationSeconds == null)) {
      throw const VaultFailure('Record audio before saving.');
    }

    final dataKey = await _cryptoService.generateDataKey();
    final payloadEncrypted =
        await _cryptoService.encryptText(draft.plaintext.trim(), dataKey);
    final hmacKey = await _deviceSecretService.loadOrCreateHmacKey();
    final deviceWrappingKey =
        await _deviceSecretService.loadOrCreateDeviceWrappingKey();

    final recipientEncrypted = recipient == null
        ? null
        : await _encryptMetadataText(recipient, deviceWrappingKey);
    final dataKeyEncrypted =
        await _encryptMetadataKey(dataKey, deviceWrappingKey);

    if (isAudio && draft.audioFilePath != null && audioFilePath != null) {
      await _uploadEncryptedAudio(
        sourceFilePath: draft.audioFilePath!,
        storagePath: audioFilePath,
        dataKey: dataKey,
      );
    }

    await _ensureProfileHmacKey(userId, hmacKey);
    final signatureMessage =
        _buildSignatureMessage(payloadEncrypted, recipientEncrypted);
    final hmacSignature =
        await _cryptoService.computeHmac(signatureMessage, hmacKey);

    final inserted = await _client.from('vault_entries').insert({
      'id': entryId,
      'user_id': userId,
      'title': normalizedTitle,
      'action_type': draft.actionType.value,
      'data_type': draft.dataType.value,
      'status': VaultStatus.active.value,
      'payload_encrypted': payloadEncrypted,
      'recipient_email_encrypted': recipientEncrypted,
      'data_key_encrypted': dataKeyEncrypted,
      'hmac_signature': hmacSignature,
      'audio_file_path': audioFilePath,
      'audio_duration_seconds': audioDurationSeconds,
    }).select().single();

    return VaultEntry.fromMap(inserted);
  }

  Future<VaultEntry> updateEntry(VaultEntry entry, VaultEntryDraft draft) async {
    await _refreshSession();
    final normalizedTitle = draft.title.trim().isEmpty
        ? 'Untitled'
        : draft.title.trim();
    final recipient = _normalizeRecipient(draft);
    if (draft.actionType == VaultActionType.send && recipient == null) {
      throw const VaultFailure('Recipient email is required.');
    }

    final isAudio = draft.dataType == VaultDataType.audio;
    final wasAudio = entry.dataType == VaultDataType.audio;
    final hasNewAudio = draft.audioFilePath != null;
    String? audioFilePath = entry.audioFilePath;
    int? audioDurationSeconds = entry.audioDurationSeconds;

    final hmacKey = await _deviceSecretService.loadOrCreateHmacKey();
    final deviceWrappingKey =
        await _deviceSecretService.loadOrCreateDeviceWrappingKey();

    final SecretKey dataKey;
    final String dataKeyEncrypted;
    if (isAudio) {
      if (hasNewAudio) {
        dataKey = await _cryptoService.generateDataKey();
        dataKeyEncrypted =
            await _encryptMetadataKey(dataKey, deviceWrappingKey);
        audioFilePath ??= _buildAudioPath(userId: entry.userId, entryId: entry.id);
        audioDurationSeconds = draft.audioDurationSeconds;
        if (audioDurationSeconds == null) {
          throw const VaultFailure('Record audio before saving.');
        }
        await _uploadEncryptedAudio(
          sourceFilePath: draft.audioFilePath!,
          storagePath: audioFilePath,
          dataKey: dataKey,
        );
      } else {
        if (audioFilePath == null || audioDurationSeconds == null) {
          throw const VaultFailure('Record audio before saving.');
        }
        dataKey = await _decryptMetadataKey(
          entry.dataKeyEncrypted,
          hmacKey: hmacKey,
          deviceWrappingKey: deviceWrappingKey,
        );
        dataKeyEncrypted = entry.dataKeyEncrypted;
      }
    } else {
      dataKey = await _cryptoService.generateDataKey();
      dataKeyEncrypted = await _encryptMetadataKey(dataKey, deviceWrappingKey);
      if (wasAudio && audioFilePath != null) {
        await _deleteAudioFile(audioFilePath);
      }
      audioFilePath = null;
      audioDurationSeconds = null;
    }

    final payloadEncrypted =
        await _cryptoService.encryptText(draft.plaintext.trim(), dataKey);
    final recipientEncrypted = recipient == null
        ? null
        : await _encryptMetadataText(recipient, deviceWrappingKey);

    await _ensureProfileHmacKey(entry.userId, hmacKey);
    final signatureMessage =
        _buildSignatureMessage(payloadEncrypted, recipientEncrypted);
    final hmacSignature =
        await _cryptoService.computeHmac(signatureMessage, hmacKey);

    final updated = await _client
        .from('vault_entries')
        .update({
          'title': normalizedTitle,
          'action_type': draft.actionType.value,
          'data_type': draft.dataType.value,
          'payload_encrypted': payloadEncrypted,
          'recipient_email_encrypted': recipientEncrypted,
          'data_key_encrypted': dataKeyEncrypted,
          'hmac_signature': hmacSignature,
          'audio_file_path': audioFilePath,
          'audio_duration_seconds': audioDurationSeconds,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', entry.id)
        .select()
        .single();

    return VaultEntry.fromMap(updated);
  }

  Future<void> deleteEntry(VaultEntry entry) async {
    await _refreshSession();
    if (entry.dataType == VaultDataType.audio && entry.audioFilePath != null) {
      await _deleteAudioFile(entry.audioFilePath!);
    }
    await _client.from('vault_entries').delete().eq('id', entry.id);
  }

  Future<void> deleteAllEntries(String userId) async {
    await _refreshSession();
    final entries = await fetchEntries(userId);
    final audioPaths = entries
        .where((entry) => entry.dataType == VaultDataType.audio)
        .map((entry) => entry.audioFilePath)
        .whereType<String>()
        .toList();
    if (audioPaths.isNotEmpty) {
      await _client.storage.from(_audioBucket).remove(audioPaths);
    }
    await _client.from('vault_entries').delete().eq('user_id', userId);
  }

  Future<String> downloadAudio(VaultEntry entry) async {
    await _refreshSession();
    final audioPath = entry.audioFilePath;
    if (audioPath == null) {
      throw const VaultFailure('Audio file missing.');
    }
    final encryptedBytes =
        await _client.storage.from(_audioBucket).download(audioPath);
    final encryptedPayload = utf8.decode(encryptedBytes);
    final hmacKey = await _deviceSecretService.loadOrCreateHmacKey();
    final deviceWrappingKey =
        await _deviceSecretService.loadOrCreateDeviceWrappingKey();
    final dataKey = await _decryptMetadataKey(
      entry.dataKeyEncrypted,
      hmacKey: hmacKey,
      deviceWrappingKey: deviceWrappingKey,
    );
    final audioBytes = await _cryptoService.decryptBytes(
      encryptedPayload,
      dataKey,
    );
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${entry.id}.m4a');
    await file.writeAsBytes(audioBytes, flush: true);
    return file.path;
  }

  Future<void> _ensureProfileHmacKey(
    String userId,
    SecretKey hmacKey,
  ) async {
    final response = await _client
        .from('profiles')
        .select('hmac_key_encrypted')
        .eq('id', userId)
        .maybeSingle();
    if (response == null || response['hmac_key_encrypted'] != null) {
      return;
    }
    final encrypted = await _serverCryptoService.encryptKey(hmacKey);
    await _client
        .from('profiles')
        .update({'hmac_key_encrypted': encrypted})
        .eq('id', userId);
  }

  Future<String> _encryptMetadataText(
    String plaintext,
    SecretKey deviceWrappingKey,
  ) async {
    final serverCipher = await _serverCryptoService.encryptText(plaintext);
    final deviceCipher =
        await _cryptoService.encryptText(plaintext, deviceWrappingKey);
    return jsonEncode({
      'v': 1,
      'server': serverCipher,
      'device': deviceCipher,
    });
  }

  Future<String> _decryptMetadataText(
    String encrypted,
    {
    required SecretKey hmacKey,
    required SecretKey deviceWrappingKey,
  }) async {
    final envelope = _tryDecodeEnvelope(encrypted);
    if (envelope != null) {
      final deviceCipher = envelope['device'];
      if (deviceCipher is String && deviceCipher.isNotEmpty) {
        return _cryptoService.decryptText(deviceCipher, deviceWrappingKey);
      }

      final serverCipher = envelope['server'];
      if (serverCipher is String && serverCipher.isNotEmpty) {
        final proof = await _cryptoService.computeHmac(serverCipher, hmacKey);
        return _serverCryptoService.decryptText(serverCipher, proofB64: proof);
      }
    }

    final proof = await _cryptoService.computeHmac(encrypted, hmacKey);
    return _serverCryptoService.decryptText(encrypted, proofB64: proof);
  }

  Future<String> _encryptMetadataKey(
    SecretKey key,
    SecretKey deviceWrappingKey,
  ) async {
    final bytes = await key.extractBytes();
    final serverCipher = await _serverCryptoService.encryptBytes(bytes);
    final deviceCipher = await _cryptoService.encryptBytes(bytes, deviceWrappingKey);
    return jsonEncode({
      'v': 1,
      'server': serverCipher,
      'device': deviceCipher,
    });
  }

  Future<SecretKey> _decryptMetadataKey(
    String encrypted,
    {
    required SecretKey hmacKey,
    required SecretKey deviceWrappingKey,
  }) async {
    final envelope = _tryDecodeEnvelope(encrypted);
    if (envelope != null) {
      final deviceCipher = envelope['device'];
      if (deviceCipher is String && deviceCipher.isNotEmpty) {
        return _cryptoService.decryptKey(deviceCipher, deviceWrappingKey);
      }
      final serverCipher = envelope['server'];
      if (serverCipher is String && serverCipher.isNotEmpty) {
        final proof = await _cryptoService.computeHmac(serverCipher, hmacKey);
        final bytes =
            await _serverCryptoService.decryptBytes(serverCipher, proofB64: proof);
        return SecretKey(bytes);
      }
    }

    final proof = await _cryptoService.computeHmac(encrypted, hmacKey);
    final bytes =
        await _serverCryptoService.decryptBytes(encrypted, proofB64: proof);
    return SecretKey(bytes);
  }

  Map<String, dynamic>? _tryDecodeEnvelope(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _buildSignatureMessage(
    String payloadEncrypted,
    String? recipientEncrypted,
  ) {
    return '$payloadEncrypted|${recipientEncrypted ?? ''}';
  }

  String _buildAudioPath({required String userId, required String entryId}) {
    return '$userId/$entryId.enc';
  }

  Future<void> _uploadEncryptedAudio({
    required String sourceFilePath,
    required String storagePath,
    required SecretKey dataKey,
  }) async {
    await _refreshSession();
    final bytes = await File(sourceFilePath).readAsBytes();
    final encrypted = await _cryptoService.encryptBytes(bytes, dataKey);
    final encryptedBytes = utf8.encode(encrypted);
    await _client.storage.from(_audioBucket).uploadBinary(
          storagePath,
          encryptedBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/octet-stream',
          ),
        );
  }

  Future<void> _deleteAudioFile(String path) async {
    await _refreshSession();
    await _client.storage.from(_audioBucket).remove([path]);
  }

  String? _normalizeRecipient(VaultEntryDraft draft) {
    final raw = draft.recipientEmail?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }
}

class VaultFailure implements Exception {
  const VaultFailure(this.message);

  final String message;
}
