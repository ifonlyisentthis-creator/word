import 'package:flutter/foundation.dart';

import '../models/vault_entry.dart';
import 'vault_service.dart';

class VaultController extends ChangeNotifier {
  VaultController({required VaultService vaultService, required String userId})
    : _vaultService = vaultService,
      _userId = userId;

  bool _isDisposed = false;

  static const int audioTimeBankSecondsLifetime = 600;
  static const int audioTimeBankSecondsPro = 60;

  static int audioTimeBankFor({required bool isLifetime}) =>
      isLifetime ? audioTimeBankSecondsLifetime : audioTimeBankSecondsPro;
  static const int maxPlaintextLength = 50000;
  static const Duration createRateLimit = Duration(seconds: 5);

  static const int maxEntriesFree = 3;
  static const int maxEntriesPro = 20;
  static const int maxEntriesLifetime = 50;

  static int maxEntriesFor({required bool isPro, required bool isLifetime}) {
    if (isLifetime) return maxEntriesLifetime;
    if (isPro) return maxEntriesPro;
    return maxEntriesFree;
  }

  final VaultService _vaultService;
  final String _userId;

  final Map<String, VaultEntryPayload> _payloadCache = {};
  final Map<String, String> _audioCache = {};
  List<VaultEntry> _entries = [];
  bool _entriesLoaded = false;
  Future<void>? _entriesLoadFuture;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastCreateAttemptAt;

  List<VaultEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  int get audioSecondsUsed => _entries
      .where(
        (entry) =>
            entry.status == VaultStatus.active &&
            entry.dataType == VaultDataType.audio,
      )
      .fold(0, (total, entry) => total + (entry.audioDurationSeconds ?? 0));

  Future<void> loadEntries() async {
    if (_isDisposed) return;
    if (_entriesLoadFuture != null) {
      await _entriesLoadFuture;
      return;
    }

    final future = _loadEntriesInternal();
    _entriesLoadFuture = future;
    try {
      await future;
    } finally {
      _entriesLoadFuture = null;
    }
  }

  Future<void> _loadEntriesInternal() async {
    _setLoading(true);
    try {
      _entries = await _vaultService.fetchEntries(_userId);
      _entriesLoaded = true;
      if (_isDisposed) return;
      _errorMessage = null;
    } catch (_) {
      _errorMessage = 'Unable to load your vault.';
    } finally {
      _setLoading(false);
    }
  }

  Future<VaultEntryPayload?> loadPayload(VaultEntry entry) async {
    if (_payloadCache.containsKey(entry.id)) {
      return _payloadCache[entry.id];
    }
    try {
      final payload = await _vaultService.decryptEntry(entry);
      _payloadCache[entry.id] = payload;
      return payload;
    } catch (_) {
      _errorMessage = 'Unable to decrypt this entry.';
      notifyListeners();
      return null;
    }
  }

  Future<String?> loadAudioPath(VaultEntry entry) async {
    if (entry.dataType != VaultDataType.audio) {
      return null;
    }
    if (_audioCache.containsKey(entry.id)) {
      return _audioCache[entry.id];
    }
    try {
      final path = await _vaultService.downloadAudio(entry);
      _audioCache[entry.id] = path;
      return path;
    } catch (_) {
      _errorMessage = 'Unable to load audio playback.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> createEntry(
    VaultEntryDraft draft, {
    required bool isPro,
    required bool isLifetime,
  }) async {
    if (!_entriesLoaded) {
      await loadEntries();
      if (!_entriesLoaded) {
        _errorMessage = 'Unable to verify vault limits. Please try again.';
        notifyListeners();
        return false;
      }
    }

    final normalizedDraft = _applyPlaintextLimit(draft);
    final failure = _validateDraft(
      normalizedDraft,
      isPro: isPro,
      isLifetime: isLifetime,
      isNew: true,
      existingEntry: null,
    );
    if (failure != null) {
      _errorMessage = failure;
      notifyListeners();
      return false;
    }
    if (_isRateLimited()) {
      _errorMessage = 'Please wait a moment before creating another entry.';
      notifyListeners();
      return false;
    }
    _lastCreateAttemptAt = DateTime.now();

    _setLoading(true);
    try {
      final entry = await _vaultService.createEntry(_userId, normalizedDraft);
      _entries = [entry, ..._entries];
      _errorMessage = null;
      return true;
    } on VaultFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to save this entry. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateEntry(
    VaultEntry entry,
    VaultEntryDraft draft, {
    required bool isPro,
    required bool isLifetime,
  }) async {
    if (!_entriesLoaded) {
      await loadEntries();
      if (!_entriesLoaded) {
        _errorMessage = 'Unable to verify vault limits. Please try again.';
        notifyListeners();
        return false;
      }
    }

    if (!entry.isEditable) {
      _errorMessage = 'This entry is locked.';
      notifyListeners();
      return false;
    }
    final normalizedDraft = _applyPlaintextLimit(draft);
    final failure = _validateDraft(
      normalizedDraft,
      isPro: isPro,
      isLifetime: isLifetime,
      isNew: false,
      existingEntry: entry,
    );
    if (failure != null) {
      _errorMessage = failure;
      notifyListeners();
      return false;
    }

    _setLoading(true);
    try {
      final updated = await _vaultService.updateEntry(entry, normalizedDraft);
      _entries = _entries
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      _payloadCache.remove(entry.id);
      _audioCache.remove(entry.id);
      _errorMessage = null;
      return true;
    } on VaultFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'Unable to update this entry.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteEntry(VaultEntry entry) async {
    _setLoading(true);
    try {
      await _vaultService.deleteEntry(entry);
      _entries = _entries.where((item) => item.id != entry.id).toList();
      _payloadCache.remove(entry.id);
      _audioCache.remove(entry.id);
      _errorMessage = null;
      return true;
    } catch (_) {
      _errorMessage = 'Unable to delete this entry.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  String? _validateDraft(
    VaultEntryDraft draft, {
    required bool isPro,
    required bool isLifetime,
    required bool isNew,
    required VaultEntry? existingEntry,
  }) {
    final isAudio = draft.dataType == VaultDataType.audio;
    if (!isAudio && draft.plaintext.trim().isEmpty) {
      return 'Write something before saving.';
    }

    // Tier-based vault count limits
    final activeEntriesCount = _entries
        .where((entry) => entry.status == VaultStatus.active)
        .length;
    final maxEntries = maxEntriesFor(isPro: isPro, isLifetime: isLifetime);

    if (!isPro) {
      if (draft.actionType == VaultActionType.destroy) {
        return 'Upgrade to unlock Secure Erase mode.';
      }
    }
    if (isNew && activeEntriesCount >= maxEntries) {
      final tierName = isLifetime ? 'Lifetime' : (isPro ? 'Pro' : 'Free');
      return '$tierName plan allows up to $maxEntries entries.';
    }

    if (draft.dataType == VaultDataType.audio && !isPro) {
      return 'Audio vault requires Pro or Lifetime.';
    }
    if (isAudio) {
      final hasExistingAudio = existingEntry?.dataType == VaultDataType.audio;
      if (draft.audioFilePath == null && !hasExistingAudio) {
        return 'Record audio before saving.';
      }
      final durationSeconds =
          draft.audioDurationSeconds ?? existingEntry?.audioDurationSeconds;
      if (durationSeconds == null || durationSeconds <= 0) {
        return 'Record audio before saving.';
      }
      final totalUsed = audioSecondsUsed;
      final bankLimit = audioTimeBankFor(isLifetime: isLifetime);
      final availableSeconds =
          bankLimit -
          totalUsed +
          (hasExistingAudio ? (existingEntry?.audioDurationSeconds ?? 0) : 0);
      if (durationSeconds > availableSeconds) {
        return 'Audio time bank limit reached.';
      }
    }
    if (draft.actionType == VaultActionType.send) {
      final email = draft.recipientEmail?.trim() ?? '';
      if (email.isEmpty) {
        return 'Recipient email is required.';
      }
      if (!_isValidEmail(email)) {
        return 'Please enter a valid email address.';
      }
    }

    // Validate scheduled delivery date (Time Capsule mode)
    if (draft.scheduledAt != null) {
      final now = DateTime.now().toUtc();
      if (draft.scheduledAt!.isBefore(now)) {
        return 'Scheduled date must be in the future.';
      }
      final maxDays = isLifetime ? 3650 : (isPro ? 365 : 30);
      final maxDate = now.add(Duration(days: maxDays));
      if (draft.scheduledAt!.isAfter(maxDate)) {
        final tierName = isLifetime ? 'Lifetime' : (isPro ? 'Pro' : 'Free');
        return '$tierName plan allows scheduling up to $maxDays days ahead.';
      }
    }

    return null;
  }

  void _setLoading(bool value) {
    if (_isDisposed) return;
    _isLoading = value;
    notifyListeners();
  }

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static bool _isValidEmail(String email) {
    return _emailRegex.hasMatch(email);
  }

  bool _isRateLimited() {
    final lastAttempt = _lastCreateAttemptAt;
    if (lastAttempt == null) {
      return false;
    }
    return DateTime.now().difference(lastAttempt) < createRateLimit;
  }

  VaultEntryDraft _applyPlaintextLimit(VaultEntryDraft draft) {
    final capped = draft.plaintext.length > maxPlaintextLength
        ? draft.plaintext.substring(0, maxPlaintextLength)
        : draft.plaintext;
    if (capped == draft.plaintext) {
      return draft;
    }
    return VaultEntryDraft(
      title: draft.title,
      plaintext: capped,
      recipientEmail: draft.recipientEmail,
      actionType: draft.actionType,
      dataType: draft.dataType,
      audioFilePath: draft.audioFilePath,
      audioDurationSeconds: draft.audioDurationSeconds,
      isZeroKnowledge: draft.isZeroKnowledge,
      scheduledAt: draft.scheduledAt,
    );
  }
}
