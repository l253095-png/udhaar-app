import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';

/// The backend stores `created_at` as a UTC timestamp (no timezone suffix,
/// e.g. "2026-08-26 12:30:00"). Dart's DateTime.parse treats a string with
/// no timezone marker as LOCAL time, which silently skips the UTC->local
/// conversion and makes every displayed time lag behind by the device's
/// UTC offset (5 hours behind in Pakistan, since PKT is UTC+5). This helper
/// forces the string to be parsed as UTC, then converts it to the device's
/// actual local time.
DateTime _parseServerTimestamp(String raw) {
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final withZ = normalized.endsWith('Z') ? normalized : '${normalized}Z';
  return DateTime.parse(withZ).toLocal();
}

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
    final accentColor = widget.type == null ? AppColors.deepIndigo : (isDebit ? AppColors.rickshawRed : AppColors.truckGreen);

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
                                                AnimatedBalanceText(
                          value: _total,
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: accentColor),
                        ),
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
                                d = _parseServerTimestamp(t['created_at']);
                              } catch (_) {}
                              return ListTile(
                                                                leading: Icon(
                                  txnIsDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: txnIsDebit ? AppColors.rickshawRed : AppColors.truckGreen,
                                ),
                                title: Text(t['customer_name'] ?? 'Unknown'),
                                subtitle: Text(d != null ? dateFormat.format(d) : ''),
                                trailing: AnimatedBalanceText(
                                  value: (t['amount'] as num).toDouble(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: txnIsDebit ? AppColors.rickshawRed : AppColors.truckGreen,
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