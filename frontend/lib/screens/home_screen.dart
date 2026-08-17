import 'package:flutter/material.dart';
import 'owner_dashboard.dart';
import 'expense_list_screen.dart';
import 'pending_approvals_screen.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

/// Owner's main landing screen after login — 5 module tiles + pending review badge.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final count = await ApiService.getPendingSyncCount();
      if (mounted) setState(() => _pendingCount = count);
    } catch (_) {
      // ignore - badge just won't show if this fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Dashboard'),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: _loadPendingCount,
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
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerDashboard()));
                    _loadPendingCount();
                  },
                ),
                _ModuleTile(
                  title: 'Monthly Expense',
                  icon: Icons.calendar_month,
                  color: Colors.orange,
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
                  title: 'Daily Card Transaction',
                  icon: Icons.credit_card,
                  color: Colors.purple,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ExpenseListScreen(category: 'daily_card', title: 'Daily Card Transaction'))),
                ),
                _ModuleTile(
                  title: 'Daily Main Branch Purchase',
                  icon: Icons.store,
                  color: Colors.brown,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ExpenseListScreen(
                          category: 'daily_main_branch_purchase', title: 'Daily Main Branch Purchase'))),
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

  const _ModuleTile({required this.title, required this.icon, required this.color, required this.onTap});

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
          ],
        ),
      ),
    );
  }
}
