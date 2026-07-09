import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentsProvider);
    final canWrite = ref.watch(authProvider).user?.canWrite == true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Departments', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              if (canWrite)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Department'),
                  onPressed: () => _editDialog(context, ref, null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: departments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No departments'))
                  : Card(
                      child: SingleChildScrollView(
                        child: DataTable(
                          showCheckboxColumn: false,
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Code')),
                            DataColumn(label: Text('Building')),
                            DataColumn(label: Text('Floor')),
                            DataColumn(label: Text('Tickets')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: [
                            for (final d in items)
                              DataRow(cells: [
                                DataCell(Text(d.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(d.code ?? '—')),
                                DataCell(Text(d.building ?? '—')),
                                DataCell(Text(d.floor ?? '—')),
                                DataCell(Text('${d.ticketCount}')),
                                DataCell(Row(children: [
                                  if (canWrite)
                                    IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _editDialog(context, ref, d)),
                                  if (canWrite)
                                    IconButton(
                                      tooltip: 'Deactivate',
                                      icon: const Icon(Icons.visibility_off, size: 18),
                                      onPressed: () async {
                                        await ref
                                            .read(apiProvider)
                                            .delete('/api/departments/${d.id}');
                                        ref.invalidate(departmentsProvider);
                                      },
                                    ),
                                ])),
                              ]),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDialog(BuildContext context, WidgetRef ref, Department? dept) async {
    final name = TextEditingController(text: dept?.name ?? '');
    final code = TextEditingController(text: dept?.code ?? '');
    final building = TextEditingController(text: dept?.building ?? '');
    final floor = TextEditingController(text: dept?.floor ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dept == null ? 'Add Department' : 'Edit Department'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name *')),
            const SizedBox(height: 10),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: building,
                      decoration: const InputDecoration(labelText: 'Building'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: floor, decoration: const InputDecoration(labelText: 'Floor'))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true || name.text.trim().isEmpty) return;
    final body = {
      'name': name.text.trim(),
      if (code.text.isNotEmpty) 'code': code.text,
      if (building.text.isNotEmpty) 'building': building.text,
      if (floor.text.isNotEmpty) 'floor': floor.text,
    };
    try {
      final api = ref.read(apiProvider);
      if (dept == null) {
        await api.post('/api/departments', body: body);
      } else {
        await api.patch('/api/departments/${dept.id}', body: body);
      }
      ref.invalidate(departmentsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}
