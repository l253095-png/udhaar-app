import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/animated_balance_text.dart';

/// The backend now stores `created_at` already as Pakistan wall-clock time
/// (fixed via backend/utils/dateHelper.js — no more UTC storage). So we
/// parse it directly, with NO timezone conversion — the string already
/// says exactly what time it was in Pakistan.
DateTime _parseServerTimestamp(String raw) {
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  return DateTime.parse(normalized);
}
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
  DateTimeRange? _selectedDateRange;

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

  Future<void> _sendWhatsAppReminder(double balance) async {
    final phone = _customer?['phone'] ?? '';
    final name = _customer?['name'] ?? 'Customer';

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this customer!')),
      );
      return;
    }

    String historyLink = '';
    try {
      historyLink = await ApiService.getPublicHistoryLink(widget.customerId);
    } catch (_) {
      // Link generation failed — still send the reminder without it.
    }

    final message = Uri.encodeComponent(
      "Assalam-o-Alaikum $name,\n"
      "Tis is a computer generated message.\n"
      "Your Remaining balance is Rs ${balance.toStringAsFixed(0)} hai.\n"
      "If you want to see your full transaction history, please click the link below:\n"
      "Thanks!\n\n"
      "${historyLink.isNotEmpty ? '\n\nCheck your complete transaction history:\n$historyLink' : ''}",
    );

    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri.parse("https://api.whatsapp.com/send?phone=$cleanPhone&text=$message");

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching WhatsApp: $e')),
      );
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> txn) async {
    final amountController = TextEditingController(text: txn['amount'].toString());
    final descriptionController = TextEditingController(text: txn['note']?.toString() ?? '');
    String type = txn['type'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Transaction Type:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'udhaar', label: Text('Debit')),
                  ButtonSegment(value: 'wasooli', label: Text('Credit')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDialogState(() => type = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g., Food, Rent, Supplies...',
                  border: OutlineInputBorder(),
                ),
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
      await ApiService.updateTransaction(txn['id'], type, amount, descriptionController.text.trim());
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
    final descriptionController = TextEditingController();
    final isDebit = type == 'udhaar';

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
              decoration: const InputDecoration(
                labelText: 'Amount (Rs)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: isDebit ? 'e.g., Food, Supplies, Rent...' : 'e.g., Payment received, Deposit...',
                border: const OutlineInputBorder(),
              ),
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
      await ApiService.addTransaction(widget.customerId, type, amount, descriptionController.text.trim());
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

    final balance = ((_customer!['balance'] as num?) ?? 0).toDouble();
    List<dynamic> rawTxns = _customer!['transactions'] as List<dynamic>? ?? [];

    List<dynamic> transactions = rawTxns.where((t) {
      if (_selectedDateRange == null) return true;
      try {
        final dt = _parseServerTimestamp(t['created_at']);
        return dt.isAfter(_selectedDateRange!.start.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      } catch (_) {
        return true;
      }
    }).toList();

    final Map<dynamic, double> balanceAfterMap = {};
    double _runningBalance = balance;
    for (final t in rawTxns) {
      balanceAfterMap[t['id']] = _runningBalance;
      final amt = ((t['amount'] as num?) ?? 0).toDouble();
      final effect = t['type'] == 'udhaar' ? amt : -amt;
      _runningBalance -= effect;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_customer!['name'] ?? 'Customer Detail'),
        actions: [
          IconButton(
            icon: Icon(
              _selectedDateRange != null ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _selectedDateRange != null ? Colors.orange : null,
            ),
            tooltip: 'Filter by Date',
            onPressed: _pickDateRange,
          ),
          if (_selectedDateRange != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Date Filter',
              onPressed: () => setState(() => _selectedDateRange = null),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Column(
                children: [
                  Text(_customer!['phone'] ?? 'No phone', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  AnimatedBalanceText(
                    value: balance.abs(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: balance > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                  Text(
                    balance > 0 ? 'Baqaya (Outstanding Udhaar)' : 'Clear / Advance',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (balance > 0 && !widget.readOnly)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () => _sendWhatsAppReminder(balance),
                      icon: const Icon(Icons.send),
                      label: const Text('Send WhatsApp Reminder'),
                    ),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _showEntryDialog('udhaar'),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Debit (Udhaar)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _showEntryDialog('wasooli'),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Credit (Wasooli)'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_selectedDateRange != null)
              Container(
                color: Colors.orange.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filtered: ${_selectedDateRange!.start.toString().split(' ')[0]} to ${_selectedDateRange!.end.toString().split(' ')[0]}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                    InkWell(
                      onTap: () => setState(() => _selectedDateRange = null),
                      child: const Text('Reset', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: Text('No transactions found', style: TextStyle(color: Colors.grey))),
              )
            else
              ...transactions.map<Widget>((t) {
                final isDebit = t['type'] == 'udhaar';
                DateTime? parsedDate;
                String? dateStr;
                String? timeStr;
                try {
                  parsedDate = _parseServerTimestamp(t['created_at']);
                  dateStr = parsedDate.toString().split(' ')[0];
                  timeStr = '${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}';
                } catch (_) {}

                final description = t['note']?.toString() ?? 'No description';
                final balanceAfter = balanceAfterMap[t['id']];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: Icon(
                      isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isDebit ? Colors.red : Colors.green,
                      size: 28,
                    ),
                    title: Text(
                      isDebit ? 'Udhaar (Debit)' : 'Wasooli (Credit)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Description: $description',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (dateStr != null && timeStr != null)
                          Text(
                            'Date: $dateStr | Time: $timeStr',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        if (balanceAfter != null)
                          Text(
                            'Balance after: Rs ${balanceAfter.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    trailing: widget.readOnly
                        ? Text(
                            'Rs ${((t['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDebit ? Colors.red : Colors.green,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rs ${((t['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDebit ? Colors.red : Colors.green,
                                ),
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
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
