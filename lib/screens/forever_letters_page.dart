import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vault_entry.dart';
import '../services/crypto_service.dart';
import '../services/device_secret_service.dart';
import '../services/home_controller.dart';
import '../services/revenuecat_controller.dart';
import '../services/server_crypto_service.dart';
import '../services/vault_controller.dart';
import '../services/vault_service.dart';
import '../widgets/ambient_background.dart';

class ForeverLettersPage extends StatefulWidget {
  const ForeverLettersPage({super.key, required this.userId});

  final String userId;

  @override
  State<ForeverLettersPage> createState() => _ForeverLettersPageState();
}

class _ForeverLettersPageState extends State<ForeverLettersPage> {
  late final VaultController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = VaultController(
      vaultService: VaultService(
        client: Supabase.instance.client,
        cryptoService: CryptoService(),
        deviceSecretService: DeviceSecretService(),
        serverCryptoService: ServerCryptoService(
          client: Supabase.instance.client,
        ),
      ),
      userId: widget.userId,
    );
    _load();
  }

  Future<void> _load() async {
    await _controller.loadEntries();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<VaultEntry> get _recurringEntries =>
      _controller.entries.where((e) => e.isRecurring).toList()
        ..sort((a, b) {
          final aMonth = a.scheduledAt?.month ?? 0;
          final bMonth = b.scheduledAt?.month ?? 0;
          if (aMonth != bMonth) return aMonth.compareTo(bMonth);
          final aDay = a.scheduledAt?.day ?? 0;
          final bDay = b.scheduledAt?.day ?? 0;
          return aDay.compareTo(bDay);
        });

  int get _totalActiveEntries =>
      _controller.entries.where((e) => e.status == VaultStatus.active).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revenueCat = context.watch<RevenueCatController>();
    final isLifetime = revenueCat.isLifetime;
    final isPro = revenueCat.isPro || isLifetime;
    final maxEntries =
        VaultController.maxEntriesFor(isPro: isPro, isLifetime: isLifetime);
    final recurring = _recurringEntries;
    final atLimit = _totalActiveEntries >= maxEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forever Letters'),
        backgroundColor: const Color(0xFF0E0E0E),
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const RepaintBoundary(child: AmbientBackground()),
          SafeArea(
            top: false,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : isPro
                    ? _buildContent(
                        theme, recurring, atLimit, isPro, isLifetime, maxEntries)
                    : _buildLockedState(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              'Forever Letters',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to your loved one every year on a date you choose. Available for Pro and Lifetime members.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, List<VaultEntry> recurring,
      bool atLimit, bool isPro, bool isLifetime, int maxEntries) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 32 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        // Explainer card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'HOW IT WORKS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StepRow(
                  number: '1',
                  text: 'Write a message or record audio, pick a date.',
                  theme: theme),
              const SizedBox(height: 8),
              _StepRow(
                  number: '2',
                  text:
                      'Every year on that date, your recipient gets the message.',
                  theme: theme),
              const SizedBox(height: 8),
              _StepRow(
                  number: '3',
                  text:
                      'You can view, edit, or delete your letters anytime.',
                  theme: theme),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Capacity info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${recurring.length} forever letter${recurring.length == 1 ? '' : 's'} \u00b7 '
                  '$_totalActiveEntries / $maxEntries total slots used',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Create button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: atLimit
                ? null
                : () => _openCreateSheet(context, isPro, isLifetime),
            icon: const Icon(Icons.add),
            label: const Text('Create Forever Letter'),
          ),
        ),
        if (atLimit) ...[
          const SizedBox(height: 8),
          Text(
            'All $maxEntries entry slots are in use across your vault.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        // Entries list
        if (recurring.isEmpty)
          _EmptyState(theme: theme)
        else
          ...recurring.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ForeverLetterCard(
                  entry: entry,
                  theme: theme,
                  controller: _controller,
                  isPro: isPro,
                  isLifetime: isLifetime,
                  onChanged: () {
                    if (mounted) {
                      setState(() {});
                      context.read<HomeController>().refreshVaultStatus();
                    }
                  },
                ),
              )),
      ],
    );
  }

  Future<void> _openCreateSheet(
      BuildContext ctx, bool isPro, bool isLifetime) async {
    final created = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xF0000000),
      builder: (_) => _CreateForeverLetterSheet(
        controller: _controller,
        isPro: isPro,
        isLifetime: isLifetime,
      ),
    );
    if (created == true && mounted) {
      setState(() {});
      if (ctx.mounted) {
        ctx.read<HomeController>().refreshVaultStatus();
      }
    }
  }
}

// ─── Card for each recurring entry (tappable → details) ─────────

class _ForeverLetterCard extends StatelessWidget {
  const _ForeverLetterCard({
    required this.entry,
    required this.theme,
    required this.controller,
    required this.isPro,
    required this.isLifetime,
    required this.onChanged,
  });

  final VaultEntry entry;
  final ThemeData theme;
  final VaultController controller;
  final bool isPro;
  final bool isLifetime;
  final VoidCallback onChanged;

  DateTime? _nextDelivery() {
    final s = entry.scheduledAt;
    if (s == null) return null;
    final now = DateTime.now().toUtc();
    final thisYear = DateTime.utc(now.year, s.month, s.day, 12);
    if (thisYear.isAfter(now)) return thisYear;
    return DateTime.utc(now.year + 1, s.month, s.day, 12);
  }

  @override
  Widget build(BuildContext context) {
    final date = entry.scheduledAt;
    final monthDay = date != null ? DateFormat('MMMM d').format(date) : '\u2014';
    final lastSent = entry.lastSentYear;
    final isAudio = entry.dataType == VaultDataType.audio;
    final now = DateTime.now().toUtc();
    final next = _nextDelivery();
    final accent = theme.colorScheme.primary;

    // Progress: bar DECREASES as time passes (remaining fraction)
    String statusText;
    String progressLabel;
    double progress = 1.0; // starts full, decreases
    Color progressColor = accent.withValues(alpha: 0.6);

    if (lastSent != null && lastSent >= now.year && date != null) {
      final sentDate = DateTime.utc(now.year, date.month, date.day, 12);
      final nextDate = DateTime.utc(now.year + 1, date.month, date.day, 12);
      final totalDays = nextDate.difference(sentDate).inDays;
      final daysLeft = nextDate.difference(now).inDays;
      progress =
          totalDays > 0 ? (daysLeft / totalDays).clamp(0.0, 1.0) : 0.0;
      statusText = 'Sent for $lastSent';
      progressLabel =
          '$daysLeft day${daysLeft == 1 ? '' : 's'} until next delivery';
      progressColor = Colors.green.withValues(alpha: 0.5);
    } else if (next != null) {
      final daysUntil = next.difference(now).inDays;
      final created = entry.createdAt.toUtc();
      final totalDays = next.difference(created).inDays;
      progress = totalDays > 0
          ? (daysUntil / totalDays).clamp(0.0, 1.0)
          : 0.0;

      if (daysUntil <= 0) {
        statusText = 'Delivering soon';
        progressLabel = 'Delivery imminent';
        progress = 0.0;
      } else if (daysUntil == 1) {
        statusText = 'Tomorrow';
        progressLabel = 'First delivery tomorrow';
      } else {
        statusText = '$daysUntil days';
        progressLabel = 'until ${DateFormat('MMM d').format(next.toLocal())}';
      }
    } else {
      statusText = 'Pending';
      progressLabel = '';
    }

    return GestureDetector(
      onTap: () => _openDetails(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.all_inclusive,
                    size: 16, color: accent.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isAudio)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.mic, size: 14, color: Colors.white38),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  statusText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'every $monthDay',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation(progressColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              progressLabel,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xF0000000),
      builder: (_) => _EntryDetailsSheet(
        entry: entry,
        controller: controller,
        isPro: isPro,
        isLifetime: isLifetime,
      ),
    ).then((changed) {
      if (changed == true) onChanged();
    });
  }
}

// ─── Entry details / view / edit / delete sheet ─────────────────

class _EntryDetailsSheet extends StatefulWidget {
  const _EntryDetailsSheet({
    required this.entry,
    required this.controller,
    required this.isPro,
    required this.isLifetime,
  });

  final VaultEntry entry;
  final VaultController controller;
  final bool isPro;
  final bool isLifetime;

  @override
  State<_EntryDetailsSheet> createState() => _EntryDetailsSheetState();
}

class _EntryDetailsSheetState extends State<_EntryDetailsSheet> {
  VaultEntryPayload? _payload;
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decrypt();
  }

  Future<void> _decrypt() async {
    final payload = await widget.controller.loadPayload(widget.entry);
    if (mounted) {
      setState(() {
        _payload = payload;
        _loading = false;
      });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Forever Letter?'),
        content: const Text(
            'This will permanently remove this letter. It will no longer be sent annually.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);
    final ok = await widget.controller.deleteEntry(widget.entry);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _deleting = false;
        _error = widget.controller.errorMessage ?? 'Delete failed.';
      });
    }
  }

  Future<void> _edit() async {
    if (_payload == null) return;
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xF0000000),
      builder: (_) => _CreateForeverLetterSheet(
        controller: widget.controller,
        isPro: widget.isPro,
        isLifetime: widget.isLifetime,
        editEntry: widget.entry,
        editPayload: _payload,
      ),
    );
    if (edited == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = widget.entry.scheduledAt;
    final monthDay =
        date != null ? DateFormat('MMMM d').format(date) : '\u2014';
    final isAudio = widget.entry.dataType == VaultDataType.audio;
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(widget.entry.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              // Date
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.white38),
                  const SizedBox(width: 8),
                  Text('Every $monthDay',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white54)),
                  if (widget.entry.lastSentYear != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sent ${widget.entry.lastSentYear}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // Recipient
              if (_payload?.recipientEmail != null)
                Row(
                  children: [
                    Icon(Icons.email_outlined,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _payload!.recipientEmail!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
              // Content
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ))
              else if (isAudio)
                _AudioSection(
                  entry: widget.entry,
                  controller: widget.controller,
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _payload?.plaintext ?? '(Unable to decrypt)',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70, height: 1.5),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _edit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _deleting ? null : _delete,
                      icon: Icon(Icons.delete_outline,
                          size: 16,
                          color: _deleting
                              ? null
                              : theme.colorScheme.error),
                      label: Text(
                        _deleting ? 'Deleting...' : 'Delete',
                        style: TextStyle(
                            color: _deleting
                                ? null
                                : theme.colorScheme.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: _deleting
                                ? Colors.white12
                                : theme.colorScheme.error
                                    .withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Audio playback section in details sheet ─────────────────────

class _AudioSection extends StatefulWidget {
  const _AudioSection({required this.entry, required this.controller});
  final VaultEntry entry;
  final VaultController controller;

  @override
  State<_AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<_AudioSection> {
  AudioPlayer? _player;
  bool _loadingAudio = true;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    final path = await widget.controller.loadAudioPath(widget.entry);
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _loadingAudio = false;
        _audioError = 'Unable to load audio.';
      });
      return;
    }
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
    } catch (_) {
      setState(() {
        _loadingAudio = false;
        _audioError = 'Unable to play audio.';
      });
      return;
    }
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _loadingAudio = false;
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingAudio) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_audioError != null) {
      return Text(_audioError!,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38));
    }
    final player = _player!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (_, snap) {
                  final state = snap.data;
                  final playing = state?.playing ?? false;
                  final completed = state?.processingState ==
                      ProcessingState.completed;
                  return IconButton(
                    onPressed: () async {
                      if (completed) {
                        await player.seek(Duration.zero);
                        await player.play();
                      } else if (playing) {
                        await player.pause();
                      } else {
                        player.play();
                      }
                    },
                    icon: Icon(
                        playing && !completed
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: theme.colorScheme.primary),
                  );
                },
              ),
              Expanded(
                child: StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  builder: (_, durSnap) {
                    final total = durSnap.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (_, posSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        final maxMs = total.inMilliseconds.toDouble();
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5),
                              ),
                              child: Slider(
                                value: pos.inMilliseconds
                                    .toDouble()
                                    .clamp(0, maxMs),
                                max: maxMs > 0 ? maxMs : 1,
                                onChanged: (v) =>
                                    player.seek(Duration(
                                        milliseconds: v.toInt())),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_fmtDur(pos),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                  Text(_fmtDur(total),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─── Empty state ────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.all_inclusive, size: 40, color: Colors.white12),
          const SizedBox(height: 12),
          Text('No forever letters yet',
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: Colors.white30)),
          const SizedBox(height: 4),
          Text('Create one to send a message every year.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: Colors.white24)),
        ],
      ),
    );
  }
}

// ─── Step row ───────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  const _StepRow(
      {required this.number, required this.text, required this.theme});
  final String number;
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(number,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54)),
        ),
      ],
    );
  }
}

// ─── Create / Edit sheet ────────────────────────────────────────

class _CreateForeverLetterSheet extends StatefulWidget {
  const _CreateForeverLetterSheet({
    required this.controller,
    required this.isPro,
    required this.isLifetime,
    this.editEntry,
    this.editPayload,
  });

  final VaultController controller;
  final bool isPro;
  final bool isLifetime;
  final VaultEntry? editEntry;
  final VaultEntryPayload? editPayload;

  @override
  State<_CreateForeverLetterSheet> createState() =>
      _CreateForeverLetterSheetState();
}

class _CreateForeverLetterSheetState
    extends State<_CreateForeverLetterSheet> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  DateTime? _selectedDate;
  bool _saving = false;
  String? _error;

  // Audio
  bool _isAudioMode = false;
  AudioRecorder? _recorder;
  AudioRecorder get _rec => _recorder ??= AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedFilePath;
  int? _recordedDurationSeconds;
  bool _savedSuccessfully = false;
  bool _audioUsageLoaded = false;

  // Audio playback preview
  AudioPlayer? _previewPlayer;

  bool get _isEditing => widget.editEntry != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleCtrl.text = widget.editEntry!.title;
      _recipientCtrl.text = widget.editPayload?.recipientEmail ?? '';
      _selectedDate = widget.editEntry!.scheduledAt;
      _isAudioMode = widget.editEntry!.dataType == VaultDataType.audio;
      if (!_isAudioMode) {
        _messageCtrl.text = widget.editPayload?.plaintext ?? '';
      }
    }
    _ensureAudioUsage();
  }

  Future<void> _ensureAudioUsage() async {
    await widget.controller.loadEntries();
    if (mounted) setState(() => _audioUsageLoaded = true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _recipientCtrl.dispose();
    _recordTimer?.cancel();
    if ((_isRecording || _isPaused) && _recorder != null) {
      unawaited(_recorder!.stop());
    }
    _recorder?.dispose();
    if (!_savedSuccessfully && _recordedFilePath != null) {
      final path = _recordedFilePath!;
      File(path).delete().catchError((_) => File(path));
    }
    _previewPlayer?.dispose();
    super.dispose();
  }

  // ── Audio recording ──

  Future<void> _startRecording(int maxSeconds) async {
    if (_isRecording || _isPaused) return;
    final hasPermission = await _rec.hasPermission();
    if (!hasPermission) {
      setState(() => _error = 'Microphone permission denied.');
      return;
    }
    await _discardRecording();
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/afterword_fl_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _recordedFilePath = path;
      _recordSeconds = 0;
      _error = null;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _recordSeconds++);
      if (_recordSeconds >= maxSeconds) {
        await _stopRecording();
      }
    });
  }

  Future<void> _pauseRecording() async {
    await _rec.pause();
    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isPaused = true;
    });
  }

  Future<void> _resumeRecording(int maxSeconds) async {
    await _rec.resume();
    setState(() {
      _isRecording = true;
      _isPaused = false;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _recordSeconds++);
      if (_recordSeconds >= maxSeconds) {
        await _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    final effectivePath = path ?? _recordedFilePath;
    final duration = _recordSeconds > 0 ? _recordSeconds : null;
    if (duration == null && effectivePath != null) {
      try {
        await File(effectivePath).delete();
      } catch (_) {}
    }
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordedFilePath = duration != null ? effectivePath : null;
      _recordedDurationSeconds = duration;
    });
  }

  Future<void> _discardRecording() async {
    _recordTimer?.cancel();
    if ((_isRecording || _isPaused) && _recorder != null) {
      try {
        await _recorder!.stop();
      } catch (_) {}
    }
    if (_recordedFilePath != null) {
      try {
        await File(_recordedFilePath!).delete();
      } catch (_) {}
    }
    _previewPlayer?.dispose();
    _previewPlayer = null;
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordedFilePath = null;
      _recordedDurationSeconds = null;
      _recordSeconds = 0;
    });
  }

  Future<void> _togglePreview() async {
    if (_recordedFilePath == null) return;
    _previewPlayer ??= AudioPlayer();
    final player = _previewPlayer!;
    final state = player.playerState;
    if (state.playing) {
      await player.pause();
    } else {
      if (state.processingState == ProcessingState.completed ||
          state.processingState == ProcessingState.idle) {
        await player.setFilePath(_recordedFilePath!);
      }
      player.play();
    }
    setState(() {});
  }

  // ── Save ──

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final recipient = _recipientCtrl.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give your letter a title.');
      return;
    }
    if (_isAudioMode) {
      // For editing audio entries, allow keeping existing audio
      if (_recordedFilePath == null && !_isEditing) {
        setState(() => _error = 'Record an audio message first.');
        return;
      }
    } else {
      if (_messageCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Write something before saving.');
        return;
      }
    }
    if (recipient.isEmpty) {
      setState(() => _error = 'Recipient email is required.');
      return;
    }
    if (_selectedDate == null) {
      setState(() => _error = 'Select a delivery date.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final draft = VaultEntryDraft(
      title: title,
      plaintext: _isAudioMode ? '' : _messageCtrl.text.trim(),
      recipientEmail: recipient,
      actionType: VaultActionType.send,
      dataType: _isAudioMode ? VaultDataType.audio : VaultDataType.text,
      scheduledAt: _selectedDate,
      entryMode: 'recurring',
      audioFilePath: _isAudioMode ? _recordedFilePath : null,
      audioDurationSeconds: _isAudioMode ? _recordedDurationSeconds : null,
    );

    bool success;
    if (_isEditing) {
      success = await widget.controller.updateEntry(
        widget.editEntry!,
        draft,
        isPro: widget.isPro,
        isLifetime: widget.isLifetime,
      );
    } else {
      success = await widget.controller.createEntry(
        draft,
        isPro: widget.isPro,
        isLifetime: widget.isLifetime,
      );
    }

    if (!mounted) return;

    if (success) {
      _savedSuccessfully = true;
      if (_recordedFilePath != null) {
        try {
          await File(_recordedFilePath!).delete();
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.errorMessage ?? 'Failed to save.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final dateLabel = _selectedDate != null
        ? DateFormat('MMMM d').format(_selectedDate!)
        : 'Select date';

    // Audio time bank
    final timeBankLimit =
        VaultController.audioTimeBankFor(isLifetime: widget.isLifetime);
    final audioUsed = widget.controller.audioSecondsUsed;
    final existingAudioSec =
        _isEditing ? (widget.editEntry!.audioDurationSeconds ?? 0) : 0;
    final remainingSeconds =
        (timeBankLimit - audioUsed + existingAudioSec).clamp(0, timeBankLimit);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + bottomInset + bottomPad),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                  _isEditing
                      ? 'Edit Forever Letter'
                      : 'New Forever Letter',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'This message will be sent every year on the date you choose.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38),
              ),
              const SizedBox(height: 20),
              // Title
              TextField(
                controller: _titleCtrl,
                style: theme.textTheme.bodyMedium,
                decoration: _inputDecoration(theme, 'Title'),
                maxLength: 80,
              ),
              const SizedBox(height: 8),
              // Recipient
              TextField(
                controller: _recipientCtrl,
                style: theme.textTheme.bodyMedium,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(theme, 'Recipient email'),
              ),
              const SizedBox(height: 12),
              // Date picker
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16, color: Colors.white38),
                      const SizedBox(width: 10),
                      Text(
                        dateLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _selectedDate != null
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                      const Spacer(),
                      Text('Every year',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Data type toggle (text / audio)
              Row(
                children: [
                  Expanded(
                    child: _ToggleChip(
                      label: 'Text',
                      icon: Icons.edit_note,
                      selected: !_isAudioMode,
                      onTap: () {
                        if (!_isAudioMode) return;
                        setState(() => _isAudioMode = false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ToggleChip(
                      label: 'Audio',
                      icon: Icons.mic,
                      selected: _isAudioMode,
                      onTap: () {
                        if (_isAudioMode) return;
                        setState(() => _isAudioMode = true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Content area
              if (_isAudioMode)
                _buildAudioControls(theme, remainingSeconds, timeBankLimit)
              else
                TextField(
                  controller: _messageCtrl,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 6,
                  minLines: 4,
                  maxLength: VaultController.maxPlaintextLength,
                  decoration:
                      _inputDecoration(theme, 'Your message',
                          alignHint: true),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              // Consent
              Text(
                'By saving, I confirm this message will be encrypted and delivered to my recipient every year on the selected date.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white30),
              ),
              const SizedBox(height: 16),
              // Save
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_saving || _isRecording || _isPaused)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white38))
                      : Text(_isEditing
                          ? 'Save Changes'
                          : 'Seal Forever Letter'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioControls(
      ThemeData theme, int remainingSeconds, int timeBankLimit) {
    final hasRecording = _recordedFilePath != null && !_isRecording && !_isPaused;
    final isEditingAudioEntry =
        _isEditing && widget.editEntry!.dataType == VaultDataType.audio;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          // Time bank
          if (_audioUsageLoaded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    '${remainingSeconds}s remaining of ${timeBankLimit}s',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          // Recording in progress
          if (_isRecording || _isPaused)
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isRecording)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                    if (_isRecording) const SizedBox(width: 8),
                    Text(
                      '${_recordSeconds}s',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _isPaused
                          ? () => _resumeRecording(remainingSeconds)
                          : _pauseRecording,
                      icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _stopRecording,
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ],
            )
          else if (hasRecording)
            // Playback preview + re-record
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle,
                        size: 16,
                        color: Colors.green.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Text(
                      'Recorded ${_recordedDurationSeconds ?? 0}s',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _togglePreview,
                      icon: StreamBuilder<PlayerState>(
                        stream: _previewPlayer?.playerStateStream,
                        builder: (_, snap) {
                          final playing =
                              snap.data?.playing ?? false;
                          return Icon(
                              playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 16);
                        },
                      ),
                      label: const Text('Preview'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _discardRecording();
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Re-record'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            // Start recording or show existing audio info
            Column(
              children: [
                if (isEditingAudioEntry && _recordedFilePath == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Current audio: ${widget.editEntry!.audioDurationSeconds ?? 0}s. Record new to replace.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white38),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (!_audioUsageLoaded || remainingSeconds <= 0)
                        ? null
                        : () => _startRecording(remainingSeconds),
                    icon: const Icon(Icons.mic, size: 18),
                    label: Text(remainingSeconds <= 0
                        ? 'Time bank empty'
                        : 'Start Recording'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, String label,
      {bool alignHint = false}) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignHint,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                surface: const Color(0xFF1A1A1A),
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate =
            DateTime.utc(picked.year, picked.month, picked.day, 12, 0, 0);
      });
    }
  }
}

// ─── Toggle chip for text/audio mode ────────────────────────────

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.3)
                : Colors.white12,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? accent : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? accent : Colors.white38,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
