import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'add_customer_screen.dart';
import 'customer_detail_screen.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  List<dynamic> _customers = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customers = await ApiService.getCustomers();
      setState(() => _customers = customers);
    } catch (e) {
      _showSnack('Failed to load: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Step 1: preview what will be imported from Google Sheet.
  /// Step 2: owner confirms, then rows are actually synced and marked "Synced" in the Sheet.
  Future<void> _syncFromSheet() async {
    setState(() => _syncing = true);
    try {
      final preview = await ApiService.previewSheetSync();
      final rows = preview['preview'] as List<dynamic>;

      if (rows.isEmpty) {
        _showSnack('No new rows to sync.');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${rows.length} entries found'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  title: Text('${r['name']} (${r['phone'] ?? '-'})'),
                  subtitle: Text('${r['type']} - Rs ${r['amount']}${r['isNewCustomer'] ? '  [NEW]' : ''}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm & Import')),
          ],
        ),
      );

      if (confirmed == true) {
        final result = await ApiService.confirmSheetSync(rows);
        _showSnack('Synced ${result['syncedCount']} entries (${result['newCustomerCount']} new customers)');
        _load();
      }
    } catch (e) {
      _showSnack('Sync failed: $e');
    } finally {
      setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Customer',
            onPressed: () async {
              final added = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
              );
              if (added == true) _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.logout();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncing ? null : _syncFromSheet,
        icon: _syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
        label: Text(_syncing ? 'Syncing...' : 'Sync from Google Sheet'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No customers yet'),
                      const SizedBox(height: 8),
                      const Text('Tap the person-add icon above to add your first customer,',
                          style: TextStyle(color: Colors.grey)),
                      const Text('or use "Sync from Google Sheet" below.',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _customers.length,
                itemBuilder: (context, index) {
                  final c = _customers[index];
                  final balance = (c['balance'] as num).toDouble();
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(c['name']),
                    subtitle: Text(c['phone'] ?? ''),
                    trailing: Text(
                      'Rs ${balance.toStringAsFixed(0)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: balance > 0 ? Colors.red : Colors.green),
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c['id'])),
                      );
                      _load(); // refresh balances after returning from detail screen
                    },
                  );
                },
              ),
            ),
    );
  }
}
