import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/models.dart';

final apiProvider = Provider<ApiClient>((ref) => ApiClient());

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
  return AuthNotifier(ref.read(apiProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api) : super(const AuthState()) {
    _restore();
  }

  final ApiClient _api;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    _api.token = token;
    try {
      final me = await _api.get('/api/auth/me');
      state = AuthState(
        user: AuthUser(
          id: me['id'],
          username: me['username'],
          fullName: me['full_name'] ?? '',
          role: me['role'] ?? 'viewer',
        ),
      );
    } catch (_) {
      _api.token = null;
      prefs.remove('token');
    }
  }

  Future<void> login(String username, String password) async {
    state = const AuthState(loading: true);
    try {
      final data = await _api.post('/api/auth/login', body: {'username': username, 'password': password});
      _api.token = data['token'];
      (await SharedPreferences.getInstance()).setString('token', data['token']);
      state = AuthState(user: AuthUser.fromJson(data['user']));
    } catch (e) {
      state = AuthState(error: ApiClient.errorMessage(e));
    }
  }

  Future<void> logout() async {
    _api.token = null;
    (await SharedPreferences.getInstance()).remove('token');
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
