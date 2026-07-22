import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'providers/providers.dart';
import 'screens/audit_log_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/executive_screen.dart';
import 'screens/departments_screen.dart';
import 'screens/login_screen.dart';
import 'screens/printers_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell.dart';
import 'screens/ticket_detail_screen.dart';
import 'screens/ticket_form_screen.dart';
import 'screens/tickets_screen.dart';
import 'screens/users_screen.dart';
import 'screens/vendors_screen.dart';

void main() {
  runApp(const ProviderScope(child: PrinterUpkeepApp()));
}

final _routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ValueNotifier(0);
  ref.listen(authProvider, (_, __) => authListenable.value++);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final loggedIn = ref.read(authProvider).isLoggedIn;
      final onLogin = state.uri.path == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/tickets', builder: (context, state) => const TicketsScreen()),
          GoRoute(path: '/tickets/new', builder: (context, state) => const TicketFormScreen()),
          GoRoute(
            path: '/tickets/:id',
            builder: (context, state) =>
                TicketDetailScreen(ticketId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/printers', builder: (context, state) => const PrintersScreen()),
          GoRoute(path: '/vendors', builder: (context, state) => const VendorsScreen()),
          GoRoute(path: '/departments', builder: (context, state) => const DepartmentsScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/executive', builder: (context, state) => const ExecutiveScreen()),
          GoRoute(path: '/users', builder: (context, state) => const UsersScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
          GoRoute(path: '/audit-log', builder: (context, state) => const AuditLogScreen()),
        ],
      ),
    ],
  );
});

class PrinterUpkeepApp extends ConsumerWidget {
  const PrinterUpkeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'ICT Printer Upkeep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: ref.watch(_routerProvider),
    );
  }
}
