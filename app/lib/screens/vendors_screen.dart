import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class VendorsScreen extends ConsumerStatefulWidget {
  const VendorsScreen({super.key});

  @override
  ConsumerState<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends ConsumerState<VendorsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final vendors = ref.watch(vendorsProvider);
    final canWrite = ref.watch(authProvider).user?.canWrite == true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Vendors', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search vendors…', prefixIcon: Icon(Icons.search, size: 20)),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              if (canWrite)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Vendor'),
                  onPressed: () => _editDialog(null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: vendors.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) {
                final filtered = items
                    .where((v) => _search.isEmpty || v.companyName.toLowerCase().contains(_search))
                    .toList();
                if (filtered.isEmpty) return const Center(child: Text('No vendors'));
                return Card(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Company')),
                          DataColumn(label: Text('Contact Person')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Types')),
                          DataColumn(label: Text('Tickets')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final v in filtered)
                            DataRow(cells: [
                              DataCell(Text(v.companyName,
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(v.contactPerson ?? '—')),
                              DataCell(Text(v.phone ?? '—')),
                              DataCell(Text(v.email ?? '—')),
                              DataCell(Text(v.vendorTypes.isEmpty ? '—' : v.vendorTypes.join(', '))),
                              DataCell(Text('${v.ticketCount}')),
                              DataCell(Row(children: [
                                if (canWrite)
                                  IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _editDialog(v)),
                                if (canWrite)
                                  IconButton(
                                    tooltip: 'Deactivate',
                                    icon: const Icon(Icons.visibility_off, size: 18),
                                    onPressed: () async {
                                      await ref.read(apiProvider).delete('/api/vendors/${v.id}');
                                      ref.invalidate(vendorsProvider);
                                    },
                                  ),
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

  Future<void> _editDialog(Vendor? vendor) async {
    final name = TextEditingController(text: vendor?.companyName ?? '');
    final address = TextEditingController(text: vendor?.address ?? '');
    final phone = TextEditingController(text: vendor?.phone ?? '');
    final email = TextEditingController(text: vendor?.email ?? '');
    final contact = TextEditingController(text: vendor?.contactPerson ?? '');
    final website = TextEditingController(text: vendor?.website ?? '');
    final notes = TextEditingController(text: vendor?.notes ?? '');
    final types = {...(vendor?.vendorTypes ?? <String>[])};

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(vendor == null ? 'Add Vendor' : 'Edit Vendor'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Company name *')),
                const SizedBox(height: 10),
                TextField(controller: contact, decoration: const InputDecoration(labelText: 'Contact person')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: phone, decoration: const InputDecoration(labelText: 'Phone'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: email, decoration: const InputDecoration(labelText: 'Email'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 10),
                TextField(controller: website, decoration: const InputDecoration(labelText: 'Website')),
                const SizedBox(height: 10),
                TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes')),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, children: [
                    for (final t in ['printer', 'consumables', 'maintenance', 'other'])
                      FilterChip(
                        label: Text(t),
                        selected: types.contains(t),
                        onSelected: (sel) =>
                            setState(() => sel ? types.add(t) : types.remove(t)),
                      ),
                  ]),
                ),
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

    if (ok != true || name.text.trim().isEmpty) return;
    final body = {
      'companyName': name.text.trim(),
      if (address.text.isNotEmpty) 'address': address.text,
      if (phone.text.isNotEmpty) 'phone': phone.text,
      if (email.text.isNotEmpty) 'email': email.text,
      if (contact.text.isNotEmpty) 'contactPerson': contact.text,
      if (website.text.isNotEmpty) 'website': website.text,
      if (notes.text.isNotEmpty) 'notes': notes.text,
      'vendorTypes': types.toList(),
    };
    try {
      final api = ref.read(apiProvider);
      if (vendor == null) {
        await api.post('/api/vendors', body: body);
      } else {
        await api.patch('/api/vendors/${vendor.id}', body: body);
      }
      ref.invalidate(vendorsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}
