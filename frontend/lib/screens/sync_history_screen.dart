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
      setState(() => _history = data);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _undo(String tabName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Undo Sync for "$tabName"?'),
        content: const Text(
          'This will reverse every transaction and expense entry that this sync created — '
          'customer balances go back to what they were before. The day can then be synced '
          'fresh from the Sheet again. This cannot be undone.',
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
      final result = await ApiService.undoSync(tabName);
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
          : _history.isEmpty
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
    );
  }
}
