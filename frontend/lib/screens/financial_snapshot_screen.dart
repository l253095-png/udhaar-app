import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';

/// Every 15 days, owner logs Stock Position + Cash on Hand manually.
/// Total Udhaar is always fetched live from the app (never typed in),
/// and the three are summed into a Total Net Worth entry.
class FinancialSnapshotScreen extends StatefulWidget {
  const FinancialSnapshotScreen({super.key});

  @override
  State<FinancialSnapshotScreen> createState() => _FinancialSnapshotScreenState();
}

class _FinancialSnapshotScreenState extends State<FinancialSnapshotScreen> {
  List<dynamic> _snapshots = [];
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snapshots = await ApiService.getFinancialSnapshots();
      final status = await ApiService.getSnapshotStatus();
      setState(() {
        _snapshots = snapshots;
        _status = status;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openAddDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddSnapshotDialog(),
    );
    if (added == true) _load();
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = _status?['due'] == true;
    final daysSince = _status?['daysSince'];

    return Scaffold(
      appBar: AppBar(title: const Text('Stock / Cash / Udhaar')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.marigold,
        foregroundColor: AppColors.deepIndigo,
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (due)
                    Card(
                      color: AppColors.gulabiPink.withOpacity(0.12),
                      child: ListTile(
                        leading: Icon(Icons.notifications_active, color: AppColors.gulabiPink),
                        title: Text(
                          daysSince == null
                              ? 'Koi entry abhi tak nahi hui'
                              : '$daysSince din ho gaye pichli entry ko',
                        ),
                        subtitle: const Text('Naya entry dalne ka waqt aa gaya hai (har 15 din)'),
                      ),
                    ),
                  if (due) const SizedBox(height: 16),
                  const Text('History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_snapshots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Abhi tak koi entry nahi hui', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ..._snapshots.map((s) {
                      final total = (s['total'] as num).toDouble();
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDate(s['snapshot_date']),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  AnimatedBalanceText(
                                    value: total,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.deepIndigo,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              _row('Stock Position', (s['stock_position'] as num).toDouble()),
                              _row('Cash on Hand', (s['cash_on_hand'] as num).toDouble()),
                              _row('Total Udhaar', (s['udhaar_total'] as num).toDouble()),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text('Rs ${value.abs().toStringAsFixed(0)}', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _AddSnapshotDialog extends StatefulWidget {
  const _AddSnapshotDialog();

  @override
  State<_AddSnapshotDialog> createState() => _AddSnapshotDialogState();
}

class _AddSnapshotDialogState extends State<_AddSnapshotDialog> {
  final _stockController = TextEditingController();
  final _cashController = TextEditingController();
  double? _udhaarTotal;
  bool _loadingUdhaar = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUdhaar();
    _stockController.addListener(() => setState(() {}));
    _cashController.addListener(() => setState(() {}));
  }

  Future<void> _fetchUdhaar() async {
    try {
      final total = await ApiService.getCustomersTotalBalance();
      if (mounted) setState(() => _udhaarTotal = total);
    } catch (_) {
      if (mounted) setState(() => _udhaarTotal = 0.0);
    } finally {
      if (mounted) setState(() => _loadingUdhaar = false);
    }
  }

  double get _stock => double.tryParse(_stockController.text.trim()) ?? 0;
  double get _cash => double.tryParse(_cashController.text.trim()) ?? 0;
  double get _total => _stock + _cash + (_udhaarTotal ?? 0);

  Future<void> _save() async {
    if (_stockController.text.trim().isEmpty || _cashController.text.trim().isEmpty) {
      setState(() => _error = 'Stock Position aur Cash on Hand dono zaroori hain');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.addFinancialSnapshot(_stock, _cash);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _stockController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Stock / Cash / Udhaar Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _stockController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock Position (Rs)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cashController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cash on Hand (Rs)'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Udhaar (auto)', style: TextStyle(color: Colors.grey, fontSize: 13)),
                _loadingUdhaar
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Rs ${(_udhaarTotal ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rs ${_total.toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepIndigo)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: (_saving || _loadingUdhaar) ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}