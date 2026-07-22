/// Domain models mirroring the REST API's snake_case JSON.
library;

String? _s(dynamic v) => v?.toString();
int _i(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
double? _d(dynamic v) => v == null ? null : double.tryParse(v.toString());
bool _b(dynamic v) => v == true || v == 'true';

class AuthUser {
  AuthUser({required this.id, required this.username, required this.fullName, required this.role});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'],
        username: json['username'],
        fullName: json['fullName'] ?? json['full_name'] ?? '',
        role: json['role'] ?? 'viewer',
      );

  final String id;
  final String username;
  final String fullName;
  final String role;

  bool get canWrite => role == 'admin' || role == 'ict_officer';
  bool get isAdmin => role == 'admin';
}

class WorkflowStage {
  WorkflowStage({
    required this.id,
    required this.code,
    required this.name,
    required this.statusLabel,
    required this.sortOrder,
    required this.isTerminal,
  });

  factory WorkflowStage.fromJson(Map<String, dynamic> json) => WorkflowStage(
        id: _i(json['id']),
        code: json['code'],
        name: json['name'],
        statusLabel: json['status_label'] ?? '',
        sortOrder: _i(json['sort_order']),
        isTerminal: _b(json['is_terminal']),
      );

  final int id;
  final String code;
  final String name;
  final String statusLabel;
  final int sortOrder;
  final bool isTerminal;
}

class TrackerStep {
  TrackerStep({required this.code, required this.name, required this.state, required this.reached});

  factory TrackerStep.fromJson(Map<String, dynamic> json) => TrackerStep(
        code: json['code'],
        name: json['name'],
        state: json['state'],
        reached: _b(json['reached']),
      );

  final String code;
  final String name;
  final String state; // done | current | waiting | blocked | not_started
  final bool reached;
}

class Ticket {
  Ticket.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        ticketNumber = json['ticket_number'] ?? '',
        dateReceived = _s(json['date_received']),
        timeReceived = _s(json['time_received']),
        reportedBy = json['reported_by'] ?? '',
        priority = json['priority'] ?? 'medium',
        departmentName = _s(json['department_name']),
        vendorName = _s(json['vendor_name']),
        printerAssetNumber = _s(json['printer_asset_number']),
        printerModel = _s(json['printer_model']),
        printerType = _s(json['printer_type']),
        issueCategory = _s(json['issue_category']),
        assignedToName = _s(json['assigned_to_name']),
        stageCode = json['stage_code'] ?? '',
        stageName = json['stage_name'] ?? '',
        statusLabel = json['status_label'] ?? '',
        stageSortOrder = _i(json['stage_sort_order']),
        isBlocked = _b(json['is_blocked']),
        isTerminal = _b(json['is_terminal']),
        ictTicketNumber = _s(json['ict_ticket_number']),
        vendorTicketNumber = _s(json['vendor_ticket_number']),
        completionDate = _s(json['completion_date']),
        description = _s(json['description']),
        contactPhone = _s(json['contact_phone']),
        contactEmail = _s(json['contact_email']),
        reportingMethod = _s(json['reporting_method']),
        remarks = _s(json['remarks']),
        departmentId = _s(json['department_id']),
        vendorId = _s(json['vendor_id']),
        printerId = _s(json['printer_id']),
        issueCategoryId = json['issue_category_id'] == null ? null : _i(json['issue_category_id']),
        assignedTo = _s(json['assigned_to']),
        printerSerial = _s(json['printer_serial']),
        printerLocation = _s(json['printer_location']);

  final String id;
  final String ticketNumber;
  final String? dateReceived;
  final String? timeReceived;
  final String reportedBy;
  final String priority;
  final String? departmentName;
  final String? vendorName;
  final String? printerAssetNumber;
  final String? printerModel;
  final String? printerType;
  final String? issueCategory;
  final String? assignedToName;
  final String stageCode;
  final String stageName;
  final String statusLabel;
  final int stageSortOrder;
  final bool isBlocked;
  final bool isTerminal;
  final String? ictTicketNumber;
  final String? vendorTicketNumber;
  final String? completionDate;
  final String? description;
  final String? contactPhone;
  final String? contactEmail;
  final String? reportingMethod;
  final String? remarks;
  final String? departmentId;
  final String? vendorId;
  final String? printerId;
  final int? issueCategoryId;
  final String? assignedTo;
  final String? printerSerial;
  final String? printerLocation;
}

class TicketDetail {
  TicketDetail.fromJson(Map<String, dynamic> json)
      : ticket = Ticket.fromJson(json['ticket']),
        progress = _d(json['progress']) ?? 0,
        tracker = (json['tracker'] as List).map((e) => TrackerStep.fromJson(e)).toList(),
        history = (json['history'] as List).cast<Map<String, dynamic>>(),
        notes = (json['notes'] as List).cast<Map<String, dynamic>>(),
        files = (json['files'] as List).cast<Map<String, dynamic>>(),
        quotations = (json['quotations'] as List).cast<Map<String, dynamic>>(),
        requisitions = (json['requisitions'] as List).cast<Map<String, dynamic>>(),
        approvals = (json['approvals'] as List).cast<Map<String, dynamic>>(),
        purchaseOrders = (json['purchase_orders'] as List).cast<Map<String, dynamic>>(),
        deliveryNotes = (json['delivery_notes'] as List).cast<Map<String, dynamic>>(),
        consumables = (json['consumables'] as List? ?? const []).cast<Map<String, dynamic>>();

  final Ticket ticket;
  final double progress;
  final List<TrackerStep> tracker;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> files;
  final List<Map<String, dynamic>> quotations;
  final List<Map<String, dynamic>> requisitions;
  final List<Map<String, dynamic>> approvals;
  final List<Map<String, dynamic>> purchaseOrders;
  final List<Map<String, dynamic>> deliveryNotes;
  final List<Map<String, dynamic>> consumables;
}

class TicketPage {
  TicketPage.fromJson(Map<String, dynamic> json)
      : items = (json['items'] as List).map((e) => Ticket.fromJson(e)).toList(),
        total = _i(json['total']),
        page = _i(json['page']),
        pageSize = _i(json['pageSize']);

  final List<Ticket> items;
  final int total;
  final int page;
  final int pageSize;
}

class Vendor {
  Vendor.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        companyName = json['company_name'] ?? '',
        address = _s(json['address']),
        phone = _s(json['phone']),
        email = _s(json['email']),
        contactPerson = _s(json['contact_person']),
        website = _s(json['website']),
        notes = _s(json['notes']),
        vendorTypes = (json['vendor_types'] as List? ?? []).map((e) => e.toString()).toList(),
        isActive = _b(json['is_active']),
        ticketCount = _i(json['ticket_count']);

  final String id;
  final String companyName;
  final String? address;
  final String? phone;
  final String? email;
  final String? contactPerson;
  final String? website;
  final String? notes;
  final List<String> vendorTypes;
  final bool isActive;
  final int ticketCount;
}

class Printer {
  Printer.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        assetNumber = json['asset_number'] ?? '',
        model = json['model'] ?? '',
        serialNumber = _s(json['serial_number']),
        printerType = json['printer_type'] ?? 'owned',
        departmentId = _s(json['department_id']),
        departmentName = _s(json['department_name']),
        location = _s(json['location']),
        building = _s(json['building']),
        floor = _s(json['floor']),
        vendorId = _s(json['vendor_id']),
        vendorName = _s(json['vendor_name']),
        warrantyExpiry = _s(json['warranty_expiry']),
        status = json['status'] ?? 'active',
        notes = _s(json['notes']),
        name = _s(json['name']),
        ipAddress = _s(json['ip_address']),
        macAddress = _s(json['mac_address']),
        connectionType = json['connection_type'] ?? 'network',
        isColor = _b(json['is_color']),
        consumablesModel = _s(json['consumables_model']),
        leaseStart = _s(json['lease_start']),
        leaseEnd = _s(json['lease_end']),
        leaseMonthlyCost = _d(json['lease_monthly_cost']),
        purchaseDate = _s(json['purchase_date']),
        purchaseCost = _d(json['purchase_cost']),
        lastServiceDate = _s(json['last_service_date']),
        nextServiceDue = _s(json['next_service_due']),
        totalIssues = _i(json['total_issues']),
        openIssues = _i(json['open_issues']),
        lastActivity = _s(json['last_activity']),
        lastTicketId = _s(json['last_ticket_id']),
        lastTicketNumber = _s(json['last_ticket_number']),
        lastStatusLabel = _s(json['last_status_label']),
        lastIssue = _s(json['last_issue']);

  final String id;
  final String assetNumber;
  final String model;
  final String? serialNumber;
  final String printerType;
  final String? departmentId;
  final String? departmentName;
  final String? location;
  final String? building;
  final String? floor;
  final String? vendorId;
  final String? vendorName;
  final String? warrantyExpiry;
  final String status;
  final String? notes;
  final String? name;
  final String? ipAddress;
  final String? macAddress;
  final String connectionType;
  final bool isColor;
  final String? consumablesModel;
  final String? leaseStart;
  final String? leaseEnd;
  final double? leaseMonthlyCost;
  final String? purchaseDate;
  final double? purchaseCost;
  final String? lastServiceDate;
  final String? nextServiceDue;

  // Per-printer activity summary (see printerRepo.SELECT).
  final int totalIssues;
  final int openIssues;
  final String? lastActivity;
  final String? lastTicketId;
  final String? lastTicketNumber;
  final String? lastStatusLabel;
  final String? lastIssue;

  bool get isLeased => printerType == 'leased';

  /// Short human-readable summary of the most recent activity, e.g.
  /// "2026-07-14 · Work In Progress" or "No issues logged".
  String get lastActivitySummary {
    if (lastActivity == null) return 'No issues logged';
    final date = lastActivity!.length >= 10 ? lastActivity!.substring(0, 10) : lastActivity!;
    return lastStatusLabel == null ? date : '$date · $lastStatusLabel';
  }

  String get label =>
      name?.isNotEmpty == true ? '$assetNumber — $name ($model)' : '$assetNumber — $model';

  /// "2026-01-01 → 2027-12-31" or null when not leased / no dates set.
  String? get leasePeriod {
    if (!isLeased || (leaseStart == null && leaseEnd == null)) return null;
    String d(String? v) => v == null ? '?' : v.substring(0, v.length >= 10 ? 10 : v.length);
    return '${d(leaseStart)} → ${d(leaseEnd)}';
  }
}

/// One item in a printer's consumables/parts catalogue (a toner, drum, part…),
/// defined by an admin so ticket-raisers pick from a list instead of typing.
class PrinterConsumable {
  PrinterConsumable.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        kind = json['kind'] ?? 'toner',
        color = _s(json['color']),
        modelCode = _s(json['model_code']),
        label = _s(json['label']);

  final String id;
  final String kind;
  final String? color;
  final String? modelCode;
  final String? label;

  static String titleCase(String v) =>
      v.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  /// Short label for a selection chip, e.g. "Black" or "Drum".
  String get shortLabel =>
      color != null ? titleCase(color!) : (label?.isNotEmpty == true ? label! : titleCase(kind));

  /// Full descriptive label, e.g. "Black Toner — HP 26A (CF226A)".
  String get fullLabel {
    final base = label?.isNotEmpty == true
        ? label!
        : [if (color != null) titleCase(color!), titleCase(kind)].join(' ');
    return modelCode?.isNotEmpty == true ? '$base — $modelCode' : base;
  }
}

class Department {
  Department.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        name = json['name'] ?? '',
        code = _s(json['code']),
        building = _s(json['building']),
        floor = _s(json['floor']),
        isActive = _b(json['is_active']),
        ticketCount = _i(json['ticket_count']);

  final String id;
  final String name;
  final String? code;
  final String? building;
  final String? floor;
  final bool isActive;
  final int ticketCount;
}

class UserAccount {
  UserAccount.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        username = json['username'] ?? '',
        fullName = json['full_name'] ?? '',
        email = _s(json['email']),
        phone = _s(json['phone']),
        role = json['role'] ?? 'viewer',
        roleName = _s(json['role_name']) ?? '',
        isActive = _b(json['is_active']);

  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final String roleName;
  final bool isActive;
}

class IssueCategory {
  IssueCategory.fromJson(Map<String, dynamic> json)
      : id = _i(json['id']),
        name = json['name'] ?? '';

  final int id;
  final String name;
}

class ChartPoint {
  ChartPoint.fromJson(Map<String, dynamic> json)
      : label = (json['label'] ?? json['month'] ?? '').toString(),
        count = _i(json['count']);

  final String label;
  final int count;
}

class DashboardData {
  DashboardData.fromJson(Map<String, dynamic> json)
      : stats = json['stats'] as Map<String, dynamic>,
        recentActivity = (json['recent_activity'] as List).cast<Map<String, dynamic>>(),
        monthlyRequests =
            ((json['charts']['monthly_requests']) as List).map((e) => ChartPoint.fromJson(e)).toList(),
        byDepartment = ((json['charts']['by_department']) as List).map((e) => ChartPoint.fromJson(e)).toList(),
        byVendor = ((json['charts']['by_vendor']) as List).map((e) => ChartPoint.fromJson(e)).toList(),
        ownedVsLeased =
            ((json['charts']['owned_vs_leased']) as List).map((e) => ChartPoint.fromJson(e)).toList(),
        statusBreakdown =
            ((json['charts']['status_breakdown']) as List).map((e) => ChartPoint.fromJson(e)).toList();

  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> recentActivity;
  final List<ChartPoint> monthlyRequests;
  final List<ChartPoint> byDepartment;
  final List<ChartPoint> byVendor;
  final List<ChartPoint> ownedVsLeased;
  final List<ChartPoint> statusBreakdown;

  double? get avgCompletionDays => _d(stats['avg_completion_days']);
}

/// One row of the audit trail: who did what, to which entity, and when.
class AuditLogEntry {
  AuditLogEntry.fromJson(Map<String, dynamic> json)
      : id = _i(json['id']),
        entityType = json['entity_type'] ?? '',
        entityId = _s(json['entity_id']) ?? '',
        action = json['action'] ?? '',
        field = _s(json['field']),
        oldValue = _s(json['old_value']),
        newValue = _s(json['new_value']),
        userId = _s(json['user_id']),
        userName = _s(json['user_name']),
        createdAt = _s(json['created_at']) ?? '';

  final int id;
  final String entityType;
  final String entityId;
  final String action;
  final String? field;
  final String? oldValue;
  final String? newValue;
  final String? userId;
  final String? userName;
  final String createdAt;
}

class AuditLogPage {
  AuditLogPage.fromJson(Map<String, dynamic> json)
      : items = (json['items'] as List).map((e) => AuditLogEntry.fromJson(e)).toList(),
        total = _i(json['total']),
        page = _i(json['page']),
        pageSize = _i(json['pageSize']);

  final List<AuditLogEntry> items;
  final int total;
  final int page;
  final int pageSize;
}

class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> json)
      : id = _i(json['id']),
        type = json['type'] ?? '',
        title = json['title'] ?? '',
        message = json['message'] ?? '',
        ticketId = _s(json['ticket_id']),
        ticketNumber = _s(json['ticket_number']),
        isRead = _b(json['is_read']),
        createdAt = _s(json['created_at']) ?? '';

  final int id;
  final String type;
  final String title;
  final String message;
  final String? ticketId;
  final String? ticketNumber;
  final bool isRead;
  final String createdAt;
}
