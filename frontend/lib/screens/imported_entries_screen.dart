import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

/// Every entry from a Sheet sync lands here first — NOT in the customer's
/// balance yet. The Owner reviews and approves each one (or Approves All)
/// before it actually counts as a real transaction.
class ImportedEntriesScreen extends StatefulWidget {
  const ImportedEntriesScreen({super.key});

  @override
  State<ImportedEntriesScreen> createState() => _ImportedEntriesScreenState();
}

class _ImportedEntriesScreenState extends State<ImportedEntriesScreen> {
  List<dynamic> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getStagedEntries();
      setState(() => _entries = data);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    try {
      await ApiService.approveStagedEntry(item['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item['customer_name']} — applied to balance')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject This Entry?'),
        content: Text(
          'This will NOT be applied to ${item['customer_name']}\'s balance. '
          'If it appears again in a future sync, it will be reviewed again.',
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
    if (confirmed != true) return;
    try {
      await ApiService.rejectStagedEntry(item['id']);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _approveAll() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve All Imported Entries?'),
        content: Text('All ${_entries.length} entries will be applied to their customers\' balances right now.'),
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
      final result = await ApiService.bulkApproveStagedEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Approved all')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM, hh:mm a');
    final total = _entries.fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(title: const Text('Imported Entries')),
      floatingActionButton: _entries.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _approveAll,
              backgroundColor: Colors.green,
              icon: const Icon(Icons.done_all),
              label: const Text('Approve All'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Column(
                    children: [
                      Text(
                        '${_entries.length} entries awaiting your approval',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text('Total: Rs ${total.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      const Text(
                        'These have NOT been added to any customer\'s balance yet.',
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                              SizedBox(height: 12),
                              Text('Nothing waiting for approval'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final item = _entries[index];
                            final isDebit = item['type'] == 'udhaar';
                            DateTime? d;
                            try {
                              d = DateTime.parse(item['created_at']);
                            } catch (_) {}

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                          color: isDebit ? Colors.red : Colors.green,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item['customer_name'] ?? 'Unknown',
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
                                    Text(
                                      '${isDebit ? "Udhaar (Debit)" : "Wasooli (Credit)"}'
                                      '${d != null ? " · ${dateFormat.format(d)}" : ""}',
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                            onPressed: () => _approve(item),
                                            child: const Text('Approve'),
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
              ],
            ),
    );
  }
}
