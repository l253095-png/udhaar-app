import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

/// Shows a filtered list of transactions (e.g. "Today's Debit",
/// "This Month's Credit") with a running total at the top.
class TransactionReportScreen extends StatefulWidget {
  final String title;
  final String? type; // 'udhaar' | 'wasooli' | null (both)
  final String? period; // 'today' | 'month' | null (all time)

  const TransactionReportScreen({super.key, required this.title, this.type, this.period});

  @override
  State<TransactionReportScreen> createState() => _TransactionReportScreenState();
}

class _TransactionReportScreenState extends State<TransactionReportScreen> {
  List<dynamic> _transactions = [];
  double _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getTransactionsFiltered(type: widget.type, period: widget.period);
      setState(() {
        _transactions = data['transactions'] ?? [];
        _total = ((data['total'] as num?) ?? 0).toDouble();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM, hh:mm a');
    final isDebit = widget.type == 'udhaar';
    final accentColor = widget.type == null ? Colors.blueGrey : (isDebit ? Colors.red : Colors.green);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    color: accentColor.withOpacity(0.08),
                    child: Column(
                      children: [
                        Text('Total: Rs ${_total.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: accentColor)),
                        const SizedBox(height: 4),
                        Text('${_transactions.length} entries', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _transactions.isEmpty
                        ? const Center(child: Text('No entries found', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _transactions.length,
                            itemBuilder: (context, index) {
                              final t = _transactions[index];
                              final txnIsDebit = t['type'] == 'udhaar';
                              DateTime? d;
                              try {
                                d = DateTime.parse(t['created_at']);
                              } catch (_) {}
                              return ListTile(
                                leading: Icon(
                                  txnIsDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: txnIsDebit ? Colors.red : Colors.green,
                                ),
                                title: Text(t['customer_name'] ?? 'Unknown'),
                                subtitle: Text(d != null ? dateFormat.format(d) : ''),
                                trailing: Text(
                                  'Rs ${(t['amount'] as num).toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: txnIsDebit ? Colors.red : Colors.green,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
