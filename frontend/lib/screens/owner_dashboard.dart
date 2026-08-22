import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'add_customer_screen.dart';
import 'customer_detail_screen.dart';
import 'transaction_report_screen.dart';

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
  String _sortBy = 'latest_first'; // 'balance_desc', 'name_asc', 'latest_first'

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
    } else if (_sortBy == 'latest_first') {
      temp.sort((a, b) {
        final dateA = a['last_transaction_at'] != null
            ? DateTime.tryParse(a['last_transaction_at'].toString())
            : null;
        final dateB = b['last_transaction_at'] != null
            ? DateTime.tryParse(b['last_transaction_at'].toString())
            : null;

        // Customers with no transactions ever go to the bottom.
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateB.compareTo(dateA); // Most recent first
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

  /// Quick Credit/Debit entry directly from the customer list
  Future<void> _showQuickTransactionDialog(Map<String, dynamic> customer, String type) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final isDebit = type == 'udhaar';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${isDebit ? 'Add Udhaar (Debit)' : 'Add Wasooli (Credit)'} — ${customer['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount (Rs)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isDebit ? Colors.red : Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isDebit ? 'Add Debit' : 'Add Credit'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount');
      return;
    }

    try {
      await ApiService.addTransaction(customer['id'], type, amount, noteController.text.trim());
      _showSnack('${isDebit ? 'Debit' : 'Credit'} of Rs $amount added for ${customer['name']}');
      _load();
    } catch (e) {
      _showSnack('Failed: $e');
    }
  }
    Future<void> _generateRangeReport() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;

    _showSnack('Generating PDF report...');
    try {
      await ApiService.downloadRangeReportPdf(picked.start, picked.end);
      _showSnack('Report downloaded');
    } catch (e) {
      _showSnack('Failed to generate report: $e');
    }
  }

  Widget _buildReportTile(String label, IconData icon, Color color, VoidCallback onTap, {int? count}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
                ),
              ],
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
          // REPORT QUICK-ACCESS TILES AT TOP
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              children: [
                _buildReportTile(
                  'This Month\nDebit',
                  Icons.calendar_month,
                  Colors.red,
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TransactionReportScreen(
                          title: 'This Month — Debit', type: 'udhaar', period: 'month'))),
                ),
                _buildReportTile(
                  'This Month\nCredit',
                  Icons.calendar_month,
                  Colors.green,
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TransactionReportScreen(
                          title: 'This Month — Credit', type: 'wasooli', period: 'month'))),
                ),
                _buildReportTile(
                  "Today's\nDebit",
                  Icons.today,
                  Colors.red,
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TransactionReportScreen(
                          title: "Today's Debit", type: 'udhaar', period: 'today'))),
                ),
                _buildReportTile(
                  "Today's\nCredit",
                  Icons.today,
                  Colors.green,
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TransactionReportScreen(
                          title: "Today's Credit", type: 'wasooli', period: 'today'))),
                ),
                _buildReportTile(
                  'Total\nCustomers',
                  Icons.people,
                  Colors.blueGrey,
                  () {
                    setState(() => _searchTerm = '');
                    _load();
                  },
                  count: _allCustomers.length,
                ),
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
                    DropdownMenuItem(value: 'latest_first', child: Text('Latest Entry First', style: TextStyle(fontSize: 13))),
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
                                      if (value == 'debit') _showQuickTransactionDialog(c, 'udhaar');
                                      if (value == 'credit') _showQuickTransactionDialog(c, 'wasooli');
                                      if (value == 'edit') _showEditCustomerDialog(c);
                                      if (value == 'delete') _deleteCustomer(c['id'], c['name']);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'debit', child: Text('➕ Add Debit (Udhaar)')),
                                      const PopupMenuItem(value: 'credit', child: Text('➖ Add Credit (Wasooli)')),
                                      const PopupMenuDivider(),
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