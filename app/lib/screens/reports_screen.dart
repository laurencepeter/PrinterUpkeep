import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  if (_selected != null)
                    MenuAnchor(
                      builder: (context, controller, _) => OutlinedButton.icon(
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in items)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
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
                    : _ReportTable(reportKey: _selected!),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportTable extends ConsumerWidget {
  const _ReportTable({required this.reportKey});

  final String reportKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(_reportDataProvider(reportKey));
    return report.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (data) {
        final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
        if (rows.isEmpty) return const Center(child: Text('No data for this report yet'));
        final columns = rows.first.keys.toList();
        return Card(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final c in columns)
                    DataColumn(label: Text(c.replaceAll('_', ' ').toUpperCase())),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(cells: [
                      for (final c in columns) DataCell(Text('${row[c] ?? '—'}')),
                    ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
