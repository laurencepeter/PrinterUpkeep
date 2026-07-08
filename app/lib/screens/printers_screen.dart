import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class PrintersScreen extends ConsumerStatefulWidget {
  const PrintersScreen({super.key});

  @override
  ConsumerState<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends ConsumerState<PrintersScreen> {
  String _search = '';
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final printers = ref.watch(printersProvider);
    final canWrite = ref.watch(authProvider).user?.canWrite == true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Printers', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search asset/model/serial…',
                      prefixIcon: Icon(Icons.search, size: 20)),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: 'owned', label: Text('Owned')),
                  ButtonSegment(value: 'leased', label: Text('Leased')),
                ],
                selected: {_typeFilter},
                onSelectionChanged: (s) => setState(() => _typeFilter = s.first),
              ),
              const SizedBox(width: 8),
              if (canWrite)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Printer'),
                  onPressed: () => _editDialog(null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: printers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final filtered = items.where((p) {
                  final matchesSearch = _search.isEmpty ||
                      p.assetNumber.toLowerCase().contains(_search) ||
                      p.model.toLowerCase().contains(_search) ||
                      (p.serialNumber ?? '').toLowerCase().contains(_search);
                  final matchesType = _typeFilter == null || p.printerType == _typeFilter;
                  return matchesSearch && matchesType;
                }).toList();
                if (filtered.isEmpty) return const Center(child: Text('No printers'));
                return Card(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Asset #')),
                          DataColumn(label: Text('Model')),
                          DataColumn(label: Text('Serial')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Location')),
                          DataColumn(label: Text('Vendor')),
                          DataColumn(label: Text('Warranty')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final p in filtered)
                            DataRow(cells: [
                              DataCell(Text(p.assetNumber,
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(p.model)),
                              DataCell(Text(p.serialNumber ?? '—')),
                              DataCell(Chip(
                                label: Text(p.printerType.toUpperCase(),
                                    style: const TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                              )),
                              DataCell(Text(p.departmentName ?? '—')),
                              DataCell(Text(p.location ?? '—')),
                              DataCell(Text(p.vendorName ?? '—')),
                              DataCell(Text(p.warrantyExpiry?.substring(0, 10) ?? '—')),
                              DataCell(Text(p.status)),
                              DataCell(Row(children: [
                                IconButton(
                                  tooltip: 'Maintenance history',
                                  icon: const Icon(Icons.history, size: 18),
                                  onPressed: () => _historyDialog(p),
                                ),
                                if (canWrite)
                                  IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _editDialog(p)),
                              ])),
                            ]),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _historyDialog(Printer p) async {
    final history = await ref.read(apiProvider).get('/api/printers/${p.id}/history');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Maintenance History — ${p.assetNumber}'),
        content: SizedBox(
          width: 520,
          height: 380,
          child: (history as List).isEmpty
              ? const Center(child: Text('No tickets for this printer'))
              : ListView(
                  children: [
                    for (final h in history)
                      ListTile(
                        dense: true,
                        title: Text('${h['ticket_number']} — ${h['issue_category'] ?? 'Uncategorised'}'),
                        subtitle: Text(
                            '${h['status_label']} · received ${'${h['date_received']}'.substring(0, 10)}'),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _editDialog(Printer? printer) async {
    final departments = ref.read(departmentsProvider).valueOrNull ?? [];
    final vendors = ref.read(vendorsProvider).valueOrNull ?? [];
    final asset = TextEditingController(text: printer?.assetNumber ?? '');
    final model = TextEditingController(text: printer?.model ?? '');
    final serial = TextEditingController(text: printer?.serialNumber ?? '');
    final location = TextEditingController(text: printer?.location ?? '');
    final building = TextEditingController(text: printer?.building ?? '');
    final floor = TextEditingController(text: printer?.floor ?? '');
    String type = printer?.printerType ?? 'owned';
    String status = printer?.status ?? 'active';
    String? departmentId = printer?.departmentId;
    String? vendorId = printer?.vendorId;
    DateTime? warranty = DateTime.tryParse(printer?.warrantyExpiry ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(printer == null ? 'Add Printer' : 'Edit Printer'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: asset,
                          decoration: const InputDecoration(labelText: 'Asset number *'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: model,
                          decoration: const InputDecoration(labelText: 'Model *'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: serial,
                          decoration: const InputDecoration(labelText: 'Serial number'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'Owned / Leased'),
                      items: const [
                        DropdownMenuItem(value: 'owned', child: Text('Owned')),
                        DropdownMenuItem(value: 'leased', child: Text('Leased')),
                      ],
                      onChanged: (v) => setState(() => type = v ?? 'owned'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: departmentId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final d in departments) DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) => setState(() => departmentId = v),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: location,
                          decoration: const InputDecoration(labelText: 'Location'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: building,
                          decoration: const InputDecoration(labelText: 'Building'))),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: TextField(
                        controller: floor, decoration: const InputDecoration(labelText: 'Floor')),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: vendorId,
                  decoration: const InputDecoration(labelText: 'Vendor'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final v in vendors) DropdownMenuItem(value: v.id, child: Text(v.companyName)),
                  ],
                  onChanged: (v) => setState(() => vendorId = v),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(warranty == null
                          ? 'Warranty expiry'
                          : DateFormat('y-MM-dd').format(warranty!)),
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2015),
                            lastDate: DateTime(2040));
                        if (d != null) setState(() => warranty = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(value: 'repair', child: Text('In Repair')),
                        DropdownMenuItem(value: 'disposed', child: Text('Disposed')),
                      ],
                      onChanged: (v) => setState(() => status = v ?? 'active'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || asset.text.trim().isEmpty || model.text.trim().isEmpty) return;
    final body = {
      'assetNumber': asset.text.trim(),
      'model': model.text.trim(),
      if (serial.text.isNotEmpty) 'serialNumber': serial.text,
      'printerType': type,
      'departmentId': departmentId,
      'vendorId': vendorId,
      if (location.text.isNotEmpty) 'location': location.text,
      if (building.text.isNotEmpty) 'building': building.text,
      if (floor.text.isNotEmpty) 'floor': floor.text,
      if (warranty != null) 'warrantyExpiry': DateFormat('y-MM-dd').format(warranty!),
      'status': status,
    };
    try {
      final api = ref.read(apiProvider);
      if (printer == null) {
        await api.post('/api/printers', body: body);
      } else {
        await api.patch('/api/printers/${printer.id}', body: body);
      }
      ref.invalidate(printersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}
