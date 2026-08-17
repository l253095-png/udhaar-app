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

  Future<void> _link(Map<String, dynamic> item) async {
    try {
      await ApiService.resolvePendingSync(item['id'], 'link', customerId: item['suggested_customer_id']);
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
        content: const Text('This sheet row will be ignored — no customer or transaction will be created.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Sheet Review')),
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
                                const Text('No matching customer found — likely a new customer',
                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                              const SizedBox(height: 12),
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
