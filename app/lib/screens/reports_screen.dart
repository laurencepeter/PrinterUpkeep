import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

final _reportsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/reports');
  return (data as List).cast<Map<String, dynamic>>();
});

final _reportDataProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, key) async {
  final data = await ref.read(apiProvider).get('/api/reports/$key', query: {'format': 'json'});
  return data as Map<String, dynamic>;
});

/// An icon per report key so the selector reads at a glance.
IconData _reportIcon(String key) => switch (key) {
      'monthly-repairs' => Icons.calendar_month,
      'vendor-performance' => Icons.storefront_outlined,
      'department-usage' => Icons.apartment_outlined,
      'average-repair-time' => Icons.timer_outlined,
      'consumables-cost' => Icons.water_drop_outlined,
      'common-issues' => Icons.report_problem_outlined,
      'most-repaired-printers' => Icons.build_outlined,
      'printer-activity' => Icons.print_outlined,
      'tickets-by-officer' => Icons.badge_outlined,
      'user-completion' => Icons.task_alt,
      'approvals-by-department' => Icons.approval_outlined,
      'owned-vs-leased' => Icons.compare_arrows,
      _ => Icons.bar_chart,
    };

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(_reportsListProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: reports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          _selected ??= items.isEmpty ? null : items.first['key'] as String;
          final selectedTitle = items.firstWhere((r) => r['key'] == _selected,
              orElse: () => <String, dynamic>{})['title'];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  if (_selected != null)
                    MenuAnchor(
                      builder: (context, controller, _) => FilledButton.tonalIcon(
                        icon: const Icon(Icons.download),
                        label: const Text('Export report'),
                        onPressed: () =>
                            controller.isOpen ? controller.close() : controller.open(),
                      ),
                      menuChildren: [
                        for (final f in ['csv', 'xlsx', 'pdf', 'json'])
                          MenuItemButton(
                            child: Text(f.toUpperCase()),
                            onPressed: () => launchUrlString(ref
                                .read(apiProvider)
                                .downloadUrl('/api/reports/$_selected?format=$f')),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Report selector.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in items)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(_reportIcon(r['key'] as String),
                              size: 18,
                              color: _selected == r['key']
                                  ? Theme.of(context).colorScheme.onSecondaryContainer
                                  : Theme.of(context).colorScheme.primary),
                          label: Text(r['title'] as String),
                          selected: _selected == r['key'],
                          onSelected: (_) => setState(() => _selected = r['key'] as String),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _selected == null
                    ? const Center(child: Text('Select a report'))
                    : _ReportView(reportKey: _selected!, title: '${selectedTitle ?? ''}'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportView extends ConsumerWidget {
  const _ReportView({required this.reportKey, required this.title});

  final String reportKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(_reportDataProvider(reportKey));
    return report.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (data) {
        final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
        if (rows.isEmpty) {
          return const Center(child: Text('No data for this report yet'));
        }
        final columns = rows.first.keys.toList();

        // Which columns are numeric (for right-alignment + heat bars), scaled to
        // the column's own max. Skip identifier/date/text columns.
        final numericMax = <String, double>{};
        for (final c in columns) {
          if (_isTextColumn(c)) continue;
          double? maxv;
          var allNum = true;
          var any = false;
          for (final r in rows) {
            final s = r[c]?.toString() ?? '';
            if (s.isEmpty) continue;
            final n = double.tryParse(s);
            if (n == null) {
              allNum = false;
              break;
            }
            any = true;
            maxv = (maxv == null || n > maxv) ? n : maxv;
          }
          if (allNum && any && maxv != null && maxv > 0) numericMax[c] = maxv;
        }

        final scheme = Theme.of(context).colorScheme;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Icon(_reportIcon(reportKey), color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${rows.length} rows',
                          style: TextStyle(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                      columns: [
                        for (final c in columns)
                          DataColumn(
                            numeric: numericMax.containsKey(c),
                            label: Text(_prettyHeader(c),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ],
                      rows: [
                        for (var i = 0; i < rows.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? null : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            ),
                            cells: [
                              for (var j = 0; j < columns.length; j++)
                                DataCell(_buildCell(context, columns[j], rows[i][columns[j]],
                                    isFirst: j == 0, numericMax: numericMax)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, String col, dynamic value,
      {required bool isFirst, required Map<String, double> numericMax}) {
    final scheme = Theme.of(context).colorScheme;
    final text = value?.toString() ?? '—';

    // Numeric → right-aligned value over a proportional heat bar.
    if (numericMax.containsKey(col) && text.isNotEmpty && text != '—') {
      final n = double.tryParse(text) ?? 0;
      final frac = (n / numericMax[col]!).clamp(0.0, 1.0);
      final isPct = col.contains('pct') || col.contains('percent');
      final barColor = isPct ? _pctColor(n) : scheme.primary;
      const barW = 96.0;
      return SizedBox(
        width: barW,
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: (barW * frac).clamp(3.0, barW),
                height: 22,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(isPct ? '$text%' : text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    // Status / priority / decision-like columns → coloured pill.
    final pill = _pillColor(col, text.toLowerCase());
    if (pill != null && text != '—') {
      return _pill(text, pill);
    }

    return Text(text,
        style: isFirst ? const TextStyle(fontWeight: FontWeight.w600) : null);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );

  static bool _isTextColumn(String c) {
    const textish = [
      'number', 'date', 'month', 'name', 'model', 'asset', 'serial', 'ip',
      'username', 'officer', 'vendor', 'department', 'issue', 'user', 'type',
      'status', 'decision', 'approval', 'priority',
    ];
    return textish.any((t) => c.contains(t));
  }

  static String _prettyHeader(String c) =>
      c.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  static Color _pctColor(double v) {
    if (v >= 75) return const Color(0xFF2E7D32);
    if (v >= 40) return const Color(0xFFF9A825);
    return const Color(0xFFC62828);
  }

  /// Colour for status/priority/decision-style columns, by column name + value.
  static Color? _pillColor(String col, String v) {
    if (col.contains('priority')) return PriorityColors.forPriority(v);
    final isStatusish = col.contains('status') ||
        col.contains('decision') ||
        col.contains('approval') ||
        col == 'type' ||
        col.contains('printer_type');
    if (!isStatusish) return null;
    const green = Color(0xFF2E7D32);
    const red = Color(0xFFC62828);
    const amber = Color(0xFFF9A825);
    const blue = Color(0xFF1565C0);
    const slate = Color(0xFF546E7A);
    for (final kw in ['active', 'completed', 'approved', 'funds_available', 'done', 'closed', 'owned']) {
      if (v.contains(kw)) return green;
    }
    for (final kw in ['disposed', 'rejected', 'cancelled', 'blocked', 'overdue', 'not available']) {
      if (v.contains(kw)) return red;
    }
    for (final kw in ['repair', 'inactive', 'pending', 'awaiting', 'progress', 'wip', 'leased']) {
      if (v.contains(kw)) return amber;
    }
    if (v.contains('owned')) return blue;
    return slate;
  }
}
