import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../core/api_client.dart';
import '../models/models.dart';

final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Supabase client. Data queries target the `printerupkeep` schema via
/// `sb.schema('printerupkeep').from(...)`.
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

// --- Theme ------------------------------------------------------------------

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, bool>((ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<bool> {
  ThemeModeNotifier() : super(false) {
    SharedPreferences.getInstance().then((p) => state = p.getBool('darkMode') ?? false);
  }

  Future<void> toggle() async {
    state = !state;
    (await SharedPreferences.getInstance()).setBool('darkMode', state);
  }
}

// --- Auth --------------------------------------------------------------------

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});
  final AuthUser? user;
  final bool loading;
  final String? error;

  bool get isLoggedIn => user != null;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(supabaseProvider));
});

/// Auth backed by Supabase Auth (email + password). The app-specific role +
/// display name live in printerupkeep.profiles, keyed to the auth user id.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._sb) : super(const AuthState()) {
    _restore();
    // Clear local state if the Supabase session ends (expiry / sign-out).
    _sb.auth.onAuthStateChange.listen((data) {
      if (data.session == null && mounted) state = const AuthState();
    });
  }

  final SupabaseClient _sb;

  /// Load the caller's profile (role, full name) to build an AuthUser.
  Future<AuthUser> _profile(User user) async {
    try {
      final row = await _sb
          .schema('printerupkeep')
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .maybeSingle();
      final fullName = (row?['full_name'] as String?) ?? '';
      return AuthUser(
        id: user.id,
        username: user.email ?? '',
        fullName: fullName.isNotEmpty ? fullName : (user.email ?? ''),
        role: (row?['role'] as String?) ?? 'viewer',
      );
    } catch (_) {
      return AuthUser(id: user.id, username: user.email ?? '', fullName: user.email ?? '', role: 'viewer');
    }
  }

  Future<void> _restore() async {
    final user = _sb.auth.currentUser;
    if (user != null) state = AuthState(user: await _profile(user));
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(loading: true);
    try {
      final res = await _sb.auth.signInWithPassword(email: email.trim(), password: password);
      final user = res.user;
      if (user == null) {
        state = const AuthState(error: 'Login failed');
        return;
      }
      state = AuthState(user: await _profile(user));
    } on AuthException catch (e) {
      state = AuthState(error: e.message);
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  Future<void> logout() async {
    await _sb.auth.signOut();
    state = const AuthState();
  }
}

// --- Lookups (dropdown data) --------------------------------------------------

final workflowStagesProvider = FutureProvider<List<WorkflowStage>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/lookups/workflow-stages');
  return (data as List).map((e) => WorkflowStage.fromJson(e)).toList();
});

final issueCategoriesProvider = FutureProvider<List<IssueCategory>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/lookups/issue-categories');
  return (data as List).map((e) => IssueCategory.fromJson(e)).toList();
});

final departmentsProvider = FutureProvider<List<Department>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/departments');
  return (data as List).map((e) => Department.fromJson(e)).toList();
});

final vendorsProvider = FutureProvider<List<Vendor>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/vendors');
  return (data as List).map((e) => Vendor.fromJson(e)).toList();
});

final printersProvider = FutureProvider<List<Printer>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/printers');
  return (data as List).map((e) => Printer.fromJson(e)).toList();
});

/// A single printer's consumables catalogue (toners/drums/parts), used by the
/// ticket form so the reporter simply ticks which colour(s)/parts to replace.
final printerConsumablesProvider =
    FutureProvider.family<List<PrinterConsumable>, String>((ref, printerId) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/printers/$printerId/consumables');
  return (data as List).map((e) => PrinterConsumable.fromJson(e)).toList();
});

final usersProvider = FutureProvider<List<UserAccount>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/users');
  return (data as List).map((e) => UserAccount.fromJson(e)).toList();
});

// --- Tickets -------------------------------------------------------------------

class TicketFilters {
  const TicketFilters({
    this.search,
    this.status,
    this.departmentId,
    this.vendorId,
    this.priority,
    this.printerType,
    this.printerId,
    this.printerLabel,
    this.assignedTo,
    this.dateFrom,
    this.dateTo,
    this.openOnly = false,
    this.page = 1,
  });

  final String? search;
  final String? status;
  final String? departmentId;
  final String? vendorId;
  final String? priority;
  final String? printerType;
  final String? printerId;
  final String? printerLabel; // display-only, for the active-filter chip
  final String? assignedTo;
  final String? dateFrom;
  final String? dateTo;
  final bool openOnly;
  final int page;

  TicketFilters copyWith({
    String? Function()? search,
    String? Function()? status,
    String? Function()? departmentId,
    String? Function()? vendorId,
    String? Function()? priority,
    String? Function()? printerType,
    String? Function()? printerId,
    String? Function()? printerLabel,
    String? Function()? assignedTo,
    String? Function()? dateFrom,
    String? Function()? dateTo,
    bool? openOnly,
    int? page,
  }) =>
      TicketFilters(
        search: search != null ? search() : this.search,
        status: status != null ? status() : this.status,
        departmentId: departmentId != null ? departmentId() : this.departmentId,
        vendorId: vendorId != null ? vendorId() : this.vendorId,
        priority: priority != null ? priority() : this.priority,
        printerType: printerType != null ? printerType() : this.printerType,
        printerId: printerId != null ? printerId() : this.printerId,
        printerLabel: printerLabel != null ? printerLabel() : this.printerLabel,
        assignedTo: assignedTo != null ? assignedTo() : this.assignedTo,
        dateFrom: dateFrom != null ? dateFrom() : this.dateFrom,
        dateTo: dateTo != null ? dateTo() : this.dateTo,
        openOnly: openOnly ?? this.openOnly,
        page: page ?? this.page,
      );

  Map<String, dynamic> toQuery() => {
        if (search?.isNotEmpty == true) 'search': search,
        if (status != null) 'status': status,
        if (departmentId != null) 'department_id': departmentId,
        if (vendorId != null) 'vendor_id': vendorId,
        if (priority != null) 'priority': priority,
        if (printerType != null) 'printer_type': printerType,
        if (printerId != null) 'printer_id': printerId,
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (openOnly) 'open_only': 'true',
        'page': page,
        'page_size': 25,
      };
}

final ticketFiltersProvider = StateProvider<TicketFilters>((ref) => const TicketFilters());

final ticketsProvider = FutureProvider<TicketPage>((ref) async {
  ref.watch(authProvider);
  final filters = ref.watch(ticketFiltersProvider);
  final data = await ref.read(apiProvider).get('/api/tickets', query: filters.toQuery());
  return TicketPage.fromJson(data);
});

final ticketDetailProvider = FutureProvider.family<TicketDetail, String>((ref, id) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/tickets/$id');
  return TicketDetail.fromJson(data);
});

// --- Dashboard / notifications ---------------------------------------------------

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/dashboard');
  return DashboardData.fromJson(data);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/notifications', query: {'unread_only': 'true'});
  return (data as List).map((e) => AppNotification.fromJson(e)).toList();
});

// --- Audit log --------------------------------------------------------------

/// Filters for the admin audit-log viewer.
class AuditFilters {
  const AuditFilters({this.entityType, this.action, this.page = 1});

  final String? entityType;
  final String? action; // filtered client-side; kept here for future use
  final int page;

  AuditFilters copyWith({String? Function()? entityType, String? Function()? action, int? page}) =>
      AuditFilters(
        entityType: entityType != null ? entityType() : this.entityType,
        action: action != null ? action() : this.action,
        page: page ?? this.page,
      );
}

final auditFiltersProvider = StateProvider<AuditFilters>((ref) => const AuditFilters());

// --- Executive summary ------------------------------------------------------

/// Consolidated executive KPIs + supporting breakdowns for justifying ICT
/// resourcing. Raw JSON from /api/reports/executive/summary.
final executiveSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authProvider);
  final data = await ref.read(apiProvider).get('/api/reports/executive/summary');
  return data as Map<String, dynamic>;
});

final auditLogProvider = FutureProvider<AuditLogPage>((ref) async {
  ref.watch(authProvider);
  final f = ref.watch(auditFiltersProvider);
  final data = await ref.read(apiProvider).get('/api/audit-logs', query: {
    if (f.entityType != null) 'entity_type': f.entityType,
    'page': f.page,
    'page_size': 50,
  });
  return AuditLogPage.fromJson(data);
});
