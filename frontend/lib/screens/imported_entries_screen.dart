import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';
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

  Future<void> _rejectAll() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject All Imported Entries?'),
        content: Text('All ${_entries.length} entries will be discarded without applying to customer balances.'),
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
      final result = await ApiService.bulkRejectStagedEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Rejected all')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    // Split entries into debit (udhaar) and credit (wasooli) so we can show
    // a correct net balance instead of just summing every amount together.
    final totalDebit = _entries
        .where((e) => e['type'] == 'udhaar')
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
    final totalCredit = _entries
        .where((e) => e['type'] != 'udhaar')
        .fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
    final netBalance = totalDebit - totalCredit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imported Entries (Approval List)'),
        actions: _entries.isNotEmpty
            ? [
                Tooltip(
                  message: 'Approve All Entries',
                  child: IconButton(
                    icon: const Icon(Icons.done_all, color: Colors.green),
                    onPressed: _approveAll,
                  ),
                ),
                Tooltip(
                  message: 'Reject All Entries',
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: _rejectAll,
                  ),
                ),
              ]
            : null,
      ),
      bottomNavigationBar: _entries.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Reject All', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _rejectAll,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Approve All', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _approveAll,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.marigold.withOpacity(0.12),
                  child: Column(
                    children: [
                                            Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Udhaar: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          AnimatedBalanceText(value: totalDebit, style: const TextStyle(color: AppColors.rickshawRed, fontSize: 12, fontWeight: FontWeight.bold)),
                          const Text('   |   Wasooli: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          AnimatedBalanceText(value: totalCredit, style: const TextStyle(color: AppColors.truckGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Udhaar: Rs ${totalDebit.toStringAsFixed(0)}   |   Wasooli: Rs ${totalCredit.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Net Balance: Rs ${netBalance.abs().toStringAsFixed(0)}'
                        '${netBalance > 0 ? " (Udhaar)" : (netBalance < 0 ? " (Wasooli)" : "")}',
                        style: TextStyle(
                          color: netBalance > 0
                              ? Colors.red
                              : (netBalance < 0 ? Colors.green : Colors.grey),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
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
                                          color: isDebit ? AppColors.rickshawRed : AppColors.truckGreen,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item['customer_name'] ?? 'Unknown',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ),
                                        AnimatedBalanceText(
                                          value: (item['amount'] as num).toDouble(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDebit ? AppColors.rickshawRed : AppColors.truckGreen,
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