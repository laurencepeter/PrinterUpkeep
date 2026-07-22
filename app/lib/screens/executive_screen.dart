import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/charts.dart';

/// Executive summary: the headline numbers and supporting breakdowns the ICT
/// team can put in front of management to justify staffing and spend — total
/// workload, what is still open, how quickly issues are resolved, workload per
/// officer and the most troublesome printers. Exportable to PDF/Excel.
class ExecutiveScreen extends ConsumerWidget {
  const ExecutiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(executiveSummaryProvider);
    final api = ref.read(apiProvider);

    return summary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (data) {
        final kpis = (data['kpis'] as Map).cast<String, dynamic>();
        final byOfficer = (data['by_officer'] as List).cast<Map<String, dynamic>>();
        final topPrinters = (data['top_printers'] as List).cast<Map<String, dynamic>>();
        final monthly = (data['monthly'] as List).cast<Map<String, dynamic>>();
        final byIssue = (data['by_issue'] as List).cast<Map<String, dynamic>>();
        final generated = _s(data['generated_at']);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Executive Summary',
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (generated != null)
                        Text('Generated ${generated.replaceFirst('T', ' ').substring(0, 16)}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(executiveSummaryProvider),
                ),
                const SizedBox(width: 4),
                MenuAnchor(
                  builder: (context, controller, _) => OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Export'),
                    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  ),
                  menuChildren: [
                    for (final r in const [
                      ('printer-activity', 'Printer activity log'),
                      ('tickets-by-officer', 'Workload by ICT officer'),
                      ('most-repaired-printers', 'Most active printers'),
                    ])
                      for (final f in const ['pdf', 'xlsx', 'csv'])
                        MenuItemButton(
                          child: Text('${r.$2} (${f.toUpperCase()})'),
                          onPressed: () => launchUrlString(
                              api.downloadUrl('/api/reports/${r.$1}?format=$f')),
                        ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _kpiGrid(context, kpis),
            const SizedBox(height: 20),
            _section(
              context,
              'Monthly issue volume',
              'Issues logged per month over the last year',
              MonthlyBarChart(
                points: [
                  for (final m in monthly)
                    ChartPoint.fromJson({'label': m['month'], 'count': m['total']}),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              context,
              'Workload by ICT officer',
              'Issues assigned to and resolved by each officer',
              byOfficer.isEmpty
                  ? const Text('No assigned issues yet')
                  : _officerTable(context, byOfficer),
            ),
            const SizedBox(height: 16),
            _section(
              context,
              'Most active printers',
              'The printers generating the most support work',
              topPrinters.isEmpty
                  ? const Text('No issues logged yet')
                  : _printersTable(context, topPrinters),
            ),
            const SizedBox(height: 16),
            _section(
              context,
              'Most common issues',
              'What the team spends its time on',
              HorizontalBarList(
                points: [
                  for (final i in byIssue)
                    ChartPoint.fromJson({'label': i['issue'], 'count': i['count']}),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiGrid(BuildContext context, Map<String, dynamic> k) {
    final scheme = Theme.of(context).colorScheme;
    final cards = [
      _Kpi('Total issues', '${k['total_issues'] ?? 0}', Icons.confirmation_number_outlined, scheme.primary),
      _Kpi('Still open', '${k['open_issues'] ?? 0}', Icons.pending_actions, const Color(0xFFEF6C00)),
      _Kpi('Resolved', '${k['resolved_issues'] ?? 0}', Icons.check_circle_outline, const Color(0xFF2E7D32)),
      _Kpi('Avg resolution', k['avg_resolution_days'] == null ? '—' : '${k['avg_resolution_days']} d',
          Icons.timer_outlined, const Color(0xFF1565C0)),
      _Kpi('Issues this month', '${k['issues_this_month'] ?? 0}', Icons.calendar_month, scheme.primary),
      _Kpi('Last 30 days', '${k['issues_last_30_days'] ?? 0}', Icons.trending_up, const Color(0xFF6A1B9A)),
      _Kpi('Printers serviced', '${k['printers_serviced'] ?? 0}', Icons.build_outlined, const Color(0xFF00695C)),
      _Kpi('Printers managed', '${k['printers_managed'] ?? 0}', Icons.print_outlined, scheme.primary),
      _Kpi('In repair now', '${k['printers_in_repair'] ?? 0}', Icons.build_circle, const Color(0xFFF9A825)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: as many ~220px cards per row as fit (min 1).
        final perRow = (constraints.maxWidth / 230).floor().clamp(1, cards.length);
        final width = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in cards)
              SizedBox(
                width: width,
                child: StatCard(label: c.label, value: c.value, icon: c.icon, color: c.color),
              ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, String subtitle, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _officerTable(BuildContext context, List<Map<String, dynamic>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Officer')),
          DataColumn(label: Text('Assigned'), numeric: true),
          DataColumn(label: Text('Completed'), numeric: true),
          DataColumn(label: Text('Avg days'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('${r['officer'] ?? '—'}')),
              DataCell(Text('${r['assigned'] ?? 0}')),
              DataCell(Text('${r['completed'] ?? 0}')),
              DataCell(Text('${r['avg_days'] ?? '—'}')),
            ]),
        ],
      ),
    );
  }

  Widget _printersTable(BuildContext context, List<Map<String, dynamic>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Asset #')),
          DataColumn(label: Text('Model')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Department')),
          DataColumn(label: Text('Issues'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('${r['asset_number'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('${r['model'] ?? '—'}')),
              DataCell(Text('${r['printer_type'] ?? '—'}')),
              DataCell(Text('${r['department'] ?? '—'}')),
              DataCell(Text('${r['repairs'] ?? 0}')),
            ]),
        ],
      ),
    );
  }

  static String? _s(dynamic v) => v?.toString();
}

class _Kpi {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
