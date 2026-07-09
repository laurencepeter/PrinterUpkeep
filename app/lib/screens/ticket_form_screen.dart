import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// New-ticket form. Everything selectable is a dropdown/date-picker; typing
/// is limited to the reporter's name, contacts and the issue description.
class TicketFormScreen extends ConsumerStatefulWidget {
  const TicketFormScreen({super.key});

  @override
  ConsumerState<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends ConsumerState<TicketFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reportedBy = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _description = TextEditingController();
  final _ictTicket = TextEditingController();
  final _vendorTicket = TextEditingController();

  DateTime _dateReceived = DateTime.now();
  TimeOfDay _timeReceived = TimeOfDay.now();
  String _reportingMethod = 'walk_in';
  String _priority = 'medium';
  String? _departmentId;
  String? _printerId;
  String? _vendorId;
  int? _issueCategoryId;
  String? _assignedTo;
  final Set<String> _selectedConsumables = {};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider).valueOrNull ?? [];
    final printers = ref.watch(printersProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final categories = ref.watch(issueCategoriesProvider).valueOrNull ?? [];
    final users = ref.watch(usersProvider).valueOrNull ?? [];

    final selectedPrinter =
        _printerId == null ? null : printers.where((p) => p.id == _printerId).firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/tickets')),
                    Text('New Ticket', style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
                    Text('Ticket number is generated automatically',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                _card('General Information', [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('Date: ${DateFormat('y-MM-dd').format(_dateReceived)}'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateReceived,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _dateReceived = d);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text('Time: ${_timeReceived.format(context)}'),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _timeReceived);
                        if (t != null) setState(() => _timeReceived = t);
                      },
                    ),
                    _dropdown<String>(
                      label: 'Reporting Method',
                      value: _reportingMethod,
                      items: const {
                        'walk_in': 'Walk In',
                        'phone': 'Phone',
                        'email': 'Email',
                        'ict_ticket': 'ICT Ticket',
                        'vendor_ticket': 'Vendor Ticket',
                      },
                      onChanged: (v) => setState(() => _reportingMethod = v ?? 'walk_in'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _reportedBy,
                        decoration: const InputDecoration(labelText: 'Reported by *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dropdownFromList<Department>(
                        label: 'Department',
                        value: _departmentId,
                        items: departments,
                        id: (d) => d.id,
                        display: (d) => d.name,
                        onChanged: (v) => setState(() => _departmentId = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _phone,
                            decoration: const InputDecoration(labelText: 'Contact phone'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                            controller: _email,
                            decoration: const InputDecoration(labelText: 'Contact email'))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _ictTicket,
                            decoration:
                                const InputDecoration(labelText: 'ICT ticket # (external system)'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                            controller: _vendorTicket,
                            decoration: const InputDecoration(labelText: 'Vendor/MBC ticket #'))),
                  ]),
                ]),
                _card('Printer', [
                  _searchableDropdown(
                    label: 'Printer (search by asset tag or model)',
                    entries: [for (final p in printers) (p.id, p.label)],
                    value: _printerId,
                    onChanged: (v) => setState(() {
                      _printerId = v;
                      _selectedConsumables.clear();
                    }),
                  ),
                  if (selectedPrinter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(spacing: 20, children: [
                        _kv('Type', selectedPrinter.printerType.toUpperCase()),
                        _kv('Serial', selectedPrinter.serialNumber ?? '—'),
                        _kv('Location', selectedPrinter.location ?? '—'),
                        _kv('Department', selectedPrinter.departmentName ?? '—'),
                      ]),
                    ),
                  if (_printerId != null) _consumablesSelector(_printerId!),
                ]),
                _card('Issue', [
                  Row(children: [
                    Expanded(
                      child: _dropdownFromList<IssueCategory>(
                        label: 'Issue category',
                        value: _issueCategoryId?.toString(),
                        items: categories,
                        id: (c) => c.id.toString(),
                        display: (c) => c.name,
                        onChanged: (v) =>
                            setState(() => _issueCategoryId = v == null ? null : int.parse(v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dropdown<String>(
                        label: 'Priority',
                        value: _priority,
                        items: const {
                          'low': 'Low',
                          'medium': 'Medium',
                          'high': 'High',
                          'critical': 'Critical',
                        },
                        onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                    ),
                  ),
                ]),
                _card('Vendor & Assignment', [
                  Row(children: [
                    Expanded(
                      child: _searchableDropdown(
                        label: 'Vendor (search)',
                        entries: [for (final v in vendors) (v.id, v.companyName)],
                        value: _vendorId,
                        onChanged: (v) => setState(() => _vendorId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add_business, size: 18),
                      label: const Text('New vendor'),
                      onPressed: () => _newVendorDialog(context),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _dropdownFromList<UserAccount>(
                    label: 'Assign to ICT officer',
                    value: _assignedTo,
                    items: users.where((u) => u.isActive && u.role != 'viewer').toList(),
                    id: (u) => u.id,
                    display: (u) => u.fullName,
                    onChanged: (v) => setState(() => _assignedTo = v),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => context.go('/tickets'), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Saving…' : 'Create Ticket'),
                      onPressed: _saving ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      final result = await api.post('/api/tickets', body: {
        'reportedBy': _reportedBy.text.trim(),
        'dateReceived': DateFormat('y-MM-dd').format(_dateReceived),
        'timeReceived':
            '${_timeReceived.hour.toString().padLeft(2, '0')}:${_timeReceived.minute.toString().padLeft(2, '0')}',
        'reportingMethod': _reportingMethod,
        'priority': _priority,
        if (_departmentId != null) 'departmentId': _departmentId,
        if (_printerId != null) 'printerId': _printerId,
        if (_vendorId != null) 'vendorId': _vendorId,
        if (_issueCategoryId != null) 'issueCategoryId': _issueCategoryId,
        if (_assignedTo != null) 'assignedTo': _assignedTo,
        if (_phone.text.isNotEmpty) 'contactPhone': _phone.text,
        if (_email.text.isNotEmpty) 'contactEmail': _email.text,
        if (_description.text.isNotEmpty) 'description': _description.text,
        if (_ictTicket.text.isNotEmpty) 'ictTicketNumber': _ictTicket.text,
        if (_vendorTicket.text.isNotEmpty) 'vendorTicketNumber': _vendorTicket.text,
        if (_selectedConsumables.isNotEmpty)
          'consumables': [for (final id in _selectedConsumables) {'consumableId': id}],
      });
      ref.invalidate(ticketsProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        final id = result['ticket']['id'];
        final number = result['ticket']['ticket_number'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created $number')));
        context.go('/tickets/$id');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _newVendorDialog(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final contact = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Vendor'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Company name *')),
            const SizedBox(height: 10),
            TextField(controller: contact, decoration: const InputDecoration(labelText: 'Contact person')),
            const SizedBox(height: 10),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 10),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        final vendor = await ref.read(apiProvider).post('/api/vendors', body: {
          'companyName': name.text.trim(),
          if (contact.text.isNotEmpty) 'contactPerson': contact.text,
          if (phone.text.isNotEmpty) 'phone': phone.text,
          if (email.text.isNotEmpty) 'email': email.text,
        });
        ref.invalidate(vendorsProvider);
        setState(() => _vendorId = vendor['id']);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
        }
      }
    }
  }

  /// Colour-coded multi-select of the selected printer's consumables catalogue.
  /// The reporter simply ticks which colour(s)/parts need replacing.
  Widget _consumablesSelector(String printerId) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ref.watch(printerConsumablesProvider(printerId)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  'No consumables catalogued for this printer yet. An admin can add its '
                  'toners/parts on the Printers screen.',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Consumables to replace',
                      style: Theme.of(context).textTheme.labelLarge),
                  Text('Tick which colour(s)/parts are needed',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final c in items)
                        FilterChip(
                          avatar: _colorDot(c.color),
                          label: Text(c.fullLabel),
                          selected: _selectedConsumables.contains(c.id),
                          onSelected: (sel) => setState(() => sel
                              ? _selectedConsumables.add(c.id)
                              : _selectedConsumables.remove(c.id)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
    );
  }

  /// Small colour swatch for a consumable chip (null for non-colour parts).
  Widget? _colorDot(String? color) {
    final swatch = switch (color) {
      'black' => Colors.black,
      'cyan' => Colors.cyan,
      'magenta' => const Color(0xFFD81B60),
      'yellow' => const Color(0xFFF9A825),
      'tricolor' => Colors.deepPurple,
      'other' => Colors.blueGrey,
      _ => null,
    };
    if (swatch == null) return null;
    return CircleAvatar(radius: 7, backgroundColor: swatch);
  }

  // --- Small builders -----------------------------------------------------------

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _kv(String k, String v) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Theme.of(context).textTheme.labelSmall),
          Text(v),
        ],
      );

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required Map<T, String> items,
    required void Function(T?) onChanged,
  }) =>
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<T>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _dropdownFromList<T>({
    required String label,
    required String? value,
    required List<T> items,
    required String Function(T) id,
    required String Function(T) display,
    required void Function(String?) onChanged,
  }) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('—')),
          for (final item in items)
            DropdownMenuItem(value: id(item), child: Text(display(item), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );

  /// Autocomplete-backed searchable dropdown (type a few letters, pick).
  Widget _searchableDropdown({
    required String label,
    required List<(String, String)> entries,
    required String? value,
    required void Function(String?) onChanged,
  }) {
    final current = entries.where((e) => e.$1 == value).firstOrNull;
    return Autocomplete<(String, String)>(
      key: ValueKey('$label-$value-${entries.length}'),
      initialValue: TextEditingValue(text: current?.$2 ?? ''),
      displayStringForOption: (e) => e.$2,
      optionsBuilder: (text) {
        if (text.text.isEmpty) return entries;
        final q = text.text.toLowerCase();
        return entries.where((e) => e.$2.toLowerCase().contains(q));
      },
      onSelected: (e) => onChanged(e.$1),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.search, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged(null);
                  },
                ),
        ),
      ),
    );
  }
}
