class VaultEntry {
  VaultEntry({
    required this.id,
    required this.userId,
    required this.title,
    required this.actionType,
    required this.dataType,
    required this.status,
    required this.payloadEncrypted,
    required this.recipientEncrypted,
    required this.dataKeyEncrypted,
    required this.hmacSignature,
    required this.createdAt,
    this.updatedAt,
    this.sentAt,
    this.audioFilePath,
    this.audioDurationSeconds,
  });

  final String id;
  final String userId;
  final String title;
  final VaultActionType actionType;
  final VaultDataType dataType;
  final VaultStatus status;
  final String payloadEncrypted;
  final String? recipientEncrypted;
  final String dataKeyEncrypted;
  final String hmacSignature;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? sentAt;
  final String? audioFilePath;
  final int? audioDurationSeconds;

  factory VaultEntry.fromMap(Map<String, dynamic> map) {
    return VaultEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title'] as String
          : 'Untitled',
      actionType: VaultActionTypeX.fromString(map['action_type'] as String?),
      dataType: VaultDataTypeX.fromString(map['data_type'] as String?),
      status: VaultStatusX.fromString(map['status'] as String?),
      payloadEncrypted: map['payload_encrypted'] as String,
      recipientEncrypted: map['recipient_email_encrypted'] as String?,
      dataKeyEncrypted: map['data_key_encrypted'] as String,
      hmacSignature: map['hmac_signature'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      sentAt: map['sent_at'] != null
          ? DateTime.parse(map['sent_at'] as String)
          : null,
      audioFilePath: map['audio_file_path'] as String?,
      audioDurationSeconds: map['audio_duration_seconds'] as int?,
    );
  }

  bool get isEditable => status == VaultStatus.active;
}

enum VaultActionType { send, destroy }

enum VaultDataType { text, audio }

enum VaultStatus { active, sending, sent }

extension VaultActionTypeX on VaultActionType {
  String get value => switch (this) {
        VaultActionType.send => 'send',
        VaultActionType.destroy => 'destroy',
      };

  String get label => switch (this) {
        VaultActionType.send => 'Send',
        VaultActionType.destroy => 'Erase',
      };

  static VaultActionType fromString(String? value) {
    return value == 'destroy' ? VaultActionType.destroy : VaultActionType.send;
  }
}

extension VaultDataTypeX on VaultDataType {
  String get value => this == VaultDataType.audio ? 'audio' : 'text';

  static VaultDataType fromString(String? value) {
    return value == 'audio' ? VaultDataType.audio : VaultDataType.text;
  }
}

extension VaultStatusX on VaultStatus {
  String get value => switch (this) {
        VaultStatus.active => 'active',
        VaultStatus.sending => 'sending',
        VaultStatus.sent => 'sent',
      };

  String get label => switch (this) {
        VaultStatus.active => 'Active',
        VaultStatus.sending => 'Sending',
        VaultStatus.sent => 'Sent',
      };

  static VaultStatus fromString(String? value) {
    return switch (value) {
      'sent' => VaultStatus.sent,
      'sending' => VaultStatus.sending,
      _ => VaultStatus.active,
    };
  }
}

class VaultEntryPayload {
  const VaultEntryPayload({
    this.plaintext,
    this.recipientEmail,
    this.audioFilePath,
    this.audioDurationSeconds,
  });

  final String? plaintext;
  final String? recipientEmail;
  final String? audioFilePath;
  final int? audioDurationSeconds;
}

class VaultEntryDraft {
  const VaultEntryDraft({
    required this.title,
    required this.plaintext,
    required this.actionType,
    required this.dataType,
    this.recipientEmail,
    this.audioFilePath,
    this.audioDurationSeconds,
  });

  final String title;
  final String plaintext;
  final String? recipientEmail;
  final String? audioFilePath;
  final int? audioDurationSeconds;
  final VaultActionType actionType;
  final VaultDataType dataType;
}
