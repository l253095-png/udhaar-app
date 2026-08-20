import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Shows past sync runs (by day/tab) with an option to fully undo one —
/// reversing every transaction it created, so that day can be synced fresh.
class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  List<dynamic> _history = [];
  int _legacyCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.getSyncHistory();
      final legacy = await ApiService.getLegacyCount();
      setState(() {
        _history = data;
        _legacyCount = legacy;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _undoLegacy() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clean Up Old (Pre-Fix) Entries?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This reverses $_legacyCount transaction(s) that were synced BEFORE the day-tracking '
              'fix (they have no day tag, so the normal per-day Undo can\'t reach them). '
              'Customer balances go back to what they were before. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Undo Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await ApiService.undoLegacy(passwordController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Cleanup complete')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _undo(String tabName) async {
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Undo Sync for "$tabName"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will reverse every transaction and expense entry that this sync created — '
              'customer balances go back to what they were before. The day can then be synced '
              'fresh from the Sheet again. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Undo Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo Sync'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await ApiService.undoSync(tabName, passwordController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Undo complete')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_legacyCount > 0)
                  Card(
                    margin: const EdgeInsets.all(12),
                    color: Colors.orange.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text('$_legacyCount old entries from before the day-tracking fix'),
                      subtitle: const Text("These don't have a day tag — use this one-time cleanup instead"),
                      trailing: TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _undoLegacy,
                        child: const Text('Clean Up'),
                      ),
                    ),
                  ),
                Expanded(
                  child: _history.isEmpty
                      ? const Center(child: Text('No sync runs yet', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _history.length,
                            itemBuilder: (context, index) {
                              final entry = _history[index];
                              final tabName = entry['tab_name'] ?? 'Unknown day';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.sync, color: Colors.teal),
                                  title: Text(tabName),
                                  subtitle: Text(
                                    '${entry['rows_synced'] ?? 0} synced · ${entry['new_customers_flagged'] ?? 0} pending review\n'
                                    'Ran at: ${entry['synced_at'] ?? ''}',
                                  ),
                                  isThreeLine: true,
                                  trailing: tabName != 'Unknown day'
                                      ? TextButton(
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                          onPressed: () => _undo(tabName),
                                          child: const Text('Undo'),
                                        )
                                      : null,
                                ),
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
