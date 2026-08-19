import 'package:flutter/material.dart';
import 'owner_dashboard.dart';
import 'expense_list_screen.dart';
import 'pending_approvals_screen.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'manage_users_screen.dart';

/// Owner's main landing screen after login — 5 module tiles + pending review badge.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pendingCount = 0;
  double _monthlyExpenseTotal = 0.0;
  double _udhaarSystemTotal = 0.0;
  double _mainBranchPurchaseTotal = 0.0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
    _loadMonthlyExpenseTotal();
    _loadUdhaarSystemTotal();
    _loadMainBranchPurchaseTotal();
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

  Future<void> _loadMainBranchPurchaseTotal() async {
    try {
      final data = await ApiService.getMonthlyExpenseTotal('daily_main_branch_purchase');
      if (mounted) setState(() => _mainBranchPurchaseTotal = (data['total'] as num).toDouble());
    } catch (_) {
      // ignore
    }
  }

  /// The ONE sync button for the whole app.
  /// Exact-match rows import immediately, everything else goes to Pending Approval.
  Future<void> _syncFromSheet() async {
    setState(() => _syncing = true);
    try {
      final result = await ApiService.runSheetSync();
      final processed = result['processedCount'] ?? 0;
      final pending = result['pendingCount'] ?? 0;
      _showSnack(
        pending > 0
            ? '$processed entries imported. $pending need your review below.'
            : '$processed entries imported.',
      );
      _loadPendingCount();
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
            _loadMonthlyExpenseTotal(),
            _loadUdhaarSystemTotal(),
            _loadMainBranchPurchaseTotal(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_pendingCount > 0)
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: const Icon(Icons.pending_actions, color: Colors.orange),
                  title: Text('$_pendingCount entries pending sheet review'),
                  subtitle: const Text('Tap to review and approve/reject'),
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
                  title: 'Udhaar System',
                  icon: Icons.receipt_long,
                  color: Colors.teal,
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
