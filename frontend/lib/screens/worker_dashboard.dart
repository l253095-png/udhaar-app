import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

/// Worker can only VIEW customers, balances, and transaction history.
/// No add / edit / delete buttons exist anywhere on this screen.
class WorkerDashboard extends StatefulWidget {
  const WorkerDashboard({super.key});

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  List<dynamic> _customers = [];
  bool _loading = true;

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
    } catch (_) {
      // In production: fall back to Hive-cached data if offline
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers (View Only)'),
        actions: [
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                    subtitle: Text('House: ${c['house_number'] ?? '-'}'),
                    trailing: Text(
                      'Rs ${balance.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: balance > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
