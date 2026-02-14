import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.userId});
  final String userId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _fmt = DateFormat('MMM d, yyyy · h:mm a');
  bool _loading = true;
  List<_HistoryGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // Fetch sent entries (grace period — still viewable)
      // Only show 'send' type entries in history — 'destroy' entries leave no trace
      final sentRows = await client
          .from('vault_entries')
          .select('id, title, action_type, data_type, sent_at')
          .eq('user_id', widget.userId)
          .eq('status', 'sent')
          .eq('action_type', 'send')
          .order('sent_at', ascending: false);

      // Fetch tombstones (permanently deleted after 30-day grace)
      final tombRows = await client
          .from('vault_entry_tombstones')
          .select('vault_entry_id, sender_name, sent_at, expired_at')
          .eq('user_id', widget.userId)
          .order('expired_at', ascending: false);

      // Group by execution date (sent_at date)
      final Map<String, _HistoryGroup> groups = {};

      for (final row in sentRows as List) {
        final sentAt = DateTime.parse(row['sent_at'] as String);
        final dateKey = DateFormat('yyyy-MM-dd').format(sentAt.toLocal());
        final group = groups.putIfAbsent(
            dateKey,
            () => _HistoryGroup(
                  executionDate: sentAt,
                  sentItems: [],
                  deletedItems: [],
                ));
        group.sentItems.add(_SentItem(
          title: (row['title'] as String?) ?? 'Untitled',
          actionType: (row['action_type'] as String?) ?? 'send',
          dataType: (row['data_type'] as String?) ?? 'text',
          sentAt: sentAt,
        ));
      }

      for (final row in tombRows as List) {
        final expiredAt = DateTime.parse(row['expired_at'] as String);
        final sentAt = row['sent_at'] != null
            ? DateTime.parse(row['sent_at'] as String)
            : null;
        final dateKey = sentAt != null
            ? DateFormat('yyyy-MM-dd').format(sentAt.toLocal())
            : DateFormat('yyyy-MM-dd').format(expiredAt.toLocal());
        final group = groups.putIfAbsent(
            dateKey,
            () => _HistoryGroup(
                  executionDate: sentAt ?? expiredAt,
                  sentItems: [],
                  deletedItems: [],
                ));
        group.deletedItems.add(_DeletedItem(
          expiredAt: expiredAt,
        ));
      }

      final sorted = groups.values.toList()
        ..sort((a, b) => b.executionDate.compareTo(a.executionDate));

      if (mounted) setState(() { _groups = sorted; _loading = false; });
    } catch (e) {
      debugPrint('History load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text(
                        'No history yet',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white38),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Protocol executions will appear here.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white24),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    itemCount: _groups.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (_, i) =>
                        _HistoryGroupCard(group: _groups[i], fmt: _fmt),
                  ),
                ),
    );
  }
}

class _HistoryGroup {
  _HistoryGroup({
    required this.executionDate,
    required this.sentItems,
    required this.deletedItems,
  });
  final DateTime executionDate;
  final List<_SentItem> sentItems;
  final List<_DeletedItem> deletedItems;
}

class _SentItem {
  const _SentItem({
    required this.title,
    required this.actionType,
    required this.dataType,
    required this.sentAt,
  });
  final String title;
  final String actionType;
  final String dataType;
  final DateTime sentAt;
}

class _DeletedItem {
  const _DeletedItem({required this.expiredAt});
  final DateTime expiredAt;
}

class _HistoryGroupCard extends StatelessWidget {
  const _HistoryGroupCard({required this.group, required this.fmt});
  final _HistoryGroup group;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('MMM d, yyyy');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF181818),
            const Color(0xFF0E0E0E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Execution date header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_outlined,
                      size: 16, color: theme.colorScheme.error),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Protocol Executed · ${dateFmt.format(group.executionDate.toLocal())}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // Sent items
            if (group.sentItems.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...group.sentItems.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          item.actionType == 'destroy'
                              ? Icons.delete_forever
                              : item.dataType == 'audio'
                                  ? Icons.mic
                                  : Icons.mail_outline,
                          size: 16,
                          color: item.actionType == 'destroy'
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item.actionType == 'destroy'
                                ? theme.colorScheme.error
                                    .withValues(alpha: 0.12)
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.actionType == 'destroy'
                                ? 'DESTROYED'
                                : 'SENT',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: item.actionType == 'destroy'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              Text(
                'Sent items are read-only. Auto-deleted after 30 days.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],

            // Deleted items
            if (group.deletedItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.delete_sweep,
                      size: 16, color: Colors.white38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Data permanently erased on ${dateFmt.format(group.deletedItems.first.expiredAt.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
