import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

/// Desktop-first app shell: persistent left navigation rail, top bar with
/// notification bell and dark-mode toggle. Collapses to a drawer on narrow
/// screens.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    (route: '/dashboard', icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (route: '/tickets', icon: Icons.confirmation_number_outlined, label: 'Tickets'),
    (route: '/printers', icon: Icons.print_outlined, label: 'Printers'),
    (route: '/vendors', icon: Icons.storefront_outlined, label: 'Vendors'),
    (route: '/departments', icon: Icons.apartment_outlined, label: 'Departments'),
    (route: '/reports', icon: Icons.bar_chart_outlined, label: 'Reports'),
    (route: '/users', icon: Icons.group_outlined, label: 'Users'),
    (route: '/settings', icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final selected = _destinations.indexWhere((d) => location.startsWith(d.route));
    final auth = ref.watch(authProvider);
    final notifications = ref.watch(notificationsProvider).valueOrNull ?? [];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final rail = NavigationRail(
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (i) => context.go(_destinations[i].route),
      extended: MediaQuery.sizeOf(context).width >= 1200,
      labelType: MediaQuery.sizeOf(context).width >= 1200
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.print, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('ICT Printer Upkeep'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _showNotifications(context, ref),
            icon: Badge(
              isLabelVisible: notifications.isNotEmpty,
              label: Text('${notifications.length}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Toggle dark mode',
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(ref.watch(themeModeProvider) ? Icons.light_mode : Icons.dark_mode),
          ),
          PopupMenuButton<String>(
            tooltip: auth.user?.fullName ?? '',
            icon: CircleAvatar(
              radius: 14,
              child: Text(
                auth.user?.fullName.isNotEmpty == true ? auth.user!.fullName[0] : '?',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${auth.user?.fullName ?? ''}\n${auth.user?.role ?? ''}'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            onSelected: (v) {
              if (v == 'logout') ref.read(authProvider.notifier).logout();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: ListView(
                children: [
                  for (final d in _destinations)
                    ListTile(
                      leading: Icon(d.icon),
                      title: Text(d.label),
                      selected: location.startsWith(d.route),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(d.route);
                      },
                    ),
                ],
              ),
            ),
      body: Row(
        children: [
          if (wide) rail,
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final notifications = ref.watch(notificationsProvider);
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Notifications')),
                TextButton(
                  onPressed: () async {
                    await ref.read(apiProvider).post('/api/notifications/read-all');
                    ref.invalidate(notificationsProvider);
                  },
                  child: const Text('Mark all read'),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 420,
              child: notifications.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No unread notifications'))
                    : ListView(
                        children: [
                          for (final n in items)
                            ListTile(
                              leading: Icon(switch (n.type) {
                                'overdue' => Icons.warning_amber,
                                'vendor_delay' => Icons.local_shipping_outlined,
                                _ => Icons.pending_actions,
                              }),
                              title: Text(n.title),
                              subtitle: Text(n.message),
                              onTap: n.ticketId == null
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      context.go('/tickets/${n.ticketId}');
                                    },
                            ),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}
