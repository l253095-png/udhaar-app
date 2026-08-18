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
  List<dynamic> _allCustomers = [];
  List<dynamic> _filteredCustomers = [];
  bool _loading = true;
  String _searchTerm = '';
  
  // Filter and Sorting options
  String _filterType = 'all'; // 'all', 'has_balance', 'zero_balance'
  String _sortBy = 'balance_desc'; // 'balance_desc', 'name_asc'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customers = await ApiService.getCustomers(search: _searchTerm);
      setState(() {
        _allCustomers = customers;
        _applyFiltersAndSort();
      });
    } catch (e) {
      _showSnack('Failed to load: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyFiltersAndSort() {
    List<dynamic> temp = List.from(_allCustomers);

    // Filter Logic
    if (_filterType == 'has_balance') {
      temp = temp.where((c) => ((c['balance'] as num?) ?? 0) > 0).toList();
    } else if (_filterType == 'zero_balance') {
      temp = temp.where((c) => ((c['balance'] as num?) ?? 0) <= 0).toList();
    }

    // Sort Logic
    if (_sortBy == 'balance_desc') {
      temp.sort((a, b) {
        final balA = ((a['balance'] as num?) ?? 0).toDouble();
        final balB = ((b['balance'] as num?) ?? 0).toDouble();
        return balB.compareTo(balA); // Highest balance first
      });
    } else if (_sortBy == 'name_asc') {
      temp.sort((a, b) {
        final nameA = (a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    }

    _filteredCustomers = temp;
  }

  // Dashboard Totals Calculations
  double get _totalUdhaar {
    return _allCustomers.fold(0.0, (sum, item) {
      final bal = ((item['balance'] as num?) ?? 0).toDouble();
      return sum + (bal > 0 ? bal : 0);
    });
  }

  int get _borrowerCount {
    return _allCustomers.where((c) => ((c['balance'] as num?) ?? 0) > 0).length;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showEditCustomerDialog(Map<String, dynamic> customer) async {
    final nameController = TextEditingController(text: customer['name'] ?? '');
    final phoneController = TextEditingController(text: customer['phone'] ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Customer name cannot be empty');
      return;
    }

    try {
      await ApiService.updateCustomer(customer['id'], name, phoneController.text.trim());
      _showSnack('Customer updated successfully');
      _load();
    } catch (e) {
      _showSnack('Failed to update: $e');
    }
  }

  Future<void> _deleteCustomer(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text('Delete "$name" and all associated transactions? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteCustomer(id);
      _showSnack('Customer deleted');
      _load();
    } catch (e) {
      _showSnack('Failed to delete: $e');
    }
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Udhaar System'),
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
      body: Column(
        children: [
          // SUMMARY CARDS AT TOP
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                _buildSummaryCard('Total Udhaar', 'Rs ${_totalUdhaar.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.red),
                _buildSummaryCard('Total Customers', '${_allCustomers.length}', Icons.people, Colors.blue),
                _buildSummaryCard('With Udhaar', '$_borrowerCount', Icons.warning_amber_rounded, Colors.orange),
              ],
            ),
          ),

          // SEARCH BAR
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
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

          // FILTER & SORT BAR
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Filter Dropdown
                DropdownButton<String>(
                  value: _filterType,
                  underline: Container(),
                  icon: const Icon(Icons.filter_list, size: 20),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Customers', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'has_balance', child: Text('Pending Udhaar Only', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'zero_balance', child: Text('Zero Balance Only', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _filterType = val;
                        _applyFiltersAndSort();
                      });
                    }
                  },
                ),

                // Sort Dropdown
                DropdownButton<String>(
                  value: _sortBy,
                  underline: Container(),
                  icon: const Icon(Icons.sort, size: 20),
                  items: const [
                    DropdownMenuItem(value: 'balance_desc', child: Text('Highest Balance First', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'name_asc', child: Text('Sort by Name (A-Z)', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _sortBy = val;
                        _applyFiltersAndSort();
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // CUSTOMER LIST
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(_searchTerm.isEmpty ? 'No customers match the filter' : 'No matching customers'),
                            if (_searchTerm.isEmpty && _allCustomers.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('Tap the person-add icon above to add your first customer,',
                                  style: TextStyle(color: Colors.grey)),
                              const Text('or use "Sync from Google Sheet" on the Home screen.',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final c = _filteredCustomers[index];
                            final balance = ((c['balance'] as num?) ?? 0).toDouble();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                                child: Icon(Icons.person, color: balance > 0 ? Colors.red : Colors.green),
                              ),
                              title: Text(c['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(c['phone'] ?? 'No phone'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Rs ${balance.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: balance > 0 ? Colors.red : Colors.green,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') _showEditCustomerDialog(c);
                                      if (value == 'delete') _deleteCustomer(c['id'], c['name']);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c['id'])),
                                );
                                _load();
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