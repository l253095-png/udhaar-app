import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Full audit trail — every add/edit/delete action across the system,
/// newest first.
class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await ApiService.getAuditLog();
      setState(() => _logs = logs);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'create':
        return Colors.green;
      case 'update':
        return Colors.orange;
      case 'delete':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'create':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Failed to load: $_error'))
                : _logs.isEmpty
                    ? const Center(child: Text('No history yet'))
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          final action = (log['action'] ?? '').toString();
                          final entityType = (log['entity_type'] ?? '').toString();
                          final description = (log['description'] ?? '').toString();
                          final performedBy = log['performed_by_name']?.toString() ?? 'Unknown';
                          final createdAt = (log['created_at'] ?? '').toString();

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: Icon(_actionIcon(action), color: _actionColor(action)),
                              title: Text(description, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                '${entityType.toUpperCase()} - ${action.toUpperCase()} - by $performedBy\n$createdAt',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}