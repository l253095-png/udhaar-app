import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

/// Shows one customer's balance + full transaction history.
/// If [readOnly] is true (Worker), the Credit/Debit buttons are hidden.
class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final bool readOnly;

  const CustomerDetailScreen({super.key, required this.customerId, this.readOnly = false});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Map<String, dynamic>? _customer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getCustomerDetail(widget.customerId);
      setState(() => _customer = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> txn) async {
    final amountController = TextEditingController(text: txn['amount'].toString());
    final noteController = TextEditingController(text: txn['note']?.toString() ?? '');
    String type = txn['type'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'udhaar', label: Text('Debit')),
                  ButtonSegment(value: 'wasooli', label: Text('Credit')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDialogState(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (Rs)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;

    try {
      await ApiService.updateTransaction(txn['id'], type, amount, noteController.text.trim());
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteEntry(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This will remove the entry and adjust the balance. Cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.deleteTransaction(id);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _showEntryDialog(String type) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final isDebit = type == 'udhaar'; // udhaar = customer owes more (debit)

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isDebit ? 'Add Udhaar (Debit)' : 'Add Wasooli (Credit)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount (Rs)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isDebit ? Colors.red : Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isDebit ? 'Add Debit' : 'Add Credit'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    try {
      await ApiService.addTransaction(widget.customerId, type, amount, noteController.text.trim());
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_customer == null) {
      return const Scaffold(body: Center(child: Text('Customer not found')));
    }

    final balance = (_customer!['balance'] as num).toDouble();
    final transactions = _customer!['transactions'] as List<dynamic>;
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    return Scaffold(
      appBar: AppBar(title: Text(_customer!['name'])),
      body: RefreshIndicator(
        onRefresh: _load,
        // Use a ListView as the direct child so RefreshIndicator finds a Scrollable descendant.
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Column(
                children: [
                  Text(_customer!['phone'] ?? '', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    'Rs ${balance.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: balance > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                  Text(balance > 0 ? 'Baqaya (Outstanding)' : 'Clear / Advance', style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            if (!widget.readOnly)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => _showEntryDialog('udhaar'),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Debit (Udhaar)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => _showEntryDialog('wasooli'),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Credit (Wasooli)'),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey))),
              )
            else ...transactions.map<Widget>((t) {
              final isDebit = t['type'] == 'udhaar';
              DateTime? parsedDate;
              try {
                parsedDate = DateTime.parse(t['created_at']);
              } catch (_) {}
              return ListTile(
                leading: Icon(
                  isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isDebit ? Colors.red : Colors.green,
                ),
                title: Text(isDebit ? 'Udhaar (Debit)' : 'Wasooli (Credit)'),
                subtitle: Text(
                  [
                    if (t['note'] != null && t['note'].toString().isNotEmpty) t['note'],
                    if (parsedDate != null) dateFormat.format(parsedDate),
                  ].join(' · '),
                ),
                trailing: widget.readOnly
                    ? Text(
                        'Rs ${(t['amount'] as num).toStringAsFixed(0)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: isDebit ? Colors.red : Colors.green),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Rs ${(t['amount'] as num).toStringAsFixed(0)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: isDebit ? Colors.red : Colors.green),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _showEditDialog(t);
                              if (value == 'delete') _deleteEntry(t['id']);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
