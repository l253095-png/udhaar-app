import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'worker_dashboard.dart';
import '../theme/app_colors.dart';
import '../widgets/developer_credit_overlay.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showCredit = true;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.login(_usernameController.text.trim(), _passwordController.text);
      await ApiService.saveSession(data['token'], data['user']);

      if (!mounted) return;
      final role = data['user']['role'];
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => role == 'owner' ? const HomeScreen() : const WorkerDashboard(),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                                  const Icon(Icons.storefront_rounded, size: 72, color: AppColors.marigold),
                  const SizedBox(height: 12),
                  Text('Professoron Ka Khata', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading ? const CircularProgressIndicator() : const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showCredit)
          DeveloperCreditOverlay(
            onFinished: () => setState(() => _showCredit = false),
          ),
      ],
    );
  }
}