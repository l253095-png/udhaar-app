import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';

class NetSummaryScreen extends StatefulWidget {
  const NetSummaryScreen({super.key});

  @override
  State<NetSummaryScreen> createState() => _NetSummaryScreenState();
}

class _NetSummaryScreenState extends State<NetSummaryScreen> {
  Map<String, dynamic>? _current;
  List<dynamic> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final current = await ApiService.getNetSummary();
      final history = await ApiService.getNetSummaryHistory();
      setState(() {
        _current = current;
        _history = history;
      });
      if (current['isLastDay'] == true) {
        _maybeShowLastDayPopup(current);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _maybeShowLastDayPopup(Map<String, dynamic> current) async {
    final prefs = await SharedPreferences.getInstance();
    final flagKey = 'seen_month_end_popup_${current['ym']}';
    if (prefs.getBool(flagKey) == true) return;
    await prefs.setBool(flagKey, true);

    if (!mounted) return;
    final net = (current['net'] as num).toDouble();
    final owedLabel = net < 0 ? 'Dady ko dene hain' : 'Dady se lene hain';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Month Ending Today'),
        content: Text(
          'This is the last day of ${current['ym']}.\n\n'
          '$owedLabel: Rs ${net.abs().toStringAsFixed(0)}\n\n'
          'Ready to share this with the CEO?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _confirmAndClearBalance() async {
    if (_current == null) return;
    final net = (_current!['net'] as num).toDouble();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear This Month\'s Balance?'),
        content: Text(
          'This will mark this month\'s Online, Main Branch Purchase and Expense '
          'entries as settled (as if paid to Dady).\n\n'
          'Current Net: Rs ${net.abs().toStringAsFixed(0)} ${net < 0 ? '(ko dene hain)' : '(se lene hain)'}\n\n'
          'Old entries stay safely in the audit log — nothing gets deleted. '
          'This just resets the live "This Month" total to Rs 0 going forward.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rickshawRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Balance'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await ApiService.settleNetSummary();
      if (!mounted) return;
      _showSettledConfirmation(result);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  /// After settling, show exactly what was paid/received so it's clear
  /// the old khata is closed and a fresh one has started.
  void _showSettledConfirmation(Map<String, dynamic> result) {
    final net = (result['net'] as num).toDouble();
    final isOwed = net < 0; // dady ko dene hain
    final amount = net.abs().toStringAsFixed(0);
    final color = isOwed ? AppColors.rickshawRed : AppColors.truckGreen;
    final message = isOwed
        ? 'Rs $amount Dady ko de diye hain.'
        : 'Rs $amount Dady se le liye hain.';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: color),
            const SizedBox(width: 8),
            const Text('Cleared'),
          ],
        ),
        content: Text(
          '$message\n\nYe mahine ka khata ab band ho gaya hai — naya khata Rs 0 se shuru ho gaya hai.',
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, num value, {bool isNegative = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${isNegative ? '- ' : ''}Rs ${value.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? (value >= 0 ? AppColors.truckGreen : AppColors.rickshawRed) : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Net total row with "Dady ko dene hain" / "Dady se lene hain" label.
  /// net < 0  → owner owes CEO   → label BEFORE the amount
  /// net >= 0 → CEO owes owner   → label AFTER the amount
  Widget _netTotalRow(num netValue) {
    final net = netValue.toDouble();
    final isOwed = net < 0; // dady ko dene hain
    final color = net >= 0 ? AppColors.truckGreen : AppColors.rickshawRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Net Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                if (isOwed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      'Dady ko dene hain:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                Text(
                  'Rs ${net.abs().toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ],
        ),
        if (!isOwed)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Dady se lene hain',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Net Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Clear Balance',
            onPressed: _current == null ? null : _confirmAndClearBalance,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_current != null)
                    Card(
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('This Month (${_current!['ym']}) — Live', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 8),
                            _breakdownRow('Online Total', _current!['online']),
                            _breakdownRow('Main Branch Purchase', _current!['mainBranch'], isNegative: true),
                            _breakdownRow('Other Expenses', _current!['expense'], isNegative: true),
                            const Divider(),
                            _netTotalRow(_current!['net']),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text('Previous Months', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Text('No previous months yet', style: TextStyle(color: Colors.grey))
                  else
                    ..._history.map((h) {
                      final net = (h['net'] as num).toDouble();
                      final isOwed = net < 0;
                      final color = net >= 0 ? AppColors.truckGreen : AppColors.rickshawRed;
                      return Card(
                        child: ListTile(
                          title: Text(h['ym']),
                          subtitle: Text(
                            isOwed ? 'Dady ko dene hain' : 'Dady se lene hain',
                            style: TextStyle(fontSize: 12, color: color),
                          ),
                          trailing: AnimatedBalanceText(
                            value: net.abs(),
                            style: TextStyle(fontWeight: FontWeight.bold, color: color),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}