import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
          // Sort by month/day
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
                                    size: 18,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'HOW IT WORKS',
                                  style:
                                      theme.textTheme.labelSmall?.copyWith(
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
                                text:
                                    'Write a message and pick a date.',
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
                                    'Letters are permanent \u2014 no edits, no deletions.',
                                theme: theme),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Capacity info
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: Colors.white38),
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
                              : () => _openCreateSheet(
                                  context, isPro, isLifetime),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Forever Letter'),
                        ),
                      ),
                      if (atLimit) ...[
                        const SizedBox(height: 8),
                        Text(
                          'All $maxEntries entry slots are in use across your vault.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white38),
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
                              ),
                            )),
                    ],
                  ),
          ),
        ],
      ),
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
      // Refresh home screen vault count
      if (ctx.mounted) {
        ctx.read<HomeController>().refreshVaultStatus();
      }
    }
  }
}

// ─── Readonly card for each recurring entry ─────────────────────

class _ForeverLetterCard extends StatelessWidget {
  const _ForeverLetterCard({required this.entry, required this.theme});

  final VaultEntry entry;
  final ThemeData theme;

  /// Next delivery date for this entry's month/day.
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
    final monthDay = date != null
        ? DateFormat('MMMM d').format(date)
        : '—';
    final lastSent = entry.lastSentYear;
    final isAudio = entry.dataType == VaultDataType.audio;
    final now = DateTime.now().toUtc();
    final next = _nextDelivery();
    final accent = theme.colorScheme.primary;

    // Progress calculation
    String statusText;
    String progressLabel;
    double progress = 0.0;
    Color progressColor = accent.withValues(alpha: 0.6);

    if (lastSent != null && lastSent >= now.year && date != null) {
      // Already sent this year — waiting for next year
      final sentDate = DateTime.utc(now.year, date.month, date.day, 12);
      final nextDate = DateTime.utc(now.year + 1, date.month, date.day, 12);
      final totalDays = nextDate.difference(sentDate).inDays;
      final elapsedDays = now.difference(sentDate).inDays;
      progress = totalDays > 0 ? (elapsedDays / totalDays).clamp(0.0, 1.0) : 0.0;
      statusText = 'Sent for $lastSent';
      final daysLeft = nextDate.difference(now).inDays;
      progressLabel = '$daysLeft day${daysLeft == 1 ? '' : 's'} until next delivery';
      progressColor = Colors.green.withValues(alpha: 0.5);
    } else if (next != null) {
      // Awaiting delivery
      final daysUntil = next.difference(now).inDays;
      final created = entry.createdAt.toUtc();
      final totalDays = next.difference(created).inDays;
      final elapsed = now.difference(created).inDays;
      progress = totalDays > 0 ? (elapsed / totalDays).clamp(0.0, 1.0) : 0.0;

      if (daysUntil <= 0) {
        statusText = 'Delivering soon';
        progressLabel = 'Delivery imminent';
        progress = 1.0;
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + title + audio badge
          Row(
            children: [
              Icon(
                Icons.all_inclusive,
                size: 16,
                color: accent.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAudio)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.mic, size: 14, color: Colors.white38),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Status line
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
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
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
          // Progress label
          Text(
            progressLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

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
          Text(
            'No forever letters yet',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: Colors.white30),
          ),
          const SizedBox(height: 4),
          Text(
            'Create one to send a message every year.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: Colors.white24),
          ),
        ],
      ),
    );
  }
}

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

// ─── Create sheet ───────────────────────────────────────────────

class _CreateForeverLetterSheet extends StatefulWidget {
  const _CreateForeverLetterSheet({
    required this.controller,
    required this.isPro,
    required this.isLifetime,
  });

  final VaultController controller;
  final bool isPro;
  final bool isLifetime;

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

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _recipientCtrl.dispose();
    super.dispose();
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
        // Store as UTC noon on the picked month/day
        _selectedDate =
            DateTime.utc(picked.year, picked.month, picked.day, 12, 0, 0);
      });
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    final recipient = _recipientCtrl.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give your letter a title.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = 'Write something before saving.');
      return;
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
      plaintext: message,
      recipientEmail: recipient,
      actionType: VaultActionType.send,
      dataType: VaultDataType.text,
      scheduledAt: _selectedDate,
      entryMode: 'recurring',
    );

    final success = await widget.controller.createEntry(
      draft,
      isPro: widget.isPro,
      isLifetime: widget.isLifetime,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
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
    final dateLabel = _selectedDate != null
        ? DateFormat('MMMM d').format(_selectedDate!)
        : 'Select date';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('New Forever Letter',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
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
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                ),
                maxLength: 80,
              ),
              const SizedBox(height: 8),
              // Recipient
              TextField(
                controller: _recipientCtrl,
                style: theme.textTheme.bodyMedium,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Recipient email',
                  labelStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Date picker
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                      Text(
                        'Every year',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Message
              TextField(
                controller: _messageCtrl,
                style: theme.textTheme.bodyMedium,
                maxLines: 6,
                minLines: 4,
                maxLength: VaultController.maxPlaintextLength,
                decoration: InputDecoration(
                  labelText: 'Your message',
                  alignLabelWithHint: true,
                  labelStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                ),
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
                'By saving, I confirm this message will be encrypted and delivered to my recipient every year on the selected date. '
                'Forever letters cannot be edited or deleted.',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white30),
              ),
              const SizedBox(height: 16),
              // Save
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white38))
                      : const Text('Seal Forever Letter'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
