import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/workflow_tracker.dart';

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticketId));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load ticket: $e')),
      data: (d) => _TicketDetailView(detail: d),
    );
  }
}

class _TicketDetailView extends ConsumerWidget {
  const _TicketDetailView({required this.detail});

  final TicketDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = detail.ticket;
    final auth = ref.watch(authProvider);
    final canWrite = auth.user?.canWrite == true;
    final stages = ref.watch(workflowStagesProvider).valueOrNull ?? [];

    // First-reached timestamp per stage for the tracker column.
    final timestamps = <String, String>{};
    for (final h in detail.history) {
      timestamps.putIfAbsent(
          h['stage_code'] as String, () => _fmtShort(h['created_at']));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
            Text(t.ticketNumber, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 12),
            StatusBadge(label: t.statusLabel, blocked: t.isBlocked),
            const Spacer(),
            if (canWrite && !t.isTerminal) ...[
              OutlinedButton.icon(
                icon: Icon(t.isBlocked ? Icons.play_arrow : Icons.block),
                label: Text(t.isBlocked ? 'Unblock' : 'Mark Blocked'),
                onPressed: () => _toggleBlocked(context, ref, t),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Change Stage'),
                onPressed: () => _changeStageDialog(context, ref, t, stages),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Progress', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 16),
                    StageProgressBar(progress: detail.progress),
                    const Spacer(),
                    Text('Current stage: ${t.stageName}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 950;
          final left = Column(
            children: [
              _section(context, 'Process Tracking',
                  WorkflowTracker(steps: detail.tracker, timestamps: timestamps)),
              _section(context, 'General Information', _infoGrid(context, [
                ('Date Received', _dateOnly(t.dateReceived)),
                ('Time Received', t.timeReceived ?? '—'),
                ('ICT Ticket #', t.ictTicketNumber ?? '—'),
                ('Vendor Ticket #', t.vendorTicketNumber ?? '—'),
                ('Reported By', t.reportedBy),
                ('Department', t.departmentName ?? '—'),
                ('Phone', t.contactPhone ?? '—'),
                ('Email', t.contactEmail ?? '—'),
                ('Reporting Method', _title(t.reportingMethod)),
                ('Priority', t.priority.toUpperCase()),
              ])),
              _section(context, 'Printer', _infoGrid(context, [
                ('Asset Tag', t.printerAssetNumber ?? '—'),
                ('Model', t.printerModel ?? '—'),
                ('Serial Number', t.printerSerial ?? '—'),
                ('Owned/Leased', _title(t.printerType)),
                ('Location', t.printerLocation ?? '—'),
              ])),
              _section(
                context,
                'Issue',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Category: ${t.issueCategory ?? '—'}'),
                    const SizedBox(height: 6),
                    Text(t.description ?? 'No description'),
                    if (detail.consumables.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Consumables requested',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final c in detail.consumables)
                            Chip(
                              avatar: _colorDot(c['color']?.toString()),
                              label: Text(_consumableLabel(c)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          final right = Column(
            children: [
              _procurementSection(context, ref, canWrite),
              _historySection(context),
              _notesSection(context, ref, canWrite),
              _filesSection(context, ref, canWrite),
            ],
          );
          if (!wide) return Column(children: [left, right]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right),
            ],
          );
        }),
      ],
    );
  }

  // --- Sections --------------------------------------------------------------

  Widget _section(BuildContext context, String title, Widget child, {Widget? action}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  if (action != null) action,
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  Widget _infoGrid(BuildContext context, List<(String, String)> entries) => Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          for (final (label, value) in entries)
            SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      );

  Widget _procurementSection(BuildContext context, WidgetRef ref, bool canWrite) {
    final t = detail.ticket;
    final quotation = detail.quotations.isEmpty ? null : detail.quotations.last;
    final requisition = detail.requisitions.isEmpty ? null : detail.requisitions.last;
    final accounts = detail.approvals.where((a) => a['approval_type'] == 'accounts').toList();
    final ga = detail.approvals.where((a) => a['approval_type'] == 'ga').toList();
    final po = detail.purchaseOrders.isEmpty ? null : detail.purchaseOrders.last;
    final api = ref.read(apiProvider);

    Widget row(String label, String value, {VoidCallback? onEdit, List<Widget> extra = const []}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
              Expanded(child: Text(value)),
              ...extra,
              if (onEdit != null && canWrite)
                IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: onEdit),
            ],
          ),
        );

    return _section(
      context,
      'Procurement',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vendor', style: Theme.of(context).textTheme.titleSmall),
          row('Vendor', t.vendorName ?? 'Not assigned'),
          const Divider(),
          Text('Quotation', style: Theme.of(context).textTheme.titleSmall),
          row(
            'Quotation',
            quotation == null
                ? 'None recorded'
                : '#${quotation['quotation_number'] ?? '—'} · ${quotation['currency']} ${quotation['amount'] ?? '—'}'
                    ' · received ${_dateOnly(quotation['received_date']?.toString())}',
            onEdit: () => _quotationDialog(context, ref, quotation),
          ),
          if (canWrite && quotation == null)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Record quotation'),
              onPressed: () => _quotationDialog(context, ref, null),
            ),
          const Divider(),
          Text('Requisition', style: Theme.of(context).textTheme.titleSmall),
          row(
            'Requisition',
            requisition == null
                ? 'Not prepared'
                : '${requisition['requisition_number']} · ${_dateOnly(requisition['prepared_date']?.toString())}',
            extra: [
              if (requisition != null)
                IconButton(
                  tooltip: 'Download PDF',
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  onPressed: () => launchUrlString(api.downloadUrl(
                      '/api/tickets/${t.id}/requisitions/${requisition['id']}/pdf')),
                ),
            ],
          ),
          if (canWrite && requisition == null)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Generate requisition'),
              onPressed: () async {
                await api.post('/api/tickets/${t.id}/requisitions', body: {});
                ref.invalidate(ticketDetailProvider(t.id));
              },
            ),
          const Divider(),
          Text('Accounts', style: Theme.of(context).textTheme.titleSmall),
          row(
            'Funds',
            accounts.isEmpty ? 'Not sent yet' : _approvalSummary(accounts.last),
            onEdit: () => _approvalDialog(context, ref, 'accounts',
                accounts.isEmpty ? null : accounts.last),
          ),
          const Divider(),
          Text('GA', style: Theme.of(context).textTheme.titleSmall),
          row(
            'Approval',
            ga.isEmpty ? 'Not sent yet' : _approvalSummary(ga.last),
            onEdit: () => _approvalDialog(context, ref, 'ga', ga.isEmpty ? null : ga.last),
          ),
          const Divider(),
          Text('Purchase Order', style: Theme.of(context).textTheme.titleSmall),
          row(
            'PO',
            po == null
                ? 'Not issued'
                : '${po['po_number']} · ${_dateOnly(po['issued_date']?.toString())}',
          ),
          if (canWrite && po == null)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Record purchase order'),
              onPressed: () => _poDialog(context, ref),
            ),
        ],
      ),
    );
  }

  Widget _historySection(BuildContext context) => _section(
        context,
        'Status History',
        Column(
          children: [
            for (final h in detail.history.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text('${h['stage_name']}'),
                subtitle: Text(
                  '${h['changed_by_name']} · ${_fmtLong(h['created_at'])}'
                  '${h['notes'] != null && '${h['notes']}'.isNotEmpty ? '\n${h['notes']}' : ''}',
                ),
              ),
          ],
        ),
      );

  Widget _notesSection(BuildContext context, WidgetRef ref, bool canWrite) => _section(
        context,
        'Notes',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail.notes.isEmpty) const Text('No notes'),
            for (final n in detail.notes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sticky_note_2_outlined, size: 18),
                title: Text('${n['note']}'),
                subtitle: Text('${n['user_name']} · ${_fmtLong(n['created_at'])}'),
              ),
          ],
        ),
        action: canWrite
            ? TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add note'),
                onPressed: () => _addNoteDialog(context, ref),
              )
            : null,
      );

  Widget _filesSection(BuildContext context, WidgetRef ref, bool canWrite) {
    final api = ref.read(apiProvider);
    return _section(
      context,
      'Attachments',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.files.isEmpty) const Text('No attachments'),
          for (final f in detail.files)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file, size: 18),
              title: Text('${f['file_name']}'),
              subtitle: Text('${f['category']} · ${f['uploaded_by_name']} · ${_fmtLong(f['created_at'])}'),
              onTap: () => launchUrlString(api.downloadUrl('/api/files/${f['id']}')),
            ),
        ],
      ),
      action: canWrite
          ? TextButton.icon(
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Upload'),
              onPressed: () => _uploadFile(context, ref),
            )
          : null,
    );
  }

  // --- Dialog helpers ----------------------------------------------------------

  Future<void> _changeStageDialog(
      BuildContext context, WidgetRef ref, Ticket t, List<WorkflowStage> stages) async {
    final selectable = stages.where((s) => s.id != 0 && s.code != t.stageCode).toList();
    // Default to the next stage on the happy path.
    WorkflowStage? selected = selectable
        .where((s) => s.sortOrder > t.stageSortOrder && s.sortOrder < 90)
        .fold<WorkflowStage?>(null, (min, s) => min == null || s.sortOrder < min.sortOrder ? s : min);
    final notes = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Workflow Stage'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<WorkflowStage>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'New stage'),
                  items: [
                    for (final s in selectable)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => selected = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      await _apiAction(context, ref, () async {
        await ref.read(apiProvider).post('/api/tickets/${t.id}/stage', body: {
          'stage': selected!.code,
          if (notes.text.isNotEmpty) 'notes': notes.text,
        });
      });
    }
  }

  Future<void> _toggleBlocked(BuildContext context, WidgetRef ref, Ticket t) async {
    String? reason;
    if (!t.isBlocked) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark ticket as blocked'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text;
    }
    await _apiAction(context, ref, () async {
      await ref.read(apiProvider).patch('/api/tickets/${t.id}', body: {
        'isBlocked': !t.isBlocked,
        'blockedReason': reason,
      });
    });
  }

  Future<void> _quotationDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? existing) async {
    final number = TextEditingController(text: existing?['quotation_number']?.toString() ?? '');
    final amount = TextEditingController(text: existing?['amount']?.toString() ?? '');
    DateTime? received = DateTime.tryParse(existing?['received_date']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Record Quotation' : 'Edit Quotation'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: number, decoration: const InputDecoration(labelText: 'Quotation number')),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(received == null
                      ? 'Date received'
                      : DateFormat('y-MM-dd').format(received!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => received = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _apiAction(context, ref, () async {
        await ref.read(apiProvider).post('/api/tickets/${detail.ticket.id}/quotations', body: {
          if (existing != null) 'id': existing['id'],
          'vendorId': detail.ticket.vendorId,
          if (number.text.isNotEmpty) 'quotationNumber': number.text,
          if (amount.text.isNotEmpty) 'amount': double.tryParse(amount.text),
          if (received != null) 'receivedDate': DateFormat('y-MM-dd').format(received!),
        });
      });
    }
  }

  Future<void> _approvalDialog(
      BuildContext context, WidgetRef ref, String type, Map<String, dynamic>? existing) async {
    final decisions = type == 'accounts'
        ? ['pending', 'funds_available', 'funds_unavailable']
        : ['pending', 'approved', 'rejected'];
    String decision = existing?['decision']?.toString() ?? 'pending';
    DateTime? sent = DateTime.tryParse(existing?['sent_date']?.toString() ?? '');
    DateTime? decided = DateTime.tryParse(existing?['decision_date']?.toString() ?? '');
    final approvedBy = TextEditingController(text: existing?['approved_by']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(type == 'accounts' ? 'Accounts Approval' : 'GA Approval'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: decision,
                  decoration: const InputDecoration(labelText: 'Decision'),
                  items: [for (final d in decisions) DropdownMenuItem(value: d, child: Text(_title(d)))],
                  onChanged: (v) => setState(() => decision = v ?? 'pending'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(sent == null ? 'Date sent' : 'Sent ${DateFormat('y-MM-dd').format(sent!)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => sent = d);
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: Text(decided == null
                      ? 'Decision date'
                      : 'Decided ${DateFormat('y-MM-dd').format(decided!)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => decided = d);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: approvedBy,
                  decoration: InputDecoration(
                    labelText: 'Approved by',
                    hintText: type == 'accounts' ? 'Accounts officer name' : 'GA officer name',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _apiAction(context, ref, () async {
        await ref.read(apiProvider).post('/api/tickets/${detail.ticket.id}/approvals/$type', body: {
          'decision': decision,
          if (sent != null) 'sentDate': DateFormat('y-MM-dd').format(sent!),
          if (decided != null) 'decisionDate': DateFormat('y-MM-dd').format(decided!),
          if (approvedBy.text.trim().isNotEmpty) 'approvedBy': approvedBy.text.trim(),
        });
      });
    }
  }

  Future<void> _poDialog(BuildContext context, WidgetRef ref) async {
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Purchase Order'),
        content: TextField(
          controller: number,
          decoration: const InputDecoration(labelText: 'PO number'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && number.text.isNotEmpty) {
      await _apiAction(context, ref, () async {
        await ref
            .read(apiProvider)
            .post('/api/tickets/${detail.ticket.id}/purchase-orders', body: {'poNumber': number.text});
      });
    }
  }

  Future<void> _addNoteDialog(BuildContext context, WidgetRef ref) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: note,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && note.text.trim().isNotEmpty) {
      await _apiAction(context, ref, () async {
        await ref
            .read(apiProvider)
            .post('/api/tickets/${detail.ticket.id}/notes', body: {'note': note.text.trim()});
      });
    }
  }

  Future<void> _uploadFile(BuildContext context, WidgetRef ref) async {
    String category = 'document';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Upload Attachment'),
          content: DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [
              DropdownMenuItem(value: 'screenshot', child: Text('Screenshot')),
              DropdownMenuItem(value: 'photo', child: Text('Photo')),
              DropdownMenuItem(value: 'document', child: Text('Supporting Document')),
              DropdownMenuItem(value: 'quotation', child: Text('Quotation')),
              DropdownMenuItem(value: 'requisition', child: Text('Signed Requisition')),
              DropdownMenuItem(value: 'purchase_order', child: Text('Purchase Order')),
              DropdownMenuItem(value: 'delivery_note', child: Text('Delivery Note')),
            ],
            onChanged: (v) => setState(() => category = v ?? 'document'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose file…')),
          ],
        ),
      ),
    );
    if (proceed != true) return;

    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    await _apiAction(context, ref, () async {
      await ref.read(apiProvider).upload(
            '/api/files/tickets/${detail.ticket.id}?category=$category',
            MultipartFile.fromBytes(file.bytes!, filename: file.name),
          );
    });
  }

  Future<void> _apiAction(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(ticketDetailProvider(detail.ticket.id));
      ref.invalidate(ticketsProvider);
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  /// One-line summary of an approval row: decision, dates and who approved.
  static String _approvalSummary(Map<String, dynamic> a) {
    final parts = <String>[_title(a['decision']?.toString())];
    if (a['sent_date'] != null) parts.add('sent ${_dateOnly(a['sent_date']?.toString())}');
    if (a['decision_date'] != null) {
      parts.add('decided ${_dateOnly(a['decision_date']?.toString())}');
    }
    final by = a['approved_by']?.toString();
    if (by != null && by.isNotEmpty && by != '—') parts.add('by $by');
    return parts.join(' · ');
  }

  /// Label for a requested consumable chip, e.g. "Black Toner ×2 (HP 26A)".
  static String _consumableLabel(Map<String, dynamic> c) {
    final color = c['color']?.toString();
    final label = c['label']?.toString();
    final kind = c['kind']?.toString() ?? '';
    var text = label != null && label.isNotEmpty
        ? label
        : [if (color != null && color.isNotEmpty) _title(color), _title(kind)].join(' ');
    final qty = c['quantity'];
    if (qty is int && qty > 1) text = '$text ×$qty';
    final model = c['model_code']?.toString();
    if (model != null && model.isNotEmpty) text = '$text ($model)';
    return text;
  }

  /// Small colour swatch avatar for a consumable chip (null for non-colour).
  static Widget? _colorDot(String? color) {
    final swatch = switch (color) {
      'black' => Colors.black,
      'cyan' => Colors.cyan,
      'magenta' => const Color(0xFFD81B60),
      'yellow' => const Color(0xFFF9A825),
      'tricolor' => Colors.deepPurple,
      'other' => Colors.blueGrey,
      _ => null,
    };
    return swatch == null ? null : CircleAvatar(radius: 7, backgroundColor: swatch);
  }

  // --- Formatting -------------------------------------------------------------

  static String _dateOnly(String? value) =>
      value == null || value.isEmpty ? '—' : value.substring(0, value.length >= 10 ? 10 : value.length);

  static String _title(String? value) => value == null || value.isEmpty
      ? '—'
      : value.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

  static String _fmtShort(dynamic value) {
    final dt = DateTime.tryParse('$value')?.toLocal();
    return dt == null ? '' : DateFormat('d MMM, h:mm a').format(dt);
  }

  static String _fmtLong(dynamic value) {
    final dt = DateTime.tryParse('$value')?.toLocal();
    return dt == null ? '$value' : DateFormat('d MMM y, h:mm a').format(dt);
  }
}
