import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  List<dynamic> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getPendingSyncs();
      setState(() => _pending = data);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _bulkApproveAsCreate() async {
    if (_pending.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve All Entries?'),
        content: Text('Create new customers for all ${_pending.length} pending entries and import transactions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final pendingIds = _pending.map<int>((item) => item['id'] as int).toList();
      await ApiService.bulkApproveAsCreate(pendingIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_pending.length} entries approved and customers created')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _bulkReject() async {
    if (_pending.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject All Entries?'),
        content: Text('Reject all ${_pending.length} pending entries. No customers or transactions will be created.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final pendingIds = _pending.map<int>((item) => item['id'] as int).toList();
      await ApiService.bulkRejectPending(pendingIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_pending.length} entries rejected')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _link(Map<String, dynamic> item) async {
    try {
      await ApiService.resolvePendingSync(item['id'], 'link', customerId: item['suggested_customer_id']);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  /// Opens a searchable list of ALL customers so the Owner can link this sheet
  /// entry to whichever customer they choose — used when the auto-suggestion
  /// is wrong, or when there was no suggestion at all.
  Future<void> _linkToChosenCustomer(Map<String, dynamic> item) async {
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomerPickerDialog(sheetName: item['sheet_name']?.toString() ?? ''),
    );
    if (chosen == null) return;

    try {
      await ApiService.resolvePendingSync(item['id'], 'link', customerId: chosen['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linked to ${chosen['name']}')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _createNew(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['sheet_name']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create New Customer'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create & Import')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.resolvePendingSync(item['id'], 'create', newCustomerName: controller.text.trim());
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Entry?'),
        content: const Text(
          'This sheet row will be ignored — no customer or transaction will be created. '
          'If this name appears again in a future sheet, it will be flagged for review again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.resolvePendingSync(item['id'], 'reject');
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _ignorePermanently(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ignore This Name Permanently?'),
        content: Text(
          '"${item['sheet_name']}" will be skipped automatically every time it appears in the sheet '
          'from now on (useful for entries like "43BRENT" that turn out to be a rent/location code, '
          'not a real customer). You will not be asked about it again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ignore Permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.resolvePendingSync(item['id'], 'ignore');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item['sheet_name']}" will be auto-skipped from now on')),
          );
        }
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Sheet Review'),
        actions: _pending.isNotEmpty
            ? [
                Tooltip(
                  message: 'Approve all entries as new customers',
                  child: IconButton(
                    icon: const Icon(Icons.check_circle),
                    onPressed: _bulkApproveAsCreate,
                  ),
                ),
                Tooltip(
                  message: 'Reject all entries',
                  child: IconButton(
                    icon: const Icon(Icons.cancel),
                    onPressed: _bulkReject,
                  ),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                      SizedBox(height: 12),
                      Text('All caught up — nothing pending review'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _pending.length,
                    itemBuilder: (context, index) {
                      final item = _pending[index];
                      final hasSuggestion = item['suggested_customer_id'] != null;
                      final isDebit = item['type'] == 'udhaar';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['sheet_name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Text(
                                    'Rs ${(item['amount'] as num).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDebit ? Colors.red : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              Text(isDebit ? 'Udhaar (Debit)' : 'Wasooli (Credit)',
                                  style: const TextStyle(color: Colors.grey)),
                              if (item['note'] != null && item['note'].toString().isNotEmpty)
                                Text(item['note'], style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              if (hasSuggestion)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Did you mean: ${item['suggested_customer_name']}?'),
                                )
                              else
                                const Text('No matching customer found — pick one below, or create new',
                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                              const SizedBox(height: 10),
                              // Always available: browse/search the full customer list and
                              // link to whichever customer the Owner picks. This is the way
                              // out when the auto-suggestion is wrong or missing.
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.teal,
                                    side: const BorderSide(color: Colors.teal),
                                  ),
                                  icon: const Icon(Icons.person_search, size: 18),
                                  label: const Text('Link By List'),
                                  onPressed: () => _linkToChosenCustomer(item),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (hasSuggestion)
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _link(item),
                                        child: const Text('Link'),
                                      ),
                                    ),
                                  if (hasSuggestion) const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _createNew(item),
                                      child: const Text('Create New'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      onPressed: () => _reject(item),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Ignore this name permanently (skip it every time it appears)',
                                    icon: Icon(Icons.block, color: Colors.grey.shade700),
                                    onPressed: () => _ignorePermanently(item),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// A searchable picker listing every customer, so a pending sheet entry can be
/// linked to any of them — not just whatever the fuzzy matcher suggested.
class _CustomerPickerDialog extends StatefulWidget {
  final String sheetName;
  const _CustomerPickerDialog({required this.sheetName});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  List<dynamic> _all = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await ApiService.getCustomers();
      if (!mounted) return;
      setState(() {
        _all = customers;
        _filtered = customers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load customers: $e')));
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((c) {
              final name = (c['name'] ?? '').toString().toLowerCase();
              final phone = (c['phone'] ?? '').toString().toLowerCase();
              return name.contains(q) || phone.contains(q);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 500,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Link By List — Select Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (widget.sheetName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sheet entry: "${widget.sheetName}"',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _filter,
                    decoration: const InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(child: Text('No matching customers', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final c = _filtered[index];
                            final balance = ((c['balance'] as num?) ?? 0).toDouble();
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person, size: 20)),
                              title: Text(c['name']?.toString() ?? 'Unnamed'),
                              subtitle: Text(
                                (c['phone'] == null || c['phone'].toString().isEmpty)
                                    ? 'No phone'
                                    : c['phone'].toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Text(
                                'Rs ${balance.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: balance > 0 ? Colors.red : Colors.grey,
                                ),
                              ),
                              onTap: () => Navigator.pop(context, Map<String, dynamic>.from(c)),
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
