import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api_client.dart';
import '../providers/providers.dart';

final _settingsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/settings');
  return (data as List).cast<Map<String, dynamic>>();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(_settingsProvider);
    final auth = ref.watch(authProvider);
    final isAdmin = auth.user?.isAdmin == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Account', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Signed in as ${auth.user?.fullName} (${auth.user?.role})'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.key),
                  label: const Text('Change password'),
                  onPressed: () => _changePasswordDialog(context, ref),
                ),
              ],
            ),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Audit Log'),
              subtitle: const Text('Who accessed the system and who changed or deleted records'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/audit-log'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('System Settings', style: Theme.of(context).textTheme.titleMedium),
                if (!isAdmin)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Only administrators can change system settings.'),
                  ),
                const SizedBox(height: 8),
                settings.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('$e'),
                  data: (items) => Column(
                    children: [
                      for (final s in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${s['key']}'),
                          subtitle: Text('${s['description'] ?? ''}'),
                          trailing: SizedBox(
                            width: 220,
                            child: Text('${s['value']}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          onTap: isAdmin ? () => _editSetting(context, ref, s) : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editSetting(BuildContext context, WidgetRef ref, Map<String, dynamic> setting) async {
    final controller = TextEditingController(text: '${setting['value']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${setting['key']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: '${setting['description'] ?? 'Value'}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(apiProvider).put('/api/settings/${setting['key']}', body: {'value': controller.text});
      ref.invalidate(_settingsProvider);
    }
  }

  Future<void> _changePasswordDialog(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 10),
            TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password (min 8 chars)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiProvider).post('/api/auth/change-password', body: {
          'currentPassword': current.text,
          'newPassword': next.text,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Password changed')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
        }
      }
    }
  }
}
