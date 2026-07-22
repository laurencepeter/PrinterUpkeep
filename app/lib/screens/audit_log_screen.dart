import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// Administrator audit trail: who accessed the system and who created, changed
/// or deleted records, most recent first. Backed by /api/audit-logs.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  static const _entityFilters = [
    (value: null, label: 'All'),
    (value: 'printer', label: 'Printers'),
    (value: 'ticket', label: 'Tickets'),
    (value: 'user', label: 'Users & logins'),
    (value: 'vendor', label: 'Vendors'),
    (value: 'setting', label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.user?.isAdmin != true) {
      return const Center(child: Text('Only administrators can view the audit log.'));
    }
    final logs = ref.watch(auditLogProvider);
    final filters = ref.watch(auditFiltersProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Audit Log', style: Theme.of(context).textTheme.headlineSmall),
              ),
              for (final f in _entityFilters)
                ChoiceChip(
                  label: Text(f.label),
                  selected: filters.entityType == f.value,
                  onSelected: (_) => ref.read(auditFiltersProvider.notifier).state =
                      filters.copyWith(entityType: () => f.value, page: 1),
                ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(auditLogProvider),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: logs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (page) {
                if (page.items.isEmpty) {
                  return const Center(child: Text('No audit entries'));
                }
                return Column(
                  children: [
                    Expanded(
                      child: Card(
                        child: ListView.separated(
                          itemCount: page.items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => _AuditTile(page.items[i]),
                        ),
                      ),
                    ),
                    _pager(context, ref, page, filters),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager(BuildContext context, WidgetRef ref, AuditLogPage page, AuditFilters filters) {
    final totalPages = (page.total / page.pageSize).ceil().clamp(1, 1 << 30);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${page.total} entries · page ${page.page} of $totalPages',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: page.page > 1
                ? () => ref.read(auditFiltersProvider.notifier).state =
                    filters.copyWith(page: page.page - 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: page.page < totalPages
                ? () => ref.read(auditFiltersProvider.notifier).state =
                    filters.copyWith(page: page.page + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile(this.entry);

  final AuditLogEntry entry;

  static const _actionColors = {
    'create': Color(0xFF2E7D32),
    'update': Color(0xFF1565C0),
    'delete': Color(0xFFC62828),
    'login': Color(0xFF6A1B9A),
    'stage_change': Color(0xFFEF6C00),
  };

  IconData get _icon => switch (entry.action) {
        'create' => Icons.add_circle_outline,
        'update' => Icons.edit_outlined,
        'delete' => Icons.delete_outline,
        'login' => Icons.login,
        'stage_change' => Icons.sync_alt,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final color = _actionColors[entry.action] ?? const Color(0xFF616161);
    final when = DateTime.tryParse(entry.createdAt);
    final whenText =
        when == null ? entry.createdAt : DateFormat('y-MM-dd HH:mm').format(when.toLocal());

    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(_icon, size: 18, color: color),
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(
            text: entry.userName?.isNotEmpty == true ? entry.userName : 'System',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: '  ${_actionLabel(entry)} '),
        TextSpan(
            text: entry.entityType,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ])),
      subtitle: _detail(context),
      trailing: Text(whenText, style: Theme.of(context).textTheme.bodySmall),
      isThreeLine: entry.oldValue != null || entry.newValue != null,
    );
  }

  String _actionLabel(AuditLogEntry e) => switch (e.action) {
        'create' => 'created',
        'update' => 'updated',
        'delete' => 'deleted',
        'login' => 'signed in —',
        'stage_change' => 'advanced',
        _ => e.action,
      };

  Widget? _detail(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (entry.action == 'login') return null;
    final parts = <String>[];
    if (entry.field != null) parts.add(entry.field!);
    final change = [
      if (entry.oldValue != null) _short(entry.oldValue!),
      if (entry.newValue != null) _short(entry.newValue!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty) Text(parts.join(' · '), style: style),
        if (change.isNotEmpty)
          Text(change.join('  →  '), style: style?.copyWith(fontStyle: FontStyle.italic)),
      ],
    );
  }

  static String _short(String v) => v.length > 120 ? '${v.substring(0, 120)}…' : v;
}
