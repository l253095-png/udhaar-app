import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Central place for talking to the backend.
///
/// Right now this points at your own laptop's backend (localhost),
/// since both the app and the backend are running on the same machine.
///
/// Later, when the backend moves to the Shop PC + Cloudflare Tunnel,
/// this ONE line is all you'll need to change:
///   static const String baseUrl = 'https://your-tunnel-url.com';
class ApiService {
  static const String baseUrl = 'http://localhost:3000';

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
  static Future<List<dynamic>> getCustomers() async {
    final res = await http.get(Uri.parse('$baseUrl/api/customers'), headers: await _headers());
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

  // ---- Transactions ----
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

  // ---- Google Sheets Sync (Owner only) ----
  static Future<Map<String, dynamic>> previewSheetSync() async {
    final res = await http.get(Uri.parse('$baseUrl/api/sheets-sync/preview'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> confirmSheetSync(List<dynamic> rows) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sheets-sync/confirm'),
      headers: await _headers(),
      body: jsonEncode({'rows': rows}),
    );
    return jsonDecode(res.body);
  }
}
