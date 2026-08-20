import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Custom exception for sync errors that includes error code and details
class SyncException implements Exception {
  final String message;
  final String errorCode;
  final String details;

  SyncException(this.message, this.errorCode, this.details);

  @override
  String toString() => message;

  String get fullMessage => '$message\n\n$details';
}

/// Central place for talking to the backend.
///
/// This automatically picks the right address per platform:
/// - Windows desktop app: talks to localhost, because it always runs
///   on the SAME machine as the backend (laptop today, Shop PC later).
/// - Android / Web: talks to the public tunnel URL, because it runs on
///   a separate device that reaches the backend over the internet.
///
/// Update PUBLIC_TUNNEL_URL below whenever the tunnel address changes.
class ApiService {
  static const String _publicTunnelUrl = 'https://dosage-ssl-recording-determine.trycloudflare.com';
  static const String _localUrl = 'http://localhost:3000';

  static String get baseUrl {
    if (!kIsWeb && Platform.isWindows) {
      return _localUrl;
    }
    return _publicTunnelUrl;
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', user['role']);
    await prefs.setString('name', user['name']);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ---- Auth ----
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Login failed');
    }
    return data;
  }

  // ---- Customers ----
  static Future<List<dynamic>> getCustomers({String? search}) async {
    final uri = (search != null && search.trim().isNotEmpty)
        ? Uri.parse('$baseUrl/api/customers?search=${Uri.encodeComponent(search.trim())}')
        : Uri.parse('$baseUrl/api/customers');
    final res = await http.get(uri, headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getCustomerDetail(int id) async {
    final res = await http.get(Uri.parse('$baseUrl/api/customers/$id'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<void> addCustomer(String name, String phone) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/customers'),
      headers: await _headers(),
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to add customer');
    }
  }

  static Future<void> updateCustomer(int id, String name, String phone) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/customers/$id'),
      headers: await _headers(),
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update customer');
    }
  }

  static Future<void> deleteCustomer(int id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/customers/$id'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to delete customer');
    }
  }

  static Future<double> getCustomersTotalBalance() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/customers/stats/total-balance'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return 0.0;
    final data = jsonDecode(res.body);
    return (data['totalBalance'] as num?)?.toDouble() ?? 0.0;
  }

  // ---- Transactions ----
  // ---- Transactions ----
  static Future<Map<String, dynamic>> getTransactionsFiltered({String? type, String? period}) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (period != null) params['period'] = period;
    final uri = Uri.parse('$baseUrl/api/transactions').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> getTransactions() async {
    final res = await http.get(Uri.parse('$baseUrl/api/transactions'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<void> addTransaction(int customerId, String type, double amount, String note) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/transactions'),
      headers: await _headers(),
      body: jsonEncode({'customer_id': customerId, 'type': type, 'amount': amount, 'note': note}),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to add transaction');
    }
  }

  static Future<void> updateTransaction(int id, String type, double amount, String note) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/transactions/$id'),
      headers: await _headers(),
      body: jsonEncode({'type': type, 'amount': amount, 'note': note}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update transaction');
    }
  }

  static Future<void> deleteTransaction(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/transactions/$id'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to delete transaction');
    }
  }

  // ---- Expenses (Monthly Expense / Daily Online / Daily Card / Daily Main Branch Purchase) ----
  static Future<List<dynamic>> getExpenses(String category) async {
    final res = await http.get(Uri.parse('$baseUrl/api/expenses/$category'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getMonthlyExpenseTotal(String category) async {
    final res = await http.get(Uri.parse('$baseUrl/api/expenses/monthly-total/$category'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to fetch monthly total');
    }
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getDailyExpenseTotal(String category) async {
    final res = await http.get(Uri.parse('$baseUrl/api/expenses/daily-total/$category'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to fetch daily total');
    }
    return jsonDecode(res.body);
  }

  static Future<void> addExpense(String category, double amount, String note) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/expenses/$category'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount, 'note': note}),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to add entry');
    }
  }

  static Future<void> updateExpense(int id, double amount, String note) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/expenses/entry/$id'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount, 'note': note}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update entry');
    }
  }

  static Future<void> deleteExpense(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/expenses/entry/$id'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to delete entry');
    }
  }

  // ---- Google Sheets Sync (Owner only) ----
  static Future<Map<String, dynamic>> runSheetSync({String? tabName}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/run'),
      headers: await _headers(),
      body: jsonEncode(tabName != null ? {'tabName': tabName} : {}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      final errorMessage = data['error'] ?? 'Sync failed';
      final errorCode = data['errorCode'] ?? 'UNKNOWN_ERROR';
      final details = data['details'] ?? '';
      throw SyncException(errorMessage, errorCode, details);
    }
    return data;
  }

  static Future<List<dynamic>> getSyncHistory() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/history'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> undoSync(String tabName, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/undo'),
      headers: await _headers(),
      body: jsonEncode({'tabName': tabName, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to undo sync');
    }
    return data;
  }

  static Future<List<dynamic>> getStagedEntries() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/staged'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<int> getStagedCount() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/staged-count'), headers: await _headers());
    final data = jsonDecode(res.body);
    return data['count'] ?? 0;
  }

  static Future<void> approveStagedEntry(int id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/sheets-sync/staged/$id/approve'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to approve entry');
    }
  }

  static Future<void> rejectStagedEntry(int id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/sheets-sync/staged/$id/reject'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to reject entry');
    }
  }

  static Future<Map<String, dynamic>> bulkApproveStagedEntries() async {
    final res = await http.post(Uri.parse('$baseUrl/api/sheets-sync/staged/bulk-approve'), headers: await _headers());
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to bulk approve');
    }
    return data;
  }

  static Future<List<dynamic>> getPendingSyncs() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/pending'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<int> getPendingSyncCount() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/pending-count'), headers: await _headers());
    final data = jsonDecode(res.body);
    return data['count'] ?? 0;
  }

  static Future<void> resolvePendingSync(int pendingId, String action, {int? customerId, String? newCustomerName}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/approve'),
      headers: await _headers(),
      body: jsonEncode({
        'pendingId': pendingId,
        'action': action,
        if (customerId != null) 'customerId': customerId,
        if (newCustomerName != null) 'newCustomerName': newCustomerName,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to resolve entry');
    }
  }

  static Future<Map<String, dynamic>> bulkRejectPending(List<int> pendingIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/bulk-reject'),
      headers: await _headers(),
      body: jsonEncode({'pendingIds': pendingIds}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to bulk reject');
    }
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> bulkApproveAsCreate(List<int> pendingIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/bulk-approve-as-create'),
      headers: await _headers(),
      body: jsonEncode({'pendingIds': pendingIds}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to bulk approve');
    }
    return jsonDecode(res.body);
  }

  // ---- User management (Owner only, except change-password) ----
  static Future<void> createWorker(String name, String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/create-worker'),
      headers: await _headers(),
      body: jsonEncode({'name': name, 'username': username, 'password': password}),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create worker');
    }
  }

  static Future<List<dynamic>> getWorkers() async {
    final res = await http.get(Uri.parse('$baseUrl/api/auth/workers'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<void> deleteWorker(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/auth/workers/$id'), headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to delete worker');
    }
  }

  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/change-password'),
      headers: await _headers(),
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to change password');
    }
  }
}
