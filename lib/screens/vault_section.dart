import 'dart:async';

import 'dart:io';



import 'package:flutter/material.dart';

import 'package:just_audio/just_audio.dart';

import 'package:path_provider/path_provider.dart';

import 'package:provider/provider.dart';

import 'package:record/record.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/theme_provider.dart';



import '../models/vault_entry.dart';

import '../services/crypto_service.dart';

import '../services/device_secret_service.dart';

import '../services/server_crypto_service.dart';

import '../services/vault_controller.dart';

import '../services/vault_service.dart';



class VaultSection extends StatelessWidget {

  const VaultSection({

    super.key,

    required this.userId,

    required this.isPro,

    required this.isLifetime,

    this.onVaultChanged,

    this.readOnly = false,

  });



  final String userId;

  final bool isPro;

  final bool isLifetime;

  final VoidCallback? onVaultChanged;

  final bool readOnly;



  @override

  Widget build(BuildContext context) {

    return ChangeNotifierProvider(

      key: ValueKey(userId),

      create: (_) => VaultController(

        vaultService: VaultService(

          client: Supabase.instance.client,

          cryptoService: CryptoService(),

          serverCryptoService:

              ServerCryptoService(client: Supabase.instance.client),

          deviceSecretService: DeviceSecretService(),

        ),

        userId: userId,

      )..loadEntries(),

      child: _VaultSectionView(

        isPro: isPro,

        isLifetime: isLifetime,

        onVaultChanged: onVaultChanged,

        readOnly: readOnly,

      ),

    );

  }

}



/// Opens the vault entry editor sheet from any screen.
/// Returns `true` if an entry was successfully created.
Future<bool> openVaultEntryEditor(
  BuildContext context, {
  required String userId,
  required bool isPro,
  required bool isLifetime,
}) async {
  final controller = VaultController(
    vaultService: VaultService(
      client: Supabase.instance.client,
      cryptoService: CryptoService(),
      deviceSecretService: DeviceSecretService(),
      serverCryptoService: ServerCryptoService(client: Supabase.instance.client),
    ),
    userId: userId,
  );

  bool created = false;

  try {
    // Fire-and-forget: load entries in background so the sheet opens instantly.
    // VaultController will notifyListeners() when done, updating audio time bank.
    unawaited(controller.loadEntries());

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ChangeNotifierProvider.value(
        value: controller,
        child: _SheetContainer(
          child: VaultEntrySheet(
            entry: null,
            payload: null,
            isPro: isPro,
            isLifetime: isLifetime,
            onSave: (draft) async {
              return controller.createEntry(
                draft,
                isPro: isPro,
                isLifetime: isLifetime,
              );
            },
          ),
        ),
      ),
    );
    created = result == true;
  } finally {
    controller.dispose();
  }

  if (created && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry saved.')),
    );
  }

  return created;
}

class _VaultSectionView extends StatelessWidget {

  const _VaultSectionView({

    required this.isPro,

    required this.isLifetime,

    this.onVaultChanged,

    this.readOnly = false,

  });



  final bool isPro;

  final bool isLifetime;

  final VoidCallback? onVaultChanged;

  final bool readOnly;



  @override

  Widget build(BuildContext context) {

    final controller = context.watch<VaultController>();

    final entries = controller.entries;

    final activeEntries = entries

        .where((entry) => entry.status == VaultStatus.active)

        .toList();

    final sentEntries = entries

        .where((entry) => entry.status == VaultStatus.sent)

        .toList();

    final emptyMessage = sentEntries.isEmpty

        ? 'Your vault is empty. Add a secure message to protect it.'

        : 'No active items right now. Sent items live in History.';



    List<Widget> buildEntryTiles(List<VaultEntry> entries) {

      return [

        for (final entry in entries) ...[

          const SizedBox(height: 12),

          _VaultEntryTile(

            entry: entry,

            onView: () async {

              await _showEntryDetails(context, controller, entry);

            },

            onEdit: readOnly ? null : (entry.isEditable

                ? () async {

                    final payload = await controller.loadPayload(entry);

                    if (payload == null) return;

                    if (!context.mounted) return;

                    await _openEditor(

                      context,

                      controller,

                      entry: entry,

                      payload: payload,

                    );

                  }

                : null),

            onDelete: readOnly ? null : (() async {

              final confirmed = await _confirmDelete(context);

              if (!confirmed) return;

              await controller.deleteEntry(entry);

              if (context.mounted) onVaultChanged?.call();

            }),

          ),

        ],

      ];

    }



    return _VaultCard(

      child: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              children: [

                Container(

                  padding: const EdgeInsets.all(8),

                  decoration: BoxDecoration(

                    color: Colors.white10,

                    borderRadius: BorderRadius.circular(12),

                  ),

                  child: const Icon(Icons.lock_outline, size: 18),

                ),

                const SizedBox(width: 10),

                Text(

                  'Vault',

                  style: Theme.of(context).textTheme.titleMedium,

                ),

                if (activeEntries.isNotEmpty) ...[

                  const SizedBox(width: 8),

                  _VaultStatPill(label: '${activeEntries.length}'),

                ],

                const Spacer(),

                if (entries.isNotEmpty)

                  SizedBox(

                    width: 32,

                    height: 32,

                    child: IconButton(

                      padding: EdgeInsets.zero,

                      iconSize: 18,

                      tooltip: 'Refresh',

                      icon: const Icon(Icons.refresh),

                      onPressed:

                          controller.isLoading ? null : controller.loadEntries,

                    ),

                  ),

              ],

            ),

            const SizedBox(height: 8),

            Text(

              'Encrypted entries released on protocol.',

              style: Theme.of(context)

                  .textTheme

                  .bodySmall

                  ?.copyWith(color: Colors.white60),

            ),

            if (controller.errorMessage != null) ...[

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

            ],

            if (controller.isLoading && entries.isEmpty)

              const Padding(

                padding: EdgeInsets.only(top: 20),

                child: Center(child: CircularProgressIndicator()),

              )

            else if (activeEntries.isEmpty)

              Container(

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(

                  color: Colors.white.withValues(alpha: 0.03),

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: Colors.white12),

                ),

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Row(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Container(

                          padding: const EdgeInsets.all(8),

                          decoration: BoxDecoration(

                            color: Colors.white10,

                            borderRadius: BorderRadius.circular(12),

                          ),

                          child: const Icon(Icons.inbox_outlined, size: 18),

                        ),

                        const SizedBox(width: 12),

                        Expanded(

                          child: Text(

                            emptyMessage,

                            style: Theme.of(context)

                                .textTheme

                                .bodySmall

                                ?.copyWith(color: Colors.white70),

                          ),

                        ),

                      ],

                    ),

                    if (!readOnly) ...[

                    const SizedBox(height: 12),

                    SizedBox(

                      width: double.infinity,

                      child: OutlinedButton.icon(

                        onPressed: controller.isLoading

                            ? null

                            : () async {

                                await _openEditor(context, controller);

                              },

                        icon: const Icon(Icons.add),

                        label: const Text('Create entry'),

                      ),

                    ),

                    ],

                  ],

                ),

              )

            else ...[

              ...buildEntryTiles(activeEntries),

              if (!readOnly) ...[

              const SizedBox(height: 12),

              SizedBox(

                width: double.infinity,

                child: OutlinedButton.icon(

                  onPressed: controller.isLoading

                      ? null

                      : () async {

                          await _openEditor(context, controller);

                        },

                  icon: const Icon(Icons.add),

                  label: const Text('Add Entry'),

                ),

              ),

              ],

            ],

            if (sentEntries.isNotEmpty) ...[

              const SizedBox(height: 20),

              const Divider(color: Colors.white12, height: 1),

              const SizedBox(height: 12),

              Row(

                children: [

                  Container(

                    padding: const EdgeInsets.all(8),

                    decoration: BoxDecoration(

                      color: Colors.white10,

                      borderRadius: BorderRadius.circular(12),

                    ),

                    child: const Icon(Icons.history, size: 18),

                  ),

                  const SizedBox(width: 12),

                  Text(

                    'History',

                    style: Theme.of(context).textTheme.titleSmall,

                  ),

                  const SizedBox(width: 8),

                  _VaultStatPill(label: 'Sent ${sentEntries.length}'),

                ],

              ),

              const SizedBox(height: 6),

              Text(

                'Sent items are read-only and retained for 30 days.',

                style: Theme.of(context)

                    .textTheme

                    .bodySmall

                    ?.copyWith(color: Colors.white60),

              ),

              ...buildEntryTiles(sentEntries),

            ],

          ],

        ),

      ),

    );

  }



  Future<void> _openEditor(

    BuildContext context,

    VaultController controller, {

    VaultEntry? entry,

    VaultEntryPayload? payload,

  }) async {

    final result = await showModalBottomSheet<bool>(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (sheetContext) => ChangeNotifierProvider.value(

        value: controller,

        child: _SheetContainer(

        child: VaultEntrySheet(

          entry: entry,

          payload: payload,

          isPro: isPro,

          isLifetime: isLifetime,

          onSave: (draft) async {

            return entry == null

                ? controller.createEntry(

                    draft,

                    isPro: isPro,

                    isLifetime: isLifetime,

                  )

                : controller.updateEntry(

                    entry,

                    draft,

                    isPro: isPro,

                    isLifetime: isLifetime,

                  );

          },

        ),

      ),

      ),

    );



    if (result == true && context.mounted) {

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(entry == null ? 'Entry saved.' : 'Entry updated.'),

        ),

      );

      onVaultChanged?.call();

    }

  }



  Future<void> _showEntryDetails(

    BuildContext context,

    VaultController controller,

    VaultEntry entry,

  ) async {

    await showModalBottomSheet<void>(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (sheetContext) => _SheetContainer(

        child: _EntryDetailsSheet(

          controller: controller,

          entry: entry,

          sheetContext: sheetContext,

        ),

      ),

    );

  }



  Future<bool> _confirmDelete(BuildContext context) async {

    final result = await showDialog<bool>(

      context: context,

      builder: (context) => AlertDialog(

        title: const Text('Delete entry?'),

        content: const Text('This permanently deletes the encrypted entry.'),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(context, false),

            child: const Text('Cancel'),

          ),

          FilledButton(

            onPressed: () => Navigator.pop(context, true),

            child: const Text('Delete'),

          ),

        ],

      ),

    );

    return result ?? false;

  }

}



class _EntryDetailsSheet extends StatefulWidget {
  const _EntryDetailsSheet({
    required this.controller,
    required this.entry,
    required this.sheetContext,
  });

  final VaultController controller;
  final VaultEntry entry;
  final BuildContext sheetContext;

  @override
  State<_EntryDetailsSheet> createState() => _EntryDetailsSheetState();
}

class _EntryDetailsSheetState extends State<_EntryDetailsSheet> {
  late final Future<VaultEntryPayload?> _payloadFuture;
  Future<String?>? _audioFuture;

  @override
  void initState() {
    super.initState();
    _payloadFuture = widget.controller.loadPayload(widget.entry);
    if (widget.entry.dataType == VaultDataType.audio) {
      _audioFuture = widget.controller.loadAudioPath(widget.entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VaultEntryPayload?>(
      future: _payloadFuture,
      builder: (context, snapshot) {
        final payload = snapshot.data;
        final message = payload?.plaintext?.trim() ?? '';

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetHandle(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.entry.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(widget.sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _VaultChip(label: widget.entry.actionType.label),
                      _VaultChip(label: widget.entry.dataType.name),
                      _VaultChip(label: widget.entry.status.label),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (payload == null)
                    Text(
                      'Unable to decrypt this entry.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    )
                  else ...[
                    if (widget.entry.actionType == VaultActionType.send &&
                        payload.recipientEmail != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.alternate_email,
                              size: 16, color: Colors.white60),
                          const SizedBox(width: 6),
                          Text(
                            'Recipient',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white60),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(payload.recipientEmail!),
                      const SizedBox(height: 12),
                    ],
                    if (widget.entry.dataType == VaultDataType.audio &&
                        _audioFuture != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.graphic_eq,
                              size: 16, color: Colors.white60),
                          const SizedBox(width: 6),
                          Text(
                            'Audio Vault',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white60),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<String?>(
                        future: _audioFuture,
                        builder: (context, audioSnapshot) {
                          if (audioSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final audioPath = audioSnapshot.data;
                          if (audioPath == null) {
                            return Text(
                              'Unable to load audio.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.white70),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: _AudioPlaybackSection(
                              audioPath: audioPath,
                              durationSeconds:
                                  widget.entry.audioDurationSeconds,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (message.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 16, color: Colors.white60),
                          const SizedBox(width: 6),
                          Text(
                            'Message',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white60),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ] else
                      Text(
                        'No message attached.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VaultEntryTile extends StatelessWidget {

  const _VaultEntryTile({

    required this.entry,

    required this.onView,

    required this.onEdit,

    required this.onDelete,

  });



  final VaultEntry entry;

  final VoidCallback onView;

  final VoidCallback? onEdit;

  final VoidCallback? onDelete;



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final statusColor = entry.status == VaultStatus.sent

        ? theme.colorScheme.secondary

        : theme.colorScheme.primary;

    final typeIcon = entry.dataType == VaultDataType.audio

        ? Icons.graphic_eq

        : Icons.text_snippet_outlined;

    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [context.read<ThemeProvider>().themeData.cardGradientStart, context.read<ThemeProvider>().themeData.cardGradientEnd],

        ),

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: context.read<ThemeProvider>().themeData.dividerColor),

      ),

      padding: const EdgeInsets.all(16),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Container(

            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(

              color: statusColor.withValues(alpha: 0.16),

              shape: BoxShape.circle,

              border: Border.all(color: statusColor.withValues(alpha: 0.4)),

            ),

            child: Icon(typeIcon, color: statusColor, size: 18),

          ),

          const SizedBox(width: 12),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  entry.title,

                  style: theme.textTheme.titleMedium?.copyWith(

                    fontWeight: FontWeight.w600,

                  ),

                ),

                const SizedBox(height: 6),

                Wrap(

                  spacing: 8,

                  runSpacing: 8,

                  children: [

                    _VaultChip(label: entry.actionType.label),

                    _VaultChip(label: entry.dataType.name),

                    _VaultChip(label: entry.status.label),

                  ],

                ),

              ],

            ),

          ),

          const SizedBox(width: 8),

          Column(

            children: [

              _EntryActionButton(

                tooltip: 'View',

                icon: Icons.visibility_outlined,

                onPressed: onView,

              ),

              if (onEdit != null || onDelete != null) ...[

              const SizedBox(height: 8),

              _EntryActionButton(

                tooltip: entry.isEditable ? 'Edit' : 'Locked',

                icon:

                    entry.isEditable ? Icons.edit_outlined : Icons.lock_outline,

                onPressed: onEdit,

              ),

              ],

              if (onDelete != null) ...[

              const SizedBox(height: 8),

              _EntryActionButton(

                tooltip: 'Delete',

                icon: Icons.delete_outline,

                onPressed: onDelete!,

              ),

              ],

            ],

          ),

        ],

      ),

    );

  }

}



class VaultEntrySheet extends StatefulWidget {

  const VaultEntrySheet({

    super.key,

    required this.entry,

    required this.payload,

    required this.isPro,

    required this.isLifetime,

    required this.onSave,

  });



  final VaultEntry? entry;

  final VaultEntryPayload? payload;

  final bool isPro;

  final bool isLifetime;

  final Future<bool> Function(VaultEntryDraft draft) onSave;



  @override

  State<VaultEntrySheet> createState() => _VaultEntrySheetState();

}



class _VaultEntrySheetState extends State<VaultEntrySheet> {

  late final TextEditingController _titleController;

  late final TextEditingController _recipientController;

  late final TextEditingController _bodyController;

  late VaultActionType _actionType;

  late VaultDataType _dataType;

  AudioRecorder? _recorder;
  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  Timer? _recordTimer;

  int _recordSeconds = 0;

  bool _isRecording = false;

  String? _recordedFilePath;

  int? _recordedDurationSeconds;

  String? _audioError;

  bool _isSaving = false;
  bool _consentChecked = false;

  String? _saveError;



  @override

  void initState() {

    super.initState();

    _titleController = TextEditingController(text: widget.entry?.title ?? '');

    _recipientController = TextEditingController(

      text: widget.payload?.recipientEmail ?? '',

    );

    _bodyController = TextEditingController(

      text: widget.payload?.plaintext ?? '',

    );

    _actionType = widget.entry?.actionType ?? VaultActionType.send;

    _dataType = widget.entry?.dataType ?? VaultDataType.text;

  }



  @override

  void dispose() {

    _recordTimer?.cancel();

    if (_isRecording && _recorder != null) {

      unawaited(_recorder!.stop());

    }

    _recorder?.dispose();

    _titleController.dispose();

    _recipientController.dispose();

    _bodyController.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final isEditing = widget.entry != null;

    // Only subscribe to audioSecondsUsed (and only when audio mode is active)
    // to avoid full rebuilds from VaultController during keyboard animation.
    final audioSecondsUsed = _dataType == VaultDataType.audio
        ? context.select<VaultController, int>((c) => c.audioSecondsUsed)
        : 0;

    final existingAudioSeconds =

        widget.entry?.dataType == VaultDataType.audio &&

                widget.entry?.audioDurationSeconds != null

            ? widget.entry!.audioDurationSeconds!

            : 0;

    final remainingSecondsRaw = VaultController.audioTimeBankSeconds -

        audioSecondsUsed +

        existingAudioSeconds;

    final remainingSeconds = remainingSecondsRaw > 0 ? remainingSecondsRaw : 0;

    final hasRemainingSeconds = remainingSeconds > 0;

    final hasExistingAudio =

        widget.entry?.dataType == VaultDataType.audio &&

            widget.entry?.audioDurationSeconds != null;

    final hasNewRecording = _recordedFilePath != null;

    final recordedSeconds = _isRecording

        ? _recordSeconds

        : (_recordedDurationSeconds ??

            (hasExistingAudio ? existingAudioSeconds : null));

    final timeBankTotal = VaultController.audioTimeBankSeconds;

    final timeBankProgress = timeBankTotal == 0

        ? 0.0

        : (timeBankTotal - remainingSeconds) / timeBankTotal;



    return SafeArea(

      child: SingleChildScrollView(

        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            const _SheetHandle(),

            const SizedBox(height: 12),

            Row(

              children: [

                Expanded(

                  child: Text(

                    isEditing ? 'Edit Vault Entry' : 'New Vault Entry',

                    style: Theme.of(context).textTheme.titleLarge,

                  ),

                ),

                IconButton(

                  tooltip: 'Close',

                  onPressed: _isSaving ? null : () => Navigator.pop(context),

                  icon: const Icon(Icons.close),

                ),

              ],

            ),

            const SizedBox(height: 12),

            TextField(

              controller: _titleController,

              decoration: const InputDecoration(

                labelText: 'Title',

                filled: true,

                prefixIcon: Icon(Icons.title_outlined),

              ),

            ),

            const SizedBox(height: 12),

            Row(

              children: [

                const Icon(Icons.bolt_outlined, size: 16, color: Colors.white60),

                const SizedBox(width: 6),

                Text(

                  'Action',

                  style: Theme.of(context)

                      .textTheme

                      .labelSmall

                      ?.copyWith(color: Colors.white60),

                ),

              ],

            ),

            const SizedBox(height: 8),

            Wrap(

              spacing: 8,

              children: [

                ChoiceChip(

                  label: const Row(

                    mainAxisSize: MainAxisSize.min,

                    children: [

                      Icon(Icons.send_outlined, size: 16),

                      SizedBox(width: 4),

                      Text('Send'),

                    ],

                  ),

                  selected: _actionType == VaultActionType.send,

                  onSelected: _isSaving

                      ? null

                      : (_) {

                          setState(() {

                            _actionType = VaultActionType.send;

                          });

                        },

                ),

                ChoiceChip(

                  label: Row(

                    mainAxisSize: MainAxisSize.min,

                    children: [

                      const Icon(Icons.delete_forever_outlined, size: 16),

                      const SizedBox(width: 4),

                      const Text('Erase'),

                      const SizedBox(width: 4),

                      if (!widget.isPro)

                        const Icon(Icons.lock_outline, size: 16),

                    ],

                  ),

                  selected: _actionType == VaultActionType.destroy,

                  onSelected: widget.isPro && !_isSaving

                      ? (_) {

                          setState(() {

                            _actionType = VaultActionType.destroy;

                          });

                        }

                      : null,

                ),

              ],

            ),

            if (!widget.isPro) ...[

              const SizedBox(height: 6),

              Text(

                'Protocol Zero (erase) is unlocked on Pro.',

                style: Theme.of(context)

                    .textTheme

                    .bodySmall

                    ?.copyWith(color: Colors.white54),

              ),

            ],

            const SizedBox(height: 16),

            Row(

              children: [

                const Icon(Icons.layers_outlined, size: 16, color: Colors.white60),

                const SizedBox(width: 6),

                Text(

                  'Data Type',

                  style: Theme.of(context)

                      .textTheme

                      .labelSmall

                      ?.copyWith(color: Colors.white60),

                ),

              ],

            ),

            const SizedBox(height: 8),

            Wrap(

              spacing: 8,

              children: [

                ChoiceChip(

                  label: const Row(

                    mainAxisSize: MainAxisSize.min,

                    children: [

                      Icon(Icons.text_snippet_outlined, size: 16),

                      SizedBox(width: 4),

                      Text('Text'),

                    ],

                  ),

                  selected: _dataType == VaultDataType.text,

                  onSelected: _isSaving

                      ? null

                      : (_) async {

                          await _handleDataTypeChange(VaultDataType.text);

                        },

                ),

                ChoiceChip(

                  label: Row(

                    mainAxisSize: MainAxisSize.min,

                    children: [

                      const Text('Audio'),

                      const SizedBox(width: 4),

                      const Icon(Icons.graphic_eq, size: 16),

                      if (!widget.isLifetime) ...[

                        const SizedBox(width: 4),

                        const Icon(Icons.lock_outline, size: 16),

                      ],

                    ],

                  ),

                  selected: _dataType == VaultDataType.audio,

                  onSelected: widget.isLifetime && !_isSaving

                      ? (_) async {

                          await _handleDataTypeChange(VaultDataType.audio);

                        }

                      : null,

                ),

              ],

            ),

            const SizedBox(height: 6),

            Text(

              widget.isLifetime

                  ? 'Audio vault includes a 10 minute time bank.'

                  : 'Audio vault unlocks on Lifetime.',

              style: Theme.of(context)

                  .textTheme

                  .bodySmall

                  ?.copyWith(color: Colors.white54),

            ),

            if (_dataType == VaultDataType.audio) ...[

              const SizedBox(height: 12),

              Container(

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(

                  gradient: const LinearGradient(

                    begin: Alignment.topLeft,

                    end: Alignment.bottomRight,

                    colors: [Color(0xFF1A1A1A), Color(0xFF0E0E0E)],

                  ),

                  borderRadius: BorderRadius.circular(18),

                  border: Border.all(color: Colors.white12),

                ),

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      'Recording',

                      style: Theme.of(context)

                          .textTheme

                          .labelSmall

                          ?.copyWith(color: Colors.white60),

                    ),

                    const SizedBox(height: 6),

                    Text(

                      'Time bank: ${_formatSeconds(remainingSeconds)} left of ${_formatSeconds(VaultController.audioTimeBankSeconds)}',

                      style: Theme.of(context)

                          .textTheme

                          .bodySmall

                          ?.copyWith(color: Colors.white70),

                    ),

                    const SizedBox(height: 10),

                    ClipRRect(

                      borderRadius: BorderRadius.circular(999),

                      child: LinearProgressIndicator(

                        value: timeBankProgress.clamp(0, 1),

                        minHeight: 6,

                        backgroundColor: Colors.white12,

                      ),

                    ),

                    if (!hasRemainingSeconds) ...[

                      const SizedBox(height: 4),

                      Text(

                        'Time bank exhausted. Delete an audio entry to free time.',

                        style: Theme.of(context)

                            .textTheme

                            .bodySmall

                            ?.copyWith(

                              color: Theme.of(context).colorScheme.error,

                            ),

                      ),

                    ],

                    const SizedBox(height: 12),

                    Wrap(

                      spacing: 8,

                      runSpacing: 8,

                      children: [

                        FilledButton.icon(

                          onPressed: _isSaving || !hasRemainingSeconds

                              ? null

                              : () async {

                                  if (_isRecording) {

                                    await _stopRecording(reachedLimit: false);

                                  } else {

                                    await _startRecording(remainingSeconds);

                                  }

                                },

                          icon: Icon(

                            _isRecording

                                ? Icons.stop_circle_outlined

                                : Icons.mic_none,

                          ),

                          label:

                              Text(_isRecording ? 'Stop' : 'Record'),

                        ),

                        if (!_isRecording && hasNewRecording)

                          TextButton.icon(

                            onPressed: _isSaving

                                ? null

                                : () async {

                                    await _discardRecording();

                                  },

                            icon: const Icon(Icons.delete_outline),

                            label: const Text('Discard'),

                          ),

                      ],

                    ),

                    if (_isRecording || recordedSeconds != null) ...[

                      const SizedBox(height: 8),

                      Text(

                        _isRecording

                            ? 'Recording: ${_formatSeconds(_recordSeconds)}'

                            : '${hasNewRecording ? 'New recording' : 'Recording'}: ${_formatSeconds(recordedSeconds ?? 0)}',

                        style: Theme.of(context)

                            .textTheme

                            .bodySmall

                            ?.copyWith(color: Colors.white70),

                      ),

                    ],

                    if (hasExistingAudio && !hasNewRecording) ...[

                      const SizedBox(height: 4),

                      Text(

                        'Current recording: ${_formatSeconds(existingAudioSeconds)}',

                        style: Theme.of(context)

                            .textTheme

                            .bodySmall

                            ?.copyWith(color: Colors.white60),

                      ),

                    ],

                    if (_audioError != null) ...[

                      const SizedBox(height: 8),

                      Text(

                        _audioError!,

                        style: Theme.of(context)

                            .textTheme

                            .bodySmall

                            ?.copyWith(

                              color: Theme.of(context).colorScheme.error,

                            ),

                      ),

                    ],

                  ],

                ),

              ),

            ],

            const SizedBox(height: 16),

            if (_actionType == VaultActionType.send) ...[

              TextField(

                controller: _recipientController,

                keyboardType: TextInputType.emailAddress,

                decoration: const InputDecoration(

                  labelText: 'Recipient email',

                  filled: true,

                  prefixIcon: Icon(Icons.alternate_email),

                ),

              ),

              const SizedBox(height: 12),

            ],

            TextField(

              controller: _bodyController,

              maxLength: VaultController.maxPlaintextLength,

              maxLines: 8,

              buildCounter: (

                context, {

                required currentLength,

                required isFocused,

                maxLength,

              }) => null,

              decoration: InputDecoration(

                labelText: _dataType == VaultDataType.audio

                    ? 'Message (optional)'

                    : 'Message',

                alignLabelWithHint: true,

                filled: true,

              ),

            ),

            const SizedBox(height: 16),

            if (_saveError != null) ...[

              Container(

                width: double.infinity,

                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(

                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),

                  borderRadius: BorderRadius.circular(10),

                  border: Border.all(

                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),

                  ),

                ),

                child: Text(

                  _saveError!,

                  style: Theme.of(context).textTheme.bodySmall?.copyWith(

                    color: Theme.of(context).colorScheme.error,

                  ),

                ),

              ),

              const SizedBox(height: 12),

            ],

            // Consent checkbox — mandatory before saving
            CheckboxListTile(
              value: _consentChecked,
              onChanged: (v) => setState(() => _consentChecked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'I confirm this content is lawful and intended for legitimate '
                'personal use. I understand that if I stop checking in, my vault '
                'entries will be delivered or erased based on the timer I set.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(

              width: double.infinity,

              child: FilledButton.icon(

                onPressed: _isSaving || _isRecording || !_consentChecked

                    ? null

                    : () async {

                        await _handleSave(context);

                      },

                icon: const Icon(Icons.save_outlined),

                label: Text(_isSaving ? 'Saving...' : 'Save Entry'),

              ),

            ),

            TextButton.icon(

              onPressed: _isSaving

                  ? null

                  : () {

                      Navigator.pop(context);

                    },

              icon: const Icon(Icons.close),

              label: const Text('Cancel'),

            ),

            const _KeyboardSpacer(),

          ],

        ),

      ),

    );

  }



  Future<void> _handleSave(BuildContext context) async {

    setState(() {

      _isSaving = true;

      _saveError = null;

    });

    FocusScope.of(context).unfocus();

    final nav = Navigator.of(context);

    final ctrl = context.read<VaultController>();

    final isAudio = _dataType == VaultDataType.audio;

    final draft = VaultEntryDraft(

      title: _titleController.text,

      plaintext: _bodyController.text,

      recipientEmail: _actionType == VaultActionType.send

          ? _recipientController.text

          : null,

      actionType: _actionType,

      dataType: _dataType,

      audioFilePath: isAudio ? _recordedFilePath : null,

      audioDurationSeconds: isAudio ? _recordedDurationSeconds : null,

    );

    final success = await widget.onSave(draft);

    if (!mounted) return;

    if (success) {

      setState(() {

        _isSaving = false;

      });

      if (_recordedFilePath != null) {

        try {

          await File(_recordedFilePath!).delete();

        } catch (_) {}

      }

      if (mounted) nav.pop(true);

    } else {

      setState(() {

        _isSaving = false;

        _saveError = ctrl.errorMessage ?? 'Unable to save this entry. Please try again.';

      });

    }

  }



  Future<void> _handleDataTypeChange(VaultDataType type) async {

    if (_dataType == type) {

      return;

    }

    if (_isRecording) {

      await _stopRecording(reachedLimit: false);

    }

    if (type != VaultDataType.audio) {

      await _discardRecording();

    }

    if (!mounted) return;

    setState(() {

      _dataType = type;

      _audioError = null;

    });

  }



  Future<void> _startRecording(int maxSeconds) async {

    if (_isRecording) return;

    setState(() {

      _audioError = null;

    });

    final hasPermission = await _rec.hasPermission();

    if (!hasPermission) {

      if (!mounted) return;

      setState(() {

        _audioError = 'Microphone permission is required to record.';

      });

      return;

    }



    await _discardRecording();

    final directory = await getTemporaryDirectory();

    final path =

        '${directory.path}/afterword_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {

      await _rec.start(

        const RecordConfig(

          encoder: AudioEncoder.aacLc,

          bitRate: 128000,

          sampleRate: 44100,

        ),

        path: path,

      );

    } catch (_) {

      if (!mounted) return;

      setState(() {

        _audioError = 'Unable to start recording.';

      });

      return;

    }



    if (!mounted) return;

    setState(() {

      _isRecording = true;

      _recordSeconds = 0;

      _recordedFilePath = path;

      _recordedDurationSeconds = null;

    });

    _recordTimer?.cancel();

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {

      if (!mounted) {

        timer.cancel();

        return;

      }

      setState(() {

        _recordSeconds += 1;

      });

      if (_recordSeconds >= maxSeconds) {

        await _stopRecording(reachedLimit: true);

      }

    });

  }



  Future<void> _stopRecording({required bool reachedLimit}) async {

    _recordTimer?.cancel();

    String? path;

    try {

      path = await _rec.stop();

    } catch (_) {}

    if (!mounted) return;

    final effectivePath = path ?? _recordedFilePath;

    setState(() {

      _isRecording = false;

      _recordedFilePath = effectivePath;

      _recordedDurationSeconds = _recordSeconds > 0 ? _recordSeconds : null;

      if (reachedLimit) {

        _audioError = 'Time bank limit reached. Recording stopped.';

      }

    });

    if (effectivePath == null && mounted) {

      setState(() {

        _audioError = 'Recording failed. Try again.';

      });

    }

  }



  Future<void> _discardRecording() async {

    _recordTimer?.cancel();

    if (_isRecording) {

      try {

        await _rec.stop();

      } catch (_) {}

    }

    final path = _recordedFilePath;

    if (path != null) {

      try {

        await File(path).delete();

      } catch (_) {}

    }

    if (!mounted) return;

    setState(() {

      _isRecording = false;

      _recordSeconds = 0;

      _recordedFilePath = null;

      _recordedDurationSeconds = null;

      _audioError = null;

    });

  }

}



class _AudioPlaybackSection extends StatefulWidget {

  const _AudioPlaybackSection({

    required this.audioPath,

    required this.durationSeconds,

  });



  final String audioPath;

  final int? durationSeconds;



  @override

  State<_AudioPlaybackSection> createState() => _AudioPlaybackSectionState();

}



class _AudioPlaybackSectionState extends State<_AudioPlaybackSection> {

  late final AudioPlayer _player;

  String? _error;



  @override

  void initState() {

    super.initState();

    _player = AudioPlayer();

    _loadAudio();

  }



  Future<void> _loadAudio() async {

    try {

      await _player.setFilePath(widget.audioPath);

    } catch (_) {

      if (!mounted) return;

      setState(() {

        _error = 'Unable to prepare audio.';

      });

    }

  }



  @override

  void dispose() {

    _player.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    if (_error != null) {

      return Text(

        _error!,

        style: Theme.of(context)

            .textTheme

            .bodySmall

            ?.copyWith(color: Theme.of(context).colorScheme.error),

      );

    }



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        StreamBuilder<PlayerState>(

          stream: _player.playerStateStream,

          builder: (context, snapshot) {

            final state = snapshot.data;

            final processingState = state?.processingState;

            final isBuffering = processingState == ProcessingState.loading ||

                processingState == ProcessingState.buffering;

            final isPlaying = state?.playing ?? false;

            final isCompleted = processingState == ProcessingState.completed;

            return Row(

              children: [

                Container(

                  decoration: BoxDecoration(

                    color: Colors.white10,

                    borderRadius: BorderRadius.circular(16),

                    border: Border.all(color: Colors.white12),

                  ),

                  child: IconButton(

                    iconSize: 30,

                    onPressed: isBuffering

                        ? null

                        : () async {

                            if (isCompleted) {

                              await _player.seek(Duration.zero);

                              await _player.play();

                            } else if (isPlaying) {

                              await _player.pause();

                            } else {

                              await _player.play();

                            }

                          },

                    icon: Icon(

                      isPlaying

                          ? Icons.pause_circle_filled

                          : Icons.play_circle,

                    ),

                  ),

                ),

                if (isBuffering)

                  const SizedBox(

                    width: 20,

                    height: 20,

                    child: CircularProgressIndicator(strokeWidth: 2),

                  ),

              ],

            );

          },

        ),

        StreamBuilder<Duration?>(

          stream: _player.durationStream,

          builder: (context, durationSnapshot) {

            final duration = durationSnapshot.data ??

                Duration(seconds: widget.durationSeconds ?? 0);

            return StreamBuilder<Duration>(

              stream: _player.positionStream,

              builder: (context, positionSnapshot) {

                final position = positionSnapshot.data ?? Duration.zero;

                final totalMs = duration.inMilliseconds;

                final clampedPositionMs = totalMs > 0

                    ? position.inMilliseconds.clamp(0, totalMs)

                    : 0;

                final sliderMax = totalMs > 0 ? totalMs.toDouble() : 1.0;

                return Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Slider(

                      value: totalMs > 0

                          ? clampedPositionMs.toDouble()

                          : 0,

                      min: 0,

                      max: sliderMax,

                      onChanged: totalMs > 0

                          ? (value) async {

                              await _player.seek(

                                Duration(milliseconds: value.round()),

                              );

                            }

                          : null,

                    ),

                    Text(

                      '${_formatSeconds(position.inSeconds)} / ${_formatSeconds(duration.inSeconds)}',

                      style: Theme.of(context)

                          .textTheme

                          .bodySmall

                          ?.copyWith(color: Colors.white60),

                    ),

                  ],

                );

              },

            );

          },

        ),

      ],

    );

  }

}



String _formatSeconds(int seconds) {

  final minutes = seconds ~/ 60;

  final remainingSeconds = seconds % 60;

  final minutesString = minutes.toString().padLeft(2, '0');

  final secondsString = remainingSeconds.toString().padLeft(2, '0');

  return '$minutesString:$secondsString';

}



class _SheetContainer extends StatelessWidget {

  const _SheetContainer({required this.child});



  final Widget child;



  @override

  Widget build(BuildContext context) {

    final topPad = MediaQuery.paddingOf(context).top;
    // read, not watch — theme won't change while sheet is open
    final td = context.read<ThemeProvider>().themeData;

    return Padding(

      padding: EdgeInsets.fromLTRB(8, topPad + 8, 8, 8),

      child: Container(

        constraints: BoxConstraints(

          maxHeight: MediaQuery.sizeOf(context).height * 0.92 - topPad,

        ),

        decoration: BoxDecoration(

          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [td.cardGradientStart, td.cardGradientEnd],
          ),

          borderRadius: BorderRadius.circular(28),

          border: Border.all(color: td.dividerColor),

          // No BoxShadow — blurred shadows are extremely expensive to
          // re-rasterize on every keyboard animation frame.

        ),

        child: ClipRRect(

          borderRadius: BorderRadius.circular(28),

          child: RepaintBoundary(child: child),

        ),

      ),

    );

  }

}



class _SheetHandle extends StatelessWidget {

  const _SheetHandle();



  @override

  Widget build(BuildContext context) {

    return Center(

      child: Container(

        width: 48,

        height: 4,

        decoration: BoxDecoration(

          color: Colors.white24,

          borderRadius: BorderRadius.circular(999),

        ),

      ),

    );

  }

}



/// Isolates keyboard-aware bottom padding so the entire form does NOT rebuild
/// when the soft keyboard opens or closes. Only this widget rebuilds.
class _KeyboardSpacer extends StatelessWidget {
  const _KeyboardSpacer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: MediaQuery.viewInsetsOf(context).bottom);
  }
}

class _VaultCard extends StatelessWidget {

  const _VaultCard({required this.child});



  final Widget child;



  @override

  Widget build(BuildContext context) {

    final td = context.watch<ThemeProvider>().themeData;

    return Container(

      decoration: BoxDecoration(

        gradient: LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [td.cardGradientStart, td.cardGradientEnd],

        ),

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: td.dividerColor),

      ),

      child: ClipRRect(

        borderRadius: BorderRadius.circular(22),

        child: child,

      ),

    );

  }

}



class _VaultChip extends StatelessWidget {

  const _VaultChip({required this.label});



  final String label;



  @override

  Widget build(BuildContext context) {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

      decoration: BoxDecoration(

        color: Colors.white10,

        borderRadius: BorderRadius.circular(999),

        border: Border.all(color: Colors.white12),

      ),

      child: Text(

        label,

        style: Theme.of(context)

            .textTheme

            .labelSmall

            ?.copyWith(color: Colors.white70),

      ),

    );

  }

}



class _VaultStatPill extends StatelessWidget {

  const _VaultStatPill({required this.label});



  final String label;



  @override

  Widget build(BuildContext context) {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(

        color: Colors.white10,

        borderRadius: BorderRadius.circular(999),

        border: Border.all(color: Colors.white12),

      ),

      child: Text(

        label,

        style: Theme.of(context)

            .textTheme

            .labelSmall

            ?.copyWith(color: Colors.white70),

      ),

    );

  }

}




class _EntryActionButton extends StatelessWidget {

  const _EntryActionButton({

    required this.tooltip,

    required this.icon,

    required this.onPressed,

  });



  final String tooltip;

  final IconData icon;

  final VoidCallback? onPressed;



  @override

  Widget build(BuildContext context) {

    return Container(

      decoration: BoxDecoration(

        color: Colors.white10,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: Colors.white12),

      ),

      child: IconButton(

        tooltip: tooltip,

        onPressed: onPressed,

        icon: Icon(icon, size: 20),

      ),

    );

  }

}

