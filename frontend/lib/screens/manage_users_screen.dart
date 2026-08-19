import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  List<dynamic> _workers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() => _loading = true);
    try {
      final workers = await ApiService.getWorkers();
      setState(() => _workers = workers);
    } catch (e) {
      _showSnack('Failed to load: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showAddWorkerDialog() async {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Worker Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Worker Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: 'Username (for login)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );

    if (confirmed != true) return;

    final name = nameController.text.trim();
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      _showSnack('All fields are required');
      return;
    }

    try {
      await ApiService.createWorker(name, username, password);
      _showSnack('Worker account "$username" created');
      _loadWorkers();
    } catch (e) {
      _showSnack('Failed: $e');
    }
  }

  Future<void> _deleteWorker(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Worker?'),
        content: Text('Remove login access for "$name"? They will no longer be able to log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.deleteWorker(id);
        _showSnack('Worker removed');
        _loadWorkers();
      } catch (e) {
        _showSnack('Failed: $e');
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change My Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Change')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.changePassword(currentController.text.trim(), newController.text.trim());
      _showSnack('Password changed successfully');
    } catch (e) {
      _showSnack('Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Change My Password'),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Worker Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                TextButton.icon(
                  onPressed: _showAddWorkerDialog,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add Worker'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _workers.isEmpty
                    ? const Center(child: Text('No worker accounts yet', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _workers.length,
                        itemBuilder: (context, index) {
                          final w = _workers[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(w['name']),
                            subtitle: Text('Username: ${w['username']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteWorker(w['id'], w['name']),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
