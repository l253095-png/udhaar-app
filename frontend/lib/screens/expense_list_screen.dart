import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';

class ExpenseListScreen extends StatefulWidget {
  final String category;
  final String title;
  const ExpenseListScreen({super.key, required this.category, required this.title});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
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
      final data = await ApiService.getExpenses(widget.category);
      setState(() => _entries = data);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showEntryDialog({Map<String, dynamic>? existing}) async {
    final amountController = TextEditingController(text: existing?['amount']?.toString() ?? '');
    final noteController = TextEditingController(text: existing?['note']?.toString() ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Entry' : 'Edit Entry'),
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
              decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
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
      if (existing == null) {
        await ApiService.addExpense(widget.category, amount, noteController.text.trim());
      } else {
        await ApiService.updateExpense(existing['id'], amount, noteController.text.trim());
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _delete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This cannot be undone.'),
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
        await ApiService.deleteExpense(id);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Widget _entryTile(Map<String, dynamic> e, DateFormat dateFormat) {
    DateTime? d;
    try {
      d = DateTime.parse(e['entry_date']);
    } catch (_) {}
    return ListTile(
      title: Text('Rs ${(e['amount'] as num).toStringAsFixed(0)}'),
      subtitle: Text(
        [
          if (e['note'] != null && e['note'].toString().isNotEmpty) e['note'],
          if (d != null) dateFormat.format(d),
        ].join(' · '),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') _showEntryDialog(existing: e);
          if (value == 'delete') _delete(e['id']);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final now = DateTime.now();

    // Group ALL entries by calendar month (yyyy-MM), so nothing is ever
    // hidden — it just moves into "Previous Months" once the month ends.
    final Map<String, List<dynamic>> byMonth = {};
    for (final e in _entries) {
      DateTime? d;
      try {
        d = DateTime.parse(e['entry_date']);
      } catch (_) {
        continue;
      }
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(e);
    }

    final currentKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final currentMonthEntries = byMonth[currentKey] ?? [];
    final total = currentMonthEntries.fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());

    final previousKeys = byMonth.keys.where((k) => k != currentKey).toList()
      ..sort((a, b) => b.compareTo(a)); // most recent previous month first

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEntryDialog(),
        backgroundColor: AppColors.marigold,
        foregroundColor: AppColors.deepIndigo,
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.marigold.withOpacity(0.12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('This Month Total: ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      AnimatedBalanceText(
                        value: total,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepIndigo),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (currentMonthEntries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No entries yet this month', style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ...currentMonthEntries.map((e) => _entryTile(e, dateFormat)),

                      if (previousKeys.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Text('Previous Months', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        ...previousKeys.map((key) {
                          final monthEntries = byMonth[key]!;
                          final monthTotal = monthEntries.fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
                          final label = DateFormat('MMMM yyyy').format(DateTime.parse('$key-01'));
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ExpansionTile(
                              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Rs ${monthTotal.toStringAsFixed(0)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepIndigo)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.expand_more, size: 20),
                                ],
                              ),
                              children: monthEntries.map((e) => _entryTile(e, dateFormat)).toList(),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}