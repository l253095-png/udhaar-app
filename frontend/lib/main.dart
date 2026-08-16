import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const UdhaarApp());
}

class UdhaarApp extends StatelessWidget {
  const UdhaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Udhaar Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
