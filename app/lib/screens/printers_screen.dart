import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
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
                width: 230,
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name/asset/model/IP…',
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
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import'),
                  onPressed: _importDialog,
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
                      (p.name ?? '').toLowerCase().contains(_search) ||
                      (p.ipAddress ?? '').toLowerCase().contains(_search) ||
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
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Model')),
                          DataColumn(label: Text('IP Address')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Lease Period')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Location')),
                          DataColumn(label: Text('Next Service')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final p in filtered)
                            DataRow(cells: [
                              DataCell(Text(p.assetNumber,
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(p.name ?? '—')),
                              DataCell(Text(p.model)),
                              DataCell(Text(p.ipAddress ?? '—')),
                              DataCell(Chip(
                                label: Text(p.printerType.toUpperCase(),
                                    style: const TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                              )),
                              DataCell(_leaseCell(context, p)),
                              DataCell(Text(p.departmentName ?? '—')),
                              DataCell(Text(p.location ?? '—')),
                              DataCell(Text(p.nextServiceDue?.substring(0, 10) ?? '—')),
                              DataCell(Text(p.status)),
                              DataCell(Row(children: [
                                IconButton(
                                  tooltip: 'Details & maintenance history',
                                  icon: const Icon(Icons.info_outline, size: 18),
                                  onPressed: () => _detailsDialog(p),
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

  /// Bulk-import printers from a CSV / Excel / JSON file. Existing printers
  /// (matching serial number, IP or asset number) are skipped server-side so a
  /// re-import never creates duplicates.
  Future<void> _importDialog() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Printers'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Upload a CSV, Excel (.xlsx) or JSON file. Recognised columns:'),
              const SizedBox(height: 8),
              Text(
                'Department · IP Address · Model · Serial Number · Status · '
                'Ownership Status · Toner Model · Waste Toner Model · Path',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _bullet('Only Model is required. Unknown departments are created automatically.'),
              _bullet('Toner Model may list several toners, one per line — e.g. '
                  '"Yellow  W9052MC" then "Black  W9050MC" — each is imported and '
                  'listed as its own colour + code.'),
              _bullet('Printers that already exist (matching serial number, IP address '
                  'or asset number) are skipped, so re-importing is safe.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose file…'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'json'],
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    try {
      final res = await ref.read(apiProvider).upload(
            '/api/export/import/printers',
            MultipartFile.fromBytes(file.bytes!, filename: file.name),
          );
      ref.invalidate(printersProvider);
      if (!mounted) return;
      _showImportResult(res as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  void _showImportResult(Map<String, dynamic> res) {
    final imported = res['imported'] ?? 0;
    final skipped = (res['skipped_duplicates'] as List?) ?? const [];
    final errors = (res['errors'] as List?) ?? const [];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import complete'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 8),
                  Text('$imported printer(s) imported',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${skipped.length} skipped (already exist):',
                      style: Theme.of(context).textTheme.titleSmall),
                  for (final s in skipped.take(25))
                    Text('• $s', style: Theme.of(context).textTheme.bodySmall),
                  if (skipped.length > 25)
                    Text('…and ${skipped.length - 25} more',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${errors.length} row error(s):',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error)),
                  for (final s in errors.take(25))
                    Text('• $s', style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ]),
      );

  /// Lease period cell, highlighted red when the lease has ≤30 days left.
  Widget _leaseCell(BuildContext context, Printer p) {
    final period = p.leasePeriod;
    if (period == null) return const Text('—');
    Color? color;
    final end = DateTime.tryParse(p.leaseEnd ?? '');
    if (end != null) {
      final daysLeft = end.difference(DateTime.now()).inDays;
      if (daysLeft < 0) {
        color = Theme.of(context).colorScheme.error;
      } else if (daysLeft <= 30) {
        color = const Color(0xFFEF6C00);
      }
    }
    return Text(period, style: TextStyle(color: color, fontWeight: color != null ? FontWeight.w600 : null));
  }

  Future<void> _detailsDialog(Printer p) async {
    final history = await ref.read(apiProvider).get('/api/printers/${p.id}/history');
    final consumables = await ref.read(apiProvider).get('/api/printers/${p.id}/consumables');
    if (!mounted) return;
    final items =
        (consumables as List).map((e) => PrinterConsumable.fromJson(e as Map<String, dynamic>)).toList();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(p.label),
        content: SizedBox(
          width: 560,
          height: 460,
          child: ListView(
            children: [
              Wrap(spacing: 24, runSpacing: 10, children: [
                _kv('Serial', p.serialNumber ?? '—'),
                _kv('IP Address', p.ipAddress ?? '—'),
                _kv('MAC Address', p.macAddress ?? '—'),
                _kv('Connection', p.connectionType),
                _kv('Colour', p.isColor ? 'Colour' : 'Mono'),
                _kv('Consumables', p.consumablesModel ?? '—'),
                _kv('Type', p.printerType.toUpperCase()),
                if (p.isLeased) _kv('Lease Period', p.leasePeriod ?? '—'),
                if (p.isLeased)
                  _kv('Monthly Cost',
                      p.leaseMonthlyCost == null ? '—' : p.leaseMonthlyCost!.toStringAsFixed(2)),
                if (!p.isLeased) _kv('Purchased', p.purchaseDate?.substring(0, 10) ?? '—'),
                if (!p.isLeased)
                  _kv('Purchase Cost',
                      p.purchaseCost == null ? '—' : p.purchaseCost!.toStringAsFixed(2)),
                _kv('Warranty Until', p.warrantyExpiry?.substring(0, 10) ?? '—'),
                _kv('Last Service', p.lastServiceDate?.substring(0, 10) ?? '—'),
                _kv('Next Service Due', p.nextServiceDue?.substring(0, 10) ?? '—'),
                _kv('Vendor', p.vendorName ?? '—'),
                _kv('Building/Floor', '${p.building ?? '—'} / ${p.floor ?? '—'}'),
              ]),
              const Divider(height: 24),
              Text('Toners & Consumables', style: Theme.of(context).textTheme.titleSmall),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No toners/consumables defined'),
                ),
              for (final c in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.water_drop_outlined, size: 18),
                  title: Text(c.fullLabel),
                  subtitle: Text(PrinterConsumable.titleCase(c.kind)),
                ),
              const Divider(height: 24),
              Text('Maintenance History', style: Theme.of(context).textTheme.titleSmall),
              if ((history as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No tickets for this printer'),
                ),
              for (final h in history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
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

  Widget _kv(String k, String v) => SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: Theme.of(context).textTheme.labelSmall),
            Text(v),
          ],
        ),
      );

  Future<void> _editDialog(Printer? printer) async {
    final departments = ref.read(departmentsProvider).valueOrNull ?? [];
    final vendors = ref.read(vendorsProvider).valueOrNull ?? [];

    // Editable working copy of the printer's consumables/parts catalogue.
    // Each row is a mutable map; ObjectKey keeps text-field state stable across
    // add/remove. Loaded up-front for an existing printer.
    final consumableRows = <Map<String, dynamic>>[];
    if (printer != null) {
      try {
        final data = await ref.read(apiProvider).get('/api/printers/${printer.id}/consumables');
        for (final c in (data as List)) {
          consumableRows.add({
            'kind': c['kind'] ?? 'toner',
            'color': c['color'],
            'modelCode': c['model_code'] ?? '',
          });
        }
      } catch (_) {/* new/unsaved printers simply start empty */}
    }
    if (!mounted) return;
    final asset = TextEditingController(text: printer?.assetNumber ?? '');
    final name = TextEditingController(text: printer?.name ?? '');
    final model = TextEditingController(text: printer?.model ?? '');
    final serial = TextEditingController(text: printer?.serialNumber ?? '');
    final ip = TextEditingController(text: printer?.ipAddress ?? '');
    final mac = TextEditingController(text: printer?.macAddress ?? '');
    final consumables = TextEditingController(text: printer?.consumablesModel ?? '');
    final location = TextEditingController(text: printer?.location ?? '');
    final building = TextEditingController(text: printer?.building ?? '');
    final floor = TextEditingController(text: printer?.floor ?? '');
    final leaseCost = TextEditingController(text: printer?.leaseMonthlyCost?.toString() ?? '');
    final purchaseCost = TextEditingController(text: printer?.purchaseCost?.toString() ?? '');
    String type = printer?.printerType ?? 'owned';
    String connection = printer?.connectionType ?? 'network';
    bool isColor = printer?.isColor ?? false;
    String status = printer?.status ?? 'active';
    String? departmentId = printer?.departmentId;
    String? vendorId = printer?.vendorId;
    DateTime? warranty = DateTime.tryParse(printer?.warrantyExpiry ?? '');
    DateTime? leaseStart = DateTime.tryParse(printer?.leaseStart ?? '');
    DateTime? leaseEnd = DateTime.tryParse(printer?.leaseEnd ?? '');
    DateTime? purchaseDate = DateTime.tryParse(printer?.purchaseDate ?? '');
    DateTime? lastService = DateTime.tryParse(printer?.lastServiceDate ?? '');
    DateTime? nextService = DateTime.tryParse(printer?.nextServiceDue ?? '');

    final fmt = DateFormat('y-MM-dd');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Widget dateButton({
            required String label,
            required DateTime? value,
            required void Function(DateTime?) onPicked,
            DateTime? first,
            DateTime? last,
          }) =>
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text(value == null ? label : '$label: ${fmt.format(value)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: value ?? DateTime.now(),
                    firstDate: first ?? DateTime(2010),
                    lastDate: last ?? DateTime(2045),
                  );
                  if (d != null) setState(() => onPicked(d));
                },
              );

          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(text, style: Theme.of(context).textTheme.titleSmall),
                ),
              );

          final leaseInvalid =
              leaseStart != null && leaseEnd != null && leaseEnd!.isBefore(leaseStart!);

          return AlertDialog(
            title: Text(printer == null ? 'Add Printer' : 'Edit Printer'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  sectionLabel('Identity'),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: asset,
                            decoration: const InputDecoration(labelText: 'Asset number *'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                                labelText: 'Name', hintText: 'e.g. Accounts-Printer-1'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: model,
                            decoration: const InputDecoration(labelText: 'Model *'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: serial,
                            decoration: const InputDecoration(labelText: 'Serial number'))),
                  ]),
                  sectionLabel('Network'),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: ip,
                            decoration: const InputDecoration(
                                labelText: 'IP address', hintText: '192.168.1.50'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: mac,
                            decoration: const InputDecoration(
                                labelText: 'MAC address', hintText: 'AA:BB:CC:DD:EE:FF'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: connection,
                        decoration: const InputDecoration(labelText: 'Connection'),
                        items: const [
                          DropdownMenuItem(value: 'network', child: Text('Network (LAN)')),
                          DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi')),
                          DropdownMenuItem(value: 'usb', child: Text('USB (local)')),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => connection = v ?? 'network'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Colour printer'),
                        value: isColor,
                        onChanged: (v) => setState(() => isColor = v),
                      ),
                    ),
                  ]),
                  TextField(
                      controller: consumables,
                      decoration: const InputDecoration(
                          labelText: 'Consumables / toner model', hintText: 'e.g. HP 59A (CF259A)')),
                  sectionLabel('Ownership'),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'owned', label: Text('Owned'), icon: Icon(Icons.home_work)),
                      ButtonSegment(value: 'leased', label: Text('Leased'), icon: Icon(Icons.schedule)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setState(() => type = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (type == 'leased') ...[
                    Row(children: [
                      Expanded(
                        child: dateButton(
                          label: 'Lease start',
                          value: leaseStart,
                          onPicked: (d) => leaseStart = d,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: dateButton(
                          label: 'Lease end',
                          value: leaseEnd,
                          onPicked: (d) => leaseEnd = d,
                          first: leaseStart,
                        ),
                      ),
                    ]),
                    if (leaseInvalid)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Lease end must be on or after lease start',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    if (leaseStart != null && leaseEnd != null && !leaseInvalid)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'Lease length: ${_leaseLength(leaseStart!, leaseEnd!)}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                        controller: leaseCost,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Monthly lease cost')),
                  ] else ...[
                    Row(children: [
                      Expanded(
                        child: dateButton(
                          label: 'Purchase date',
                          value: purchaseDate,
                          onPicked: (d) => purchaseDate = d,
                          last: DateTime.now(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                            controller: purchaseCost,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Purchase cost')),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  dateButton(
                    label: 'Warranty expiry',
                    value: warranty,
                    onPicked: (d) => warranty = d,
                  ),
                  sectionLabel('Assignment'),
                  DropdownButtonFormField<String?>(
                    value: departmentId,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final d in departments)
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
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
                          controller: floor,
                          decoration: const InputDecoration(labelText: 'Floor')),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: vendorId,
                    decoration: const InputDecoration(labelText: 'Vendor / supplier'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final v in vendors)
                        DropdownMenuItem(value: v.id, child: Text(v.companyName)),
                    ],
                    onChanged: (v) => setState(() => vendorId = v),
                  ),
                  sectionLabel('Servicing'),
                  Row(children: [
                    Expanded(
                      child: dateButton(
                        label: 'Last service',
                        value: lastService,
                        onPicked: (d) => lastService = d,
                        last: DateTime.now(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: dateButton(
                        label: 'Next service due',
                        value: nextService,
                        onPicked: (d) => nextService = d,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'repair', child: Text('In Repair')),
                      DropdownMenuItem(value: 'disposed', child: Text('Disposed')),
                    ],
                    onChanged: (v) => setState(() => status = v ?? 'active'),
                  ),
                  sectionLabel('Consumables & Parts'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Define the toners/drums/parts this printer takes. Ticket-raisers '
                      'then just tick which colour(s) to replace — no typing model numbers.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < consumableRows.length; i++)
                    _consumableRow(context, setState, consumableRows, i),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add item'),
                        onPressed: () => setState(() => consumableRows.add(
                            {'kind': 'toner', 'color': isColor ? 'black' : null, 'modelCode': ''})),
                      ),
                      if (isColor)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.palette_outlined, size: 18),
                          label: const Text('Quick add C/M/Y/K'),
                          onPressed: () => setState(() {
                            for (final col in ['black', 'cyan', 'magenta', 'yellow']) {
                              consumableRows.add({'kind': 'toner', 'color': col, 'modelCode': ''});
                            }
                          }),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: leaseInvalid ? null : () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || asset.text.trim().isEmpty || model.text.trim().isEmpty) return;
    final leased = type == 'leased';
    final body = {
      'assetNumber': asset.text.trim(),
      'model': model.text.trim(),
      'name': name.text.trim().isEmpty ? null : name.text.trim(),
      if (serial.text.isNotEmpty) 'serialNumber': serial.text,
      'printerType': type,
      'ipAddress': ip.text.trim().isEmpty ? null : ip.text.trim(),
      'macAddress': mac.text.trim().isEmpty ? null : mac.text.trim(),
      'connectionType': connection,
      'isColor': isColor,
      'consumablesModel': consumables.text.trim().isEmpty ? null : consumables.text.trim(),
      'departmentId': departmentId,
      'vendorId': vendorId,
      if (location.text.isNotEmpty) 'location': location.text,
      if (building.text.isNotEmpty) 'building': building.text,
      if (floor.text.isNotEmpty) 'floor': floor.text,
      if (warranty != null) 'warrantyExpiry': fmt.format(warranty!),
      // Explicit nulls clear lease terms when the printer is owned (and vice
      // versa), so switching ownership type never leaves stale data behind.
      'leaseStart': leased && leaseStart != null ? fmt.format(leaseStart!) : null,
      'leaseEnd': leased && leaseEnd != null ? fmt.format(leaseEnd!) : null,
      'leaseMonthlyCost': leased ? double.tryParse(leaseCost.text) : null,
      'purchaseDate': !leased && purchaseDate != null ? fmt.format(purchaseDate!) : null,
      'purchaseCost': !leased ? double.tryParse(purchaseCost.text) : null,
      'lastServiceDate': lastService != null ? fmt.format(lastService!) : null,
      'nextServiceDue': nextService != null ? fmt.format(nextService!) : null,
      'status': status,
    };
    try {
      final api = ref.read(apiProvider);
      String printerId;
      if (printer == null) {
        final created = await api.post('/api/printers', body: body);
        printerId = created['id'] as String;
      } else {
        await api.patch('/api/printers/${printer.id}', body: body);
        printerId = printer.id;
      }
      await api.put('/api/printers/$printerId/consumables', body: {
        'items': [
          for (final c in consumableRows)
            {
              'kind': c['kind'],
              'color': c['color'],
              if ((c['modelCode'] as String?)?.trim().isNotEmpty == true)
                'modelCode': (c['modelCode'] as String).trim(),
            },
        ],
      });
      ref.invalidate(printersProvider);
      ref.invalidate(printerConsumablesProvider(printerId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  /// One editable row in the printer's consumables catalogue.
  Widget _consumableRow(
      BuildContext context, StateSetter setState, List<Map<String, dynamic>> rows, int index) {
    final c = rows[index];
    return Padding(
      key: ObjectKey(c),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              value: c['kind'] as String,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'toner', child: Text('Toner')),
                DropdownMenuItem(value: 'ink', child: Text('Ink')),
                DropdownMenuItem(value: 'drum', child: Text('Drum')),
                DropdownMenuItem(value: 'maintenance_kit', child: Text('Maint. kit')),
                DropdownMenuItem(value: 'fuser', child: Text('Fuser')),
                DropdownMenuItem(value: 'part', child: Text('Part')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => c['kind'] = v ?? 'toner'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String?>(
              value: c['color'] as String?,
              decoration: const InputDecoration(labelText: 'Colour'),
              items: const [
                DropdownMenuItem(value: null, child: Text('N/A')),
                DropdownMenuItem(value: 'black', child: Text('Black')),
                DropdownMenuItem(value: 'cyan', child: Text('Cyan')),
                DropdownMenuItem(value: 'magenta', child: Text('Magenta')),
                DropdownMenuItem(value: 'yellow', child: Text('Yellow')),
                DropdownMenuItem(value: 'tricolor', child: Text('Tri-colour')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => c['color'] = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextFormField(
              initialValue: c['modelCode'] as String? ?? '',
              decoration: const InputDecoration(labelText: 'Model code', hintText: 'HP 26A (CF226A)'),
              onChanged: (v) => c['modelCode'] = v,
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => rows.removeAt(index)),
          ),
        ],
      ),
    );
  }

  /// Human-readable lease length, e.g. "2 years 3 months" or "8 months".
  static String _leaseLength(DateTime start, DateTime end) {
    var months = (end.year - start.year) * 12 + (end.month - start.month);
    if (end.day >= start.day) months += 0; else months -= 1;
    if (months < 1) {
      final days = end.difference(start).inDays;
      return '$days days';
    }
    final years = months ~/ 12;
    final rem = months % 12;
    final parts = <String>[
      if (years > 0) '$years year${years == 1 ? '' : 's'}',
      if (rem > 0) '$rem month${rem == 1 ? '' : 's'}',
    ];
    return parts.join(' ');
  }
}
