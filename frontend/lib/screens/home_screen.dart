import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'owner_dashboard.dart';
import 'expense_list_screen.dart';
import 'pending_approvals_screen.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'manage_users_screen.dart';
import 'sync_history_screen.dart';
import 'imported_entries_screen.dart';
import '../theme/app_colors.dart';
import 'net_summary_screen.dart';
import 'financial_snapshot_screen.dart';

/// Owner's main landing screen after login — 5 module tiles + pending review badge.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pendingCount = 0;
  int _stagedCount = 0;
  double _monthlyExpenseTotal = 0.0;
  double _udhaarSystemTotal = 0.0;
  double _mainBranchPurchaseTotal = 0.0;
  double _dailyOnlineMonthlyTotal = 0.0;
  bool _snapshotDue = false;
  int? _daysSinceSnapshot;
  bool _syncing = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
    _loadStagedCount();
    _loadMonthlyExpenseTotal();
    _loadUdhaarSystemTotal();
    _loadMainBranchPurchaseTotal();
     _loadDailyOnlineMonthlyTotal();  
    _loadSnapshotStatus();
    // Live clock — ticks every second so the on-screen time is always current,
    // and every new entry's timestamp can be visually cross-checked against it.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadStagedCount() async {
    try {
      final count = await ApiService.getStagedCount();
      if (mounted) setState(() => _stagedCount = count);
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    try {
      final count = await ApiService.getPendingSyncCount();
      if (mounted) setState(() => _pendingCount = count);
    } catch (_) {
      // ignore - badge just won't show if this fails
    }
  }

  Future<void> _loadMonthlyExpenseTotal() async {
    try {
      final data = await ApiService.getMonthlyExpenseTotal('monthly_expense');
      if (mounted) setState(() => _monthlyExpenseTotal = (data['total'] as num).toDouble());
    } catch (_) {
      // ignore - just won't show if this fails
    }
  }

  Future<void> _loadUdhaarSystemTotal() async {
    try {
      final total = await ApiService.getCustomersTotalBalance();
      if (mounted) setState(() => _udhaarSystemTotal = total);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadSnapshotStatus() async {
    try {
      final status = await ApiService.getSnapshotStatus();
      if (mounted) {
        setState(() {
          _snapshotDue = status['due'] == true;
          _daysSinceSnapshot = status['daysSince'];
        });
      }
    } catch (_) {
      // ignore - reminder just won't show if this fails
    }
  }

  Future<void> _loadMainBranchPurchaseTotal() async {
    try {
      final data = await ApiService.getMonthlyExpenseTotal('daily_main_branch_purchase');
      if (mounted) setState(() => _mainBranchPurchaseTotal = (data['total'] as num).toDouble());
    } catch (_) {
      // ignore
    }
  }
  Future<void> _loadDailyOnlineMonthlyTotal() async {
    try {
      final data = await ApiService.getMonthlyExpenseTotal('daily_online');
      if (mounted) setState(() => _dailyOnlineMonthlyTotal = (data['total'] as num).toDouble());
    } catch (_) {
      // ignore
    }
  }

  /// The ONE sync button for the whole app.
  /// Shows Google Sheets list from Drive, user picks which sheet to sync.
  /// Matched rows go into the "Imported" list first, awaiting final approval.
  Future<void> _syncFromSheet() async {
    final chosenSheet = await showDialog<dynamic>(
      context: context,
      builder: (_) => const _SheetPickerDialog(),
    );

    if (chosenSheet == null) return;

    final sheetId = chosenSheet['id']?.toString();
    final sheetName = chosenSheet['name']?.toString() ?? 'Selected Sheet';

    setState(() => _syncing = true);
    try {
      final result = await ApiService.runSheetSync(sheetId: sheetId, fileName: sheetName);
      final staged = result['processedCount'] ?? 0;
      final pending = result['pendingCount'] ?? 0;
      _showSnack(
        pending > 0
            ? '$staged entries imported from "$sheetName". $pending need name matching below.'
            : '$staged entries imported from "$sheetName" — check "Imported Entries" to approve them.',
      );
      _loadPendingCount();
      _loadStagedCount();
    } catch (e) {
      String errorMessage;
      if (e is SyncException) {
        errorMessage = e.fullMessage;
      } else {
        errorMessage = 'Sync failed: $e';
      }
      _showErrorDialog(errorMessage);
    } finally {
      setState(() => _syncing = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Failed'),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Sync History / Undo',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncHistoryScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            tooltip: 'Monthly Net Summary',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetSummaryScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: 'Manage Users',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageUsersScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
           floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.marigold,
        foregroundColor: AppColors.deepIndigo,
        onPressed: _syncing ? null : _syncFromSheet,
        icon: _syncing
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync),
        label: Text(_syncing ? 'Syncing...' : 'Sync from Google Sheet'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadPendingCount(),
            _loadStagedCount(),
            _loadMonthlyExpenseTotal(),
            _loadUdhaarSystemTotal(),
            _loadMainBranchPurchaseTotal(),
            _loadDailyOnlineMonthlyTotal(),
            _loadSnapshotStatus(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // LIVE CLOCK — shows current date & time so entry timestamps can be
            // visually verified against "right now" on the shop PC/laptop.
                        Card(
              color: AppColors.marigold.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                child: Column(
                  children: [
                    Text(
                      DateFormat('hh:mm:ss a').format(_now),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.deepIndigo),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_stagedCount > 0)
              Card(
                color: Colors.blue.shade50,
                child: ListTile(
                  leading: const Icon(Icons.move_to_inbox, color: Colors.blue),
                  title: Text('$_stagedCount entries imported — awaiting approval'),
                  subtitle: const Text('Not yet applied to any balance. Tap to review.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ImportedEntriesScreen()),
                    );
                    _loadStagedCount();
                  },
                ),
              ),
            if (_stagedCount > 0) const SizedBox(height: 12),
            if (_pendingCount > 0)
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: const Icon(Icons.pending_actions, color: Colors.orange),
                  title: Text('$_pendingCount entries need name matching'),
                  subtitle: const Text('Tap to link/create/reject/ignore'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PendingApprovalsScreen()),
                    );
                    _loadPendingCount();
                  },
                ),
              ),
            if (_pendingCount > 0) const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _ModuleTile(
                                 
                  title: 'Udhaariyeeee',
                  icon: Icons.receipt_long,
                  color: AppColors.deepIndigo,
                  subtitle: 'Outstanding: Rs ${_udhaarSystemTotal.abs().toStringAsFixed(0)}',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerDashboard()));
                    _loadUdhaarSystemTotal();
                  },
                ),
                _ModuleTile(
                  title: 'Monthly Expense',
                  icon: Icons.calendar_month,
                  color: Colors.orange,
                  subtitle: 'Total: Rs ${_monthlyExpenseTotal.toStringAsFixed(0)}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ExpenseListScreen(category: 'monthly_expense', title: 'Monthly Expense'))),
                ),
                _ModuleTile(
                  title: 'Daily Online',
                  icon: Icons.wifi,
                  color: Colors.blue,
                  subtitle: 'Monthly: Rs ${_dailyOnlineMonthlyTotal.toStringAsFixed(0)}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ExpenseListScreen(category: 'daily_online', title: 'Daily Online'))),
                ),
                _ModuleTile(
                  title: 'Main Branch Purchase',
                  icon: Icons.store,
                  color: Colors.brown,
                  subtitle: 'Monthly: Rs ${_mainBranchPurchaseTotal.toStringAsFixed(0)}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ExpenseListScreen(
                          category: 'daily_main_branch_purchase', title: 'Main Branch Purchase'))),
                ),
                _ModuleTile(
                  title: 'Stock / Cash / Udhaar',
                  icon: Icons.pie_chart,
                  color: AppColors.gulabiPink,
                  subtitle: _snapshotDue
                      ? (_daysSinceSnapshot == null
                          ? 'Pehli entry dalain'
                          : '$_daysSinceSnapshot din ho gaye — Due!')
                      : 'Har 15 din entry karein',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FinancialSnapshotScreen()));
                    _loadSnapshotStatus();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;

  const _ModuleTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: color.withOpacity(0.7)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetPickerDialog extends StatefulWidget {
  const _SheetPickerDialog();

  @override
  State<_SheetPickerDialog> createState() => _SheetPickerDialogState();
}

class _SheetPickerDialogState extends State<_SheetPickerDialog> {
  List<dynamic> _sheets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSheets();
  }

  Future<void> _fetchSheets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getAvailableSheets();
      if (!mounted) return;
      setState(() {
        _sheets = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SyncException ? e.message : 'Failed to load sheets: $e';
        _loading = false;
      });
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr.toString()).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[dt.month - 1];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $month ${dt.year}, $hour:$minute $ampm';
    } catch (_) {
      return dateStr.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Google Sheet to Sync',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Choose a daily ledger sheet from your Google Drive',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Fetching sheets from Google Drive...'),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      onPressed: _fetchSheets,
                    ),
                  ],
                ),
              )
            else if (_sheets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No spreadsheets found in your Google Drive folder.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sheets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final sheet = _sheets[index];
                    final isLatest = index == 0;
                    final modTime = _formatDate(sheet['modifiedTime']);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: isLatest ? Colors.green.shade100 : Colors.grey.shade200,
                        child: Icon(
                          Icons.description_outlined,
                          color: isLatest ? Colors.green.shade800 : Colors.grey.shade700,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sheet['name'] ?? 'Untitled Sheet',
                              style: TextStyle(
                                fontWeight: isLatest ? FontWeight.bold : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (isLatest)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'LATEST',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      subtitle: modTime.isNotEmpty
                          ? Text('Modified: $modTime', style: const TextStyle(fontSize: 12, color: Colors.grey))
                          : null,
                      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                      onTap: () {
                        Navigator.of(context).pop(sheet);
                      },
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