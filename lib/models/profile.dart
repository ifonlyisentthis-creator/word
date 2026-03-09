class Profile {
  Profile({
    required this.id,
    required this.email,
    required this.senderName,
    required this.status,
    required this.subscriptionStatus,
    required this.lastCheckIn,
    required this.timerDays,
    this.createdAt,
    this.updatedAt,
    this.warningSentAt,
    this.hmacKeyEncrypted,
    this.selectedTheme,
    this.selectedSoulFire,
    this.push66SentAt,
    this.push33SentAt,
    this.protocolExecutedAt,
  });

  final String id;
  final String? email;
  final String senderName;
  final String status;
  final String subscriptionStatus;
  final DateTime lastCheckIn;
  final int timerDays;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? warningSentAt;
  final String? hmacKeyEncrypted;
  final String? selectedTheme;
  final String? selectedSoulFire;
  final DateTime? push66SentAt;
  final DateTime? push33SentAt;
  final DateTime? protocolExecutedAt;

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      email: map['email'] as String?,
      senderName: (map['sender_name'] as String?)?.trim().isNotEmpty == true
          ? map['sender_name'] as String
          : 'Afterword',
      status: (map['status'] as String?) ?? 'active',
      subscriptionStatus: (map['subscription_status'] as String?) ?? 'free',
      lastCheckIn: map['last_check_in'] != null
          ? DateTime.parse(map['last_check_in'] as String)
          : DateTime.now().toUtc(),
      timerDays: (map['timer_days'] as num?)?.toInt() ?? 30,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      warningSentAt: map['warning_sent_at'] != null
          ? DateTime.parse(map['warning_sent_at'] as String)
          : null,
      hmacKeyEncrypted: map['hmac_key_encrypted'] as String?,
      selectedTheme: map['selected_theme'] as String?,
      selectedSoulFire: map['selected_soul_fire'] as String?,
      push66SentAt: map['push_66_sent_at'] != null
          ? DateTime.parse(map['push_66_sent_at'] as String)
          : null,
      push33SentAt: map['push_33_sent_at'] != null
          ? DateTime.parse(map['push_33_sent_at'] as String)
          : null,
      protocolExecutedAt: map['protocol_executed_at'] != null
          ? DateTime.parse(map['protocol_executed_at'] as String)
          : null,
    );
  }

  Profile copyWith({
    String? senderName,
    String? status,
    String? subscriptionStatus,
    DateTime? lastCheckIn,
    int? timerDays,
    DateTime? updatedAt,
    DateTime? warningSentAt,
    String? hmacKeyEncrypted,
    String? selectedTheme,
    String? selectedSoulFire,
    DateTime? push66SentAt,
    DateTime? push33SentAt,
    DateTime? protocolExecutedAt,
  }) {
    return Profile(
      id: id,
      email: email,
      senderName: senderName ?? this.senderName,
      status: status ?? this.status,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      lastCheckIn: lastCheckIn ?? this.lastCheckIn,
      timerDays: timerDays ?? this.timerDays,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      warningSentAt: warningSentAt ?? this.warningSentAt,
      hmacKeyEncrypted: hmacKeyEncrypted ?? this.hmacKeyEncrypted,
      selectedTheme: selectedTheme ?? this.selectedTheme,
      selectedSoulFire: selectedSoulFire ?? this.selectedSoulFire,
      push66SentAt: push66SentAt ?? this.push66SentAt,
      push33SentAt: push33SentAt ?? this.push33SentAt,
      protocolExecutedAt: protocolExecutedAt ?? this.protocolExecutedAt,
    );
  }

  DateTime get deadline => lastCheckIn.toLocal().add(Duration(days: timerDays));

  Duration get timeRemaining => deadline.difference(DateTime.now());

  int get remainingDays => timeRemaining.isNegative ? 0 : timeRemaining.inDays;

  bool get isExpired => timeRemaining.isNegative;
}
