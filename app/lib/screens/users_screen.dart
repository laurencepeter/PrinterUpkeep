import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Users', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              if (isAdmin)
                FilledButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add User'),
                  onPressed: () => _editDialog(context, ref, null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!isAdmin)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Only administrators can manage users.'),
            ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => Card(
                child: SingleChildScrollView(
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Username')),
                      DataColumn(label: Text('Full Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Role')),
                      DataColumn(label: Text('Active')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final u in items)
                        DataRow(cells: [
                          DataCell(Text(u.username,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(u.fullName)),
                          DataCell(Text(u.email ?? '—')),
                          DataCell(Chip(
                            label: Text(u.roleName, style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          )),
                          DataCell(Icon(u.isActive ? Icons.check_circle : Icons.cancel,
                              size: 18,
                              color: u.isActive ? Colors.green : Colors.grey)),
                          DataCell(isAdmin
                              ? IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _editDialog(context, ref, u))
                              : const SizedBox()),
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

  Future<void> _editDialog(BuildContext context, WidgetRef ref, UserAccount? user) async {
    final username = TextEditingController(text: user?.username ?? '');
    final fullName = TextEditingController(text: user?.fullName ?? '');
    final email = TextEditingController(text: user?.email ?? '');
    final phone = TextEditingController(text: user?.phone ?? '');
    final password = TextEditingController();
    String role = user?.role ?? 'ict_officer';
    bool active = user?.isActive ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(user == null ? 'Add User' : 'Edit User'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: username,
                  enabled: user == null,
                  decoration: const InputDecoration(labelText: 'Username *'),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: fullName,
                    decoration: const InputDecoration(labelText: 'Full name *')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: email,
                          decoration: const InputDecoration(labelText: 'Email'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: phone,
                          decoration: const InputDecoration(labelText: 'Phone'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: user == null ? 'Password * (min 8 chars)' : 'New password (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                    DropdownMenuItem(value: 'ict_officer', child: Text('ICT Officer')),
                    DropdownMenuItem(value: 'viewer', child: Text('Viewer (read-only)')),
                  ],
                  onChanged: (v) => setState(() => role = v ?? 'ict_officer'),
                ),
                if (user != null)
                  SwitchListTile(
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
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

    if (ok != true) return;
    try {
      final api = ref.read(apiProvider);
      if (user == null) {
        await api.post('/api/users', body: {
          'username': username.text.trim(),
          'fullName': fullName.text.trim(),
          if (email.text.isNotEmpty) 'email': email.text,
          if (phone.text.isNotEmpty) 'phone': phone.text,
          'password': password.text,
          'roleCode': role,
        });
      } else {
        await api.patch('/api/users/${user.id}', body: {
          'fullName': fullName.text.trim(),
          if (email.text.isNotEmpty) 'email': email.text,
          if (phone.text.isNotEmpty) 'phone': phone.text,
          if (password.text.isNotEmpty) 'password': password.text,
          'roleCode': role,
          'isActive': active,
        });
      }
      ref.invalidate(usersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}
