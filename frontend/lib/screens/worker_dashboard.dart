import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'customer_detail_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_balance_text.dart';
/// Worker can only SEARCH customers and VIEW their transaction history.
/// No add / edit / delete / credit / debit controls exist anywhere on this screen.
class WorkerDashboard extends StatefulWidget {
  const WorkerDashboard({super.key});

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  List<dynamic> _customers = [];
  bool _loading = true;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customers = await ApiService.getCustomers(search: _searchTerm);
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
        title: const Text('Customer Search'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or phone...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                _searchTerm = value;
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? Center(child: Text(_searchTerm.isEmpty ? 'No customers yet' : 'No matching customers'))
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
                                                           trailing: AnimatedBalanceText(
                                value: balance,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: balance > 0 ? AppColors.rickshawRed : AppColors.truckGreen,
                                ),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CustomerDetailScreen(customerId: c['id'], readOnly: true),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
