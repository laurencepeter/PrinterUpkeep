import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../core/theme.dart';
import '../providers/providers.dart';
import '../widgets/workflow_tracker.dart';

const kStatusLabels = [
  'Open', 'Vendor Contacted', 'Awaiting Quote', 'Awaiting Funds', 'Awaiting Accounts',
  'Awaiting GA', 'Awaiting Purchase Order', 'Work In Progress', 'Completed', 'Closed', 'Cancelled',
];

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final filters = ref.watch(ticketFiltersProvider);
    final auth = ref.watch(authProvider);
    final departments = ref.watch(departmentsProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final officers = (ref.watch(usersProvider).valueOrNull ?? [])
        .where((u) => u.isActive && (u.role == 'admin' || u.role == 'ict_officer'))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tickets', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              MenuAnchor(
                builder: (context, controller, _) => OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export'),
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                ),
                menuChildren: [
                  for (final f in ['csv', 'xlsx', 'pdf', 'json'])
                    MenuItemButton(
                      child: Text(f.toUpperCase()),
                      onPressed: () {
                        final api = ref.read(apiProvider);
                        launchUrlString(api.downloadUrl('/api/export/tickets?format=$f'));
                      },
                    ),
                ],
              ),
              const SizedBox(width: 8),
              if (auth.user?.canWrite == true)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New Ticket'),
                  onPressed: () => context.go('/tickets/new'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Filter bar — dropdown-driven, minimal typing.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (filters.printerId != null)
                InputChip(
                  avatar: const Icon(Icons.print, size: 16),
                  label: Text('Printer: ${filters.printerLabel ?? filters.printerId}'),
                  onDeleted: () => _update((f) => f.copyWith(
                      printerId: () => null, printerLabel: () => null, page: 1)),
                ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search ticket #, reporter…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _search.clear();
                              _update((f) => f.copyWith(search: () => null, page: 1));
                            },
                          ),
                  ),
                  onSubmitted: (v) => _update((f) => f.copyWith(search: () => v, page: 1)),
                ),
              ),
              _dropdown<String>(
                hint: 'Status',
                value: filters.status,
                items: kStatusLabels,
                label: (s) => s,
                onChanged: (v) => _update((f) => f.copyWith(status: () => v, page: 1)),
              ),
              _dropdown<String>(
                hint: 'Department',
                value: filters.departmentId,
                items: departments.map((d) => d.id).toList(),
                label: (id) => departments.firstWhere((d) => d.id == id).name,
                onChanged: (v) => _update((f) => f.copyWith(departmentId: () => v, page: 1)),
              ),
              _dropdown<String>(
                hint: 'Vendor',
                value: filters.vendorId,
                items: vendors.map((v) => v.id).toList(),
                label: (id) => vendors.firstWhere((v) => v.id == id).companyName,
                onChanged: (v) => _update((f) => f.copyWith(vendorId: () => v, page: 1)),
              ),
              if (officers.isNotEmpty)
                _dropdown<String>(
                  hint: 'ICT Officer',
                  value: filters.assignedTo,
                  items: officers.map((o) => o.id).toList(),
                  label: (id) => officers
                      .firstWhere((o) => o.id == id, orElse: () => officers.first)
                      .fullName,
                  onChanged: (v) => _update((f) => f.copyWith(assignedTo: () => v, page: 1)),
                ),
              _dropdown<String>(
                hint: 'Priority',
                value: filters.priority,
                items: const ['low', 'medium', 'high', 'critical'],
                label: (s) => s[0].toUpperCase() + s.substring(1),
                onChanged: (v) => _update((f) => f.copyWith(priority: () => v, page: 1)),
              ),
              _dropdown<String>(
                hint: 'Owned/Leased',
                value: filters.printerType,
                items: const ['owned', 'leased'],
                label: (s) => s[0].toUpperCase() + s.substring(1),
                onChanged: (v) => _update((f) => f.copyWith(printerType: () => v, page: 1)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(filters.dateFrom == null
                    ? 'Date range'
                    : '${filters.dateFrom} → ${filters.dateTo ?? 'now'}'),
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (range != null) {
                    _update((f) => f.copyWith(
                          dateFrom: () => range.start.toIso8601String().substring(0, 10),
                          dateTo: () => range.end.toIso8601String().substring(0, 10),
                          page: 1,
                        ));
                  }
                },
              ),
              FilterChip(
                label: const Text('Open only'),
                selected: filters.openOnly,
                onSelected: (v) => _update((f) => f.copyWith(openOnly: v, page: 1)),
              ),
              TextButton(
                onPressed: () {
                  _search.clear();
                  ref.read(ticketFiltersProvider.notifier).state = const TicketFilters();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: tickets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load tickets: $e')),
              data: (page) => Column(
                children: [
                  Expanded(
                    child: page.items.isEmpty
                        ? const Center(child: Text('No tickets match the current filters'))
                        : Card(
                            child: SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  showCheckboxColumn: false,
                                  columns: const [
                                    DataColumn(label: Text('Ticket #')),
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Reported By')),
                                    DataColumn(label: Text('Department')),
                                    DataColumn(label: Text('Printer')),
                                    DataColumn(label: Text('Issue')),
                                    DataColumn(label: Text('Priority')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Assigned')),
                                  ],
                                  rows: [
                                    for (final t in page.items)
                                      DataRow(
                                        onSelectChanged: (_) => context.go('/tickets/${t.id}'),
                                        cells: [
                                          DataCell(Text(t.ticketNumber,
                                              style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(Text(t.dateReceived?.substring(0, 10) ?? '')),
                                          DataCell(Text(t.reportedBy)),
                                          DataCell(Text(t.departmentName ?? '—')),
                                          DataCell(Text(t.printerAssetNumber ?? '—')),
                                          DataCell(Text(t.issueCategory ?? '—')),
                                          DataCell(_priorityChip(t.priority)),
                                          DataCell(StatusBadge(label: t.statusLabel, blocked: t.isBlocked)),
                                          DataCell(Text(t.assignedToName ?? '—')),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${page.total} tickets'),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: page.page > 1
                            ? () => _update((f) => f.copyWith(page: page.page - 1))
                            : null,
                      ),
                      Text('Page ${page.page} / ${(page.total / page.pageSize).ceil().clamp(1, 9999)}'),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: page.page * page.pageSize < page.total
                            ? () => _update((f) => f.copyWith(page: page.page + 1))
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _update(TicketFilters Function(TicketFilters) fn) {
    ref.read(ticketFiltersProvider.notifier).state = fn(ref.read(ticketFiltersProvider));
  }

  Widget _priorityChip(String priority) {
    final color = PriorityColors.forPriority(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(priority.toUpperCase(),
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required void Function(T?) onChanged,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T?>(
        value: value,
        decoration: InputDecoration(labelText: hint),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text('All', style: TextStyle(color: Colors.grey.shade600))),
          for (final item in items)
            DropdownMenuItem<T?>(value: item, child: Text(label(item), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
