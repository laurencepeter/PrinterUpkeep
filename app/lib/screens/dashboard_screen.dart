import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../providers/providers.dart';
import '../widgets/charts.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load dashboard: $e')),
      data: (data) {
        final s = data.stats;
        int stat(String key) => (s[key] as num?)?.toInt() ?? 0;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 230).clamp(1, 6),
                childAspectRatio: 2.6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  StatCard(
                      label: 'Open Tickets',
                      value: '${stat('total_open')}',
                      icon: Icons.inbox,
                      color: StageColors.current,
                      onTap: () => context.go('/tickets')),
                  StatCard(
                      label: 'Completed Today',
                      value: '${stat('completed_today')}',
                      icon: Icons.today,
                      color: StageColors.done),
                  StatCard(
                      label: 'Awaiting Vendor',
                      value: '${stat('awaiting_vendor')}',
                      icon: Icons.storefront,
                      color: StageColors.waiting),
                  StatCard(
                      label: 'Awaiting Quote',
                      value: '${stat('awaiting_quote')}',
                      icon: Icons.request_quote,
                      color: StageColors.waiting),
                  StatCard(
                      label: 'Awaiting Accounts',
                      value: '${stat('awaiting_accounts')}',
                      icon: Icons.account_balance,
                      color: StageColors.waiting),
                  StatCard(
                      label: 'Awaiting GA',
                      value: '${stat('awaiting_ga')}',
                      icon: Icons.approval,
                      color: StageColors.waiting),
                  StatCard(
                      label: 'Work In Progress',
                      value: '${stat('work_in_progress')}',
                      icon: Icons.build,
                      color: StageColors.current),
                  StatCard(
                      label: 'Completed',
                      value: '${stat('completed')}',
                      icon: Icons.check_circle,
                      color: StageColors.done),
                  StatCard(
                      label: 'Closed', value: '${stat('closed')}', icon: Icons.archive, color: StageColors.notStarted),
                  StatCard(
                      label: 'Owned Printers',
                      value: '${stat('owned_printers')}',
                      icon: Icons.print,
                      onTap: () => context.go('/printers')),
                  StatCard(
                      label: 'Leased Printers',
                      value: '${stat('leased_printers')}',
                      icon: Icons.print_outlined,
                      onTap: () => context.go('/printers')),
                  StatCard(
                      label: 'Avg Completion (days)',
                      value: data.avgCompletionDays?.toStringAsFixed(1) ?? '—',
                      icon: Icons.timer_outlined),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > 900;
                  final children = [
                    _chartCard(context, 'Monthly Requests', MonthlyBarChart(points: data.monthlyRequests)),
                    _chartCard(context, 'Status Breakdown',
                        HorizontalBarList(points: data.statusBreakdown, color: StageColors.current)),
                    _chartCard(context, 'Tickets by Department', HorizontalBarList(points: data.byDepartment)),
                    _chartCard(context, 'Tickets by Vendor',
                        HorizontalBarList(points: data.byVendor, color: StageColors.waiting)),
                    _chartCard(
                        context,
                        'Owned vs Leased',
                        HorizontalBarList(
                            points: data.ownedVsLeased, color: StageColors.done)),
                    _recentActivity(context, data.recentActivity),
                  ];
                  if (!twoColumns) return Column(children: children);
                  return Column(
                    children: [
                      for (var i = 0; i < children.length; i += 2)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: children[i]),
                            const SizedBox(width: 12),
                            Expanded(
                                child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartCard(BuildContext context, String title, Widget chart) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              chart,
            ],
          ),
        ),
      );

  Widget _recentActivity(BuildContext context, List<Map<String, dynamic>> items) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (items.isEmpty) const Text('No activity yet'),
              for (final a in items.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.timeline, size: 18),
                  title: Text('${a['ticket_number']} → ${a['stage_name']}'),
                  subtitle: Text(
                    '${a['changed_by_name']} · ${_fmtTimestamp(a['created_at'])}'
                    '${a['notes'] != null && '${a['notes']}'.isNotEmpty ? ' · ${a['notes']}' : ''}',
                  ),
                  onTap: () => GoRouter.of(context).go('/tickets/${a['ticket_id']}'),
                ),
            ],
          ),
        ),
      );

  static String _fmtTimestamp(dynamic value) {
    final dt = DateTime.tryParse('$value')?.toLocal();
    return dt == null ? '$value' : DateFormat('d MMM y, h:mm a').format(dt);
  }
}
